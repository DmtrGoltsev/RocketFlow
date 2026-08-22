import Foundation
import GRDB

actor GRDBFocusCache: FocusCaching {
    private enum Kind {
        static let current = "current"
        static let history = "history"
        static let historyDetail = "historyDetail"
        static let settings = "settings"
    }

    private let database: AppDatabase
    private let lease: FeaturePersistenceLease

    init(database: AppDatabase, accountID: UUID) throws {
        self.database = database
        lease = try database.write { db in
            try FeaturePersistenceAccount.acquire(accountID, in: db)
        }
    }

    func current(accountID: UUID) throws -> FocusPeriodDTO? {
        try load(FocusPeriodDTO.self, accountID: accountID, kind: Kind.current)
    }

    func saveCurrent(_ period: FocusPeriodDTO, accountID: UUID) throws {
        try save(period, accountID: accountID, kind: Kind.current)
    }

    func history(accountID: UUID) throws -> [FocusHistorySummaryDTO]? {
        try load([FocusHistorySummaryDTO].self, accountID: accountID, kind: Kind.history)
    }

    func saveHistory(_ history: [FocusHistorySummaryDTO], accountID: UUID) throws {
        try save(history, accountID: accountID, kind: Kind.history)
    }

    func historyDetail(accountID: UUID, periodID: UUID) throws -> FocusPeriodDTO? {
        let period: FocusPeriodDTO? = try load(
            FocusPeriodDTO.self,
            accountID: accountID,
            kind: Kind.historyDetail,
            entityID: periodID.featurePersistenceKey
        )
        return period?.id == periodID ? period : nil
    }

    func saveHistoryDetail(_ period: FocusPeriodDTO, accountID: UUID) throws {
        try save(
            period,
            accountID: accountID,
            kind: Kind.historyDetail,
            entityID: period.id.featurePersistenceKey
        )
    }

    func settings(accountID: UUID) throws -> FocusNotificationSettingsDTO? {
        try load(FocusNotificationSettingsDTO.self, accountID: accountID, kind: Kind.settings)
    }

    func saveSettings(_ settings: FocusNotificationSettingsDTO, accountID: UUID) throws {
        try save(settings, accountID: accountID, kind: Kind.settings)
    }

    func clear(accountID: UUID) throws {
        try lease.require(accountID)
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try db.execute(
                sql: "DELETE FROM feature_focus_snapshots WHERE accountID = ?",
                arguments: [accountID.featurePersistenceKey]
            )
        }
    }

    private func load<Value: Decodable>(
        _ type: Value.Type,
        accountID: UUID,
        kind: String,
        entityID: String = ""
    ) throws -> Value? {
        try lease.require(accountID)
        let payload: Data? = try database.read { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try Data.fetchOne(
                db,
                sql: """
                    SELECT payloadJSON FROM feature_focus_snapshots
                    WHERE accountID = ? AND cacheKind = ? AND entityID = ?
                    """,
                arguments: [accountID.featurePersistenceKey, kind, entityID]
            )
        }
        guard let payload else { return nil }
        return FeaturePersistenceJSON.decode(type, from: payload)
    }

    private func save<Value: Encodable>(
        _ value: Value,
        accountID: UUID,
        kind: String,
        entityID: String = ""
    ) throws {
        try lease.require(accountID)
        let payload = try FeaturePersistenceJSON.encode(value)
        let timestamp = WireDateCodec.encode(Date())
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try db.execute(
                sql: """
                    INSERT INTO feature_focus_snapshots (
                        accountID, cacheKind, entityID, payloadJSON, updatedAt
                    ) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(accountID, cacheKind, entityID)
                    DO UPDATE SET payloadJSON = excluded.payloadJSON, updatedAt = excluded.updatedAt
                    """,
                arguments: [accountID.featurePersistenceKey, kind, entityID, payload, timestamp]
            )
        }
    }
}

struct FeatureFocusRetryMetadata: Equatable, Sendable {
    let retryCount: Int
    let nextRetryAt: Date?
    let lastErrorCode: String?
}

