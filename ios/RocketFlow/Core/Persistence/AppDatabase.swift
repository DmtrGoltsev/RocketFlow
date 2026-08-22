import Foundation
import GRDB

final class AppDatabase: @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try DatabaseSchema.migrator.migrate(writer)
        try writer.write { db in
            try db.execute(
                sql: """
                    UPDATE pending_mutations
                    SET state = ?, nextRetryAt = NULL, updatedAt = ?
                    WHERE state = ?
                    """,
                arguments: [
                    MutationState.queued.rawValue,
                    WireDateCodec.encode(Date()),
                    MutationState.inFlight.rawValue
                ]
            )
        }
    }

    static func inMemory() throws -> AppDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: ":memory:", configuration: configuration)
        return try AppDatabase(writer: queue)
    }

    func read<Value>(_ block: (Database) throws -> Value) throws -> Value {
        try writer.read(block)
    }

    func write<Value>(_ block: (Database) throws -> Value) throws -> Value {
        try writer.write(block)
    }

    func eraseUserData() throws {
        try write { db in
            for table in [
                "pending_mutations",
                "sync_conflicts",
                "entity_links",
                "idea_notes",
                "checklist_items",
                "task_tags",
                "tasks",
                "notes",
                "ideas",
                "goals",
                "tags",
                "folders",
                "collaboration_cache",
                "calendar_markers",
                "calendar_ranges",
                "settings_cache",
                "focus_cache",
                "entity_order",
                "id_mappings",
                "sync_metadata"
            ] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }
}

final class AppDatabaseFactory: @unchecked Sendable {
    private let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.rootURL = applicationSupport
                .appendingPathComponent("RocketFlow", isDirectory: true)
                .appendingPathComponent("Users", isDirectory: true)
        }
    }

    func open(userID: UUID) throws -> AppDatabase {
        let userDirectory = rootURL.appendingPathComponent(
            userID.uuidString.lowercased(),
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: userDirectory,
            withIntermediateDirectories: true
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDirectory = userDirectory
        try? mutableDirectory.setResourceValues(resourceValues)

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.maximumReaderCount = 4
        let databaseURL = userDirectory.appendingPathComponent("RocketFlow.sqlite")
        let pool = try DatabasePool(path: databaseURL.path, configuration: configuration)
        return try AppDatabase(writer: pool)
    }

    func inMemory() throws -> AppDatabase {
        try AppDatabase.inMemory()
    }
}
