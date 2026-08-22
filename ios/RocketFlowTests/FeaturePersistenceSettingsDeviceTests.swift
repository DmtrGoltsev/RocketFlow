import Foundation
import GRDB
import XCTest
@testable import RocketFlow

final class FeaturePersistenceSettingsDeviceTests: XCTestCase {
    func testSettingsAndPendingUpdatesAreIndependentAndAccountScoped() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        let cache = try GRDBSettingsCache(database: database, accountID: accountID)
        let otherAccountID = UUID()
        let settings = featurePersistenceSettings()
        let pending = PendingSettingsUpdate(language: .en, notificationsEnabled: false)
        try await cache.save(settings, accountID: accountID)
        try await cache.savePending(pending, accountID: accountID)

        let storedSettings = try await cache.settings(accountID: accountID)
        let storedPending = try await cache.pending(accountID: accountID)
        do {
            _ = try await cache.settings(accountID: otherAccountID)
            XCTFail("Expected scoped settings account mismatch")
        } catch {
            XCTAssertEqual(error as? FeaturePersistenceError, .accountMismatch)
        }
        let otherCache = try GRDBSettingsCache(database: database, accountID: otherAccountID)
        let otherSettings = try await otherCache.settings(accountID: otherAccountID)
        XCTAssertEqual(storedSettings, settings)
        XCTAssertEqual(storedPending, pending)
        XCTAssertNil(otherSettings)