actor GRDBFocusActionQueue: FocusActionQueuing {
    private struct StoredAction {
        let action: FocusPendingAction
        let retry: FeatureFocusRetryMetadata
    }

    private let database: AppDatabase
    private let lease: FeaturePersistenceLease
    private let now: @Sendable () -> Date
    private let issueID: @Sendable () -> UUID

    init(
        database: AppDatabase,
        accountID: UUID,
        now: @escaping @Sendable () -> Date = Date.init,
        issueID: @escaping @Sendable () -> UUID = UUID.init
    ) throws {
        self.database = database
        self.now = now
        self.issueID = issueID
        lease = try database.write { db in
            try FeaturePersistenceAccount.acquire(accountID, in: db, at: now())
        }
    }

    func enqueue(_ action: FocusPendingAction) throws {
        try lease.require(action.accountID)
        let payload = try FeaturePersistenceJSON.encode(action)
        let timestamp = WireDateCodec.encode(now())
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            let exists = try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS(
                        SELECT 1 FROM feature_focus_actions
                        WHERE accountID = ? AND actionID = ?
                    )
                    """,
                arguments: [action.accountID.featurePersistenceKey, action.id.featurePersistenceKey]
            ) ?? false
            guard !exists else { return }
            let sequence = try Int64.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(MAX(sequence), -1) + 1
                    FROM feature_focus_actions WHERE accountID = ?
                    """,
                arguments: [action.accountID.featurePersistenceKey]
            ) ?? 0
            try Self.insert(action, payload: payload, sequence: sequence, timestamp: timestamp, in: db)
        }
    }

    func pending(accountID: UUID) throws -> [FocusPendingAction] {
        try lease.require(accountID)
        let currentDate = now()
        let result: Result<[FocusPendingAction], FeaturePersistenceError> = try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT actionID, kind, expectedVersion, conflictAttempts,
                           retryCount, nextRetryAt, lastErrorCode, payloadJSON
                    FROM feature_focus_actions
                    WHERE accountID = ?
                    ORDER BY sequence ASC, createdAt ASC, actionID ASC
                    """,
                arguments: [accountID.featurePersistenceKey]
            )
            var available: [FocusPendingAction] = []
            for row in rows {
                let actionID: String = row["actionID"]
                let stored: StoredAction
                do {
                    stored = try Self.storedAction(from: row, accountID: accountID)
                } catch let corruption as FeaturePersistenceError {
                    guard available.isEmpty else { break }
                    try FeaturePersistenceCorruption.record(
                        lease: lease,
                        table: "feature_focus_actions",
                        key: actionID,
                        at: currentDate,
                        in: db
                    )
                    return .failure(corruption)
                }
                if let nextRetryAt = stored.retry.nextRetryAt, nextRetryAt > currentDate {
                    break
                }
                available.append(stored.action)
            }
            return .success(available)
        }
        return try result.get()
    }

    func acknowledge(accountID: UUID, actionID: UUID) throws {
        try lease.require(accountID)
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try db.execute(
                sql: "DELETE FROM feature_focus_actions WHERE accountID = ? AND actionID = ?",
                arguments: [accountID.featurePersistenceKey, actionID.featurePersistenceKey]
            )
        }
    }

    func incrementConflict(accountID: UUID, actionID: UUID) throws -> FocusPendingAction {
        try lease.require(accountID)
        return try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            guard var action = try Self.action(accountID: accountID, actionID: actionID, in: db) else {
                throw FocusRepositoryError.pendingActionMissing
            }
            action.conflictAttempts += 1
            let payload = try FeaturePersistenceJSON.encode(action)
            try db.execute(
                sql: """
                    UPDATE feature_focus_actions
                    SET payloadJSON = ?, conflictAttempts = ?, updatedAt = ?
                    WHERE accountID = ? AND actionID = ?
                    """,
                arguments: [
                    payload,
                    action.conflictAttempts,
                    WireDateCodec.encode(now()),
                    accountID.featurePersistenceKey,
                    actionID.featurePersistenceKey
                ]
            )
            return action
        }
    }

    func terminalize(accountID: UUID, actionID: UUID, code: String, at: Date) throws {
        try lease.require(accountID)
        let newIssueID = issueID()
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            guard let action = try Self.action(accountID: accountID, actionID: actionID, in: db) else {
                throw FocusRepositoryError.pendingActionMissing
            }
            let issue = FocusTerminalIssue(
                id: newIssueID,
                actionID: action.id,
                kind: action.kind,
                code: code,
                conflictAttempts: action.conflictAttempts,
                createdAt: at
            )
            try db.execute(
                sql: """
                    INSERT INTO feature_focus_terminal_issues (
                        accountID, issueID, payloadJSON, createdAt
                    ) VALUES (?, ?, ?, ?)
                    """,
                arguments: [
                    accountID.featurePersistenceKey,
                    newIssueID.featurePersistenceKey,
                    try FeaturePersistenceJSON.encode(issue),
                    WireDateCodec.encode(at)
                ]
            )
            try db.execute(
                sql: "DELETE FROM feature_focus_actions WHERE accountID = ? AND actionID = ?",
                arguments: [accountID.featurePersistenceKey, actionID.featurePersistenceKey]
            )
        }
    }

    func terminalIssues(accountID: UUID) throws -> [FocusTerminalIssue] {
        try lease.require(accountID)
        let payloads = try database.read { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            return try Data.fetchAll(
                db,
                sql: """
                    SELECT payloadJSON FROM feature_focus_terminal_issues
                    WHERE accountID = ? ORDER BY createdAt ASC, issueID ASC
                    """,
                arguments: [accountID.featurePersistenceKey]
            )
        }
        return try payloads.enumerated().map { offset, payload in
            try FeaturePersistenceJSON.decodeRequired(
                FocusTerminalIssue.self,
                from: payload,
                table: "feature_focus_terminal_issues",
                key: String(offset)
            )
        }
    }

    func clear(accountID: UUID) throws {
        try lease.require(accountID)
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try db.execute(
                sql: "DELETE FROM feature_focus_actions WHERE accountID = ?",
                arguments: [accountID.featurePersistenceKey]
            )
            try db.execute(
                sql: "DELETE FROM feature_focus_terminal_issues WHERE accountID = ?",
                arguments: [accountID.featurePersistenceKey]
            )
            try db.execute(
                sql: """
                    DELETE FROM feature_persistence_corruptions
                    WHERE accountID = ? AND tableName = 'feature_focus_actions'
                    """,
                arguments: [accountID.featurePersistenceKey]
            )
        }
    }

    func corruptionIssues(accountID: UUID) throws -> [FeaturePersistenceCorruptionIssue] {
        try lease.require(accountID)
        return try database.read { db in
            try FeaturePersistenceCorruption.issues(lease: lease, in: db)
        }.filter { $0.tableName == "feature_focus_actions" }
    }

    func quarantineCorruptHead(accountID: UUID, actionID: UUID) throws {
        _ = try quarantineCorruptHead(
            accountID: accountID,
            expectedActionKey: actionID.featurePersistenceKey
        )
    }

    @discardableResult
    func quarantineCorruptHead(accountID: UUID) throws -> String {
        try quarantineCorruptHead(accountID: accountID, expectedActionKey: nil)
    }

    private func quarantineCorruptHead(
        accountID: UUID,
        expectedActionKey: String?
    ) throws -> String {
        try lease.require(accountID)
        return try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT actionID, kind, expectedVersion, conflictAttempts,
                           retryCount, nextRetryAt, lastErrorCode, payloadJSON
                    FROM feature_focus_actions
                    WHERE accountID = ?
                    ORDER BY sequence ASC, createdAt ASC, actionID ASC
                    LIMIT 1
                    """,
                arguments: [accountID.featurePersistenceKey]
            ) else {
                throw FocusRepositoryError.pendingActionMissing
            }
            let rawActionID: String = row["actionID"]
            if let expectedActionKey, rawActionID != expectedActionKey {
                throw FeaturePersistenceError.corruptHeadMismatch
            }
            do {
                _ = try Self.storedAction(from: row, accountID: accountID)
                throw FeaturePersistenceError.corruptHeadMismatch
            } catch let error as FeaturePersistenceError {
                guard case .corruptRecord = error else { throw error }
            }
            try FeaturePersistenceCorruption.record(
                lease: lease,
                table: "feature_focus_actions",
                key: rawActionID,
                at: now(),
                in: db
            )
            try db.execute(
                sql: "DELETE FROM feature_focus_actions WHERE accountID = ? AND actionID = ?",
                arguments: [accountID.featurePersistenceKey, rawActionID]
            )
            return rawActionID
        }
    }

    func replacePending(_ actions: [FocusPendingAction], accountID: UUID) throws {
        try lease.require(accountID)
        guard actions.allSatisfy({ $0.accountID == accountID }) else {
            throw FeaturePersistenceError.accountMismatch
        }
        guard Set(actions.map(\.id)).count == actions.count else {
            throw FeaturePersistenceError.duplicateActionID
        }
        let timestamp = WireDateCodec.encode(now())
        let encoded = try actions.map { ($0, try FeaturePersistenceJSON.encode($0)) }
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            let retryMetadata = try Self.retryMetadataByAction(accountID: accountID, in: db)
            try db.execute(
                sql: "DELETE FROM feature_focus_actions WHERE accountID = ?",
                arguments: [accountID.featurePersistenceKey]
            )
            for (offset, pair) in encoded.enumerated() {
                try Self.insert(
                    pair.0,
                    payload: pair.1,
                    sequence: Int64(offset),
                    timestamp: timestamp,
                    retryMetadata: retryMetadata[pair.0.id],
                    in: db
                )
            }
        }
    }

    @discardableResult
    func recordRetry(
        accountID: UUID,
        actionID: UUID,
        nextRetryAt: Date?,
        errorCode: String?
    ) throws -> FeatureFocusRetryMetadata {
        try lease.require(accountID)
        return try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            guard try Self.action(accountID: accountID, actionID: actionID, in: db) != nil else {
                throw FocusRepositoryError.pendingActionMissing
            }
            try db.execute(
                sql: """
                    UPDATE feature_focus_actions
                    SET retryCount = retryCount + 1, nextRetryAt = ?, lastErrorCode = ?, updatedAt = ?
                    WHERE accountID = ? AND actionID = ?
                    """,
                arguments: [
                    nextRetryAt.map(WireDateCodec.encode),
                    errorCode,
                    WireDateCodec.encode(now()),
                    accountID.featurePersistenceKey,
                    actionID.featurePersistenceKey
                ]
            )
            guard let metadata = try Self.retryMetadata(
                accountID: accountID,
                actionID: actionID,
                in: db
            ) else {
                throw FocusRepositoryError.pendingActionMissing
            }
            return metadata
        }
    }

    func retryMetadata(accountID: UUID, actionID: UUID) throws -> FeatureFocusRetryMetadata? {
        try lease.require(accountID)
        return try database.read { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try Self.retryMetadata(accountID: accountID, actionID: actionID, in: db)
        }
    }

    private static func insert(
        _ action: FocusPendingAction,
        payload: Data,
        sequence: Int64,
        timestamp: String,
        retryMetadata: FeatureFocusRetryMetadata? = nil,
        in db: Database
    ) throws {
        let retryMetadata = retryMetadata ?? FeatureFocusRetryMetadata(
            retryCount: 0,
            nextRetryAt: nil,
            lastErrorCode: nil
        )
        try db.execute(
            sql: """
                INSERT INTO feature_focus_actions (
                    accountID, actionID, kind, payloadJSON, expectedVersion,
                    conflictAttempts, retryCount, nextRetryAt, lastErrorCode,
                    sequence, createdAt, updatedAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                action.accountID.featurePersistenceKey,
                action.id.featurePersistenceKey,
                action.kind.rawValue,
                payload,
                action.expectedVersion,
                action.conflictAttempts,
                retryMetadata.retryCount,
                retryMetadata.nextRetryAt.map(WireDateCodec.encode),
                retryMetadata.lastErrorCode,
                sequence,
                WireDateCodec.encode(action.createdAt),
                timestamp
            ]
        )
    }

    private static func action(
        accountID: UUID,
        actionID: UUID,
        in db: Database
    ) throws -> FocusPendingAction? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT actionID, kind, expectedVersion, conflictAttempts,
                       retryCount, nextRetryAt, lastErrorCode, payloadJSON
                FROM feature_focus_actions
                WHERE accountID = ? AND actionID = ?
                """,
            arguments: [accountID.featurePersistenceKey, actionID.featurePersistenceKey]
        ) else { return nil }
        return try storedAction(from: row, accountID: accountID).action
    }

    private static func storedAction(from row: Row, accountID: UUID) throws -> StoredAction {
        let actionID: String = row["actionID"]
        let table = "feature_focus_actions"
        let payload: Data = row["payloadJSON"]
        let action = try FeaturePersistenceJSON.decodeRequired(
            FocusPendingAction.self,
            from: payload,
            table: table,
            key: actionID
        )
        let kind: String = row["kind"]
        let expectedVersion: Int64 = row["expectedVersion"]
        let conflictAttempts: Int = row["conflictAttempts"]
        let retryCount: Int = row["retryCount"]
        let rawNextRetryAt: String? = row["nextRetryAt"]
        guard action.accountID == accountID,
              action.id.featurePersistenceKey == actionID,
              action.kind.rawValue == kind,
              action.expectedVersion == expectedVersion,
              action.conflictAttempts == conflictAttempts,
              conflictAttempts >= 0,
              retryCount >= 0 else {
            throw FeaturePersistenceError.corruptRecord(table: table, key: actionID)
        }
        let nextRetryAt: Date?
        if let rawNextRetryAt {
            do {
                nextRetryAt = try WireDateCodec.decode(rawNextRetryAt)
            } catch {
                throw FeaturePersistenceError.corruptRecord(table: table, key: actionID)
            }
        } else {
            nextRetryAt = nil
        }
        let lastErrorCode: String? = row["lastErrorCode"]
        return StoredAction(
            action: action,
            retry: FeatureFocusRetryMetadata(
                retryCount: retryCount,
                nextRetryAt: nextRetryAt,
                lastErrorCode: lastErrorCode
            )
        )
    }

    private static func retryMetadata(
        accountID: UUID,
        actionID: UUID,
        in db: Database
    ) throws -> FeatureFocusRetryMetadata? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT retryCount, nextRetryAt, lastErrorCode
                FROM feature_focus_actions WHERE accountID = ? AND actionID = ?
                """,
            arguments: [accountID.featurePersistenceKey, actionID.featurePersistenceKey]
        ) else { return nil }
        let retryCount: Int = row["retryCount"]
        let rawNextRetryAt: String? = row["nextRetryAt"]
        let lastErrorCode: String? = row["lastErrorCode"]
        guard retryCount >= 0 else {
            throw FeaturePersistenceError.corruptRecord(
                table: "feature_focus_actions",
                key: actionID.featurePersistenceKey
            )
        }
        let nextRetryAt: Date?
        if let rawNextRetryAt {
            do {
                nextRetryAt = try WireDateCodec.decode(rawNextRetryAt)
            } catch {
                throw FeaturePersistenceError.corruptRecord(
                    table: "feature_focus_actions",
                    key: actionID.featurePersistenceKey
                )
            }
        } else {
            nextRetryAt = nil
        }
        return FeatureFocusRetryMetadata(
            retryCount: retryCount,
            nextRetryAt: nextRetryAt,
            lastErrorCode: lastErrorCode
        )
    }

    private static func retryMetadataByAction(
        accountID: UUID,
        in db: Database
    ) throws -> [UUID: FeatureFocusRetryMetadata] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT actionID, retryCount, nextRetryAt, lastErrorCode
                FROM feature_focus_actions WHERE accountID = ?
                """,
            arguments: [accountID.featurePersistenceKey]
        )
        return Dictionary(uniqueKeysWithValues: try rows.map { row in
            let rawActionID: String = row["actionID"]
            guard let actionID = UUID(uuidString: rawActionID) else {
                throw FeaturePersistenceError.corruptRecord(
                    table: "feature_focus_actions",
                    key: rawActionID
                )
            }
            let retryCount: Int = row["retryCount"]
            let rawNextRetryAt: String? = row["nextRetryAt"]
            let lastErrorCode: String? = row["lastErrorCode"]
            guard retryCount >= 0 else {
                throw FeaturePersistenceError.corruptRecord(
                    table: "feature_focus_actions",
                    key: rawActionID
                )
            }
            let nextRetryAt: Date?
            if let rawNextRetryAt {
                do {
                    nextRetryAt = try WireDateCodec.decode(rawNextRetryAt)
                } catch {
                    throw FeaturePersistenceError.corruptRecord(
                        table: "feature_focus_actions",
                        key: rawActionID
                    )
                }
            } else {
                nextRetryAt = nil
            }
            return (
                actionID,
                FeatureFocusRetryMetadata(
                    retryCount: retryCount,
                    nextRetryAt: nextRetryAt,
                    lastErrorCode: lastErrorCode
                )
            )
        })
    }
}
