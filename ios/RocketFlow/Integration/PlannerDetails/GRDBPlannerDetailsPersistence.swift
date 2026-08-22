import Foundation
import GRDB

struct PlannerDetailsRemoteOperationKey: Hashable, Sendable {
    let kind: PlanningEntityKind
    let localID: UUID
}

struct PlannerDetailsRemoteOperationLease: Sendable {
    let key: PlannerDetailsRemoteOperationKey
    let generation: PlannerDetailsMutationGeneration
}

struct PlannerDetailsMutationGeneration: Equatable, Sendable {
    let pendingID: String?
    let pendingOperation: MutationOperation?
    let pendingPayloadJSON: Data?
    let pendingUpdatedAt: String?
    let entityVersion: Int64?
    let entityUpdatedAt: String?
}

enum PlannerDetailsGuardedApplyResult: Equatable, Sendable {
    case applied
    case preservedNewerLocalMutation
}

struct PlannerDetailsChecklistAggregateItem: Equatable, Sendable {
    let id: UUID
    let text: String
    let checked: Bool
    let displayOrder: Int
}

struct PlannerDetailsRecurrenceCreateRecovery: Codable, Equatable, Sendable {
    let localID: UUID
    let response: ActionTaskDTO
}

protocol PlannerDetailsPersistenceAccessing: Sendable {
    func localID(for kind: PlanningEntityKind, remoteID: UUID) async throws -> UUID?
    func remoteID(for kind: PlanningEntityKind, localID: UUID) async throws -> UUID
    func checklistRemoteID(localID: UUID, taskID: UUID) async throws -> UUID?
    func hasPendingMutation(kind: PlanningEntityKind, localID: UUID) async throws -> Bool
    func mutationGeneration(
        kind: PlanningEntityKind,
        localID: UUID
    ) async throws -> PlannerDetailsMutationGeneration
    func ideaNotes(ideaID: UUID) async throws -> [IdeaNoteDTO]
    func links(kind: LinkedEntityType, localID: UUID) async throws -> [EntityLinkDTO]
    func allTags() async throws -> [TaskTagDTO]
    func bindAndApply(
        kind: PlanningEntityKind,
        localID: UUID,
        remoteID: UUID,
        version: Int64,
        payloadJSON: Data
    ) async throws
    func bindAndApplyGuarded(
        kind: PlanningEntityKind,
        localID: UUID,
        remoteID: UUID,
        version: Int64,
        payloadJSON: Data,
        expectedGeneration: PlannerDetailsMutationGeneration
    ) async throws -> PlannerDetailsGuardedApplyResult
    func saveTaskAggregate(
        draft: TaskDraft,
        checklist: [PlannerDetailsChecklistAggregateItem],
        tagIDs: [UUID],
        creating: Bool
    ) async throws -> TaskDTO
    func removeSynced(kind: PlanningEntityKind, localID: UUID) async throws
    func setTaskRecurrence(localID: UUID, recurrence: RecurrenceDTO?) async throws
    func applyTaskMove(localID: UUID, response: MoveTaskResponseDTO) async throws
    func applyTaskMoveGuarded(
        localID: UUID,
        response: MoveTaskResponseDTO,
        expectedGeneration: PlannerDetailsMutationGeneration
    ) async throws -> PlannerDetailsGuardedApplyResult
    func recurrenceCreateRecovery(
        operationKey: String
    ) async throws -> PlannerDetailsRecurrenceCreateRecovery?
    func beginRecurrenceCreateRecovery(
        operationKey: String,
        localID: UUID,
        response: ActionTaskDTO
    ) async throws
    func completeRecurrenceCreateRecovery(
        operationKey: String,
        localID: UUID,
        recurrence: RecurrenceDTO
    ) async throws
    func discardRecurrenceCreateRecovery(operationKey: String, localID: UUID) async throws
    func cachedCreateTaskGoalIDs() async throws -> Set<UUID>
    func applySharedResources(_ response: ActionSharedResourcesResponseDTO) async throws -> Set<UUID>
}

