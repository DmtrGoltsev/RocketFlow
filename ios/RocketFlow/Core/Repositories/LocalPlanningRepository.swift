import Foundation
import GRDB

actor LocalPlanningRepository: PlanningRepository {
    private let database: AppDatabase
    private let clock: any SyncClock

    init(database: AppDatabase, clock: any SyncClock = SystemSyncClock()) {
        self.database = database
        self.clock = clock
    }

    func snapshot() async throws -> PlanningSnapshot {
        try database.read { db in
            let folders = try FolderRecord.fetchAll(db, sql: Self.orderedSQL(table: "folders", entity: .folder))
                .map { try $0.dto() }
            let goals = try GoalRecord.fetchAll(db, sql: Self.orderedSQL(table: "goals", entity: .goal))
                .map { try $0.dto() }
            let taskRecords = try TaskRecord.fetchAll(db, sql: Self.orderedSQL(table: "tasks", entity: .task))
            let tasks = try taskRecords.map { record in
                try record.dto(
                    tags: Self.tags(for: record.id, in: db),
                    checklistItems: Self.checklist(for: record.id, in: db)
                )
            }
            let ideas = try IdeaRecord.fetchAll(db, sql: Self.orderedSQL(table: "ideas", entity: .idea))
                .map { try $0.dto() }
            let notes = try NoteRecord.fetchAll(db, sql: Self.orderedSQL(table: "notes", entity: .note))
                .map { try $0.dto() }
            return PlanningSnapshot(
                folders: folders,
                goals: goals,
                tasks: tasks,
                ideas: ideas,
                notes: notes,
                pendingCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pending_mutations") ?? 0,
                conflictCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_conflicts") ?? 0
            )
        }
    }

    func createFolder(_ draft: FolderDraft) async throws -> FolderDTO {
        let now = await clock.now()
        return try database.write { db in
            if let parentID = draft.parentFolderID,
               try !PlanningPersistence.exists(.folder, id: parentID, in: db) {
                throw RepositoryError.invalidParent(.folder, parentID)
            }
            let record = FolderRecord(draft: draft, now: now)
            try record.insert(db)
            let dto = try record.dto()
            _ = try Self.enqueue(
                dto,
                entity: .folder,
                id: draft.id,
                operation: .create,
                baseVersion: nil,
                dependencies: Set(draft.parentFolderID.map { [$0] } ?? []),
                in: db,
                at: now
            )
            return dto
        }
    }

    func updateFolder(id: UUID, name: String, description: String) async throws {
        let now = await clock.now()
        try database.write { db in
            try Self.requireFieldUpdateSlot(entity: .folder, id: id, in: db)
            guard var record = try FolderRecord.fetchOne(db, key: Self.key(id)) else {
                throw RepositoryError.missingEntity(.folder, id)
            }
            record.name = name
            record.details = description
            record.syncState = Self.updatedState(record.syncState)
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            _ = try Self.enqueue(
                record.dto(),
                entity: .folder,
                id: id,
                operation: .update,
                baseVersion: record.version,
                dependencies: try Self.optionalUUIDSet(record.parentID),
                in: db,
                at: now
            )
        }
    }

    func moveFolder(id: UUID, to parentFolderID: UUID?) async throws {
        let now = await clock.now()
        try database.write { db in
            if let parentFolderID {
                try Self.require(.folder, id: parentFolderID, in: db)
                guard parentFolderID != id else { throw RepositoryError.invalidParent(.folder, id) }
            }
            guard var record = try FolderRecord.fetchOne(db, key: Self.key(id)) else {
                throw RepositoryError.missingEntity(.folder, id)
            }
            guard record.parentID != parentFolderID.map({ Self.key($0) }) else { return }
            let operation = try Self.moveOperation(entity: .folder, id: id, in: db)
            record.parentID = parentFolderID.map { Self.key($0) }
            record.syncState = Self.updatedState(record.syncState)
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            if operation == .create {
                _ = try Self.enqueue(
                    record.dto(), entity: .folder, id: id, operation: .update,
                    baseVersion: record.version,
                    dependencies: Set(parentFolderID.map { [$0] } ?? []), in: db, at: now
                )
            } else {
                try Self.enqueueMove(
                    entity: .folder, id: id, targetParentID: parentFolderID,
                    version: record.version,
                    dependencies: Set(parentFolderID.map { [$0] } ?? []), in: db, at: now
                )
            }
        }
    }

    func createGoal(_ draft: GoalDraft) async throws -> GoalDTO {
        let now = await clock.now()
        return try database.write { db in
            try Self.require(.folder, id: draft.folderID, in: db)
            let record = GoalRecord(draft: draft, now: now)
            try record.insert(db)
            let dto = try record.dto()
            _ = try Self.enqueue(
                dto, entity: .goal, id: draft.id, operation: .create,
                baseVersion: nil, dependencies: [draft.folderID], in: db, at: now
            )
            return dto
        }
    }

    func updateGoal(id: UUID, draft: GoalDraft) async throws {
        let now = await clock.now()
        try database.write { db in
            try Self.require(.folder, id: draft.folderID, in: db)
            try Self.requireFieldUpdateSlot(entity: .goal, id: id, in: db)
            guard var record = try GoalRecord.fetchOne(db, key: Self.key(id)) else {
                throw RepositoryError.missingEntity(.goal, id)
            }
            guard record.folderID == Self.key(draft.folderID) else {
                throw RepositoryError.parentMoveRequiresDedicatedOperation(.goal, id)
            }
            record.name = draft.name
            record.details = draft.description
            record.status = draft.status
            record.syncState = Self.updatedState(record.syncState)
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            _ = try Self.enqueue(
                record.dto(), entity: .goal, id: id, operation: .update,
                baseVersion: record.version, dependencies: [draft.folderID], in: db, at: now
            )
        }
    }

    func moveGoal(id: UUID, to folderID: UUID) async throws {
        let now = await clock.now()
        try database.write { db in
            try Self.require(.folder, id: folderID, in: db)
            guard var record = try GoalRecord.fetchOne(db, key: Self.key(id)) else {
                throw RepositoryError.missingEntity(.goal, id)
            }
            guard record.folderID != Self.key(folderID) else { return }
            let operation = try Self.moveOperation(entity: .goal, id: id, in: db)
            record.folderID = Self.key(folderID)
            record.syncState = Self.updatedState(record.syncState)
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            if operation == .create {
                _ = try Self.enqueue(
                    record.dto(), entity: .goal, id: id, operation: .update,
                    baseVersion: record.version, dependencies: [folderID], in: db, at: now
                )
            } else {
                try Self.enqueueMove(
                    entity: .goal, id: id, targetParentID: folderID, version: record.version,
                    dependencies: [folderID], in: db, at: now
                )
            }
        }
    }

    func createTask(_ draft: TaskDraft) async throws -> TaskRecord {
        let now = await clock.now()
        return try database.write { db in
            try Self.require(.goal, id: draft.goalID, in: db)
            let record = TaskRecord(draft: draft, now: now)
            try record.insert(db)
            _ = try Self.enqueue(
                record.dto(tags: [], checklistItems: []),
                entity: .task,
                id: draft.id,
                operation: .create,
                baseVersion: nil,
                dependencies: [draft.goalID],
                in: db,
                at: now
            )
            return record
        }
    }

    func updateTask(id: UUID, draft: TaskDraft) async throws {
        let now = await clock.now()
        try database.write { db in
            try Self.require(.goal, id: draft.goalID, in: db)
            try Self.requireFieldUpdateSlot(entity: .task, id: id, in: db)
            guard var record = try TaskRecord.fetchOne(db, key: Self.key(id)) else {
                throw RepositoryError.missingEntity(.task, id)
            }
            guard record.goalID == Self.key(draft.goalID) else {
                throw RepositoryError.parentMoveRequiresDedicatedOperation(.task, id)
            }
            record.title = draft.title
            record.details = draft.description
            record.type = draft.type
            record.effort = draft.effort
            record.status = draft.status
            record.plannedTime = draft.plannedTime.map(WireDateCodec.encode)
            record.dueTime = draft.dueTime.map(WireDateCodec.encode)
            record.syncState = Self.updatedState(record.syncState)
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            try Self.enqueueTask(record, in: db, at: now, extraDependencies: [draft.goalID])
        }
    }

    func moveTask(id: UUID, to goalID: UUID) async throws {
        let now = await clock.now()
        try database.write { db in
            try Self.require(.goal, id: goalID, in: db)
            guard var record = try TaskRecord.fetchOne(db, key: Self.key(id)) else {
                throw RepositoryError.missingEntity(.task, id)
            }
            guard record.goalID != Self.key(goalID) else { return }
            let operation = try Self.moveOperation(entity: .task, id: id, in: db)
            record.goalID = Self.key(goalID)
            record.syncState = Self.updatedState(record.syncState)
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            if operation == .create {
                try Self.enqueueTask(record, in: db, at: now, extraDependencies: [goalID])
            } else {
                try Self.enqueueMove(
                    entity: .task, id: id, targetParentID: goalID, version: record.version,
                    dependencies: [goalID], in: db, at: now
                )
            }
        }
    }

    func createIdea(_ draft: IdeaDraft) async throws -> IdeaDTO {
        let now = await clock.now()
        return try database.write { db in
            try Self.require(.folder, id: draft.folderID, in: db)
            let record = IdeaRecord(draft: draft, now: now)
            try record.insert(db)
            let dto = try record.dto()
            _ = try Self.enqueue(
                dto, entity: .idea, id: draft.id, operation: .create,
                baseVersion: nil, dependencies: [draft.folderID], in: db, at: now
            )
            return dto
        }
    }

    func updateIdea(id: UUID, draft: IdeaDraft) async throws {
        let now = await clock.now()
        try database.write { db in
            try Self.require(.folder, id: draft.folderID, in: db)
            try Self.requireFieldUpdateSlot(entity: .idea, id: id, in: db)
            guard var record = try IdeaRecord.fetchOne(db, key: Self.key(id)) else {
                throw RepositoryError.missingEntity(.idea, id)
            }
            guard record.folderID == Self.key(draft.folderID) else {
                throw RepositoryError.parentMoveRequiresDedicatedOperation(.idea, id)
            }
            record.title = draft.title
            record.body = draft.body
            record.status = draft.status
            record.displayOrder = draft.displayOrder
            record.allowAuthorNoteEdits = draft.allowAuthorNoteEdits
            record.syncState = Self.updatedState(record.syncState)
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            _ = try Self.enqueue(
                record.dto(), entity: .idea, id: id, operation: .update,
                baseVersion: record.version, dependencies: [draft.folderID], in: db, at: now
            )
        }
    }

    func moveIdea(id: UUID, to folderID: UUID) async throws {
        let now = await clock.now()
        try database.write { db in
            try Self.require(.folder, id: folderID, in: db)
            guard var record = try IdeaRecord.fetchOne(db, key: Self.key(id)) else {
                throw RepositoryError.missingEntity(.idea, id)
            }
            guard record.folderID != Self.key(folderID) else { return }
            let operation = try Self.moveOperation(entity: .idea, id: id, in: db)
            record.folderID = Self.key(folderID)
            record.syncState = Self.updatedState(record.syncState)
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            if operation == .create {
                _ = try Self.enqueue(
                    record.dto(), entity: .idea, id: id, operation: .update,
                    baseVersion: record.version, dependencies: [folderID], in: db, at: now
                )
            } else {
                try Self.enqueueMove(
                    entity: .idea, id: id, targetParentID: folderID, version: record.version,
                    dependencies: [folderID], in: db, at: now
                )
            }
        }
    }

    func createIdeaNote(_ draft: IdeaNoteDraft) async throws -> IdeaNoteDTO {
        let now = await clock.now()
        return try database.write { db in
            try Self.require(.idea, id: draft.ideaID, in: db)
            let record = try IdeaNoteRecord(draft: draft, now: now)
            try record.insert(db)
            let dto = try record.dto()
            _ = try Self.enqueue(
                dto, entity: .ideaNote, id: draft.id, operation: .create,
                baseVersion: nil, dependencies: [draft.ideaID], in: db, at: now
            )
            return dto
        }
    }

    func updateIdeaNote(id: UUID, draft: IdeaNoteDraft) async throws {
        let now = await clock.now()
        try database.write { db in
            guard var record = try IdeaNoteRecord.fetchOne(db, key: Self.key(id)) else {
                throw RepositoryError.missingEntity(.ideaNote, id)
            }
            guard record.ideaID == Self.key(draft.ideaID) else {
                throw RepositoryError.parentMoveRequiresDedicatedOperation(.ideaNote, id)
            }
            record.eventType = draft.eventType
            record.body = draft.body
            record.metadataJSON = try WireJSON.encoder().encode(draft.metadata)
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            _ = try Self.enqueue(
                record.dto(), entity: .ideaNote, id: id, operation: .update,
                baseVersion: record.version, dependencies: [draft.ideaID], in: db, at: now
            )
        }
    }

    func createNote(_ draft: NoteDraft) async throws -> NoteDTO {
        let now = await clock.now()
        return try database.write { db in
            try Self.require(.folder, id: draft.folderID, in: db)
            let record = NoteRecord(draft: draft, now: now)
            try record.insert(db)
            let dto = try record.dto()
            _ = try Self.enqueue(
                dto, entity: .note, id: draft.id, operation: .create,
                baseVersion: nil, dependencies: [draft.folderID], in: db, at: now
            )
            return dto
        }
    }

    func updateNote(id: UUID, draft: NoteDraft) async throws {
        let now = await clock.now()
        try database.write { db in
            try Self.require(.folder, id: draft.folderID, in: db)
            try Self.requireFieldUpdateSlot(entity: .note, id: id, in: db)
            guard var record = try NoteRecord.fetchOne(db, key: Self.key(id)) else {
                throw RepositoryError.missingEntity(.note, id)
            }
            guard record.folderID == Self.key(draft.folderID) else {
                throw RepositoryError.parentMoveRequiresDedicatedOperation(.note, id)
            }
            record.title = draft.title
            record.body = draft.body
            record.displayOrder = draft.displayOrder
            record.syncState = Self.updatedState(record.syncState)
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            _ = try Self.enqueue(
                record.dto(), entity: .note, id: id, operation: .update,
                baseVersion: record.version, dependencies: [draft.folderID], in: db, at: now
            )
        }
    }

    func moveNote(id: UUID, to folderID: UUID) async throws {
        let now = await clock.now()
        try database.write { db in
            try Self.require(.folder, id: folderID, in: db)
            guard var record = try NoteRecord.fetchOne(db, key: Self.key(id)) else {
                throw RepositoryError.missingEntity(.note, id)
            }
            guard record.folderID != Self.key(folderID) else { return }
            let operation = try Self.moveOperation(entity: .note, id: id, in: db)
            record.folderID = Self.key(folderID)
            record.syncState = Self.updatedState(record.syncState)
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            if operation == .create {
                _ = try Self.enqueue(
                    record.dto(), entity: .note, id: id, operation: .update,
                    baseVersion: record.version, dependencies: [folderID], in: db, at: now
                )
            } else {
                try Self.enqueueMove(
                    entity: .note, id: id, targetParentID: folderID, version: record.version,
                    dependencies: [folderID], in: db, at: now
                )
            }
        }
    }

    // Checklist rows are local task children; each change rewrites the parent task mutation payload.
    func createChecklistItem(_ draft: ChecklistItemDraft) async throws -> ChecklistItemDTO {
        let now = await clock.now()
        return try database.write { db in
            try Self.require(.task, id: draft.taskID, in: db)
            let record = ChecklistItemRecord(draft: draft, now: now)
            try record.insert(db)
            try Self.enqueueTask(id: draft.taskID, in: db, at: now)
            return try record.dto()
        }
    }

    func updateChecklistItem(id: UUID, draft: ChecklistItemDraft) async throws {
        let now = await clock.now()
        try database.write { db in
            try Self.require(.task, id: draft.taskID, in: db)
            guard var record = try ChecklistItemRecord.fetchOne(db, key: Self.key(id)) else {
                throw RepositoryError.missingEntity(.task, id)
            }
            record.taskID = Self.key(draft.taskID)
            record.text = draft.text
            record.checked = draft.checked
            record.displayOrder = draft.displayOrder
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            try Self.enqueueTask(id: draft.taskID, in: db, at: now)
        }
    }

    func deleteChecklistItem(id: UUID, taskID: UUID) async throws {
        let now = await clock.now()
        try database.write { db in
            guard try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM checklist_items WHERE id = ? AND taskID = ?)",
                arguments: [Self.key(id), Self.key(taskID)]
            ) == true else {
                throw RepositoryError.missingEntity(.task, id)
            }
            try db.execute(
                sql: "DELETE FROM checklist_items WHERE id = ? AND taskID = ?",
                arguments: [Self.key(id), Self.key(taskID)]
            )
            try Self.enqueueTask(id: taskID, in: db, at: now)
        }
    }

    func reorderChecklist(taskID: UUID, orderedIDs: [UUID]) async throws {
        let now = await clock.now()
        try database.write { db in
            try Self.validateUnique(orderedIDs)
            for (position, id) in orderedIDs.enumerated() {
                guard try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM checklist_items WHERE id = ? AND taskID = ?)",
                    arguments: [Self.key(id), Self.key(taskID)]
                ) == true else {
                    throw RepositoryError.missingEntity(.task, id)
                }
                try db.execute(
                    sql: "UPDATE checklist_items SET displayOrder = ?, updatedAt = ? WHERE id = ? AND taskID = ?",
                    arguments: [position, WireDateCodec.encode(now), Self.key(id), Self.key(taskID)]
                )
            }
            try Self.enqueueTask(id: taskID, in: db, at: now)
        }
    }

    func createTag(_ draft: TagDraft) async throws -> TaskTagDTO {
        let now = await clock.now()
        return try database.write { db in
            let record = TagRecord(draft: draft, now: now)
            try record.insert(db)
            let dto = try record.dto()
            _ = try Self.enqueue(
                dto, entity: .tag, id: draft.id, operation: .create,
                baseVersion: nil, dependencies: [], in: db, at: now
            )
            return dto
        }
    }

    func updateTag(id: UUID, draft: TagDraft) async throws {
        throw RepositoryError.unsupportedMutation(.tag, .update)
    }

    func setTags(_ tagIDs: [UUID], for taskID: UUID) async throws {
        let now = await clock.now()
        try database.write { db in
            try Self.require(.task, id: taskID, in: db)
            try Self.validateUnique(tagIDs)
            for id in tagIDs { try Self.require(.tag, id: id, in: db) }
            try db.execute(sql: "DELETE FROM task_tags WHERE taskID = ?", arguments: [Self.key(taskID)])
            for id in tagIDs {
                try TaskTagRecord(taskID: Self.key(taskID), tagID: Self.key(id)).insert(db)
            }
            try Self.enqueueTask(id: taskID, in: db, at: now, extraDependencies: Set(tagIDs))
        }
    }

    func createEntityLink(_ draft: EntityLinkDraft) async throws -> EntityLinkDTO {
        let now = await clock.now()
        return try database.write { db in
            try Self.require(Self.kind(for: draft.source.type), id: draft.source.id, in: db)
            try Self.require(Self.kind(for: draft.target.type), id: draft.target.id, in: db)
            let dto = EntityLinkDTO(
                id: draft.id,
                source: draft.source,
                target: draft.target,
                relationType: draft.relationType,
                createdByUserId: nil,
                createdByName: nil,
                createdAt: now,
                updatedAt: now,
                version: 0
            )
            var record = try EntityLinkRecord(dto: dto, localID: draft.id)
            record.remoteID = nil
            record.syncState = .pendingCreate
            try record.insert(db)
            _ = try Self.enqueue(
                dto, entity: .entityLink, id: draft.id, operation: .create,
                baseVersion: nil, dependencies: [draft.source.id, draft.target.id], in: db, at: now
            )
            return dto
        }
    }

    func updateEntityLink(id: UUID, relationType: EntityRelationType) async throws {
        let now = await clock.now()
        try database.write { db in
            guard var record = try EntityLinkRecord.fetchOne(db, key: Self.key(id)) else {
                throw RepositoryError.missingEntity(.entityLink, id)
            }
            let old = try record.dto()
            let dto = EntityLinkDTO(
                id: old.id,
                source: old.source,
                target: old.target,
                relationType: relationType,
                createdByUserId: old.createdByUserId,
                createdByName: old.createdByName,
                createdAt: old.createdAt,
                updatedAt: now,
                version: old.version
            )
            record.relationType = relationType
            record.payloadJSON = try WireJSON.encoder().encode(dto)
            record.syncState = Self.updatedState(record.syncState)
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            _ = try Self.enqueue(
                dto, entity: .entityLink, id: id, operation: .update,
                baseVersion: record.version, dependencies: [old.source.id, old.target.id], in: db, at: now
            )
        }
    }

    func reorder(_ entity: PlanningEntityKind, orderedIDs: [UUID]) async throws {
        guard [.folder, .idea, .note].contains(entity) else {
            throw RepositoryError.unsupportedMutation(entity, .reorder)
        }
        let now = await clock.now()
        try database.write { db in
            try Self.validateUnique(orderedIDs)
            for id in orderedIDs { try Self.require(entity, id: id, in: db) }
            for (position, id) in orderedIDs.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO entity_order (entityType, entityID, position)
                        VALUES (?, ?, ?)
                        ON CONFLICT(entityType, entityID) DO UPDATE SET position = excluded.position
                    """,
                    arguments: [entity.rawValue, Self.key(id), position]
                )
                try Self.persistServerOrder(position, entity: entity, id: id, in: db, at: now)
            }
        }
    }

    func storeFocusCache(key: String, payloadJSON: Data, version: Int64) async throws {
        try await storeCache(table: "focus_cache", key: key, payloadJSON: payloadJSON, version: version)
    }

    func focusCache(key: String) async throws -> CachedPayload? {
        try cache(table: "focus_cache", key: key)
    }

    func removeFocusCache(key: String) async throws {
        try removeCache(table: "focus_cache", key: key)
    }

    func storeSettingsCache(key: String, payloadJSON: Data, version: Int64) async throws {
        try await storeCache(table: "settings_cache", key: key, payloadJSON: payloadJSON, version: version)
    }

    func settingsCache(key: String) async throws -> CachedPayload? {
        try cache(table: "settings_cache", key: key)
    }

    func removeSettingsCache(key: String) async throws {
        try removeCache(table: "settings_cache", key: key)
    }

    func delete(_ entity: PlanningEntityKind, id: UUID) async throws {
        if entity == .tag {
            throw RepositoryError.unsupportedMutation(.tag, .delete)
        }
        let now = await clock.now()
        try database.write { db in
            guard let table = PlanningPersistence.table(for: entity) else {
                throw RepositoryError.unsupportedMutation(entity, .delete)
            }
            guard try PlanningPersistence.exists(entity, id: id, in: db) else {
                throw RepositoryError.missingEntity(entity, id)
            }
            let version = try PlanningPersistence.version(for: entity, id: id, in: db)
            let payload = DeleteMutationPayload(
                remoteID: try PlanningPersistence.remoteIDIfPresent(for: entity, localID: id, in: db),
                version: version
            )
            let disposition = try PendingMutationStore.enqueue(
                in: db,
                entityType: entity,
                entityID: id,
                operation: .delete,
                payloadJSON: try WireJSON.encoder().encode(payload),
                baseVersion: entity == .tag ? nil : version,
                dependencies: [],
                at: now
            )
            guard disposition != .cancelledUnsyncedCreate else { return }
            if Self.hasTombstone(entity) {
                try db.execute(
                    sql: "UPDATE \(table) SET deletedAt = ?, syncState = ? WHERE id = ?",
                    arguments: [WireDateCodec.encode(now), SyncState.pendingDelete.rawValue, Self.key(id)]
                )
            } else {
                try PlanningPersistence.deleteEntity(entity, id: id, in: db)
            }
        }
    }

    func applyRemote(_ snapshot: RemotePlanningSnapshot) async throws {
        try database.write { db in try PlanningPersistence.applyRemote(snapshot, in: db) }
    }

    func resetCachePreservingPending() async throws {
        try database.write { db in try PlanningPersistence.resetCachePreservingPending(in: db) }
    }

    private func storeCache(
        table: String,
        key: String,
        payloadJSON: Data,
        version: Int64
    ) async throws {
        let now = await clock.now()
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO \(table) (cacheKey, payloadJSON, version, updatedAt)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(cacheKey) DO UPDATE SET
                        payloadJSON = excluded.payloadJSON,
                        version = excluded.version,
                        updatedAt = excluded.updatedAt
                    """,
                arguments: [key, payloadJSON, version, WireDateCodec.encode(now)]
            )
        }
    }

    private func cache(table: String, key: String) throws -> CachedPayload? {
        try database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT payloadJSON, version, updatedAt FROM \(table) WHERE cacheKey = ?",
                arguments: [key]
            ) else { return nil }
            let payload: Data = row["payloadJSON"]
            let version: Int64 = row["version"]
            let updatedAt: String = row["updatedAt"]
            return CachedPayload(payloadJSON: payload, version: version, updatedAt: try date(updatedAt))
        }
    }

    private func removeCache(table: String, key: String) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM \(table) WHERE cacheKey = ?", arguments: [key])
        }
    }

    private static func enqueueTask(
        id: UUID,
        in db: Database,
        at now: Date,
        extraDependencies: Set<UUID> = []
    ) throws {
        guard let record = try TaskRecord.fetchOne(db, key: key(id)) else {
            throw RepositoryError.missingEntity(.task, id)
        }
        try enqueueTask(record, in: db, at: now, extraDependencies: extraDependencies)
    }

    private static func enqueueTask(
        _ record: TaskRecord,
        in db: Database,
        at now: Date,
        extraDependencies: Set<UUID> = []
    ) throws {
        let taskID = try uuid(record.id)
        try requireFieldUpdateSlot(entity: .task, id: taskID, in: db)
        var updated = record
        updated.syncState = updatedState(updated.syncState)
        updated.updatedAt = WireDateCodec.encode(now)
        try updated.update(db)
        var dependencies = extraDependencies
        dependencies.insert(try uuid(updated.goalID))
        _ = try enqueue(
            updated.dto(tags: tags(for: updated.id, in: db), checklistItems: checklist(for: updated.id, in: db)),
            entity: .task,
            id: taskID,
            operation: .update,
            baseVersion: updated.version,
            dependencies: dependencies,
            in: db,
            at: now
        )
    }

    private static func enqueue<Value: Encodable>(
        _ payload: Value,
        entity: PlanningEntityKind,
        id: UUID,
        operation: MutationOperation,
        baseVersion: Int64?,
        dependencies: Set<UUID>,
        in db: Database,
        at now: Date
    ) throws -> EnqueueDisposition {
        try PendingMutationStore.enqueue(
            in: db,
            entityType: entity,
            entityID: id,
            operation: operation,
            payloadJSON: WireJSON.encoder().encode(payload),
            baseVersion: baseVersion,
            dependencies: dependencies,
            at: now
        )
    }

    private static func enqueueMove(
        entity: PlanningEntityKind,
        id: UUID,
        targetParentID: UUID?,
        version: Int64,
        dependencies: Set<UUID>,
        in db: Database,
        at now: Date
    ) throws {
        _ = try enqueue(
            MoveMutationPayload(targetParentID: targetParentID, version: version),
            entity: entity,
            id: id,
            operation: .move,
            baseVersion: version,
            dependencies: dependencies,
            in: db,
            at: now
        )
    }

    private static func moveOperation(
        entity: PlanningEntityKind,
        id: UUID,
        in db: Database
    ) throws -> MutationOperation {
        guard let existing = try PendingMutationRecord.fetchOne(
            db,
            sql: "SELECT * FROM pending_mutations WHERE dedupeKey = ?",
            arguments: ["\(entity.rawValue):\(key(id))"]
        ) else { return .move }
        if existing.operation == .create, existing.state == .inFlight {
            throw RepositoryError.pendingMutationRequiresSync(entity, id)
        }
        guard existing.operation == .create || existing.operation == .move else {
            throw RepositoryError.pendingMutationRequiresSync(entity, id)
        }
        return existing.operation
    }

    private static func requireFieldUpdateSlot(
        entity: PlanningEntityKind,
        id: UUID,
        in db: Database
    ) throws {
        let rawOperation = try String.fetchOne(
            db,
            sql: "SELECT operation FROM pending_mutations WHERE dedupeKey = ?",
            arguments: ["\(entity.rawValue):\(key(id))"]
        )
        if rawOperation == MutationOperation.move.rawValue {
            throw RepositoryError.pendingMutationRequiresSync(entity, id)
        }
    }

    private static func orderedSQL(table: String, entity: PlanningEntityKind) -> String {
        """
        SELECT * FROM \(table)
        WHERE deletedAt IS NULL
        ORDER BY
            COALESCE((
                SELECT position FROM entity_order ordering
                WHERE ordering.entityType = '\(entity.rawValue)' AND ordering.entityID = \(table).id
            ), 2147483647),
            createdAt DESC,
            id ASC
        """
    }

    private static func persistServerOrder(
        _ position: Int,
        entity: PlanningEntityKind,
        id: UUID,
        in db: Database,
        at now: Date
    ) throws {
        try requireFieldUpdateSlot(entity: entity, id: id, in: db)
        switch entity {
        case .folder:
            guard var record = try FolderRecord.fetchOne(db, key: key(id)) else { return }
            record.displayOrder = position
            record.syncState = updatedState(record.syncState)
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            _ = try enqueue(
                record.dto(), entity: .folder, id: id, operation: .update,
                baseVersion: record.version, dependencies: try optionalUUIDSet(record.parentID), in: db, at: now
            )
        case .idea:
            guard var record = try IdeaRecord.fetchOne(db, key: key(id)) else { return }
            record.displayOrder = position
            record.syncState = updatedState(record.syncState)
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            _ = try enqueue(
                record.dto(), entity: .idea, id: id, operation: .update,
                baseVersion: record.version, dependencies: [try uuid(record.folderID)], in: db, at: now
            )
        case .note:
            guard var record = try NoteRecord.fetchOne(db, key: key(id)) else { return }
            record.displayOrder = position
            record.syncState = updatedState(record.syncState)
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            _ = try enqueue(
                record.dto(), entity: .note, id: id, operation: .update,
                baseVersion: record.version, dependencies: [try uuid(record.folderID)], in: db, at: now
            )
        case .goal, .task, .tag, .entityLink:
            break
        case .ideaNote, .focus, .settings:
            throw RepositoryError.unsupportedEntity(entity)
        }
    }

    private static func tags(for taskID: String, in db: Database) throws -> [TaskTagDTO] {
        try TagRecord.fetchAll(
            db,
            sql: """
                SELECT tag.* FROM tags tag
                JOIN task_tags relation ON relation.tagID = tag.id
                WHERE relation.taskID = ? AND tag.deletedAt IS NULL
                ORDER BY tag.createdAt DESC, tag.id ASC
                """,
            arguments: [taskID]
        ).map { try $0.dto() }
    }

    private static func checklist(for taskID: String, in db: Database) throws -> [ChecklistItemDTO] {
        try ChecklistItemRecord.fetchAll(
            db,
            sql: """
                SELECT * FROM checklist_items WHERE taskID = ?
                ORDER BY displayOrder ASC, createdAt DESC, id ASC
                """,
            arguments: [taskID]
        ).map { try $0.dto() }
    }

    private static func updatedState(_ state: SyncState) -> SyncState {
        state == .pendingCreate ? .pendingCreate : .pendingUpdate
    }

    private static func require(_ entity: PlanningEntityKind, id: UUID, in db: Database) throws {
        guard try PlanningPersistence.exists(entity, id: id, in: db) else {
            throw RepositoryError.invalidParent(entity, id)
        }
    }

    private static func optionalUUIDSet(_ value: String?) throws -> Set<UUID> {
        guard let value else { return [] }
        return [try uuid(value)]
    }

    private static func validateUnique(_ ids: [UUID]) throws {
        if Set(ids).count != ids.count, let duplicate = ids.first {
            throw RepositoryError.conflictExists(duplicate)
        }
    }

    private static func kind(for linkedType: LinkedEntityType) -> PlanningEntityKind {
        switch linkedType {
        case .goal: .goal
        case .task: .task
        case .idea: .idea
        case .note: .note
        }
    }

    private static func hasTombstone(_ entity: PlanningEntityKind) -> Bool {
        switch entity {
        case .folder, .goal, .task, .idea, .note, .entityLink, .tag: true
        case .ideaNote, .focus, .settings: false
        }
    }

    private static func key(_ id: UUID) -> String { id.uuidString.lowercased() }
}
