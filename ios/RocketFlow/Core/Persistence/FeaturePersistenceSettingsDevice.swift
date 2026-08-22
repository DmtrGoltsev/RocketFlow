import Foundation
import GRDB

actor GRDBSettingsCache: SettingsCacheServing {
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

    func settings(accountID: UUID) throws -> UserSettingsDTO? {
        try load(UserSettingsDTO.self, table: "feature_settings_snapshots", accountID: accountID)
    }

    func save(_ settings: UserSettingsDTO, accountID: UUID) throws {
        try save(settings, table: "feature_settings_snapshots", accountID: accountID)
    }

    func pending(accountID: UUID) throws -> PendingSettingsUpdate? {
        try loadDurablePending(accountID: accountID)
    }

    func savePending(_ pending: PendingSettingsUpdate, accountID: UUID) throws {
        try save(pending, table: "feature_settings_pending", accountID: accountID)
    }

    func clearPending(accountID: UUID) throws {
        try lease.require(accountID)
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try db.execute(
                sql: "DELETE FROM feature_settings_pending WHERE accountID = ?",
                arguments: [accountID.featurePersistenceKey]
            )
            try db.execute(
                sql: """
                    DELETE FROM feature_persistence_corruptions
                    WHERE accountID = ? AND tableName = 'feature_settings_pending'
                """,
                arguments: [accountID.featurePersistenceKey]
            )
        }
    }

    func corruptionIssues(accountID: UUID) throws -> [FeaturePersistenceCorruptionIssue] {
        try lease.require(accountID)
        return try database.read { db in
            try FeaturePersistenceCorruption.issues(lease: lease, in: db)
        }.filter { $0.tableName == "feature_settings_pending" }
    }

    func quarantineCorruptPending(accountID: UUID) throws {
        try lease.require(accountID)
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            guard let payload = try Data.fetchOne(
                db,
                sql: "SELECT payloadJSON FROM feature_settings_pending WHERE accountID = ?",
                arguments: [accountID.featurePersistenceKey]
            ) else { return }
            guard FeaturePersistenceJSON.decode(PendingSettingsUpdate.self, from: payload) == nil else {
                throw FeaturePersistenceError.corruptHeadMismatch
            }
            try FeaturePersistenceCorruption.record(
                lease: lease,
                table: "feature_settings_pending",
                key: "singleton",
                at: now(),
                in: db
            )
            try db.execute(
                sql: "DELETE FROM feature_settings_pending WHERE accountID = ?",
                arguments: [accountID.featurePersistenceKey]
            )
        }
    }

    private func load<Value: Decodable>(
        _ type: Value.Type,
        table: String,
        accountID: UUID
    ) throws -> Value? {
        try lease.require(accountID)
        let payload: Data? = try database.read { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try Data.fetchOne(
                db,
                sql: "SELECT payloadJSON FROM \(table) WHERE accountID = ?",
                arguments: [accountID.featurePersistenceKey]
            )
        }
        guard let payload else { return nil }
        return FeaturePersistenceJSON.decode(type, from: payload)
    }

    private func loadDurablePending(accountID: UUID) throws -> PendingSettingsUpdate? {
        try lease.require(accountID)
        let result: Result<PendingSettingsUpdate?, FeaturePersistenceError> = try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            guard let payload = try Data.fetchOne(
                db,
                sql: "SELECT payloadJSON FROM feature_settings_pending WHERE accountID = ?",
                arguments: [accountID.featurePersistenceKey]
            ) else { return .success(nil) }
            do {
                return .success(try FeaturePersistenceJSON.decodeRequired(
                    PendingSettingsUpdate.self,
                    from: payload,
                    table: "feature_settings_pending",
                    key: "singleton"
                ))
            } catch let corruption as FeaturePersistenceError {
                try FeaturePersistenceCorruption.record(
                    lease: lease,
                    table: "feature_settings_pending",
                    key: "singleton",
                    at: now(),
                    in: db
                )
                return .failure(corruption)
            }
        }
        return try result.get()
    }

    private func save<Value: Encodable>(
        _ value: Value,
        table: String,
        accountID: UUID
    ) throws {
        try lease.require(accountID)
        let payload = try FeaturePersistenceJSON.encode(value)
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try db.execute(
                sql: """
                    INSERT INTO \(table) (accountID, payloadJSON, updatedAt)
                    VALUES (?, ?, ?)
                    ON CONFLICT(accountID) DO UPDATE SET
                        payloadJSON = excluded.payloadJSON, updatedAt = excluded.updatedAt
                    """,
                arguments: [accountID.featurePersistenceKey, payload, WireDateCodec.encode(now())]
            )
            if table == "feature_settings_pending" {
                try db.execute(
                    sql: """
                        DELETE FROM feature_persistence_corruptions
                        WHERE accountID = ? AND tableName = ? AND recordKey = 'singleton'
                    """,
                    arguments: [accountID.featurePersistenceKey, table]
                )
            }
        }
    }
}

