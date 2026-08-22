import Foundation
import GRDB
import XCTest
@testable import RocketFlow

final class PersistenceTests: XCTestCase {
    func testFreshMigrationCreatesRequiredTables() throws {
        let database = try AppDatabase.inMemory()
        let tables = try database.read { db in
            Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
        }

        for table in [
            "folders", "goals", "tasks", "ideas", "notes", "checklist_items", "tags",
            "task_tags", "entity_links", "focus_cache", "settings_cache", "pending_mutations",
            "sync_conflicts", "sync_metadata", "entity_order"
        ] {
            XCTAssertTrue(tables.contains(table), "Missing table: \(table)")
        }
        let conflictColumns = try database.read { db in
            Set(try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('sync_conflicts')"))
        }
        XCTAssertTrue(conflictColumns.contains("serverDeleted"))
    }

    func testMigrationIsIdempotent() throws {
        let database = try AppDatabase.inMemory()
        XCTAssertNoThrow(try DatabaseSchema.migrator.migrate(database.writer))
        XCTAssertNoThrow(try DatabaseSchema.migrator.migrate(database.writer))
    }

    func testForeignKeysRejectOrphanGoal() throws {
        let database = try AppDatabase.inMemory()
        let draft = GoalDraft(folderID: UUID(), name: "Orphan")

        XCTAssertThrowsError(
            try database.write { db in try GoalRecord(draft: draft, now: Date()).insert(db) }
        )
    }

    func testFolderCascadeDeletesGoalAndTask() async throws {
        let database = try AppDatabase.inMemory()
        let repository = LocalPlanningRepository(database: database)
        let folder = try await repository.createFolder(FolderDraft(name: "Folder"))
        let goal = try await repository.createGoal(GoalDraft(folderID: folder.id, name: "Goal"))
        _ = try await repository.createTask(TaskDraft(goalID: goal.id, title: "Task"))

        try database.write { db in
            try db.execute(sql: "DELETE FROM folders WHERE id = ?", arguments: [folder.id.uuidString.lowercased()])
        }

        let counts = try database.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM goals") ?? -1,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks") ?? -1
            )
        }
        XCTAssertEqual(counts.0, 0)
        XCTAssertEqual(counts.1, 0)
    }

    func testTaskPriorityShadowDefaultsToCompatibilityValue() async throws {
        let database = try AppDatabase.inMemory()
        let repository = LocalPlanningRepository(database: database)
        let folder = try await repository.createFolder(FolderDraft(name: "Folder"))
        let goal = try await repository.createGoal(GoalDraft(folderID: folder.id, name: "Goal"))
        let task = try await repository.createTask(TaskDraft(goalID: goal.id, title: "Task"))

        XCTAssertEqual(task.priorityShadow, TaskPriorityCompatibility.defaultShadow)
        XCTAssertEqual(task.priorityShadow, 5)
    }

    func testTagRemoteIdentityDoesNotAccessMissingVersionColumn() throws {
        let database = try AppDatabase.inMemory()
        let localID = UUID()
        let remoteID = UUID()
        try database.write { db in
            try TagRecord(draft: TagDraft(id: localID, name: "Tag"), now: Date()).insert(db)
            try PlanningPersistence.attachRemoteIdentity(
                .tag,
                localID: localID,
                remoteID: remoteID,
                version: 42,
                in: db
            )
        }

        let stored: String? = try database.read { db in
            try String.fetchOne(db, sql: "SELECT remoteID FROM tags WHERE id = ?", arguments: [localID.uuidString.lowercased()])
        }
        XCTAssertEqual(stored, remoteID.uuidString.lowercased())
    }

    func testResetCachePreservesPendingEntitiesAndClearsCaches() async throws {
        let database = try AppDatabase.inMemory()
        let repository = LocalPlanningRepository(database: database)
        let folder = try await repository.createFolder(FolderDraft(name: "Offline"))
        try await repository.storeFocusCache(key: "focus", payloadJSON: Data("focus".utf8), version: 1)
        try await repository.storeSettingsCache(key: "settings", payloadJSON: Data("settings".utf8), version: 2)

        try await repository.resetCachePreservingPending()

        let snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.folders.map(\.id), [folder.id])
        let focus = try await repository.focusCache(key: "focus")
        let settings = try await repository.settingsCache(key: "settings")
        let pullRequired = try await PendingMutationStore(database: database).pullBeforePushRequired()
        XCTAssertNil(focus)
        XCTAssertNil(settings)
        XCTAssertTrue(pullRequired)
    }

    func testEntityOrderUsesUniqueEntityKey() throws {
        let database = try AppDatabase.inMemory()
        let id = UUID().uuidString.lowercased()
        try database.write { db in
            try db.execute(
                sql: "INSERT INTO entity_order (entityType, entityID, position) VALUES ('folder', ?, 0)",
                arguments: [id]
            )
            try db.execute(
                sql: "UPDATE entity_order SET position = 3 WHERE entityType = 'folder' AND entityID = ?",
                arguments: [id]
            )
        }
        let position = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT position FROM entity_order WHERE entityID = ?", arguments: [id])
        }
        XCTAssertEqual(position, 3)
    }

    func testPartialWarningRetainsCacheUntilCollectionLoadedSuccessfully() throws {
        let database = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let folder = FolderDTO(
            id: UUID(), parentFolderId: nil, name: "Folder", description: "",
            displayOrder: 0, archived: false, shared: false, fullAccess: true,
            version: 1, createdAt: now, updatedAt: now
        )
        let idea = IdeaDTO(
            id: UUID(), folderId: folder.id, title: "Cached", body: "", status: "ACTIVE",
            displayOrder: 0, archived: false, allowAuthorNoteEdits: false, shared: false,
            fullAccess: true, creatorUserId: nil, creatorEmail: nil, creatorName: nil,
            version: 1, createdAt: now, updatedAt: now
        )
        try database.write { db in
            try PlanningPersistence.applyRemote(
                RemotePlanningSnapshot(folders: [folder], ideas: [idea]),
                in: db
            )
            try PlanningPersistence.applyRemote(
                RemotePlanningSnapshot(
                    folders: [folder],
                    ideas: [],
                    loadedCollections: [.folders, .goals, .tasks],
                    partialWarnings: [RemotePullWarning(id: "ideas", resource: "ideas", code: "offline")]
                ),
                in: db
            )
        }
        var count = try database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ideas") }
        XCTAssertEqual(count, 1)

        try database.write { db in
            try PlanningPersistence.applyRemote(
                RemotePlanningSnapshot(
                    folders: [folder], ideas: [],
                    loadedCollections: [.folders, .goals, .tasks, .ideas]
                ),
                in: db
            )
        }
        count = try database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ideas") }
        XCTAssertEqual(count, 0)
    }

    func testRemoteEntityLinkReferencesMapBackToLocalIDs() throws {
        let database = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let remoteFolderID = UUID(), localFolderID = UUID()
        let remoteGoalID = UUID(), localGoalID = UUID()
        let remoteNoteID = UUID(), localNoteID = UUID()
        let folder = FolderDTO(
            id: remoteFolderID, parentFolderId: nil, name: "Folder", description: "",
            displayOrder: 0, archived: false, shared: false, fullAccess: true,
            version: 1, createdAt: now, updatedAt: now
        )
        let goal = GoalDTO(
            id: remoteGoalID, folderId: remoteFolderID, name: "Goal", description: "",
            status: .todo, archived: false, shared: false, fullAccess: true,
            version: 1, createdAt: now, updatedAt: now
        )
        let note = NoteDTO(
            id: remoteNoteID, folderId: remoteFolderID, title: "Note", body: "",
            displayOrder: 0, archived: false, shared: false, fullAccess: true,
            authorUserId: nil, authorEmail: nil, authorName: nil,
            version: 1, createdAt: now, updatedAt: now
        )
        try database.write { db in
            try FolderRecord(dto: folder, localID: localFolderID).insert(db)
            try GoalRecord(dto: goal, localID: localGoalID, folderLocalID: localFolderID).insert(db)
            try NoteRecord(dto: note, localID: localNoteID, folderLocalID: localFolderID).insert(db)
        }
        let reference: (LinkedEntityType, UUID, String) -> EntityReferenceDTO = { type, id, title in
            EntityReferenceDTO(
                type: type, id: id, title: title, subtitle: nil, status: nil,
                path: nil, archived: false, accessible: true, redacted: false
            )
        }
        let link = EntityLinkDTO(
            id: UUID(),
            source: reference(.goal, remoteGoalID, "Goal"),
            target: reference(.note, remoteNoteID, "Note"),
            relationType: .related,
            createdByUserId: nil, createdByName: nil,
            createdAt: now, updatedAt: now, version: 1
        )
        try database.write { db in
            try PlanningPersistence.applyRemote(
                RemotePlanningSnapshot(links: [link], loadedCollections: [.entityLinks]),
                in: db
            )
        }
        let stored = try database.read { db in try EntityLinkRecord.fetchOne(db, key: link.id.uuidString.lowercased()) }
        XCTAssertEqual(stored?.sourceID, localGoalID.uuidString.lowercased())
        XCTAssertEqual(stored?.targetID, localNoteID.uuidString.lowercased())
        XCTAssertEqual(try stored?.dto().source.id, localGoalID)
        XCTAssertEqual(try stored?.dto().target.id, localNoteID)
    }

    func testRedactedEntityLinkPersistsWithoutExposingPlaceholderIdentity() throws {
        let database = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let folder = FolderDTO(
            id: UUID(), parentFolderId: nil, name: "Folder", description: "",
            displayOrder: 0, archived: false, shared: false, fullAccess: true,
            version: 1, createdAt: now, updatedAt: now
        )
        let goal = GoalDTO(
            id: UUID(), folderId: folder.id, name: "Goal", description: "",
            status: .todo, archived: false, shared: false, fullAccess: true,
            version: 1, createdAt: now, updatedAt: now
        )
        let source = EntityReferenceDTO(
            type: .goal, id: goal.id, title: goal.name, subtitle: nil, status: nil,
            path: nil, archived: false, accessible: true, redacted: false
        )
        let redacted = try WireJSON.decoder().decode(
            EntityReferenceDTO.self,
            from: Data(
                """
                {"type":null,"id":null,"title":null,"subtitle":null,"status":null,"path":null,\
                "archived":null,"accessible":false,"redacted":true}
                """.utf8
            )
        )
        let link = EntityLinkDTO(
            id: UUID(), source: source, target: redacted, relationType: .related,
            createdByUserId: nil, createdByName: nil,
            createdAt: now, updatedAt: now, version: 1
        )

        try database.write { db in
            try PlanningPersistence.applyRemote(
                RemotePlanningSnapshot(
                    folders: [folder], goals: [goal], links: [link],
                    loadedCollections: [.folders, .goals, .tasks, .entityLinks]
                ),
                in: db
            )
        }

        let stored = try database.read { db in
            try XCTUnwrap(EntityLinkRecord.fetchOne(db, key: link.id.uuidString.lowercased()))
        }
        let storedDTO = try stored.dto()
        XCTAssertEqual(storedDTO.source.identity?.id, goal.id)
        XCTAssertNil(storedDTO.target.identity)
        let encoded = try WireJSON.encoder().encode(storedDTO)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let target = try XCTUnwrap(object["target"] as? [String: Any])
        XCTAssertTrue(target["id"] is NSNull)
        XCTAssertTrue(target["title"] is NSNull)
    }

    func testResetProtectsPendingEntityLinkEndpointsAndAncestors() async throws {
        let database = try AppDatabase.inMemory()
        let repository = LocalPlanningRepository(database: database)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let folder = FolderDTO(
            id: UUID(), parentFolderId: nil, name: "Folder", description: "",
            displayOrder: 0, archived: false, shared: false, fullAccess: true,
            version: 1, createdAt: now, updatedAt: now
        )
        let goal = GoalDTO(
            id: UUID(), folderId: folder.id, name: "Goal", description: "",
            status: .todo, archived: false, shared: false, fullAccess: true,
            version: 1, createdAt: now, updatedAt: now
        )
        let note = NoteDTO(
            id: UUID(), folderId: folder.id, title: "Note", body: "",
            displayOrder: 0, archived: false, shared: false, fullAccess: true,
            authorUserId: nil, authorEmail: nil, authorName: nil,
            version: 1, createdAt: now, updatedAt: now
        )
        try await repository.applyRemote(
            RemotePlanningSnapshot(folders: [folder], goals: [goal], notes: [note])
        )
        let reference: (LinkedEntityType, UUID, String) -> EntityReferenceDTO = { type, id, title in
            EntityReferenceDTO(
                type: type, id: id, title: title, subtitle: nil, status: nil,
                path: nil, archived: false, accessible: true, redacted: false
            )
        }
        let link = try await repository.createEntityLink(
            EntityLinkDraft(
                source: reference(.goal, goal.id, goal.name),
                target: reference(.note, note.id, note.title),
                relationType: .related
            )
        )

        try await repository.resetCachePreservingPending()

        let counts = try database.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM folders WHERE id = ?", arguments: [folder.id.wire]) ?? 0,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM goals WHERE id = ?", arguments: [goal.id.wire]) ?? 0,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes WHERE id = ?", arguments: [note.id.wire]) ?? 0,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entity_links WHERE id = ?", arguments: [link.id.wire]) ?? 0
            )
        }
        XCTAssertEqual(counts.0, 1)
        XCTAssertEqual(counts.1, 1)
        XCTAssertEqual(counts.2, 1)
        XCTAssertEqual(counts.3, 1)
    }
}
