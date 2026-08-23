import Foundation
import GRDB

actor GRDBCalendarRangeCache: CalendarRangeCaching {
    private let database: AppDatabase
    private let lease: FeaturePersistenceLease

    init(database: AppDatabase, accountID: UUID) throws {
        self.database = database
        lease = try database.write { db in
            try FeaturePersistenceAccount.acquire(accountID, in: db)
        }
    }

    func load(_ key: CalendarRangeKey) throws -> CalendarMarkersResponseDTO? {
        try lease.require(key.accountID)
        let payload: Data? = try database.read { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            return try Data.fetchOne(
                db,
                sql: """
                    SELECT payloadJSON
                    FROM feature_calendar_ranges
                    WHERE accountID = ? AND timezoneID = ?
                      AND fromDate = ? AND toExclusive = ?
                    """,
                arguments: [
                    key.accountID.featurePersistenceKey,
                    key.timezoneID,
                    key.from.rawValue,
                    key.toExclusive.rawValue
                ]
            )
        }
        guard let payload else { return nil }
        guard let response = FeaturePersistenceJSON.decode(
            CalendarMarkersResponseDTO.self,
            from: payload
        ), response.from == key.from,
           response.toExclusive == key.toExclusive,
           TimeZone(identifier: response.timezone)?.identifier == key.timezoneID else {
            return nil
        }
        return response
    }

    func save(_ response: CalendarMarkersResponseDTO, for key: CalendarRangeKey) throws {
        try lease.require(key.accountID)
        guard response.from == key.from,
              response.toExclusive == key.toExclusive,
              TimeZone(identifier: response.timezone)?.identifier == key.timezoneID else {
            throw FeaturePersistenceError.snapshotKeyMismatch
        }
        let payload = try FeaturePersistenceJSON.encode(response)
        let timestamp = WireDateCodec.encode(Date())
        try database.write { db in
            try FeaturePersistenceAccount.validate(lease, in: db)
            try db.execute(
                sql: """
                    INSERT INTO feature_calendar_ranges (
                        accountID, timezoneID, fromDate, toExclusive, payloadJSON, updatedAt
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(accountID, timezoneID, fromDate, toExclusive)
                    DO UPDATE SET payloadJSON = excluded.payloadJSON, updatedAt = excluded.updatedAt
                    """,
                arguments: [
                    key.accountID.featurePersistenceKey,
                    key.timezoneID,
                    key.from.rawValue,
                    key.toExclusive.rawValue,
                    payload,
                    timestamp
                ]
            )
        }
    }
}
