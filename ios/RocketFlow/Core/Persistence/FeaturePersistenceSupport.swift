import Foundation
import GRDB

enum FeaturePersistenceError: Error, Equatable, Sendable {
    case accountMismatch
    case accountLeaseRevoked
    case duplicateActionID
    case snapshotKeyMismatch
    case corruptRecord(table: String, key: String)
    case corruptHeadMismatch
    case invalidRetention
}

struct FeaturePersistenceLease: Equatable, Sendable {
    let accountID: UUID
    let generation: Int64

    func require(_ accountID: UUID) throws {
        guard self.accountID == accountID else {
            throw FeaturePersistenceError.accountMismatch
        }
    }
}

struct FeaturePersistenceCorruptionIssue: Equatable, Identifiable, Sendable {
    var id: String { "\(tableName):\(recordKey)" }
    let accountID: UUID
    let tableName: String
    let recordKey: String
    let code: String
    let detectedAt: Date
}

enum FeaturePersistenceJSON {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        try WireJSON.encoder().encode(value)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) -> Value? {
        try? WireJSON.decoder().decode(type, from: data)
    }

    static func decodeRequired<Value: Decodable>(
        _ type: Value.Type,
        from data: Data,
        table: String,
        key: String
    ) throws -> Value {
        do {
            return try WireJSON.decoder().decode(type, from: data)
        } catch {
            throw FeaturePersistenceError.corruptRecord(table: table, key: key)
        }
    }
}

enum FeaturePersistenceAccount {
    @discardableResult
    static func acquire(_ accountID: UUID, in db: Database, at date: Date = Date()) throws
        -> FeaturePersistenceLease {
        let timestamp = WireDateCodec.encode(date)
        try db.execute(
            sql: """
                INSERT INTO feature_account_leases (accountID, generation, updatedAt)
                VALUES (?, 0, ?)
                ON CONFLICT(accountID) DO NOTHING
                """,
            arguments: [accountID.featurePersistenceKey, timestamp]
        )
        guard let generation = try Int64.fetchOne(
            db,
            sql: "SELECT generation FROM feature_account_leases WHERE accountID = ?",
            arguments: [accountID.featurePersistenceKey]
        ) else {
            throw FeaturePersistenceError.accountLeaseRevoked
        }
        let lease = FeaturePersistenceLease(accountID: accountID, generation: generation)
        try activate(lease, in: db, at: date)
        return lease
    }

    @discardableResult
    static func ensure(_ accountID: UUID, in db: Database, at date: Date = Date()) throws
        -> FeaturePersistenceLease {
        try acquire(accountID, in: db, at: date)
    }

    static func validate(_ lease: FeaturePersistenceLease, in db: Database) throws {
        let generation = try Int64.fetchOne(
            db,
            sql: "SELECT generation FROM feature_account_leases WHERE accountID = ?",
            arguments: [lease.accountID.featurePersistenceKey]
        )
        let accountGeneration = try Int64.fetchOne(
            db,
            sql: "SELECT generation FROM feature_accounts WHERE accountID = ?",
            arguments: [lease.accountID.featurePersistenceKey]
        )
        guard generation == lease.generation, accountGeneration == lease.generation else {
            throw FeaturePersistenceError.accountLeaseRevoked
        }
    }

    static func revoke(_ accountID: UUID, in db: Database, at date: Date = Date()) throws {
        let timestamp = WireDateCodec.encode(date)
        try db.execute(
            sql: "DELETE FROM feature_accounts WHERE accountID = ?",
            arguments: [accountID.featurePersistenceKey]
        )
        try db.execute(
            sql: """
                INSERT INTO feature_account_leases (accountID, generation, updatedAt)
                VALUES (?, 1, ?)
                ON CONFLICT(accountID) DO UPDATE SET
                    generation = feature_account_leases.generation + 1,
                    updatedAt = excluded.updatedAt
                """,
            arguments: [accountID.featurePersistenceKey, timestamp]
        )
    }

    private static func activate(
        _ lease: FeaturePersistenceLease,
        in db: Database,
        at date: Date
    ) throws {
        let timestamp = WireDateCodec.encode(date)
        if let existing = try Int64.fetchOne(
            db,
            sql: "SELECT generation FROM feature_accounts WHERE accountID = ?",
            arguments: [lease.accountID.featurePersistenceKey]
        ) {
            guard existing == lease.generation else {
                throw FeaturePersistenceError.accountLeaseRevoked
            }
            try db.execute(
                sql: "UPDATE feature_accounts SET updatedAt = ? WHERE accountID = ?",
                arguments: [timestamp, lease.accountID.featurePersistenceKey]
            )
            return
        }
        try db.execute(
            sql: """
                INSERT INTO feature_accounts (accountID, generation, createdAt, updatedAt)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [
                lease.accountID.featurePersistenceKey,
                lease.generation,
                timestamp,
                timestamp
            ]
        )
    }
}

enum FeaturePersistenceCorruption {
    static func record(
        lease: FeaturePersistenceLease,
        table: String,
        key: String,
        code: String = "corrupt_payload",
        at date: Date,
        in db: Database
    ) throws {
        try FeaturePersistenceAccount.validate(lease, in: db)
        try db.execute(
            sql: """
                INSERT INTO feature_persistence_corruptions (
                    accountID, tableName, recordKey, code, detectedAt
                ) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(accountID, tableName, recordKey) DO UPDATE SET
                    code = excluded.code, detectedAt = excluded.detectedAt
                """,
            arguments: [
                lease.accountID.featurePersistenceKey,
                table,
                key,
                code,
                WireDateCodec.encode(date)
            ]
        )
    }

    static func issues(lease: FeaturePersistenceLease, in db: Database) throws
        -> [FeaturePersistenceCorruptionIssue] {
        try FeaturePersistenceAccount.validate(lease, in: db)
        return try Row.fetchAll(
            db,
            sql: """
                SELECT tableName, recordKey, code, detectedAt
                FROM feature_persistence_corruptions
                WHERE accountID = ?
                ORDER BY detectedAt ASC, tableName ASC, recordKey ASC
                """,
            arguments: [lease.accountID.featurePersistenceKey]
        ).map { row in
            let table: String = row["tableName"]
            let key: String = row["recordKey"]
            let rawDate: String = row["detectedAt"]
            guard let date = try? WireDateCodec.decode(rawDate) else {
                throw FeaturePersistenceError.corruptRecord(
                    table: "feature_persistence_corruptions",
                    key: "\(table):\(key)"
                )
            }
            return FeaturePersistenceCorruptionIssue(
                accountID: lease.accountID,
                tableName: table,
                recordKey: key,
                code: row["code"],
                detectedAt: date
            )
        }
    }
}

actor GRDBFeaturePersistenceCleaner {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func clear(accountID: UUID) throws {
        try database.write { db in
            try FeaturePersistenceAccount.revoke(accountID, in: db)
        }
    }
}

extension UUID {
    var featurePersistenceKey: String { uuidString.lowercased() }
}
