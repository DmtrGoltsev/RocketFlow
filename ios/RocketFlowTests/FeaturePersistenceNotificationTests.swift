import Foundation
import GRDB
import XCTest
@testable import RocketFlow

final class FeaturePersistenceNotificationTests: XCTestCase {
    func testReminderDefinitionsDefaultsAndReconciliationSurviveReopen() async throws {
        let url = featureNotificationTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let accountID = UUID()
        let taskID = UUID()
        let reminder = LocalTaskReminder(
            id: UUID(),
            accountID: accountID,
            taskID: taskID,
            taskTitle: "Durable reminder",
            triggerAt: Date(timeIntervalSince1970: 1_787_001_200),
            repeatRule: .monthly
        )
        let defaultReminder = DefaultTaskReminder(
            accountID: accountID,
            offsetMinutes: 60,
            repeatRule: .daily,
            enabled: true
        )
        let reconciledAt = Date(timeIntervalSince1970: 1_787_001_800)
        do {
            let database = try featureNotificationFileDatabase(at: url)
            let store = try GRDBTaskReminderStore(database: database, accountID: accountID)
            try await store.save(reminder, taskState: .active)
            try await store.saveDefault(defaultReminder)
            try await store.recordReconciliation(
                accountID: accountID,
                reason: .timezoneChange,
                at: reconciledAt
            )
        }

        let reopened = try featureNotificationFileDatabase(at: url)
        let store = try GRDBTaskReminderStore(database: reopened, accountID: accountID)
        let reminders = try await store.reminders(accountID: accountID)
        let defaultValue = try await store.defaultReminder(accountID: accountID)
        let state = try await store.reconciliationState(accountID: accountID)
        XCTAssertEqual(reminders, [reminder])
        XCTAssertEqual(defaultValue, defaultReminder)
        XCTAssertEqual(state, FeatureReminderReconciliationState(
            reason: .timezoneChange,
            reconciledAt: reconciledAt
        ))

        try await store.remove(accountID: accountID, taskID: taskID, reminderID: reminder.id)
        try await store.clearDefault(accountID: accountID)
        let emptyReminders = try await store.reminders(accountID: accountID)
        let emptyDefault = try await store.defaultReminder(accountID: accountID)
        XCTAssertTrue(emptyReminders.isEmpty)
        XCTAssertNil(emptyDefault)
    }

    func testRemoteNotificationDedupeIsAccountScopedAndExpiresAfterFourteenDays() async throws {
        let database = try AppDatabase.inMemory()
        let accountA = UUID()
        let accountB = UUID()
        let eventID = UUID()
        let start = Date(timeIntervalSince1970: 1_787_001_200)
        let storeA = try GRDBFocusNotificationEventStore(database: database, accountID: accountA)
        let storeB = try GRDBFocusNotificationEventStore(database: database, accountID: accountB)

        let firstA = try await storeA.markIfNew(eventID: eventID, now: start)
        let duplicateA = try await storeA.markIfNew(
            eventID: eventID,
            now: start.addingTimeInterval(13 * 24 * 60 * 60)
        )
        let firstB = try await storeB.markIfNew(eventID: eventID, now: start)
        let boundaryA = try await storeA.markIfNew(
            eventID: eventID,
            now: start.addingTimeInterval(14 * 24 * 60 * 60)
        )
        let expiredA = try await storeA.markIfNew(
            eventID: eventID,
            now: start.addingTimeInterval(14 * 24 * 60 * 60 + 0.001)
        )

        XCTAssertTrue(firstA)
        XCTAssertFalse(duplicateA)
        XCTAssertTrue(firstB)
        XCTAssertFalse(boundaryA)
        XCTAssertTrue(expiredA)
    }

    func testDedupeRejectsInvalidRetentionAndRepairsCorruptTimestamp() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        XCTAssertThrowsError(
            try GRDBFocusNotificationEventStore(
                database: database,
                accountID: accountID,
                retention: 0
            )
        ) { error in
            XCTAssertEqual(error as? FeaturePersistenceError, .invalidRetention)
        }

