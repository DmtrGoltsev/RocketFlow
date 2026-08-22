import Foundation
import GRDB
import XCTest
@testable import RocketFlow

final class FeaturePersistenceMigrationTests: XCTestCase {
    func testFeatureMigrationAppliesAdditivelyToPreviouslyMigratedDatabase() throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: ":memory:", configuration: configuration)
        try DatabaseSchema.preFeaturePersistenceMigrator.migrate(queue)
        let existingEntityID = UUID().featurePersistenceKey
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO entity_order (entityType, entityID, position)
                    VALUES ('task', ?, 7)
                    """,
                arguments: [existingEntityID]
            )
        }

        try DatabaseSchema.migrator.migrate(queue)
        try DatabaseSchema.migrator.migrate(queue)

        let tables = try queue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
        }
        for table in featurePersistenceTables {
            XCTAssertTrue(tables.contains(table), "Missing table: \(table)")
        }
        let retainedPosition = try queue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT position FROM entity_order WHERE entityType = 'task' AND entityID = ?",
                arguments: [existingEntityID]
            )
        }
        XCTAssertEqual(retainedPosition, 7)
    }

    func testFeatureRowsRequireAnAccountForeignKey() throws {
        let database = try AppDatabase.inMemory()
        XCTAssertThrowsError(try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO feature_calendar_ranges (
                        accountID, timezoneID, fromDate, toExclusive, payloadJSON, updatedAt
                    ) VALUES (?, 'UTC', '2026-08-01', '2026-09-01', ?, ?)
                    """,
                arguments: [UUID().featurePersistenceKey, Data(), WireDateCodec.encode(Date())]
            )
        })
    }

    func testAccountCleanupCascadesOnlySelectedAccount() async throws {
        let database = try AppDatabase.inMemory()
        let accountA = UUID()
        let accountB = UUID()
        let cacheA = try GRDBSettingsCache(database: database, accountID: accountA)
        let cacheB = try GRDBSettingsCache(database: database, accountID: accountB)
        let cleaner = GRDBFeaturePersistenceCleaner(database: database)
        let settingsA = featureTestSettings(language: .ru, version: 1)
        let settingsB = featureTestSettings(language: .en, version: 2)
        try await cacheA.save(settingsA, accountID: accountA)
        try await cacheB.save(settingsB, accountID: accountB)

        try await cleaner.clear(accountID: accountA)

        do {
            _ = try await cacheA.settings(accountID: accountA)
            XCTFail("Expected revoked account lease")
        } catch {
            XCTAssertEqual(error as? FeaturePersistenceError, .accountLeaseRevoked)
        }
        let reopenedA = try GRDBSettingsCache(database: database, accountID: accountA)
        let deleted = try await reopenedA.settings(accountID: accountA)
        let retained = try await cacheB.settings(accountID: accountB)
        XCTAssertNil(deleted)
        XCTAssertEqual(retained, settingsB)
    }

    func testAccountCleanupCascadesEveryFeatureTableAndRetainsLeaseTombstone() async throws {
        let database = try AppDatabase.inMemory()
        let accountA = UUID()
        let accountB = UUID()
        try database.write { db in
            try insertFeaturePersistenceRows(accountID: accountA, in: db)
            try insertFeaturePersistenceRows(accountID: accountB, in: db)
        }

        let cleaner = GRDBFeaturePersistenceCleaner(database: database)
        try await cleaner.clear(accountID: accountA)

        try database.read { db in
            for table in featurePersistenceChildTables {
                let deleted = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM \(table) WHERE accountID = ?",
                    arguments: [accountA.featurePersistenceKey]
                )
                let retained = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM \(table) WHERE accountID = ?",
                    arguments: [accountB.featurePersistenceKey]
                )
                XCTAssertEqual(deleted, 0, "Not cascaded: \(table)")
                XCTAssertEqual(retained, 1, "Removed wrong account: \(table)")
            }
            let generationA = try Int64.fetchOne(
                db,
                sql: "SELECT generation FROM feature_account_leases WHERE accountID = ?",
                arguments: [accountA.featurePersistenceKey]
            )
            let generationB = try Int64.fetchOne(
                db,
                sql: "SELECT generation FROM feature_account_leases WHERE accountID = ?",
                arguments: [accountB.featurePersistenceKey]
            )
            XCTAssertEqual(generationA, 1)
            XCTAssertEqual(generationB, 0)
        }
    }

    func testConcurrentCleanupCannotBeUndoneByStaleMultiInstanceWriters() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        let staleSettings = try GRDBSettingsCache(database: database, accountID: accountID)
        let staleReminders = try GRDBTaskReminderStore(database: database, accountID: accountID)
        let cleaner = GRDBFeaturePersistenceCleaner(database: database)
        let settings = featureTestSettings(language: .ru, version: 1)
        let reminder = LocalTaskReminder(
            id: UUID(),
            accountID: accountID,
            taskID: UUID(),
            taskTitle: "Race",
            triggerAt: Date(timeIntervalSince1970: 1_787_001_200),
            repeatRule: .none
        )

        let settingsWrite = Task {
            try? await staleSettings.save(settings, accountID: accountID)
        }
        let reminderWrite = Task {
            try? await staleReminders.save(reminder, taskState: .active)
        }
        let cleanup = Task {
            try await cleaner.clear(accountID: accountID)
        }
        _ = await settingsWrite.value
        _ = await reminderWrite.value
        try await cleanup.value

        do {
            try await staleSettings.save(settings, accountID: accountID)
            XCTFail("Expected stale settings lease to stay revoked")
        } catch {
            XCTAssertEqual(error as? FeaturePersistenceError, .accountLeaseRevoked)
        }
        do {
            try await staleReminders.save(reminder, taskState: .active)
            XCTFail("Expected stale reminder lease to stay revoked")
        } catch {
            XCTAssertEqual(error as? FeaturePersistenceError, .accountLeaseRevoked)
        }

        let remaining = try database.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM feature_accounts WHERE accountID = ?",
                arguments: [accountID.featurePersistenceKey]
            )
        }
        XCTAssertEqual(remaining, 0)

        let fresh = try GRDBSettingsCache(database: database, accountID: accountID)
        try await fresh.save(settings, accountID: accountID)
        let restored = try await fresh.settings(accountID: accountID)
        XCTAssertEqual(restored, settings)
    }
}

