import Foundation
import GRDB

enum PlanningPersistence {
    static func table(for entityType: PlanningEntityKind) -> String? {
        switch entityType {
        case .tag: "tags"
        case .folder: "folders"
        case .goal: "goals"
        case .task: "tasks"
        case .idea: "ideas"
        case .ideaNote: "idea_notes"
        case .note: "notes"
        case .entityLink: "entity_links"
        case .focus, .settings: nil
        }
    }

    static func exists(_ entityType: PlanningEntityKind, id: UUID, in db: Database) throws -> Bool {
        guard let table = table(for: entityType) else { return false }
        return try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM \(table) WHERE id = ?)",
            arguments: [id.uuidString.lowercased()]
        ) ?? false
    }

    static func deleteEntity(_ entityType: PlanningEntityKind, id: UUID, in db: Database) throws {
        guard let table = table(for: entityType) else {
            throw RepositoryError.unsupportedEntity(entityType)
        }
        try db.execute(
            sql: "DELETE FROM \(table) WHERE id = ?",
            arguments: [id.uuidString.lowercased()]
        )
        try db.execute(
            sql: "DELETE FROM entity_order WHERE entityType = ? AND entityID = ?",
            arguments: [entityType.rawValue, id.uuidString.lowercased()]
        )
    }

    static func version(for entityType: PlanningEntityKind, id: UUID, in db: Database) throws -> Int64 {
        guard entityType != .tag, let table = table(for: entityType) else { return 0 }
        return try Int64.fetchOne(
            db,
            sql: "SELECT version FROM \(table) WHERE id = ?",
            arguments: [id.uuidString.lowercased()]
        ) ?? 0
    }

    static func remoteIDIfPresent(
        for entityType: PlanningEntityKind,
        localID: UUID,
        in db: Database
    ) throws -> UUID? {
        guard let table = table(for: entityType) else { return nil }
        let value = try String.fetchOne(
            db,
            sql: "SELECT remoteID FROM \(table) WHERE id = ?",
            arguments: [localID.uuidString.lowercased()]
        )
        return try value.map(uuid)
    }

    static func setSyncState(
        _ state: SyncState,
        entityType: PlanningEntityKind,
        entityID: UUID,
        in db: Database
    ) throws {
        guard let table = table(for: entityType), hasSyncState(entityType) else { return }
        try db.execute(
            sql: "UPDATE \(table) SET syncState = ? WHERE id = ?",
            arguments: [state.rawValue, entityID.uuidString.lowercased()]
        )
    }

    static func remoteID(
        for entityType: PlanningEntityKind,
        localID: UUID,
        in db: Database
    ) throws -> UUID {
        if let table = table(for: entityType),
           let value = try String.fetchOne(
               db,
               sql: "SELECT remoteID FROM \(table) WHERE id = ?",
               arguments: [localID.uuidString.lowercased()]
           ) {
            return try uuid(value)
        }
        if let value = try String.fetchOne(
            db,
            sql: "SELECT remoteID FROM id_mappings WHERE entityType = ? AND localID = ?",
            arguments: [entityType.rawValue, localID.uuidString.lowercased()]
        ) {
            return try uuid(value)
        }
        throw RepositoryError.missingEntity(entityType, localID)
    }

    static func attachRemoteIdentity(
        _ entityType: PlanningEntityKind,
        localID: UUID,
        remoteID: UUID,
        version: Int64,
        in db: Database
    ) throws {
        guard let table = table(for: entityType) else { return }
        if entityType == .tag {
            try db.execute(
                sql: "UPDATE tags SET remoteID = ? WHERE id = ?",
                arguments: [remoteID.uuidString.lowercased(), localID.uuidString.lowercased()]
            )
        } else {
            try db.execute(
                sql: "UPDATE \(table) SET remoteID = ?, version = ? WHERE id = ?",
                arguments: [
                    remoteID.uuidString.lowercased(),
                    version,
                    localID.uuidString.lowercased()
                ]
            )
        }
    }

    static func acknowledgeEntity(
        _ entityType: PlanningEntityKind,
        localID: UUID,
        remoteID: UUID,
        version: Int64,
        serverPayloadJSON: Data?,
        in db: Database
    ) throws {
        if let serverPayloadJSON {
            try applyServerPayload(
                serverPayloadJSON,
                entityType: entityType,
                localID: localID,
                in: db
            )
        } else {
            try attachRemoteIdentity(
                entityType,
                localID: localID,
                remoteID: remoteID,
                version: version,
                in: db
            )
        }
        try setSyncState(.synced, entityType: entityType, entityID: localID, in: db)
    }

    static func applyServerPayload(
        _ payload: Data,
        entityType: PlanningEntityKind,
        localID: UUID,
        in db: Database
    ) throws {
        switch entityType {
        case .folder:
            let dto = try WireJSON.decoder().decode(FolderDTO.self, from: payload)
            let parentID = try dto.parentFolderId.map { try localID(forRemoteID: $0, entityType: .folder, in: db) }
            try FolderRecord(dto: dto, localID: localID, parentLocalID: parentID).save(db)
        case .goal:
            let dto = try WireJSON.decoder().decode(GoalDTO.self, from: payload)
            let folderID = try localID(forRemoteID: dto.folderId, entityType: .folder, in: db)
            try GoalRecord(dto: dto, localID: localID, folderLocalID: folderID).save(db)
        case .task:
            let dto = try WireJSON.decoder().decode(TaskDTO.self, from: payload)
            let goalID = try localID(forRemoteID: dto.goalId, entityType: .goal, in: db)
            try TaskRecord(dto: dto, localID: localID, goalLocalID: goalID).save(db)
            try replaceTaskChildren(dto, taskLocalID: localID, in: db)
        case .idea:
            let dto = try WireJSON.decoder().decode(IdeaDTO.self, from: payload)
            let folderID = try localID(forRemoteID: dto.folderId, entityType: .folder, in: db)
            try IdeaRecord(dto: dto, localID: localID, folderLocalID: folderID).save(db)
        case .ideaNote:
            let dto = try WireJSON.decoder().decode(IdeaNoteDTO.self, from: payload)
            let ideaID = try localID(forRemoteID: dto.ideaId, entityType: .idea, in: db)
            var record = try IdeaNoteRecord(dto: dto, ideaLocalID: ideaID)
            record.id = localID.uuidString.lowercased()
            try record.save(db)
        case .note:
            let dto = try WireJSON.decoder().decode(NoteDTO.self, from: payload)
            let folderID = try localID(forRemoteID: dto.folderId, entityType: .folder, in: db)
            try NoteRecord(dto: dto, localID: localID, folderLocalID: folderID).save(db)
        case .entityLink:
            let dto = try WireJSON.decoder().decode(EntityLinkDTO.self, from: payload)
            try EntityLinkRecord(dto: try localizedEntityLink(dto, in: db), localID: localID).save(db)
        case .tag:
            let dto = try WireJSON.decoder().decode(TaskTagDTO.self, from: payload)
            var record = TagRecord(dto: dto, now: Date())
            record.id = localID.uuidString.lowercased()
            try record.save(db)
        case .focus, .settings:
            throw RepositoryError.unsupportedEntity(entityType)
        }
    }

    static func applyRemote(_ snapshot: RemotePlanningSnapshot, in db: Database) throws {
        let protected = try protectedEntityIDs(in: db)
        let rebasePending = try String.fetchOne(
            db,
            sql: "SELECT value FROM sync_metadata WHERE key = 'pullBeforePush'"
        ) == "true"
        let folderIDs = try remoteLocalMap(
            snapshot.folders.map(\.id),
            entityType: .folder,
            in: db
        )
        for dto in snapshot.folders {
            let localID = folderIDs[dto.id] ?? dto.id
            if rebasePending { try rebasePendingMutation(.folder, localID: localID, version: dto.version, in: db) }
            guard try canApplyRemote(.folder, localID: localID, in: db) else { continue }
            let parentID = dto.parentFolderId.flatMap { folderIDs[$0] }
            try FolderRecord(dto: dto, localID: localID, parentLocalID: parentID).save(db)
            try saveMapping(.folder, localID: localID, remoteID: dto.id, in: db)
        }

        let goalIDs = try remoteLocalMap(snapshot.goals.map(\.id), entityType: .goal, in: db)
        for dto in snapshot.goals {
            let localID = goalIDs[dto.id] ?? dto.id
            if rebasePending { try rebasePendingMutation(.goal, localID: localID, version: dto.version, in: db) }
            guard try canApplyRemote(.goal, localID: localID, in: db) else { continue }
            let folderID = folderIDs[dto.folderId]
                ?? (try localID(forRemoteID: dto.folderId, entityType: .folder, in: db))
            try GoalRecord(dto: dto, localID: localID, folderLocalID: folderID).save(db)
            try saveMapping(.goal, localID: localID, remoteID: dto.id, in: db)
        }

        let taskIDs = try remoteLocalMap(snapshot.tasks.map(\.id), entityType: .task, in: db)
        for dto in snapshot.tasks {
            let localID = taskIDs[dto.id] ?? dto.id
            if rebasePending { try rebasePendingMutation(.task, localID: localID, version: dto.version, in: db) }
            guard try canApplyRemote(.task, localID: localID, in: db) else { continue }
            let goalID = goalIDs[dto.goalId]
                ?? (try localID(forRemoteID: dto.goalId, entityType: .goal, in: db))
            try TaskRecord(dto: dto, localID: localID, goalLocalID: goalID).save(db)
            try replaceTaskChildren(dto, taskLocalID: localID, in: db)
            try saveMapping(.task, localID: localID, remoteID: dto.id, in: db)
        }

        if let ideas = snapshot.ideas {
            let ideaIDs = try remoteLocalMap(ideas.map(\.id), entityType: .idea, in: db)
            for dto in ideas {
                let localID = ideaIDs[dto.id] ?? dto.id
                if rebasePending { try rebasePendingMutation(.idea, localID: localID, version: dto.version, in: db) }
                guard try canApplyRemote(.idea, localID: localID, in: db) else { continue }
                let folderID = folderIDs[dto.folderId]
                    ?? (try localID(forRemoteID: dto.folderId, entityType: .folder, in: db))
                try IdeaRecord(dto: dto, localID: localID, folderLocalID: folderID).save(db)
                try saveMapping(.idea, localID: localID, remoteID: dto.id, in: db)
            }
            if snapshot.loadedCollections.contains(.ideas) {
                try pruneSynced(
                    table: "ideas",
                    keepingRemoteIDs: Set(ideas.map { $0.id.uuidString.lowercased() }),
                    protectedLocalIDs: protected,
                    in: db
                )
            }
        }

        if let notes = snapshot.notes {
            for dto in notes {
                let localID = try localID(forRemoteID: dto.id, entityType: .note, in: db)
                if rebasePending { try rebasePendingMutation(.note, localID: localID, version: dto.version, in: db) }
                guard try canApplyRemote(.note, localID: localID, in: db) else { continue }
                let folderID = folderIDs[dto.folderId]
                    ?? (try localID(forRemoteID: dto.folderId, entityType: .folder, in: db))
                try NoteRecord(dto: dto, localID: localID, folderLocalID: folderID).save(db)
                try saveMapping(.note, localID: localID, remoteID: dto.id, in: db)
            }
            if snapshot.loadedCollections.contains(.notes) {
                try pruneSynced(
                    table: "notes",
                    keepingRemoteIDs: Set(notes.map { $0.id.uuidString.lowercased() }),
                    protectedLocalIDs: protected,
                    in: db
                )
            }
        }

        if let ideaNotes = snapshot.ideaNotes {
            for dto in ideaNotes {
                let localID = try localID(forRemoteID: dto.id, entityType: .ideaNote, in: db)
                let ideaID = try localID(forRemoteID: dto.ideaId, entityType: .idea, in: db)
                var record = try IdeaNoteRecord(dto: dto, ideaLocalID: ideaID)
                record.id = localID.uuidString.lowercased()
                try record.save(db)
                try saveMapping(.ideaNote, localID: localID, remoteID: dto.id, in: db)
            }
            if snapshot.loadedCollections.contains(.ideaNotes) {
                try pruneIdeaNotes(
                    keepingRemoteIDs: Set(ideaNotes.map { $0.id.uuidString.lowercased() }),
                    protectedLocalIDs: protected,
                    in: db
                )
            }
        }

        if let links = snapshot.links {
            for dto in links {
                let localID = try localID(forRemoteID: dto.id, entityType: .entityLink, in: db)
                if rebasePending { try rebasePendingMutation(.entityLink, localID: localID, version: dto.version, in: db) }
                guard try canApplyRemote(.entityLink, localID: localID, in: db) else { continue }
                try EntityLinkRecord(dto: try localizedEntityLink(dto, in: db), localID: localID).save(db)
                try saveMapping(.entityLink, localID: localID, remoteID: dto.id, in: db)
            }
            if snapshot.loadedCollections.contains(.entityLinks) {
                try pruneSynced(
                    table: "entity_links",
                    keepingRemoteIDs: Set(links.map { $0.id.uuidString.lowercased() }),
                    protectedLocalIDs: protected,
                    in: db
                )
            }
        }

        if snapshot.loadedCollections.contains(.tasks) {
            try pruneSynced(
                table: "tasks",
                keepingRemoteIDs: Set(snapshot.tasks.map { $0.id.uuidString.lowercased() }),
                protectedLocalIDs: protected,
                in: db
            )
        }
        if snapshot.loadedCollections.contains(.goals) {
            try pruneSynced(
                table: "goals",
                keepingRemoteIDs: Set(snapshot.goals.map { $0.id.uuidString.lowercased() }),
                protectedLocalIDs: protected,
                in: db
            )
        }
        if snapshot.loadedCollections.contains(.folders) {
            try pruneSynced(
                table: "folders",
                keepingRemoteIDs: Set(snapshot.folders.map { $0.id.uuidString.lowercased() }),
                protectedLocalIDs: protected,
                in: db
            )
        }
    }

    static func resetCachePreservingPending(in db: Database) throws {
        let protected = try protectedEntityIDs(in: db)
        for table in ["entity_links", "idea_notes", "checklist_items", "task_tags", "tasks", "notes", "ideas", "goals", "tags", "folders"] {
            guard tableHasSyncState(table) else { continue }
            try deleteSynced(table: table, protectedLocalIDs: protected, in: db)
        }
        for table in ["collaboration_cache", "calendar_markers", "calendar_ranges", "settings_cache", "focus_cache"] {
            try db.execute(sql: "DELETE FROM \(table)")
        }
        if protected.isEmpty {
            try db.execute(sql: "DELETE FROM entity_order")
        } else {
            let placeholders = Array(repeating: "?", count: protected.count).joined(separator: ", ")
            try db.execute(
                sql: "DELETE FROM entity_order WHERE entityID NOT IN (\(placeholders))",
                arguments: StatementArguments(protected.sorted())
            )
        }
        try db.execute(
            sql: """
                INSERT INTO sync_metadata (key, value, updatedAt)
                VALUES ('pullBeforePush', 'true', ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt
                """,
            arguments: [WireDateCodec.encode(Date())]
        )
    }

    private static func localID(
        forRemoteID remoteID: UUID,
        entityType: PlanningEntityKind,
        in db: Database
    ) throws -> UUID {
        if let table = table(for: entityType),
           let value = try String.fetchOne(
               db,
               sql: "SELECT id FROM \(table) WHERE remoteID = ? OR id = ? LIMIT 1",
               arguments: [remoteID.uuidString.lowercased(), remoteID.uuidString.lowercased()]
           ) {
            return try uuid(value)
        }
        if let value = try String.fetchOne(
            db,
            sql: "SELECT localID FROM id_mappings WHERE entityType = ? AND remoteID = ?",
            arguments: [entityType.rawValue, remoteID.uuidString.lowercased()]
        ) {
            return try uuid(value)
        }
        return remoteID
    }

    private static func remoteLocalMap(
        _ remoteIDs: [UUID],
        entityType: PlanningEntityKind,
        in db: Database
    ) throws -> [UUID: UUID] {
        try Dictionary(uniqueKeysWithValues: remoteIDs.map { remoteID in
            (remoteID, try localID(forRemoteID: remoteID, entityType: entityType, in: db))
        })
    }

    private static func saveMapping(
        _ entityType: PlanningEntityKind,
        localID: UUID,
        remoteID: UUID,
        in db: Database
    ) throws {
        try IDMappingRecord(
            entityType: entityType,
            localID: localID.uuidString.lowercased(),
            remoteID: remoteID.uuidString.lowercased(),
            createdAt: WireDateCodec.encode(Date())
        ).save(db)
    }

    private static func localizedEntityLink(
        _ dto: EntityLinkDTO,
        in db: Database
    ) throws -> EntityLinkDTO {
        EntityLinkDTO(
            id: dto.id,
            source: try localizedReference(dto.source, in: db),
            target: try localizedReference(dto.target, in: db),
            relationType: dto.relationType,
            createdByUserId: dto.createdByUserId,
            createdByName: dto.createdByName,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            version: dto.version
        )
    }

    private static func localizedReference(
        _ reference: EntityReferenceDTO,
        in db: Database
    ) throws -> EntityReferenceDTO {
        guard let identity = reference.identity else { return reference }
        return EntityReferenceDTO(
            type: identity.type,
            id: try localID(
                forRemoteID: identity.id,
                entityType: kind(for: identity.type),
                in: db
            ),
            title: identity.title,
            subtitle: reference.subtitle,
            status: reference.status,
            path: reference.path,
            archived: reference.archived,
            accessible: reference.accessible,
            redacted: reference.redacted
        )
    }

    private static func kind(for linkedType: LinkedEntityType) -> PlanningEntityKind {
        switch linkedType {
        case .goal: .goal
        case .task: .task
        case .idea: .idea
        case .note: .note
        }
    }

    private static func canApplyRemote(
        _ entityType: PlanningEntityKind,
        localID: UUID,
        in db: Database
    ) throws -> Bool {
        guard let table = table(for: entityType), hasSyncState(entityType) else { return true }
        let value = try String.fetchOne(
            db,
            sql: "SELECT syncState FROM \(table) WHERE id = ?",
            arguments: [localID.uuidString.lowercased()]
        )
        return value == nil || value == SyncState.synced.rawValue
    }

    private static func rebasePendingMutation(
        _ entityType: PlanningEntityKind,
        localID: UUID,
        version: Int64,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                UPDATE pending_mutations
                SET baseVersion = ?
                WHERE entityType = ? AND entityID = ? AND operation != ?
                """,
            arguments: [
                version,
                entityType.rawValue,
                localID.uuidString.lowercased(),
                MutationOperation.create.rawValue
            ]
        )
    }

    private static func replaceTaskChildren(
        _ dto: TaskDTO,
        taskLocalID: UUID,
        in db: Database
    ) throws {
        let taskID = taskLocalID.uuidString.lowercased()
        try db.execute(sql: "DELETE FROM task_tags WHERE taskID = ?", arguments: [taskID])
        for tag in dto.tags {
            let tagLocalID = try localID(forRemoteID: tag.id, entityType: .tag, in: db)
            var record = TagRecord(dto: tag, now: dto.updatedAt)
            record.id = tagLocalID.uuidString.lowercased()
            try record.save(db)
            try TaskTagRecord(taskID: taskID, tagID: record.id).insert(db)
            try saveMapping(.tag, localID: tagLocalID, remoteID: tag.id, in: db)
        }
        try db.execute(sql: "DELETE FROM checklist_items WHERE taskID = ?", arguments: [taskID])
        for item in dto.checklistItems {
            try ChecklistItemRecord(dto: item, taskLocalID: taskLocalID).save(db)
        }
    }

    private static func protectedEntityIDs(in db: Database) throws -> Set<String> {
        var protected = Set(try String.fetchAll(db, sql: "SELECT entityID FROM pending_mutations"))
        protected.formUnion(try String.fetchAll(db, sql: "SELECT entityID FROM sync_conflicts"))
        protected.formUnion(try String.fetchAll(db, sql: "SELECT entityID FROM pending_mutation_dependencies"))
        var changed = true
        while changed {
            changed = false
            for (table, parentColumn) in [
                ("folders", "parentID"),
                ("goals", "folderID"),
                ("tasks", "goalID"),
                ("ideas", "folderID"),
                ("idea_notes", "ideaID"),
                ("notes", "folderID")
            ] {
                for id in Array(protected) {
                    if let parent = try String.fetchOne(
                        db,
                        sql: "SELECT \(parentColumn) FROM \(table) WHERE id = ?",
                        arguments: [id]
                    ), protected.insert(parent).inserted {
                        changed = true
                    }
                }
            }
        }
        return protected
    }

    private static func pruneSynced(
        table: String,
        keepingRemoteIDs: Set<String>,
        protectedLocalIDs: Set<String>,
        in db: Database
    ) throws {
        var clauses = ["syncState = ?", "remoteID IS NOT NULL"]
        var arguments = [SyncState.synced.rawValue]
        if !keepingRemoteIDs.isEmpty {
            clauses.append("remoteID NOT IN (\(Array(repeating: "?", count: keepingRemoteIDs.count).joined(separator: ", ")))")
            arguments.append(contentsOf: keepingRemoteIDs.sorted())
        }
        if !protectedLocalIDs.isEmpty {
            clauses.append("id NOT IN (\(Array(repeating: "?", count: protectedLocalIDs.count).joined(separator: ", ")))")
            arguments.append(contentsOf: protectedLocalIDs.sorted())
        }
        try db.execute(
            sql: "DELETE FROM \(table) WHERE \(clauses.joined(separator: " AND "))",
            arguments: StatementArguments(arguments)
        )
    }

    private static func pruneIdeaNotes(
        keepingRemoteIDs: Set<String>,
        protectedLocalIDs: Set<String>,
        in db: Database
    ) throws {
        var clauses = ["remoteID IS NOT NULL"]
        var arguments: [String] = []
        if !keepingRemoteIDs.isEmpty {
            clauses.append("remoteID NOT IN (\(Array(repeating: "?", count: keepingRemoteIDs.count).joined(separator: ", ")))")
            arguments.append(contentsOf: keepingRemoteIDs.sorted())
        }
        if !protectedLocalIDs.isEmpty {
            clauses.append("id NOT IN (\(Array(repeating: "?", count: protectedLocalIDs.count).joined(separator: ", ")))")
            arguments.append(contentsOf: protectedLocalIDs.sorted())
        }
        try db.execute(
            sql: "DELETE FROM idea_notes WHERE \(clauses.joined(separator: " AND "))",
            arguments: StatementArguments(arguments)
        )
    }

    private static func deleteSynced(
        table: String,
        protectedLocalIDs: Set<String>,
        in db: Database
    ) throws {
        var sql = "DELETE FROM \(table) WHERE syncState = ?"
        var arguments = [SyncState.synced.rawValue]
        if !protectedLocalIDs.isEmpty {
            sql += " AND id NOT IN (\(Array(repeating: "?", count: protectedLocalIDs.count).joined(separator: ", ")))"
            arguments.append(contentsOf: protectedLocalIDs.sorted())
        }
        try db.execute(sql: sql, arguments: StatementArguments(arguments))
    }

    private static func hasSyncState(_ entityType: PlanningEntityKind) -> Bool {
        switch entityType {
        case .folder, .goal, .task, .idea, .note, .entityLink, .tag: true
        case .ideaNote, .focus, .settings: false
        }
    }

    private static func tableHasSyncState(_ table: String) -> Bool {
        ["folders", "goals", "tasks", "ideas", "notes", "entity_links", "tags"].contains(table)
    }
}