actor GRDBAccountDeviceRegistrationStateStore: DeviceRegistrationStateStoring {
    private let database: AppDatabase
    private let accountID: UUID
    private let lease: FeaturePersistenceLease
    private let now: @Sendable () -> Date

    init(
        database: AppDatabase,
        accountID: UUID,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        self.database = database
        self.accountID = accountID
        self.now = now
        lease = try database.write { db in
            try FeaturePersistenceAccount.acquire(accountID, in: db, at: now())
        }
    }

    func snapshot() throws -> DeviceRegistrationSnapshot? {
        let payload: Data? = try database.read { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try Data.fetchOne(
                db,
                sql: """
                    SELECT payloadJSON FROM feature_device_registration_state
                    WHERE accountID = ?
                    """,
                arguments: [accountID.featurePersistenceKey]
            )
        }
        guard let payload,
              let snapshot = FeaturePersistenceJSON.decode(DeviceRegistrationSnapshot.self, from: payload),
              snapshot.accountID == accountID else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: DeviceRegistrationSnapshot) throws {
        guard snapshot.accountID == accountID else {
            throw FeaturePersistenceError.accountMismatch
        }
        let payload = try FeaturePersistenceJSON.encode(snapshot)
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try db.execute(
                sql: """
                    INSERT INTO feature_device_registration_state (
                        accountID, fcmToken, installationID, deviceName,
                        registrationID, payloadJSON, updatedAt
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(accountID) DO UPDATE SET
                        fcmToken = excluded.fcmToken,
                        installationID = excluded.installationID,
                        deviceName = excluded.deviceName,
                        registrationID = excluded.registrationID,
                        payloadJSON = excluded.payloadJSON,
                        updatedAt = excluded.updatedAt
                    """,
                arguments: [
                    accountID.featurePersistenceKey,
                    snapshot.fcmToken,
                    snapshot.installationID,
                    snapshot.deviceName,
                    snapshot.registration.id.featurePersistenceKey,
                    payload,
                    WireDateCodec.encode(now())
                ]
            )
        }
    }

    func clear() throws {
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try db.execute(
                sql: "DELETE FROM feature_device_registration_state WHERE accountID = ?",
                arguments: [accountID.featurePersistenceKey]
            )
        }
    }
}

actor GRDBInstallationIdentityStore: InstallationIdentityProviding {
    private let database: AppDatabase
    private let accountID: UUID
    private let lease: FeaturePersistenceLease
    private let generator: @Sendable () -> String

    init(
        database: AppDatabase,
        accountID: UUID,
        generator: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) throws {
        self.database = database
        self.accountID = accountID
        self.generator = generator
        lease = try database.write { db in
            try FeaturePersistenceAccount.acquire(accountID, in: db)
        }
    }

    func installationID() throws -> String {
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            if let existing = try String.fetchOne(
                db,
                sql: """
                    SELECT installationID FROM feature_installation_identity
                    WHERE accountID = ?
                    """,
                arguments: [accountID.featurePersistenceKey]
            ), !existing.isEmpty {
                return existing
            }
            let created = generator()
            try db.execute(
                sql: """
                    INSERT INTO feature_installation_identity (accountID, installationID, updatedAt)
                    VALUES (?, ?, ?)
                    ON CONFLICT(accountID) DO UPDATE SET
                        installationID = excluded.installationID, updatedAt = excluded.updatedAt
                    """,
                arguments: [
                    accountID.featurePersistenceKey,
                    created,
                    WireDateCodec.encode(Date())
                ]
            )
            return created
        }
    }
}