private let featurePersistenceTables: Set<String> = [
    "feature_account_leases",
    "feature_accounts",
    "feature_calendar_ranges",
    "feature_focus_snapshots",
    "feature_focus_actions",
    "feature_focus_terminal_issues",
    "feature_task_reminders",
    "feature_default_reminders",
    "feature_reminder_reconciliation",
    "feature_remote_notification_events",
    "feature_settings_snapshots",
    "feature_settings_pending",
    "feature_device_registration_state",
    "feature_installation_identity",
    "feature_persistence_corruptions"
]

private let featurePersistenceChildTables = [
    "feature_calendar_ranges",
    "feature_focus_snapshots",
    "feature_focus_actions",
    "feature_focus_terminal_issues",
    "feature_task_reminders",
    "feature_default_reminders",
    "feature_reminder_reconciliation",
    "feature_remote_notification_events",
    "feature_settings_snapshots",
    "feature_settings_pending",
    "feature_device_registration_state",
    "feature_installation_identity",
    "feature_persistence_corruptions"
]

private func insertFeaturePersistenceRows(accountID: UUID, in db: Database) throws {
    let account = accountID.featurePersistenceKey
    let timestamp = WireDateCodec.encode(Date(timeIntervalSince1970: 1_787_001_200))
    let payload = Data("fixture".utf8)
    _ = try FeaturePersistenceAccount.ensure(accountID, in: db)
    try db.execute(
        sql: "INSERT INTO feature_calendar_ranges VALUES (?, 'UTC', '2026-08-01', '2026-09-01', ?, ?)",
        arguments: [account, payload, timestamp]
    )
    try db.execute(
        sql: "INSERT INTO feature_focus_snapshots VALUES (?, 'current', '', ?, ?)",
        arguments: [account, payload, timestamp]
    )
    try db.execute(
        sql: """
            INSERT INTO feature_focus_actions VALUES
            (?, ?, 'reorder', ?, 1, 0, 0, NULL, NULL, 0, ?, ?)
            """,
        arguments: [account, UUID().featurePersistenceKey, payload, timestamp, timestamp]
    )
    try db.execute(
        sql: "INSERT INTO feature_focus_terminal_issues VALUES (?, ?, ?, ?)",
        arguments: [account, UUID().featurePersistenceKey, payload, timestamp]
    )
    try db.execute(
        sql: "INSERT INTO feature_task_reminders VALUES (?, ?, ?, ?, 'active', ?)",
        arguments: [account, UUID().featurePersistenceKey, UUID().featurePersistenceKey, payload, timestamp]
    )
    try db.execute(
        sql: "INSERT INTO feature_default_reminders VALUES (?, ?, ?)",
        arguments: [account, payload, timestamp]
    )
    try db.execute(
        sql: "INSERT INTO feature_reminder_reconciliation VALUES (?, 'launch', ?)",
        arguments: [account, timestamp]
    )
    try db.execute(
        sql: "INSERT INTO feature_remote_notification_events VALUES (?, ?, ?)",
        arguments: [account, UUID().featurePersistenceKey, timestamp]
    )
    try db.execute(
        sql: "INSERT INTO feature_settings_snapshots VALUES (?, ?, ?)",
        arguments: [account, payload, timestamp]
    )
    try db.execute(
        sql: "INSERT INTO feature_settings_pending VALUES (?, ?, ?)",
        arguments: [account, payload, timestamp]
    )
    try db.execute(
        sql: "INSERT INTO feature_device_registration_state VALUES (?, 'fcm', 'install', NULL, ?, ?, ?)",
        arguments: [account, UUID().featurePersistenceKey, payload, timestamp]
    )
    try db.execute(
        sql: "INSERT INTO feature_installation_identity VALUES (?, 'install', ?)",
        arguments: [account, timestamp]
    )
    try db.execute(
        sql: "INSERT INTO feature_persistence_corruptions VALUES (?, 'fixture', 'one', 'corrupt', ?)",
        arguments: [account, timestamp]
    )
}

private func featureTestSettings(
    language: AppLanguage,
    version: Int64
) -> UserSettingsDTO {
    UserSettingsDTO(
        language: language,
        greenPriorityDecayPolicy: nil,
        redPriorityDecayPolicy: nil,
        notificationsEnabled: true,
        version: version
    )
}
