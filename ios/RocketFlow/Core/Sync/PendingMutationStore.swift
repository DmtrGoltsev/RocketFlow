import Foundation
import GRDB

enum RepositoryError: Error, Equatable, Sendable {
    case missingEntity(PlanningEntityKind, UUID)
    case invalidParent(PlanningEntityKind, UUID)
    case conflictExists(UUID)
    case unsupportedEntity(PlanningEntityKind)
    case unsupportedMutation(PlanningEntityKind, MutationOperation)
    case parentMoveRequiresDedicatedOperation(PlanningEntityKind, UUID)
    case pendingMutationRequiresSync(PlanningEntityKind, UUID)
    case missingServerPayload(UUID)
    case missingServerVersion(UUID)
}

enum EnqueueDisposition: Equatable, Sendable {
    case queued(UUID)
    case cancelledUnsyncedCreate
}

actor PendingMutationStore {
    private static let pullBeforePushKey = "pullBeforePush"
    let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func enqueue(
        entityType: PlanningEntityKind,
        entityID: UUID,
        operation: MutationOperation,
        payloadJSON: Data,
        baseVersion: Int64?,
        dependencies: Set<UUID> = [],
        at now: Date
    ) throws -> EnqueueDisposition {
        try database.write { db in
            try Self.enqueue(
                in: db,
                entityType: entityType,
                entityID: entityID,
                operation: operation,
                payloadJSON: payloadJSON,
                baseVersion: baseVersion,
                dependencies: dependencies,
                at: now
            )
        }
    }

    func pendingCount() throws -> Int {
        try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pending_mutations") ?? 0
        }
    }

    func conflictCount() throws -> Int {
        try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_conflicts") ?? 0
        }
    }

    func nextReady(at now: Date) throws -> PendingMutation? {
        try database.write { db in
            let records = try PendingMutationRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM pending_mutations
                    WHERE state IN (?, ?) AND (nextRetryAt IS NULL OR nextRetryAt <= ?)
                    """,
                arguments: [
                    MutationState.queued.rawValue,
                    MutationState.retry.rawValue,
                    WireDateCodec.encode(now)
                ]
            )
            let pendingEntityIDs = Set(
                try String.fetchAll(db, sql: "SELECT entityID FROM pending_mutations")
            )
            let ready = try records.filter { record in
                let dependencies = try String.fetchAll(
                    db,
                    sql: "SELECT entityID FROM pending_mutation_dependencies WHERE mutationID = ?",
                    arguments: [record.id]
                )
                return dependencies.allSatisfy { !pendingEntityIDs.contains($0) }
            }
            guard var record = ready.sorted(by: Self.ordersBefore).first else { return nil }
            record.state = .inFlight
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
            return try Self.makeMutation(record, in: db)
        }
    }

    func all() throws -> [PendingMutation] {
        try database.read { db in
            try PendingMutationRecord
                .fetchAll(db)
                .map { try Self.makeMutation($0, in: db) }
                .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        }
    }

    static func enqueue(
        in db: Database,
        entityType: PlanningEntityKind,
        entityID: UUID,
        operation: MutationOperation,
        payloadJSON: Data,
        baseVersion: Int64?,
        dependencies: Set<UUID>,
        at now: Date
    ) throws -> EnqueueDisposition {
        let entity = entityID.uuidString.lowercased()
        let dedupeKey = "\(entityType.rawValue):\(entity)"
        let existing = try PendingMutationRecord.fetchOne(
            db,
            sql: "SELECT * FROM pending_mutations WHERE dedupeKey = ?",
            arguments: [dedupeKey]
        )
        if let existing, existing.state == .conflict {
            throw RepositoryError.conflictExists(entityID)
        }
        if let existing, existing.operation == .create, operation == .delete {
            try cancelUnsyncedCreate(in: db, entityType: entityType, entityID: entityID)
            return .cancelledUnsyncedCreate
        }

        let timestamp = WireDateCodec.encode(now)
        let existingDependencies: Set<UUID>
        if let existing {
            let values = try String.fetchAll(
                db,
                sql: "SELECT entityID FROM pending_mutation_dependencies WHERE mutationID = ?",
                arguments: [existing.id]
            )
            existingDependencies = Set(try values.map(uuid))
        } else {
            existingDependencies = []
        }
        var mergedDependencies = existingDependencies.union(dependencies)
        mergedDependencies.remove(entityID)
        var record = existing ?? PendingMutationRecord(
            id: UUID().uuidString.lowercased(),
            dedupeKey: dedupeKey,
            entityType: entityType,
            entityID: entity,
            operation: operation,
            payloadJSON: payloadJSON,
            baseVersion: baseVersion,
            attemptCount: 0,
            nextRetryAt: nil,
            lastErrorCode: nil,
            state: .queued,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        if existing != nil {
            record.operation = existing?.operation == .create ? .create : operation
            record.payloadJSON = payloadJSON
            record.baseVersion = existing?.baseVersion ?? baseVersion
            record.nextRetryAt = nil
            record.lastErrorCode = nil
            record.state = .queued
            record.updatedAt = timestamp
        }
        try record.save(db)
        try db.execute(
            sql: "DELETE FROM pending_mutation_dependencies WHERE mutationID = ?",
            arguments: [record.id]
        )
        for dependency in mergedDependencies.sorted(by: { $0.uuidString < $1.uuidString }) {
            try PendingMutationDependencyRecord(
                mutationID: record.id,
                entityID: dependency.uuidString.lowercased()
            ).insert(db)
        }
        return .queued(try uuid(record.id))
    }

    static func makeMutation(_ record: PendingMutationRecord, in db: Database) throws -> PendingMutation {
        let dependencyValues = try String.fetchAll(
            db,
            sql: "SELECT entityID FROM pending_mutation_dependencies WHERE mutationID = ?",
            arguments: [record.id]
        )
        return PendingMutation(
            id: try uuid(record.id),
            entityType: record.entityType,
            entityID: try uuid(record.entityID),
            operation: record.operation,
            payloadJSON: record.payloadJSON,
            baseVersion: record.baseVersion,
            attemptCount: record.attemptCount,
            nextRetryAt: try record.nextRetryAt.map(date),
            lastErrorCode: record.lastErrorCode,
            state: record.state,
            dependencies: Set(try dependencyValues.map(uuid)),
            createdAt: try date(record.createdAt),
            updatedAt: try date(record.updatedAt)
        )
    }

    private static func ordersBefore(_ lhs: PendingMutationRecord, _ rhs: PendingMutationRecord) -> Bool {
        let leftRank = rank(entity: lhs.entityType, operation: lhs.operation)
        let rightRank = rank(entity: rhs.entityType, operation: rhs.operation)
        if leftRank != rightRank { return leftRank < rightRank }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id < rhs.id
    }

    private static func rank(entity: PlanningEntityKind, operation: MutationOperation) -> Int {
        if operation == .delete {
            switch entity {
            case .entityLink: return 0
            case .task, .note, .ideaNote: return 1
            case .goal, .idea: return 2
            case .folder: return 3
            case .tag: return 4
            case .focus, .settings: return 5
            }
        }
        switch entity {
        case .tag: return 0
        case .folder: return 1
        case .goal, .idea: return 2
        case .task, .note, .ideaNote: return 3
        case .entityLink: return 4
        case .focus, .settings: return 5
        }
    }

    func returnToQueue(_ mutation: PendingMutation, errorCode: String?, at now: Date) throws {
        try database.write { db in
            guard var record = try PendingMutationRecord.fetchOne(db, key: mutation.id.uuidString.lowercased()) else {
                return
            }
            guard record.state == .inFlight else { return }
            record.state = .queued
            record.nextRetryAt = nil
            record.lastErrorCode = errorCode
            record.updatedAt = WireDateCodec.encode(now)
            try record.update(db)
        }
    }

    func scheduleRetry(
        _ mutation: PendingMutation,
        at nextRetryAt: Date,
        errorCode: String,
        updatedAt: Date
    ) throws {
        try database.write { db in
            guard var record = try PendingMutationRecord.fetchOne(db, key: mutation.id.uuidString.lowercased()) else {
                return
            }
            record.attemptCount = max(record.attemptCount, mutation.attemptCount) + 1
            record.nextRetryAt = WireDateCodec.encode(nextRetryAt)
            record.lastErrorCode = errorCode
            record.state = .retry
            record.updatedAt = WireDateCodec.encode(updatedAt)
            try record.update(db)
        }
    }

    func acknowledge(_ mutation: PendingMutation, ack: RemoteMutationAck, at now: Date) throws {
        try database.write { db in
            guard var current = try PendingMutationRecord.fetchOne(
                db,
                key: mutation.id.uuidString.lowercased()
            ) else { return }

            try IDMappingRecord(
                entityType: mutation.entityType,
                localID: mutation.entityID.uuidString.lowercased(),
                remoteID: ack.remoteID.uuidString.lowercased(),
                createdAt: WireDateCodec.encode(now)
            ).save(db)

            let isOriginalFlight = current.state == .inFlight
                && current.payloadJSON == mutation.payloadJSON
                && current.operation == mutation.operation
            if isOriginalFlight {
                if mutation.operation == .delete {
                    try PlanningPersistence.deleteEntity(
                        mutation.entityType,
                        id: mutation.entityID,
                        in: db
                    )
                } else {
                    try PlanningPersistence.acknowledgeEntity(
                        mutation.entityType,
                        localID: mutation.entityID,
                        remoteID: ack.remoteID,
                        version: ack.version,
                        serverPayloadJSON: ack.serverPayloadJSON,
                        in: db
                    )
                }
                try db.execute(
                    sql: "DELETE FROM pending_mutations WHERE id = ?",
                    arguments: [current.id]
                )
                return
            }

            try PlanningPersistence.attachRemoteIdentity(
                mutation.entityType,
                localID: mutation.entityID,
                remoteID: ack.remoteID,
                version: ack.version,
                in: db
            )
            if current.operation == .create {
                current.operation = .update
            }
            current.baseVersion = ack.version
            current.state = .queued
            current.nextRetryAt = nil
            current.lastErrorCode = nil
            current.updatedAt = WireDateCodec.encode(now)
            try current.update(db)
        }
    }

    func recordConflict(
        _ mutation: PendingMutation,
        code: String,
        serverVersion: Int64?,
        serverPayloadJSON: Data?,
        serverDeleted: Bool,
        at now: Date
    ) throws {
        try database.write { db in
            guard var pending = try PendingMutationRecord.fetchOne(
                db,
                key: mutation.id.uuidString.lowercased()
            ) else { return }
            let timestamp = WireDateCodec.encode(now)
            let existing = try SyncConflictRecord.fetchOne(
                db,
                sql: "SELECT * FROM sync_conflicts WHERE mutationID = ?",
                arguments: [pending.id]
            )
            try SyncConflictRecord(
                id: existing?.id ?? UUID().uuidString.lowercased(),
                mutationID: pending.id,
                entityType: pending.entityType,
                entityID: pending.entityID,
                operation: pending.operation,
                localPayloadJSON: pending.payloadJSON,
                serverPayloadJSON: serverPayloadJSON,
                baseVersion: pending.baseVersion,
                serverVersion: serverVersion,
                serverDeleted: serverDeleted,
                errorCode: code,
                createdAt: existing?.createdAt ?? timestamp,
                updatedAt: timestamp
            ).save(db)
            pending.state = .conflict
            pending.nextRetryAt = nil
            pending.lastErrorCode = code
            pending.updatedAt = timestamp
            try pending.update(db)
            try PlanningPersistence.setSyncState(
                .conflict,
                entityType: pending.entityType,
                entityID: try uuid(pending.entityID),
                in: db
            )
        }
    }

    func conflicts() throws -> [SyncConflict] {
        try database.read { db in
            try SyncConflictRecord.fetchAll(
                db,
                sql: "SELECT * FROM sync_conflicts ORDER BY createdAt, id"
            ).map { record in
                SyncConflict(
                    id: try uuid(record.id),
                    mutationID: try uuid(record.mutationID),
                    entityType: record.entityType,
                    entityID: try uuid(record.entityID),
                    operation: record.operation,
                    localPayloadJSON: record.localPayloadJSON,
                    serverPayloadJSON: record.serverPayloadJSON,
                    baseVersion: record.baseVersion,
                    serverVersion: record.serverVersion,
                    serverDeleted: record.serverDeleted,
                    errorCode: record.errorCode,
                    createdAt: try date(record.createdAt),
                    updatedAt: try date(record.updatedAt)
                )
            }
        }
    }

    func recoverInterrupted(at now: Date) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE pending_mutations
                    SET state = ?, nextRetryAt = NULL, lastErrorCode = ?, updatedAt = ?
                    WHERE state = ?
                    """,
                arguments: [
                    MutationState.queued.rawValue,
                    "interrupted",
                    WireDateCodec.encode(now),
                    MutationState.inFlight.rawValue
                ]
            )
        }
    }

    func pullBeforePushRequired() throws -> Bool {
        try database.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM sync_metadata WHERE key = ?",
                arguments: [Self.pullBeforePushKey]
            ) == "true"
        }
    }

    func didCompleteRequiredPull(_ snapshot: RemotePlanningSnapshot, at now: Date) throws {
        try database.write { db in
            var resetMutations = try PendingMutationRecord.fetchAll(
                db,
                sql: "SELECT * FROM pending_mutations WHERE state = ? AND lastErrorCode = ?",
                arguments: [MutationState.conflict.rawValue, "reset_pending_pull"]
            )
            for index in resetMutations.indices {
                let entityID = try uuid(resetMutations[index].entityID)
                switch try Self.pulledState(
                    for: resetMutations[index].entityType,
                    localID: entityID,
                    snapshot: snapshot,
                    in: db
                ) {
                case let .current(version):
                    resetMutations[index].baseVersion = version
                    resetMutations[index].attemptCount = 0
                    resetMutations[index].nextRetryAt = nil
                    resetMutations[index].lastErrorCode = nil
                    resetMutations[index].state = .queued
                    resetMutations[index].updatedAt = WireDateCodec.encode(now)
                    try resetMutations[index].update(db)
                    try db.execute(
                        sql: "DELETE FROM sync_conflicts WHERE mutationID = ?",
                        arguments: [resetMutations[index].id]
                    )
                    try PlanningPersistence.setSyncState(
                        Self.localSyncState(for: resetMutations[index].operation),
                        entityType: resetMutations[index].entityType,
                        entityID: entityID,
                        in: db
                    )
                case .serverDeleted:
                    if try PlanningPersistence.exists(resetMutations[index].entityType, id: entityID, in: db) {
                        try PlanningPersistence.deleteEntity(resetMutations[index].entityType, id: entityID, in: db)
                    }
                    try resetMutations[index].delete(db)
                case .unavailable:
                    resetMutations[index].lastErrorCode = "reset_pull_incomplete"
                    resetMutations[index].updatedAt = WireDateCodec.encode(now)
                    try resetMutations[index].update(db)
                }
            }
            try db.execute(
                sql: "DELETE FROM sync_metadata WHERE key = ?",
                arguments: [Self.pullBeforePushKey]
            )
            try Self.rebaseQueuedMutations(in: db, at: now)
        }
    }

    func resolve(_ conflictID: UUID, with resolution: ConflictResolution, at now: Date) throws {
        try database.write { db in
            guard let conflict = try SyncConflictRecord.fetchOne(
                db,
                key: conflictID.uuidString.lowercased()
            ) else { return }
            guard var pending = try PendingMutationRecord.fetchOne(db, key: conflict.mutationID) else {
                try conflict.delete(db)
                return
            }
            let entityID = try uuid(conflict.entityID)
            switch resolution {
            case .keepServer:
                if conflict.serverDeleted {
                    if try PlanningPersistence.exists(conflict.entityType, id: entityID, in: db) {
                        try PlanningPersistence.deleteEntity(conflict.entityType, id: entityID, in: db)
                    }
                    try pending.delete(db)
                    return
                }
                guard let payload = conflict.serverPayloadJSON else {
                    throw RepositoryError.missingServerPayload(conflictID)
                }
                try PlanningPersistence.applyServerPayload(
                    payload,
                    entityType: conflict.entityType,
                    localID: entityID,
                    in: db
                )
                try pending.delete(db)
            case .discard:
                if conflict.serverDeleted {
                    if try PlanningPersistence.exists(conflict.entityType, id: entityID, in: db) {
                        try PlanningPersistence.deleteEntity(conflict.entityType, id: entityID, in: db)
                    }
                    try pending.delete(db)
                    return
                }
                guard let payload = conflict.serverPayloadJSON else {
                    throw RepositoryError.missingServerPayload(conflictID)
                }
                try PlanningPersistence.applyServerPayload(
                    payload,
                    entityType: conflict.entityType,
                    localID: entityID,
                    in: db
                )
                try pending.delete(db)
            case .retryLocal:
                guard let serverVersion = conflict.serverVersion else {
                    throw RepositoryError.missingServerVersion(conflictID)
                }
                pending.baseVersion = serverVersion
                pending.attemptCount = 0
                pending.nextRetryAt = nil
                pending.lastErrorCode = nil
                pending.state = .queued
                pending.updatedAt = WireDateCodec.encode(now)
                try pending.update(db)
                try conflict.delete(db)
                try PlanningPersistence.setSyncState(
                    Self.localSyncState(for: pending.operation),
                    entityType: pending.entityType,
                    entityID: entityID,
                    in: db
                )
            case .resetCache:
                pending.attemptCount = 0
                pending.nextRetryAt = nil
                pending.lastErrorCode = "reset_pending_pull"
                pending.state = .conflict
                pending.updatedAt = WireDateCodec.encode(now)
                try pending.update(db)
                try PlanningPersistence.setSyncState(
                    .conflict,
                    entityType: pending.entityType,
                    entityID: entityID,
                    in: db
                )
                try PlanningPersistence.resetCachePreservingPending(in: db)
                try db.execute(
                    sql: """
                        INSERT INTO sync_metadata (key, value, updatedAt)
                        VALUES (?, 'true', ?)
                        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt
                        """,
                    arguments: [Self.pullBeforePushKey, WireDateCodec.encode(now)]
                )
            }
        }
    }

    func remoteID(for entityType: PlanningEntityKind, localID: UUID) throws -> UUID {
        try database.read { db in
            try PlanningPersistence.remoteID(for: entityType, localID: localID, in: db)
        }
    }

    private static func cancelUnsyncedCreate(
        in db: Database,
        entityType: PlanningEntityKind,
        entityID: UUID
    ) throws {
        let rootID = entityID.uuidString.lowercased()
        var affected = [rootID: entityType]
        var frontier = [(entityType, rootID)]
        var detachedTaskIDs = Set<String>()
        while let (parentType, dependency) = frontier.popLast() {
            let dependents = try Row.fetchAll(
                db,
                sql: """
                    SELECT mutation.id AS mutationID, mutation.entityType, mutation.entityID
                    FROM pending_mutation_dependencies dependency
                    JOIN pending_mutations mutation ON mutation.id = dependency.mutationID
                    WHERE dependency.entityID = ?
                """,
                arguments: [dependency]
            )
            for row in dependents {
                let rawType: String = row["entityType"]
                let dependentID: String = row["entityID"]
                let mutationID: String = row["mutationID"]
                guard let dependentType = PlanningEntityKind(rawValue: rawType) else {
                    throw PersistenceMappingError.invalidEnum(rawType)
                }
                guard ownsDependency(parent: parentType, child: dependentType) else {
                    try db.execute(
                        sql: "DELETE FROM pending_mutation_dependencies WHERE mutationID = ? AND entityID = ?",
                        arguments: [mutationID, dependency]
                    )
                    if parentType == .tag, dependentType == .task {
                        detachedTaskIDs.insert(dependentID)
                    }
                    continue
                }
                if affected[dependentID] == nil {
                    affected[dependentID] = dependentType
                    frontier.append((dependentType, dependentID))
                }
            }
        }
        let entities = try affected.map { (type: $0.value, id: try uuid($0.key)) }
        for affectedID in affected.keys {
            try db.execute(
                sql: "DELETE FROM pending_mutations WHERE entityID = ?",
                arguments: [affectedID]
            )
        }
        let orderedEntities = entities.sorted {
            let leftRank = rank(entity: $0.0, operation: .delete)
            let rightRank = rank(entity: $1.0, operation: .delete)
            if leftRank != rightRank { return leftRank < rightRank }
            return $0.1.uuidString < $1.1.uuidString
        }
        for (type, id) in orderedEntities {
            if try PlanningPersistence.exists(type, id: id, in: db) {
                try PlanningPersistence.deleteEntity(type, id: id, in: db)
            }
        }
        if try PlanningPersistence.exists(entityType, id: entityID, in: db) {
            try PlanningPersistence.deleteEntity(entityType, id: entityID, in: db)
        }
        for taskID in detachedTaskIDs {
            try refreshTaskMutationPayload(taskID: taskID, in: db)
        }
    }

    private static func refreshTaskMutationPayload(taskID: String, in db: Database) throws {
        guard let task = try TaskRecord.fetchOne(db, key: taskID),
              var mutation = try PendingMutationRecord.fetchOne(
                  db,
                  sql: "SELECT * FROM pending_mutations WHERE entityType = ? AND entityID = ?",
                  arguments: [PlanningEntityKind.task.rawValue, taskID]
              ) else { return }
        let tags = try TagRecord.fetchAll(
            db,
            sql: """
                SELECT tag.* FROM tags tag
                JOIN task_tags relation ON relation.tagID = tag.id
                WHERE relation.taskID = ? AND tag.deletedAt IS NULL
                ORDER BY tag.createdAt DESC, tag.id ASC
                """,
            arguments: [taskID]
        ).map { try $0.dto() }
        let checklist = try ChecklistItemRecord.fetchAll(
            db,
            sql: """
                SELECT * FROM checklist_items WHERE taskID = ?
                ORDER BY displayOrder ASC, createdAt DESC, id ASC
                """,
            arguments: [taskID]
        ).map { try $0.dto() }
        mutation.payloadJSON = try WireJSON.encoder().encode(task.dto(tags: tags, checklistItems: checklist))
        try mutation.update(db)
    }

    private static func ownsDependency(
        parent: PlanningEntityKind,
        child: PlanningEntityKind
    ) -> Bool {
        if child == .entityLink { return true }
        switch parent {
        case .folder:
            return child == .folder || child == .goal || child == .idea || child == .note
        case .goal:
            return child == .task
        case .idea:
            return child == .ideaNote
        case .tag, .task, .ideaNote, .note, .entityLink, .focus, .settings:
            return false
        }
    }

    private static func rebaseQueuedMutations(in db: Database, at now: Date) throws {
        var records = try PendingMutationRecord.fetchAll(
            db,
            sql: "SELECT * FROM pending_mutations WHERE operation != ? AND state IN (?, ?)",
            arguments: [
                MutationOperation.create.rawValue,
                MutationState.queued.rawValue,
                MutationState.retry.rawValue
            ]
        )
        for index in records.indices {
            let entityID = try uuid(records[index].entityID)
            if records[index].entityType == .tag {
                records[index].baseVersion = nil
            } else {
                let localVersion = try PlanningPersistence.version(
                    for: records[index].entityType,
                    id: entityID,
                    in: db
                )
                records[index].baseVersion = max(records[index].baseVersion ?? 0, localVersion)
            }
            records[index].updatedAt = WireDateCodec.encode(now)
            records[index].state = .queued
            try records[index].update(db)
        }
    }

    private static func localSyncState(for operation: MutationOperation) -> SyncState {
        switch operation {
        case .create: .pendingCreate
        case .delete: .pendingDelete
        case .update, .reorder, .move: .pendingUpdate
        }
    }

    private enum PulledState {
        case current(Int64)
        case serverDeleted
        case unavailable
    }

    private static func pulledState(
        for entityType: PlanningEntityKind,
        localID: UUID,
        snapshot: RemotePlanningSnapshot,
        in db: Database
    ) throws -> PulledState {
        let collection: RemotePlanningCollection
        switch entityType {
        case .folder: collection = .folders
        case .goal: collection = .goals
        case .task: collection = .tasks
        case .idea: collection = .ideas
        case .ideaNote: collection = .ideaNotes
        case .note: collection = .notes
        case .entityLink: collection = .entityLinks
        case .tag, .focus, .settings: return .unavailable
        }
        guard snapshot.loadedCollections.contains(collection) else { return .unavailable }
        let mappingValue = try String.fetchOne(
            db,
            sql: "SELECT remoteID FROM id_mappings WHERE entityType = ? AND localID = ?",
            arguments: [entityType.rawValue, localID.uuidString.lowercased()]
        )
        let mapped = try PlanningPersistence.remoteIDIfPresent(
            for: entityType,
            localID: localID,
            in: db
        ) ?? mappingValue.flatMap { UUID(uuidString: $0) }
        guard let remoteID = mapped else { return .unavailable }
        let version: Int64?
        switch entityType {
        case .folder: version = snapshot.folders.first(where: { $0.id == remoteID })?.version
        case .goal: version = snapshot.goals.first(where: { $0.id == remoteID })?.version
        case .task: version = snapshot.tasks.first(where: { $0.id == remoteID })?.version
        case .idea: version = snapshot.ideas?.first(where: { $0.id == remoteID })?.version
        case .ideaNote: version = snapshot.ideaNotes?.first(where: { $0.id == remoteID })?.version
        case .note: version = snapshot.notes?.first(where: { $0.id == remoteID })?.version
        case .entityLink: version = snapshot.links?.first(where: { $0.id == remoteID })?.version
        case .tag, .focus, .settings: version = nil
        }
        return version.map(PulledState.current) ?? .serverDeleted
    }
}