        try await cache.clearPending(accountID: accountID)
        let retainedSettings = try await cache.settings(accountID: accountID)
        let clearedPending = try await cache.pending(accountID: accountID)
        XCTAssertEqual(retainedSettings, settings)
        XCTAssertNil(clearedPending)
    }

    func testDeviceSnapshotPersistsFCMInstallationDeviceAndRegistrationIDs() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        let registrationID = UUID()
        let store = try GRDBAccountDeviceRegistrationStateStore(
            database: database,
            accountID: accountID
        )
        let snapshot = DeviceRegistrationSnapshot(
            accountID: accountID,
            fcmToken: "test-fcm-token",
            installationID: "test-installation-id",
            deviceName: "Test iPhone",
            registration: DeviceRegistrationDTO(
                id: registrationID,
                platform: .ios,
                deviceName: "Test iPhone",
                active: true,
                createdAt: Date(timeIntervalSince1970: 1_787_001_200)
            )
        )
        try await store.save(snapshot)

        let stored = try await store.snapshot()
        XCTAssertEqual(stored, snapshot)
        let columns = try database.read { db -> (String?, String?, String?, String?) in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT fcmToken, installationID, deviceName, registrationID
                    FROM feature_device_registration_state WHERE accountID = ?
                    """,
                arguments: [accountID.featurePersistenceKey]
            ) else { return (nil, nil, nil, nil) }
            return (row["fcmToken"], row["installationID"], row["deviceName"], row["registrationID"])
        }
        XCTAssertEqual(columns.0, snapshot.fcmToken)
        XCTAssertEqual(columns.1, snapshot.installationID)
        XCTAssertEqual(columns.2, snapshot.deviceName)
        XCTAssertEqual(columns.3, registrationID.featurePersistenceKey)
    }

    func testDeviceStoreRejectsCrossAccountSnapshotAndClearIsScoped() async throws {
        let database = try AppDatabase.inMemory()
        let accountA = UUID()
        let accountB = UUID()
        let storeA = try GRDBAccountDeviceRegistrationStateStore(database: database, accountID: accountA)
        let storeB = try GRDBAccountDeviceRegistrationStateStore(database: database, accountID: accountB)
        let snapshotA = featureDeviceSnapshot(accountID: accountA)
        let snapshotB = featureDeviceSnapshot(accountID: accountB)
        try await storeA.save(snapshotA)
        try await storeB.save(snapshotB)

        do {
            try await storeA.save(snapshotB)
            XCTFail("Expected account mismatch")
        } catch {
            XCTAssertEqual(error as? FeaturePersistenceError, .accountMismatch)
        }
        try await storeA.clear()
        let clearedA = try await storeA.snapshot()
        let retainedB = try await storeB.snapshot()
        XCTAssertNil(clearedA)
        XCTAssertEqual(retainedB, snapshotB)
    }

    func testInstallationIdentityIsStableAndAccountScoped() async throws {
        let database = try AppDatabase.inMemory()
        let accountA = UUID()
        let accountB = UUID()
        let identityA = try GRDBInstallationIdentityStore(
            database: database,
            accountID: accountA,
            generator: { "installation-a" }
        )
        let identityB = try GRDBInstallationIdentityStore(
            database: database,
            accountID: accountB,
            generator: { "installation-b" }
        )

        let firstA = try await identityA.installationID()
        let secondA = try await identityA.installationID()
        let firstB = try await identityB.installationID()
        XCTAssertEqual(firstA, "installation-a")
        XCTAssertEqual(secondA, firstA)
        XCTAssertEqual(firstB, "installation-b")
    }

    func testCorruptSettingsAndDeviceRowsReturnEmptyState() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        try database.write { db in
            try FeaturePersistenceAccount.ensure(accountID, in: db)
            let timestamp = WireDateCodec.encode(Date())
            try db.execute(
                sql: """
                    INSERT INTO feature_settings_snapshots (accountID, payloadJSON, updatedAt)
                    VALUES (?, ?, ?)
                    """,
                arguments: [accountID.featurePersistenceKey, Data("bad".utf8), timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO feature_device_registration_state (
                        accountID, fcmToken, installationID, deviceName,
                        registrationID, payloadJSON, updatedAt
                    ) VALUES (?, 'opaque', 'install', NULL, ?, ?, ?)
                    """,
                arguments: [
                    accountID.featurePersistenceKey,
                    UUID().featurePersistenceKey,
                    Data("bad".utf8),
                    timestamp
                ]
            )
        }

        let settings = try GRDBSettingsCache(database: database, accountID: accountID)
        let device = try GRDBAccountDeviceRegistrationStateStore(
            database: database,
            accountID: accountID
        )
        let settingsValue = try await settings.settings(accountID: accountID)
        let deviceValue = try await device.snapshot()
        XCTAssertNil(settingsValue)
        XCTAssertNil(deviceValue)
    }

    func testCorruptPendingSettingsThrowsAndRequiresExplicitQuarantine() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        let cache = try GRDBSettingsCache(database: database, accountID: accountID)
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO feature_settings_pending (accountID, payloadJSON, updatedAt)
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
            _ = try await cache.pending(accountID: accountID)
            XCTFail("Expected durable pending settings corruption")
        } catch {
            XCTAssertEqual(
                error as? FeaturePersistenceError,
                .corruptRecord(table: "feature_settings_pending", key: "singleton")
            )
        }
        let issues = try await cache.corruptionIssues(accountID: accountID)
        XCTAssertEqual(issues.map(\.recordKey), ["singleton"])
        try await cache.quarantineCorruptPending(accountID: accountID)
        let recovered = try await cache.pending(accountID: accountID)
        XCTAssertNil(recovered)
    }
}

private func featurePersistenceSettings() -> UserSettingsDTO {
    UserSettingsDTO(
        language: .ru,
        greenPriorityDecayPolicy: PriorityDecayPolicyDTO(
            taskType: "green",
            enabled: false,
            thresholdPreset: "day",
            decayAmount: 1
        ),
        redPriorityDecayPolicy: nil,
        notificationsEnabled: true,
        version: 7
    )
}

private func featureDeviceSnapshot(accountID: UUID) -> DeviceRegistrationSnapshot {
    DeviceRegistrationSnapshot(
        accountID: accountID,
        fcmToken: "test-token-\(accountID.uuidString)",
        installationID: "test-installation-\(accountID.uuidString)",
        deviceName: nil,
        registration: DeviceRegistrationDTO(
            id: UUID(),
            platform: .ios,
            deviceName: nil,
            active: true,
            createdAt: Date(timeIntervalSince1970: 1_787_001_200)
        )
    )
}