        let store = try GRDBFocusNotificationEventStore(database: database, accountID: accountID)
        let eventID = UUID()
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO feature_remote_notification_events (accountID, eventID, seenAt)
                    VALUES (?, ?, 'not-a-date')
                    """,
                arguments: [accountID.featurePersistenceKey, eventID.featurePersistenceKey]
            )
        }
        let repaired = try await store.markIfNew(
            eventID: eventID,
            now: Date(timeIntervalSince1970: 1_787_001_200)
        )
        XCTAssertTrue(repaired)
    }

    func testCorruptReminderRowsSurfaceIssueAndRequireExplicitQuarantine() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        let store = try GRDBTaskReminderStore(database: database, accountID: accountID)
        let corruptTaskID = UUID()
        let corruptReminderID = UUID()
        let valid = LocalTaskReminder(
            id: UUID(),
            accountID: accountID,
            taskID: UUID(),
            taskTitle: "Valid",
            triggerAt: Date(timeIntervalSince1970: 1_787_001_200),
            repeatRule: .none
        )
        try await store.save(valid, taskState: .active)
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO feature_task_reminders
                    (accountID, taskID, reminderID, payloadJSON, taskState, updatedAt)
                    VALUES (?, ?, ?, ?, 'active', ?)
                    """,
                arguments: [
                    accountID.featurePersistenceKey,
                    corruptTaskID.featurePersistenceKey,
                    corruptReminderID.featurePersistenceKey,
                    Data("corrupt".utf8),
                    WireDateCodec.encode(Date())
                ]
            )
        }

        do {
            _ = try await store.reminders(accountID: accountID)
            XCTFail("Expected durable reminder corruption")
        } catch {
            XCTAssertEqual(
                error as? FeaturePersistenceError,
                .corruptRecord(
                    table: "feature_task_reminders",
                    key: "\(corruptTaskID.featurePersistenceKey):\(corruptReminderID.featurePersistenceKey)"
                )
            )
        }
        let issues = try await store.corruptionIssues(accountID: accountID)
        XCTAssertEqual(issues.count, 1)
        try await store.quarantineCorruptReminder(
            accountID: accountID,
            taskID: corruptTaskID,
            reminderID: corruptReminderID
        )
        let reminders = try await store.reminders(accountID: accountID)
        XCTAssertEqual(reminders, [valid])
    }

    func testCorruptDefaultReminderThrowsUntilCleared() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        let store = try GRDBTaskReminderStore(database: database, accountID: accountID)
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO feature_default_reminders (accountID, payloadJSON, updatedAt)
                    VALUES (?, ?, ?)
                    """,
                arguments: [
                    accountID.featurePersistenceKey,
                    Data("corrupt".utf8),
                    WireDateCodec.encode(Date())
                ]
            )
        }

        do {
            _ = try await store.defaultReminder(accountID: accountID)
            XCTFail("Expected durable default corruption")
        } catch {
            XCTAssertEqual(
                error as? FeaturePersistenceError,
                .corruptRecord(table: "feature_default_reminders", key: "singleton")
            )
        }
        try await store.clearDefault(accountID: accountID)
        let cleared = try await store.defaultReminder(accountID: accountID)
        XCTAssertNil(cleared)
    }

    func testCorruptReconciliationStateThrowsUntilAValidStateRepairsIt() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        let now = Date(timeIntervalSince1970: 1_787_001_200)
        let store = try GRDBTaskReminderStore(
            database: database,
            accountID: accountID,
            now: { now }
        )
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO feature_reminder_reconciliation (accountID, reason, reconciledAt)
                    VALUES (?, 'invalid', 'not-a-date')
                    """,
                arguments: [accountID.featurePersistenceKey]
            )
        }

        do {
            _ = try await store.reconciliationState(accountID: accountID)
            XCTFail("Expected durable reconciliation corruption")
        } catch {
            XCTAssertEqual(
                error as? FeaturePersistenceError,
                .corruptRecord(table: "feature_reminder_reconciliation", key: "singleton")
            )
        }
        let corruption = try await store.corruptionIssues(accountID: accountID)
        XCTAssertEqual(corruption.map(\.tableName), ["feature_reminder_reconciliation"])

        try await store.recordReconciliation(accountID: accountID, reason: .launch, at: now)
        let repaired = try await store.reconciliationState(accountID: accountID)
        let repairedIssues = try await store.corruptionIssues(accountID: accountID)
        XCTAssertEqual(repaired, FeatureReminderReconciliationState(reason: .launch, reconciledAt: now))
        XCTAssertTrue(repairedIssues.isEmpty)
    }

    func testReminderProtocolClearIsAtomicEvenWithCorruptRows() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        let store = try GRDBTaskReminderStore(database: database, accountID: accountID)
        let protocolStore: any TaskReminderStoreServing = store
        let valid = LocalTaskReminder(
            id: UUID(),
            accountID: accountID,
            taskID: UUID(),
            taskTitle: "Valid",
            triggerAt: Date(timeIntervalSince1970: 1_787_001_200),
            repeatRule: .none
        )
        try await store.save(valid, taskState: .active)
        try await store.saveDefault(DefaultTaskReminder(
            accountID: accountID,
            offsetMinutes: 30,
            repeatRule: .none,
            enabled: true
        ))
        try await store.recordReconciliation(
            accountID: accountID,
            reason: .launch,
            at: Date(timeIntervalSince1970: 1_787_001_200)
        )
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO feature_task_reminders
                    (accountID, taskID, reminderID, payloadJSON, taskState, updatedAt)
                    VALUES (?, ?, ?, ?, 'active', ?)
                    """,
                arguments: [
                    accountID.featurePersistenceKey,
                    UUID().featurePersistenceKey,
                    UUID().featurePersistenceKey,
                    Data("corrupt".utf8),
                    WireDateCodec.encode(Date())
                ]
            )
        }

        try await protocolStore.clear(accountID: accountID)

        let reminders = try await store.reminders(accountID: accountID)
        let defaultReminder = try await store.defaultReminder(accountID: accountID)
        let reconciliation = try await store.reconciliationState(accountID: accountID)
        let issues = try await store.corruptionIssues(accountID: accountID)
        XCTAssertTrue(reminders.isEmpty)
        XCTAssertNil(defaultReminder)
        XCTAssertNil(reconciliation)
        XCTAssertTrue(issues.isEmpty)
    }

    func testConcurrentReminderWritesRemainAccountIsolated() async throws {
        let database = try AppDatabase.inMemory()
        let accountA = UUID()
        let accountB = UUID()
        let storeA = try GRDBTaskReminderStore(database: database, accountID: accountA)
        let storeB = try GRDBTaskReminderStore(database: database, accountID: accountB)
        let reminders = (0..<20).map { index in
            LocalTaskReminder(
                id: UUID(),
                accountID: index.isMultiple(of: 2) ? accountA : accountB,
                taskID: UUID(),
                taskTitle: "Reminder \(index)",
                triggerAt: Date(timeIntervalSince1970: 1_787_001_200 + TimeInterval(index)),
                repeatRule: .none
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for reminder in reminders {
                let store = reminder.accountID == accountA ? storeA : storeB
                group.addTask { try await store.save(reminder, taskState: .active) }
            }
            try await group.waitForAll()
        }

        let storedA = try await storeA.reminders(accountID: accountA)
        let storedB = try await storeB.reminders(accountID: accountB)
        XCTAssertEqual(storedA.count, 10)
        XCTAssertEqual(storedB.count, 10)
        XCTAssertTrue(storedA.allSatisfy { $0.accountID == accountA })
        XCTAssertTrue(storedB.allSatisfy { $0.accountID == accountB })
    }
}

private func featureNotificationTemporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("RocketFlowNotificationPersistence-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("RocketFlow.sqlite")
}

private func featureNotificationFileDatabase(at url: URL) throws -> AppDatabase {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    return try AppDatabase(writer: DatabaseQueue(path: url.path, configuration: configuration))
}
