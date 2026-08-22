import Foundation
import GRDB

struct FeatureReminderReconciliationState: Equatable, Sendable {
    let reason: ReminderReconcileReason
    let reconciledAt: Date
}

actor GRDBTaskReminderStore: TaskReminderStoreServing {
    private let database: AppDatabase
    private let lease: FeaturePersistenceLease
    private let now: @Sendable () -> Date

    init(
        database: AppDatabase,
        accountID: UUID,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        self.database = database
        self.now = now
        lease = try database.write { db in
            try FeaturePersistenceAccount.acquire(accountID, in: db, at: now())
        }
    }

    func reconciliationItems(accountID: UUID) throws -> [TaskReminderReconciliationItem] {
        try lease.require(accountID)
        let result: Result<[TaskReminderReconciliationItem], FeaturePersistenceError> = try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT taskID, reminderID, payloadJSON, taskState
                    FROM feature_task_reminders
                    WHERE accountID = ? ORDER BY reminderID ASC
                    """,
                arguments: [accountID.featurePersistenceKey]
            )
            var values: [TaskReminderReconciliationItem] = []
            for row in rows {
                let taskID: String = row["taskID"]
                let reminderID: String = row["reminderID"]
                let key = "\(taskID):\(reminderID)"
                do {
                    let payload: Data = row["payloadJSON"]
                    let reminder = try FeaturePersistenceJSON.decodeRequired(
                        LocalTaskReminder.self,
                        from: payload,
                        table: "feature_task_reminders",
                        key: key
                    )
                    let rawTaskState: String = row["taskState"]
                    guard reminder.accountID == accountID,
                          reminder.taskID.featurePersistenceKey == taskID,
                          reminder.id.featurePersistenceKey == reminderID,
                          let taskState = ReminderTaskState(rawValue: rawTaskState) else {
                        throw FeaturePersistenceError.corruptRecord(
                            table: "feature_task_reminders",
                            key: key
                        )
                    }
                    values.append(TaskReminderReconciliationItem(
                        reminder: reminder,
                        taskState: taskState
                    ))
                } catch let corruption as FeaturePersistenceError {
                    try FeaturePersistenceCorruption.record(
                        lease: lease,
                        table: "feature_task_reminders",
                        key: key,
                        at: now(),
                        in: db
                    )
                    return .failure(corruption)
                }
            }
            return .success(values)
        }
        return try result.get()
    }

    func reminders(accountID: UUID) throws -> [LocalTaskReminder] {
        try reconciliationItems(accountID: accountID).map(\.reminder)
    }

    func save(_ reminder: LocalTaskReminder, taskState: ReminderTaskState) throws {
        try lease.require(reminder.accountID)
        let payload = try FeaturePersistenceJSON.encode(reminder)
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try db.execute(
                sql: """
                    INSERT INTO feature_task_reminders (
                        accountID, taskID, reminderID, payloadJSON, taskState, updatedAt
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(accountID, taskID, reminderID)
                    DO UPDATE SET payloadJSON = excluded.payloadJSON,
                                  taskState = excluded.taskState,
                                  updatedAt = excluded.updatedAt
                    """,
                arguments: [
                    reminder.accountID.featurePersistenceKey,
                    reminder.taskID.featurePersistenceKey,
                    reminder.id.featurePersistenceKey,
                    payload,
                    taskState.rawValue,
                    WireDateCodec.encode(now())
                ]
            )
            try db.execute(
                sql: """
                    DELETE FROM feature_persistence_corruptions
                    WHERE accountID = ? AND tableName = 'feature_task_reminders' AND recordKey = ?
                    """,
                arguments: [
                    reminder.accountID.featurePersistenceKey,
                    "\(reminder.taskID.featurePersistenceKey):\(reminder.id.featurePersistenceKey)"
                ]
            )
        }
    }

    func remove(accountID: UUID, taskID: UUID, reminderID: UUID) throws {
        try lease.require(accountID)
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try db.execute(
                sql: """
                    DELETE FROM feature_task_reminders
                    WHERE accountID = ? AND taskID = ? AND reminderID = ?
                    """,
                arguments: [
                    accountID.featurePersistenceKey,
                    taskID.featurePersistenceKey,
                    reminderID.featurePersistenceKey
                ]
            )
            try db.execute(
                sql: """
                    DELETE FROM feature_persistence_corruptions
                    WHERE accountID = ? AND tableName = 'feature_task_reminders' AND recordKey = ?
                    """,
                arguments: [
                    accountID.featurePersistenceKey,
                    "\(taskID.featurePersistenceKey):\(reminderID.featurePersistenceKey)"
                ]
            )
        }
    }

    func defaultReminder(accountID: UUID) throws -> DefaultTaskReminder? {
        try lease.require(accountID)
        let result: Result<DefaultTaskReminder?, FeaturePersistenceError> = try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            guard let payload = try Data.fetchOne(
                db,
                sql: "SELECT payloadJSON FROM feature_default_reminders WHERE accountID = ?",
                arguments: [accountID.featurePersistenceKey]
            ) else { return .success(nil) }
            do {
                let reminder = try FeaturePersistenceJSON.decodeRequired(
                    DefaultTaskReminder.self,
                    from: payload,
                    table: "feature_default_reminders",
                    key: "singleton"
                )
                guard reminder.accountID == accountID else {
                    throw FeaturePersistenceError.corruptRecord(
                        table: "feature_default_reminders",
                        key: "singleton"
                    )
                }
                return .success(reminder)
            } catch let corruption as FeaturePersistenceError {
                try FeaturePersistenceCorruption.record(
                    lease: lease,
                    table: "feature_default_reminders",
                    key: "singleton",
                    at: now(),
                    in: db
                )
                return .failure(corruption)
            }
        }
        return try result.get()
    }

    func saveDefault(_ reminder: DefaultTaskReminder) throws {
        try lease.require(reminder.accountID)
        let payload = try FeaturePersistenceJSON.encode(reminder)
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try db.execute(
                sql: """
                    INSERT INTO feature_default_reminders (accountID, payloadJSON, updatedAt)
                    VALUES (?, ?, ?)
                    ON CONFLICT(accountID) DO UPDATE SET
                        payloadJSON = excluded.payloadJSON, updatedAt = excluded.updatedAt
                    """,
                arguments: [
                    reminder.accountID.featurePersistenceKey,
                    payload,
                    WireDateCodec.encode(now())
                ]
            )
            try db.execute(
                sql: """
                    DELETE FROM feature_persistence_corruptions
                    WHERE accountID = ? AND tableName = 'feature_default_reminders'
                    """,
                arguments: [reminder.accountID.featurePersistenceKey]
            )
        }
    }

    func clearDefault(accountID: UUID) throws {
        try lease.require(accountID)
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try db.execute(
                sql: "DELETE FROM feature_default_reminders WHERE accountID = ?",
                arguments: [accountID.featurePersistenceKey]
            )
            try db.execute(
                sql: """
                    DELETE FROM feature_persistence_corruptions
                    WHERE accountID = ? AND tableName = 'feature_default_reminders'
                    """,
                arguments: [accountID.featurePersistenceKey]
            )
        }
    }

    func clear(accountID: UUID) throws {
        try lease.require(accountID)
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            for table in [
                "feature_task_reminders",
                "feature_default_reminders",
                "feature_reminder_reconciliation"
            ] {
                try db.execute(
                    sql: "DELETE FROM \(table) WHERE accountID = ?",
                    arguments: [accountID.featurePersistenceKey]
                )
            }
            try db.execute(
                sql: """
                    DELETE FROM feature_persistence_corruptions
                    WHERE accountID = ? AND tableName IN (
                        'feature_task_reminders',
                        'feature_default_reminders',
                        'feature_reminder_reconciliation'
                    )
                    """,
                arguments: [accountID.featurePersistenceKey]
            )
        }
    }

    func recordReconciliation(
        accountID: UUID,
        reason: ReminderReconcileReason,
        at date: Date
    ) throws {
        try lease.require(accountID)
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try db.execute(
                sql: """
                    INSERT INTO feature_reminder_reconciliation (accountID, reason, reconciledAt)
                    VALUES (?, ?, ?)
                    ON CONFLICT(accountID) DO UPDATE SET
                        reason = excluded.reason, reconciledAt = excluded.reconciledAt
                    """,
                arguments: [
                    accountID.featurePersistenceKey,
                    reason.rawValue,
                    WireDateCodec.encode(date)
                ]
            )
            try db.execute(
                sql: """
                    DELETE FROM feature_persistence_corruptions
                    WHERE accountID = ?
                      AND tableName = 'feature_reminder_reconciliation'
                      AND recordKey = 'singleton'
                    """,
                arguments: [accountID.featurePersistenceKey]
            )
        }
    }

    func reconciliationState(accountID: UUID) throws -> FeatureReminderReconciliationState? {
        try lease.require(accountID)
        let result: Result<FeatureReminderReconciliationState?, FeaturePersistenceError> =
            try database.write { db in
                try FeaturePersistenceAccount.validate(lease, in: db)
                guard let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT reason, reconciledAt FROM feature_reminder_reconciliation
                        WHERE accountID = ?
                        """,
                    arguments: [accountID.featurePersistenceKey]
                ) else { return .success(nil) }
                let rawReason: String = row["reason"]
                let rawDate: String = row["reconciledAt"]
                guard let reason = ReminderReconcileReason(rawValue: rawReason),
                      let date = try? WireDateCodec.decode(rawDate) else {
                    let corruption = FeaturePersistenceError.corruptRecord(
                        table: "feature_reminder_reconciliation",
                        key: "singleton"
                    )
                    try FeaturePersistenceCorruption.record(
                        lease: lease,
                        table: "feature_reminder_reconciliation",
                        key: "singleton",
                        at: now(),
                        in: db
                    )
                    return .failure(corruption)
                }
                return .success(FeatureReminderReconciliationState(
                    reason: reason,
                    reconciledAt: date
                ))
            }
        return try result.get()
    }

    func corruptionIssues(accountID: UUID) throws -> [FeaturePersistenceCorruptionIssue] {
        try lease.require(accountID)
        return try database.read { db in
            try FeaturePersistenceCorruption.issues(lease: lease, in: db)
        }.filter {
            $0.tableName == "feature_task_reminders"
                || $0.tableName == "feature_default_reminders"
                || $0.tableName == "feature_reminder_reconciliation"
        }
    }

    func quarantineCorruptReminder(
        accountID: UUID,
        taskID: UUID,
        reminderID: UUID
    ) throws {
        try lease.require(accountID)
        let key = "\(taskID.featurePersistenceKey):\(reminderID.featurePersistenceKey)"
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT payloadJSON, taskState FROM feature_task_reminders
                    WHERE accountID = ? AND taskID = ? AND reminderID = ?
                    """,
                arguments: [
                    accountID.featurePersistenceKey,
                    taskID.featurePersistenceKey,
                    reminderID.featurePersistenceKey
                ]
            ) else { return }
            let payload: Data = row["payloadJSON"]
            let rawState: String = row["taskState"]
            let decoded = FeaturePersistenceJSON.decode(LocalTaskReminder.self, from: payload)
            let isValid = decoded?.accountID == accountID
                && decoded?.taskID == taskID
                && decoded?.id == reminderID
                && ReminderTaskState(rawValue: rawState) != nil
            guard !isValid else {
                throw FeaturePersistenceError.corruptHeadMismatch
            }
            try FeaturePersistenceCorruption.record(
                lease: lease,
                table: "feature_task_reminders",
                key: key,
                at: now(),
                in: db
            )
            try db.execute(
                sql: """
                    DELETE FROM feature_task_reminders
                    WHERE accountID = ? AND taskID = ? AND reminderID = ?
                    """,
                arguments: [
                    accountID.featurePersistenceKey,
                    taskID.featurePersistenceKey,
                    reminderID.featurePersistenceKey
                ]
            )
        }
    }
}

actor GRDBFocusNotificationEventStore: FocusNotificationEventDeduplicating {
    static let retention: TimeInterval = 14 * 24 * 60 * 60

    private let database: AppDatabase
    private let accountID: UUID
    private let lease: FeaturePersistenceLease
    private let retention: TimeInterval

    init(
        database: AppDatabase,
        accountID: UUID,
        retention: TimeInterval = GRDBFocusNotificationEventStore.retention
    ) throws {
        guard retention > 0 else {
            throw FeaturePersistenceError.invalidRetention
        }
        self.database = database
        self.accountID = accountID
        self.retention = retention
        lease = try database.write { db in
            try FeaturePersistenceAccount.acquire(accountID, in: db)
        }
    }

    func markIfNew(eventID: UUID, now: Date) throws -> Bool {
        let cutoff = now.addingTimeInterval(-retention)
        return try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            let eventRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT eventID, seenAt FROM feature_remote_notification_events
                    WHERE accountID = ?
                    """,
                arguments: [accountID.featurePersistenceKey]
            )
            for row in eventRows {
                let rawEventID: String = row["eventID"]
                let rawSeenAt: String = row["seenAt"]
                if (try? WireDateCodec.decode(rawSeenAt)) == nil {
                    try db.execute(
                        sql: """
                            DELETE FROM feature_remote_notification_events
                            WHERE accountID = ? AND eventID = ?
                            """,
                        arguments: [accountID.featurePersistenceKey, rawEventID]
                    )
                }
            }
            try db.execute(
                sql: """
                    DELETE FROM feature_remote_notification_events
                    WHERE accountID = ? AND seenAt < ?
                    """,
                arguments: [accountID.featurePersistenceKey, WireDateCodec.encode(cutoff)]
            )
            let existing: String? = try String.fetchOne(
                db,
                sql: """
                    SELECT seenAt FROM feature_remote_notification_events
                    WHERE accountID = ? AND eventID = ?
                    """,
                arguments: [accountID.featurePersistenceKey, eventID.featurePersistenceKey]
            )
            if let existing,
               let seenAt = try? WireDateCodec.decode(existing),
               seenAt >= cutoff {
                return false
            }
            try db.execute(
                sql: """
                    INSERT INTO feature_remote_notification_events (accountID, eventID, seenAt)
                    VALUES (?, ?, ?)
                    ON CONFLICT(accountID, eventID) DO UPDATE SET seenAt = excluded.seenAt
                    """,
                arguments: [
                    accountID.featurePersistenceKey,
                    eventID.featurePersistenceKey,
                    WireDateCodec.encode(now)
                ]
            )
            return true
        }
    }
}