actor GRDBPlannerDetailsPersistence: PlannerDetailsPersistenceAccessing {
    private static let collaborationKey = "planner.createTaskGoalIDs"
    private static let recurrenceRecoveryPrefix = "planner.recurrenceCreate."
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func localID(for kind: PlanningEntityKind, remoteID: UUID) throws -> UUID? {
        try database.read { db in
            if let value = try String.fetchOne(
                db,
                sql: "SELECT localID FROM id_mappings WHERE entityType = ? AND remoteID = ?",
                arguments: [kind.rawValue, key(remoteID)]
            ) {
                return try uuid(value)
            }
            guard let table = PlanningPersistence.table(for: kind) else { return nil }
            let value = try String.fetchOne(
                db,
                sql: "SELECT id FROM \(table) WHERE remoteID = ?",
                arguments: [key(remoteID)]
            )
            return try value.map(uuid)
        }
    }

    func remoteID(for kind: PlanningEntityKind, localID: UUID) throws -> UUID {
        do {
            return try database.read {
                try PlanningPersistence.remoteID(for: kind, localID: localID, in: $0)
            }
        } catch {
            throw PlannerDetailsIntegrationError.missingMapping(kind: kind, id: localID)
        }
    }

    func checklistRemoteID(localID: UUID, taskID: UUID) throws -> UUID? {
        try database.read { db in
            let value = try String.fetchOne(
                db,
                sql: "SELECT remoteID FROM checklist_items WHERE id = ? AND taskID = ?",
                arguments: [key(localID), key(taskID)]
            )
            return try value.map(uuid)
        }
    }

    func hasPendingMutation(kind: PlanningEntityKind, localID: UUID) throws -> Bool {
        try database.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM pending_mutations WHERE entityType = ? AND entityID = ?)",
                arguments: [kind.rawValue, key(localID)]
            ) ?? false
        }
    }

    func mutationGeneration(
        kind: PlanningEntityKind,
        localID: UUID
    ) throws -> PlannerDetailsMutationGeneration {
        try database.read { db in
            try Self.mutationGeneration(kind: kind, localID: localID, in: db)
        }
    }

    func ideaNotes(ideaID: UUID) throws -> [IdeaNoteDTO] {
        try database.read { db in
            try IdeaNoteRecord.fetchAll(
                db,
                sql: "SELECT * FROM idea_notes WHERE ideaID = ? ORDER BY createdAt ASC, id ASC",
                arguments: [key(ideaID)]
            ).map { try $0.dto() }
        }
    }

    func links(kind: LinkedEntityType, localID: UUID) throws -> [EntityLinkDTO] {
        try database.read { db in
            try EntityLinkRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM entity_links
                    WHERE deletedAt IS NULL
                      AND ((sourceType = ? AND sourceID = ?) OR (targetType = ? AND targetID = ?))
                    ORDER BY createdAt DESC, id ASC
                    """,
                arguments: [kind.rawValue, key(localID), kind.rawValue, key(localID)]
            ).map { try $0.dto() }
        }
    }

    func allTags() throws -> [TaskTagDTO] {
        try database.read { db in
            try TagRecord.fetchAll(
                db,
                sql: "SELECT * FROM tags WHERE deletedAt IS NULL ORDER BY createdAt DESC, id ASC"
            ).map { try $0.dto() }
        }
    }

    func bindAndApply(
        kind: PlanningEntityKind,
        localID: UUID,
        remoteID: UUID,
        version: Int64,
        payloadJSON: Data
    ) throws {
        try database.write { db in
            try Self.saveMapping(
                kind: kind,
                localID: localID,
                remoteID: remoteID,
                in: db
            )
            try PlanningPersistence.acknowledgeEntity(
                kind,
                localID: localID,
                remoteID: remoteID,
                version: version,
                serverPayloadJSON: payloadJSON,
                in: db
            )
        }
    }

    func bindAndApplyGuarded(
        kind: PlanningEntityKind,
        localID: UUID,
        remoteID: UUID,
        version: Int64,
        payloadJSON: Data,
        expectedGeneration: PlannerDetailsMutationGeneration
    ) throws -> PlannerDetailsGuardedApplyResult {
        try database.write { db in
            let current = try Self.mutationGeneration(kind: kind, localID: localID, in: db)
            try Self.saveMapping(kind: kind, localID: localID, remoteID: remoteID, in: db)
            guard current == expectedGeneration else {
                try PlanningPersistence.attachRemoteIdentity(
                    kind,
                    localID: localID,
                    remoteID: remoteID,
                    version: version,
                    in: db
                )
                try Self.rebasePendingMutation(
                    kind: kind,
                    localID: localID,
                    serverVersion: version,
                    in: db
                )
                return .preservedNewerLocalMutation
            }
            try PlanningPersistence.acknowledgeEntity(
                kind,
                localID: localID,
                remoteID: remoteID,
                version: version,
                serverPayloadJSON: payloadJSON,
                in: db
            )
            return .applied
        }
    }

    func saveTaskAggregate(
        draft: TaskDraft,
        checklist: [PlannerDetailsChecklistAggregateItem],
        tagIDs: [UUID],
        creating: Bool
    ) throws -> TaskDTO {
        let now = Date()
        return try database.write { db in
            try Self.requireVisible(.goal, id: draft.goalID, in: db)
            try Self.requireUnique(tagIDs, field: "tagIds")
            try Self.requireUnique(checklist.map(\.id), field: "checklistIds")
            for tagID in tagIDs { try Self.requireVisible(.tag, id: tagID, in: db) }

            let taskKey = key(draft.id)
            var task: TaskRecord
            let baseVersion: Int64?
            if creating {
                guard try TaskRecord.fetchOne(db, key: taskKey) == nil else {
                    throw PlannerDetailsIntegrationError.conflict(
                        code: "task_create_identity_exists",
                        message: "The task creation identity is already in use."
                    )
                }
                task = TaskRecord(draft: draft, now: now)
                try task.insert(db)
                baseVersion = nil
            } else {
                try Self.requireTaskFieldUpdateSlot(draft.id, in: db)
                guard var current = try TaskRecord.fetchOne(db, key: taskKey) else {
                    throw RepositoryError.missingEntity(.task, draft.id)
                }
                guard current.goalID == key(draft.goalID) else {
                    throw RepositoryError.parentMoveRequiresDedicatedOperation(.task, draft.id)
                }
                baseVersion = current.version
                current.title = draft.title
                current.details = draft.description
                current.type = draft.type
                current.effort = draft.effort
                current.status = draft.status
                current.plannedTime = draft.plannedTime.map(WireDateCodec.encode)
                current.dueTime = draft.dueTime.map(WireDateCodec.encode)
                current.syncState = current.syncState == .pendingCreate ? .pendingCreate : .pendingUpdate
                current.updatedAt = WireDateCodec.encode(now)
                try current.update(db)
                task = current
            }

            let incomingChecklistIDs = Set(checklist.map { key($0.id) })
            let existingChecklist = try ChecklistItemRecord.fetchAll(
                db,
                sql: "SELECT * FROM checklist_items WHERE taskID = ?",
                arguments: [taskKey]
            )
            for item in existingChecklist where !incomingChecklistIDs.contains(item.id) {
                try item.delete(db)
            }
            for item in checklist {
                let itemKey = key(item.id)
                if var record = try ChecklistItemRecord.fetchOne(db, key: itemKey) {
                    guard record.taskID == taskKey else {
                        throw PlannerDetailsIntegrationError.validation(
                            message: "Checklist item belongs to another task.",
                            fields: ["checklist": "parent_mismatch"]
                        )
                    }
                    record.text = item.text
                    record.checked = item.checked
                    record.displayOrder = item.displayOrder
                    record.updatedAt = WireDateCodec.encode(now)
                    try record.update(db)
                } else {
                    try ChecklistItemRecord(
                        draft: ChecklistItemDraft(
                            id: item.id,
                            taskID: draft.id,
                            text: item.text,
                            checked: item.checked,
                            displayOrder: item.displayOrder
                        ),
                        now: now
                    ).insert(db)
                }
            }

            try db.execute(sql: "DELETE FROM task_tags WHERE taskID = ?", arguments: [taskKey])
            for tagID in tagIDs {
                try TaskTagRecord(taskID: taskKey, tagID: key(tagID)).insert(db)
            }

            let tags = try Self.tags(for: taskKey, in: db)
            let checklistDTOs = try Self.checklist(for: taskKey, in: db)
            let dto = try task.dto(tags: tags, checklistItems: checklistDTOs)
            var dependencies = Set(tagIDs)
            dependencies.insert(draft.goalID)
            _ = try PendingMutationStore.enqueue(
                in: db,
                entityType: .task,
                entityID: draft.id,
                operation: creating ? .create : .update,
                payloadJSON: try WireJSON.encoder().encode(dto),
                baseVersion: baseVersion,
                dependencies: dependencies,
                at: now
            )
            return dto
        }
    }

    func removeSynced(kind: PlanningEntityKind, localID: UUID) throws {
        try database.write { db in
            guard try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM pending_mutations WHERE entityType = ? AND entityID = ?)",
                arguments: [kind.rawValue, key(localID)]
            ) != true else {
                throw RepositoryError.pendingMutationRequiresSync(kind, localID)
            }
            var nestedIdeaNoteIDs: [String] = []
            if kind == .idea {
                nestedIdeaNoteIDs = try String.fetchAll(
                    db,
                    sql: "SELECT id FROM idea_notes WHERE ideaID = ?",
                    arguments: [key(localID)]
                )
            }
            try PlanningPersistence.deleteEntity(kind, id: localID, in: db)
            try db.execute(
                sql: "DELETE FROM id_mappings WHERE entityType = ? AND localID = ?",
                arguments: [kind.rawValue, key(localID)]
            )
            for id in nestedIdeaNoteIDs {
                try db.execute(
                    sql: "DELETE FROM id_mappings WHERE entityType = ? AND localID = ?",
                    arguments: [PlanningEntityKind.ideaNote.rawValue, id]
                )
            }
        }
    }

    func setTaskRecurrence(localID: UUID, recurrence: RecurrenceDTO?) throws {
        try database.write { db in
            guard try TaskRecord.fetchOne(db, key: key(localID)) != nil else {
                throw RepositoryError.missingEntity(.task, localID)
            }
            let payload = try recurrence.map { try WireJSON.encoder().encode($0) }
            try db.execute(
                sql: "UPDATE tasks SET recurrenceJSON = ? WHERE id = ?",
                arguments: [payload, key(localID)]
            )
        }
    }

    func applyTaskMove(localID: UUID, response: MoveTaskResponseDTO) throws {
        try database.write { db in
            try Self.applyTaskMove(localID: localID, response: response, in: db)
        }
    }

    func applyTaskMoveGuarded(
        localID: UUID,
        response: MoveTaskResponseDTO,
        expectedGeneration: PlannerDetailsMutationGeneration
    ) throws -> PlannerDetailsGuardedApplyResult {
        try database.write { db in
            guard try Self.mutationGeneration(kind: .task, localID: localID, in: db) == expectedGeneration else {
                return .preservedNewerLocalMutation
            }
            try Self.applyTaskMove(localID: localID, response: response, in: db)
            return .applied
        }
    }

    func recurrenceCreateRecovery(
        operationKey: String
    ) throws -> PlannerDetailsRecurrenceCreateRecovery? {
        try database.read { db in
            guard let payload = try Data.fetchOne(
                db,
                sql: "SELECT payloadJSON FROM collaboration_cache WHERE cacheKey = ?",
                arguments: [Self.recurrenceRecoveryKey(operationKey)]
            ) else { return nil }
            return try WireJSON.decoder().decode(
                PlannerDetailsRecurrenceCreateRecovery.self,
                from: payload
            )
        }
    }

    func beginRecurrenceCreateRecovery(
        operationKey: String,
        localID: UUID,
        response: ActionTaskDTO
    ) throws {
        try database.write { db in
            let dto = try PlannerDetailsDTOMapper.task(response)
            try Self.saveMapping(kind: .task, localID: localID, remoteID: response.id, in: db)
            try PlanningPersistence.acknowledgeEntity(
                .task,
                localID: localID,
                remoteID: response.id,
                version: response.version,
                serverPayloadJSON: try WireJSON.encoder().encode(dto),
                in: db
            )
            try Self.saveRecurrenceRecovery(
                PlannerDetailsRecurrenceCreateRecovery(localID: localID, response: response),
                operationKey: operationKey,
                in: db
            )
        }
    }

    func completeRecurrenceCreateRecovery(
        operationKey: String,
        localID: UUID,
        recurrence: RecurrenceDTO
    ) throws {
        try database.write { db in
            guard try TaskRecord.fetchOne(db, key: key(localID)) != nil else {
                throw RepositoryError.missingEntity(.task, localID)
            }
            try db.execute(
                sql: "UPDATE tasks SET recurrenceJSON = ? WHERE id = ?",
                arguments: [try WireJSON.encoder().encode(recurrence), key(localID)]
            )
            try Self.clearRecurrenceRecovery(operationKey: operationKey, in: db)
        }
    }

    func discardRecurrenceCreateRecovery(operationKey: String, localID: UUID) throws {
        try database.write { db in
            guard try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM pending_mutations WHERE entityType = ? AND entityID = ?)",
                arguments: [PlanningEntityKind.task.rawValue, key(localID)]
            ) != true else {
                throw RepositoryError.pendingMutationRequiresSync(.task, localID)
            }
            try PlanningPersistence.deleteEntity(.task, id: localID, in: db)
            try db.execute(
                sql: "DELETE FROM id_mappings WHERE entityType = ? AND localID = ?",
                arguments: [PlanningEntityKind.task.rawValue, key(localID)]
            )
            try Self.clearRecurrenceRecovery(operationKey: operationKey, in: db)
        }
    }

    func cachedCreateTaskGoalIDs() throws -> Set<UUID> {
        try database.read { db in
            guard let payload = try Data.fetchOne(
                db,
                sql: "SELECT payloadJSON FROM collaboration_cache WHERE cacheKey = ?",
                arguments: [Self.collaborationKey]
            ) else {
                return []
            }
            return Set(try WireJSON.decoder().decode([UUID].self, from: payload))
        }
    }

    func applySharedResources(_ response: ActionSharedResourcesResponseDTO) throws -> Set<UUID> {
        try database.write { db in
            for value in response.folders {
                let dto = FolderDTO(
                    id: value.id,
                    parentFolderId: nil,
                    name: value.name,
                    description: value.description ?? "",
                    displayOrder: value.displayOrder,
                    archived: value.archived,
                    shared: value.shared,
                    fullAccess: value.fullAccess,
                    version: value.version,
                    createdAt: value.createdAt,
                    updatedAt: value.updatedAt
                )
                try Self.bindAndApply(dto, kind: .folder, remoteID: dto.id, in: db)
            }
            for value in response.goals {
                let dto = PlannerDetailsDTOMapper.goal(value)
                try Self.bindAndApply(dto, kind: .goal, remoteID: dto.id, in: db)
            }
            for value in response.tasks {
                let dto = try PlannerDetailsDTOMapper.task(value)
                try Self.bindAndApply(dto, kind: .task, remoteID: dto.id, in: db)
            }
            for value in response.ideas {
                let dto = PlannerDetailsDTOMapper.idea(value)
                try Self.bindAndApply(dto, kind: .idea, remoteID: dto.id, in: db)
            }

            let localGoalIDs = try response.createTaskGoalIds.compactMap { remoteID -> UUID? in
                try Self.localID(kind: .goal, remoteID: remoteID, in: db)
            }
            let payload = try WireJSON.encoder().encode(localGoalIDs)
            try db.execute(
                sql: """
                    INSERT INTO collaboration_cache (cacheKey, payloadJSON, updatedAt)
                    VALUES (?, ?, ?)
                    ON CONFLICT(cacheKey) DO UPDATE SET
                        payloadJSON = excluded.payloadJSON,
                        updatedAt = excluded.updatedAt
                    """,
                arguments: [Self.collaborationKey, payload, WireDateCodec.encode(Date())]
            )
            return Set(localGoalIDs)
        }
    }

    private static func bindAndApply<Value: Encodable>(
        _ value: Value,
        kind: PlanningEntityKind,
        remoteID: UUID,
        in db: Database
    ) throws {
        let localID = try localID(kind: kind, remoteID: remoteID, in: db) ?? remoteID
        try saveMapping(kind: kind, localID: localID, remoteID: remoteID, in: db)
        let version = try version(value)
        try PlanningPersistence.acknowledgeEntity(
            kind,
            localID: localID,
            remoteID: remoteID,
            version: version,
            serverPayloadJSON: try WireJSON.encoder().encode(value),
            in: db
        )
    }

    private static func version<Value: Encodable>(_ value: Value) throws -> Int64 {
        let payload = try WireJSON.encoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        return (object?["version"] as? NSNumber)?.int64Value ?? 0
    }

    private static func localID(
        kind: PlanningEntityKind,
        remoteID: UUID,
        in db: Database
    ) throws -> UUID? {
        let value = try String.fetchOne(
            db,
            sql: "SELECT localID FROM id_mappings WHERE entityType = ? AND remoteID = ?",
            arguments: [kind.rawValue, key(remoteID)]
        )
        return try value.map(uuid)
    }

    private static func saveMapping(
        kind: PlanningEntityKind,
        localID: UUID,
        remoteID: UUID,
        in db: Database
    ) throws {
        try IDMappingRecord(
            entityType: kind,
            localID: key(localID),
            remoteID: key(remoteID),
            createdAt: WireDateCodec.encode(Date())
        ).save(db)
    }

    private static func mutationGeneration(
        kind: PlanningEntityKind,
        localID: UUID,
        in db: Database
    ) throws -> PlannerDetailsMutationGeneration {
        let pending = try PendingMutationRecord.fetchOne(
            db,
            sql: "SELECT * FROM pending_mutations WHERE dedupeKey = ?",
            arguments: ["\(kind.rawValue):\(key(localID))"]
        )
        let table = PlanningPersistence.table(for: kind)
        let entity: Row? = try table.flatMap {
            try Row.fetchOne(
                db,
                sql: "SELECT version, updatedAt FROM \($0) WHERE id = ?",
                arguments: [key(localID)]
            )
        }
        return PlannerDetailsMutationGeneration(
            pendingID: pending?.id,
            pendingOperation: pending?.operation,
            pendingPayloadJSON: pending?.payloadJSON,
            pendingUpdatedAt: pending?.updatedAt,
            entityVersion: entity?["version"],
            entityUpdatedAt: entity?["updatedAt"]
        )
    }

    private static func rebasePendingMutation(
        kind: PlanningEntityKind,
        localID: UUID,
        serverVersion: Int64,
        in db: Database
    ) throws {
        guard var pending = try PendingMutationRecord.fetchOne(
            db,
            sql: "SELECT * FROM pending_mutations WHERE dedupeKey = ?",
            arguments: ["\(kind.rawValue):\(key(localID))"]
        ) else { return }
        if pending.operation == .create { pending.operation = .update }
        pending.baseVersion = serverVersion
        pending.state = .queued
        pending.nextRetryAt = nil
        pending.lastErrorCode = nil
        pending.updatedAt = WireDateCodec.encode(Date())
        try pending.update(db)
    }

    private static func applyTaskMove(
        localID: UUID,
        response: MoveTaskResponseDTO,
        in db: Database
    ) throws {
        guard try TaskRecord.fetchOne(db, key: key(localID)) != nil else {
            throw RepositoryError.missingEntity(.task, localID)
        }
        try db.execute(
            sql: """
                UPDATE tasks
                SET plannedTime = ?, priorityShadow = ?, updatedAt = ?
                WHERE id = ?
                """,
            arguments: [
                WireDateCodec.encode(response.plannedTime),
                response.priorityShadow,
                WireDateCodec.encode(response.updatedAt),
                key(localID)
            ]
        )
    }

    private static func requireVisible(
        _ kind: PlanningEntityKind,
        id: UUID,
        in db: Database
    ) throws {
        guard let table = PlanningPersistence.table(for: kind),
              try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM \(table) WHERE id = ? AND deletedAt IS NULL)",
                arguments: [key(id)]
              ) == true else {
            throw RepositoryError.missingEntity(kind, id)
        }
    }

    private static func requireUnique(_ ids: [UUID], field: String) throws {
        guard Set(ids).count == ids.count else {
            throw PlannerDetailsIntegrationError.validation(
                message: "Duplicate aggregate identifiers are not allowed.",
                fields: [field: "duplicate"]
            )
        }
    }

    private static func requireTaskFieldUpdateSlot(_ id: UUID, in db: Database) throws {
        let operation = try String.fetchOne(
            db,
            sql: "SELECT operation FROM pending_mutations WHERE dedupeKey = ?",
            arguments: ["\(PlanningEntityKind.task.rawValue):\(key(id))"]
        )
        if operation == MutationOperation.move.rawValue {
            throw RepositoryError.pendingMutationRequiresSync(.task, id)
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

    private static func recurrenceRecoveryKey(_ operationKey: String) -> String {
        recurrenceRecoveryPrefix + operationKey
    }

    private static func saveRecurrenceRecovery(
        _ recovery: PlannerDetailsRecurrenceCreateRecovery,
        operationKey: String,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO collaboration_cache (cacheKey, payloadJSON, updatedAt)
                VALUES (?, ?, ?)
                ON CONFLICT(cacheKey) DO UPDATE SET
                    payloadJSON = excluded.payloadJSON,
                    updatedAt = excluded.updatedAt
                """,
            arguments: [
                recurrenceRecoveryKey(operationKey),
                try WireJSON.encoder().encode(recovery),
                WireDateCodec.encode(Date())
            ]
        )
    }

    private static func clearRecurrenceRecovery(operationKey: String, in db: Database) throws {
        try db.execute(
            sql: "DELETE FROM collaboration_cache WHERE cacheKey = ?",
            arguments: [recurrenceRecoveryKey(operationKey)]
        )
    }

    private static func key(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }

    private func key(_ value: UUID) -> String {
        Self.key(value)
    }
}
