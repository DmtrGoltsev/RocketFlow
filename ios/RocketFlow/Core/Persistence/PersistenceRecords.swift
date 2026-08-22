import Foundation
import GRDB

enum SyncState: String, Codable, CaseIterable, Equatable, Sendable {
    case synced
    case pendingCreate
    case pendingUpdate
    case pendingDelete
    case conflict
}

enum PlanningEntityKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case tag
    case folder
    case goal
    case task
    case idea
    case ideaNote
    case note
    case entityLink
    case focus
    case settings
}

enum MutationOperation: String, Codable, Equatable, Sendable {
    case create
    case update
    case delete
    case reorder
    case move
}

enum MutationState: String, Codable, Equatable, Sendable {
    case queued
    case inFlight
    case retry
    case conflict
}

enum PersistenceMappingError: Error, Equatable, Sendable {
    case invalidUUID(String)
    case invalidDate(String)
    case invalidEnum(String)
}

struct FolderRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "folders"

    var id: String
    var remoteID: String?
    var parentID: String?
    var name: String
    var details: String
    var displayOrder: Int
    var archived: Bool
    var shared: Bool
    var fullAccess: Bool
    var version: Int64
    var syncState: SyncState
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    init(draft: FolderDraft, now: Date) {
        id = draft.id.uuidString.lowercased()
        remoteID = nil
        parentID = draft.parentFolderID?.uuidString.lowercased()
        name = draft.name
        details = draft.description
        displayOrder = draft.displayOrder
        archived = false
        shared = false
        fullAccess = true
        version = 0
        syncState = .pendingCreate
        createdAt = WireDateCodec.encode(now)
        updatedAt = WireDateCodec.encode(now)
        deletedAt = nil
    }

    init(dto: FolderDTO, localID: UUID? = nil, parentLocalID: UUID? = nil) {
        id = (localID ?? dto.id).uuidString.lowercased()
        remoteID = dto.id.uuidString.lowercased()
        parentID = parentLocalID?.uuidString.lowercased()
            ?? dto.parentFolderId?.uuidString.lowercased()
        name = dto.name
        details = dto.description
        displayOrder = dto.displayOrder
        archived = dto.archived
        shared = dto.shared
        fullAccess = dto.fullAccess
        version = dto.version
        syncState = .synced
        createdAt = WireDateCodec.encode(dto.createdAt)
        updatedAt = WireDateCodec.encode(dto.updatedAt)
        deletedAt = nil
    }

    func dto() throws -> FolderDTO {
        FolderDTO(
            id: try uuid(id),
            parentFolderId: try parentID.map(uuid),
            name: name,
            description: details,
            displayOrder: displayOrder,
            archived: archived,
            shared: shared,
            fullAccess: fullAccess,
            version: version,
            createdAt: try date(createdAt),
            updatedAt: try date(updatedAt)
        )
    }
}

struct GoalRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "goals"

    var id: String
    var remoteID: String?
    var folderID: String
    var name: String
    var details: String
    var status: PlanningStatus
    var archived: Bool
    var shared: Bool
    var fullAccess: Bool
    var version: Int64
    var syncState: SyncState
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    init(draft: GoalDraft, now: Date) {
        id = draft.id.uuidString.lowercased()
        remoteID = nil
        folderID = draft.folderID.uuidString.lowercased()
        name = draft.name
        details = draft.description
        status = draft.status
        archived = false
        shared = false
        fullAccess = true
        version = 0
        syncState = .pendingCreate
        createdAt = WireDateCodec.encode(now)
        updatedAt = WireDateCodec.encode(now)
        deletedAt = nil
    }

    init(dto: GoalDTO, localID: UUID? = nil, folderLocalID: UUID? = nil) {
        id = (localID ?? dto.id).uuidString.lowercased()
        remoteID = dto.id.uuidString.lowercased()
        folderID = (folderLocalID ?? dto.folderId).uuidString.lowercased()
        name = dto.name
        details = dto.description
        status = dto.status
        archived = dto.archived
        shared = dto.shared
        fullAccess = dto.fullAccess
        version = dto.version
        syncState = .synced
        createdAt = WireDateCodec.encode(dto.createdAt)
        updatedAt = WireDateCodec.encode(dto.updatedAt)
        deletedAt = nil
    }

    func dto() throws -> GoalDTO {
        GoalDTO(
            id: try uuid(id),
            folderId: try uuid(folderID),
            name: name,
            description: details,
            status: status,
            archived: archived,
            shared: shared,
            fullAccess: fullAccess,
            version: version,
            createdAt: try date(createdAt),
            updatedAt: try date(updatedAt)
        )
    }
}

struct TaskRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "tasks"

    var id: String
    var remoteID: String?
    var goalID: String
    var title: String
    var details: String
    var type: TaskType
    var priorityShadow: Int
    var effort: Int
    var status: PlanningStatus
    var plannedTime: String?
    var dueTime: String?
    var archived: Bool
    var shared: Bool
    var fullAccess: Bool
    var creatorUserID: String?
    var creatorEmail: String?
    var creatorName: String?
    var recurrenceJSON: Data?
    var version: Int64
    var syncState: SyncState
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    init(draft: TaskDraft, now: Date) {
        id = draft.id.uuidString.lowercased()
        remoteID = nil
        goalID = draft.goalID.uuidString.lowercased()
        title = draft.title
        details = draft.description
        type = draft.type
        priorityShadow = TaskPriorityCompatibility.defaultShadow
        effort = draft.effort
        status = draft.status
        plannedTime = draft.plannedTime.map(WireDateCodec.encode)
        dueTime = draft.dueTime.map(WireDateCodec.encode)
        archived = false
        shared = false
        fullAccess = true
        creatorUserID = nil
        creatorEmail = nil
        creatorName = nil
        recurrenceJSON = nil
        version = 0
        syncState = .pendingCreate
        createdAt = WireDateCodec.encode(now)
        updatedAt = WireDateCodec.encode(now)
        deletedAt = nil
    }

    init(dto: TaskDTO, localID: UUID? = nil, goalLocalID: UUID? = nil) throws {
        id = (localID ?? dto.id).uuidString.lowercased()
        remoteID = dto.id.uuidString.lowercased()
        goalID = (goalLocalID ?? dto.goalId).uuidString.lowercased()
        title = dto.title
        details = dto.description
        type = dto.type
        priorityShadow = dto.priorityShadow
        effort = dto.effort
        status = dto.status
        plannedTime = dto.plannedTime.map(WireDateCodec.encode)
        dueTime = dto.dueTime.map(WireDateCodec.encode)
        archived = dto.archived
        shared = dto.shared
        fullAccess = dto.fullAccess
        creatorUserID = dto.creatorUserId?.uuidString.lowercased()
        creatorEmail = dto.creatorEmail
        creatorName = dto.creatorName
        recurrenceJSON = try dto.recurrence.map { try WireJSON.encoder().encode($0) }
        version = dto.version
        syncState = .synced
        createdAt = WireDateCodec.encode(dto.createdAt)
        updatedAt = WireDateCodec.encode(dto.updatedAt)
        deletedAt = nil
    }

    func dto(tags: [TaskTagDTO], checklistItems: [ChecklistItemDTO]) throws -> TaskDTO {
        let recurrence = try recurrenceJSON.map {
            try WireJSON.decoder().decode(RecurrenceDTO.self, from: $0)
        }
        let wire = TaskWire(
            id: try uuid(id),
            goalId: try uuid(goalID),
            title: title,
            description: details,
            type: type,
            priority: priorityShadow,
            effort: effort,
            status: status,
            plannedTime: try plannedTime.map(date),
            dueTime: try dueTime.map(date),
            archived: archived,
            shared: shared,
            fullAccess: fullAccess,
            creatorUserId: try creatorUserID.map(uuid),
            creatorEmail: creatorEmail,
            creatorName: creatorName,
            version: version,
            tags: tags,
            checklistItems: checklistItems,
            recurrence: recurrence,
            createdAt: try date(createdAt),
            updatedAt: try date(updatedAt)
        )
        return try WireJSON.decoder().decode(
            TaskDTO.self,
            from: WireJSON.encoder().encode(wire)
        )
    }
}

private struct TaskWire: Encodable {
    let id: UUID
    let goalId: UUID
    let title: String
    let description: String
    let type: TaskType
    let priority: Int
    let effort: Int
    let status: PlanningStatus
    let plannedTime: Date?
    let dueTime: Date?
    let archived: Bool
    let shared: Bool
    let fullAccess: Bool
    let creatorUserId: UUID?
    let creatorEmail: String?
    let creatorName: String?
    let version: Int64
    let tags: [TaskTagDTO]
    let checklistItems: [ChecklistItemDTO]
    let recurrence: RecurrenceDTO?
    let createdAt: Date
    let updatedAt: Date
}

struct ChecklistItemRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "checklist_items"

    var id: String
    var remoteID: String?
    var taskID: String
    var text: String
    var checked: Bool
    var displayOrder: Int
    var version: Int64
    var createdAt: String
    var updatedAt: String

    init(draft: ChecklistItemDraft, now: Date) {
        id = draft.id.uuidString.lowercased()
        remoteID = nil
        taskID = draft.taskID.uuidString.lowercased()
        text = draft.text
        checked = draft.checked
        displayOrder = draft.displayOrder
        version = 0
        createdAt = WireDateCodec.encode(now)
        updatedAt = WireDateCodec.encode(now)
    }

    init(dto: ChecklistItemDTO, taskLocalID: UUID? = nil) {
        id = dto.id.uuidString.lowercased()
        remoteID = dto.id.uuidString.lowercased()
        taskID = (taskLocalID ?? dto.taskId).uuidString.lowercased()
        text = dto.text
        checked = dto.checked
        displayOrder = dto.displayOrder
        version = dto.version
        createdAt = WireDateCodec.encode(dto.createdAt)
        updatedAt = WireDateCodec.encode(dto.updatedAt)
    }

    func dto() throws -> ChecklistItemDTO {
        ChecklistItemDTO(
            id: try uuid(id),
            taskId: try uuid(taskID),
            text: text,
            checked: checked,
            displayOrder: displayOrder,
            version: version,
            createdAt: try date(createdAt),
            updatedAt: try date(updatedAt)
        )
    }
}

struct TagRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "tags"

    var id: String
    var remoteID: String?
    var name: String
    var color: String?
    var syncState: SyncState
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    init(draft: TagDraft, now: Date) {
        id = draft.id.uuidString.lowercased()
        remoteID = nil
        name = draft.name
        color = draft.color
        syncState = .pendingCreate
        createdAt = WireDateCodec.encode(now)
        updatedAt = WireDateCodec.encode(now)
        deletedAt = nil
    }

    init(dto: TaskTagDTO, now: Date) {
        id = dto.id.uuidString.lowercased()
        remoteID = dto.id.uuidString.lowercased()
        name = dto.name
        color = dto.color
        syncState = .synced
        createdAt = WireDateCodec.encode(now)
        updatedAt = WireDateCodec.encode(now)
        deletedAt = nil
    }

    func dto() throws -> TaskTagDTO {
        TaskTagDTO(id: try uuid(id), name: name, color: color)
    }
}

struct TaskTagRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "task_tags"
    var taskID: String
    var tagID: String
}

struct IdeaRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "ideas"

    var id: String
    var remoteID: String?
    var folderID: String
    var title: String
    var body: String
    var status: String
    var displayOrder: Int
    var archived: Bool
    var allowAuthorNoteEdits: Bool
    var shared: Bool
    var fullAccess: Bool
    var creatorUserID: String?
    var creatorEmail: String?
    var creatorName: String?
    var version: Int64
    var syncState: SyncState
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    init(draft: IdeaDraft, now: Date) {
        id = draft.id.uuidString.lowercased()
        remoteID = nil
        folderID = draft.folderID.uuidString.lowercased()
        title = draft.title
        body = draft.body
        status = draft.status
        displayOrder = draft.displayOrder
        archived = false
        allowAuthorNoteEdits = draft.allowAuthorNoteEdits
        shared = false
        fullAccess = true
        creatorUserID = nil
        creatorEmail = nil
        creatorName = nil
        version = 0
        syncState = .pendingCreate
        createdAt = WireDateCodec.encode(now)
        updatedAt = WireDateCodec.encode(now)
        deletedAt = nil
    }

    init(dto: IdeaDTO, localID: UUID? = nil, folderLocalID: UUID? = nil) {
        id = (localID ?? dto.id).uuidString.lowercased()
        remoteID = dto.id.uuidString.lowercased()
        folderID = (folderLocalID ?? dto.folderId).uuidString.lowercased()
        title = dto.title
        body = dto.body
        status = dto.status
        displayOrder = dto.displayOrder
        archived = dto.archived
        allowAuthorNoteEdits = dto.allowAuthorNoteEdits
        shared = dto.shared
        fullAccess = dto.fullAccess
        creatorUserID = dto.creatorUserId?.uuidString.lowercased()
        creatorEmail = dto.creatorEmail
        creatorName = dto.creatorName
        version = dto.version
        syncState = .synced
        createdAt = WireDateCodec.encode(dto.createdAt)
        updatedAt = WireDateCodec.encode(dto.updatedAt)
        deletedAt = nil
    }

    func dto() throws -> IdeaDTO {
        IdeaDTO(
            id: try uuid(id),
            folderId: try uuid(folderID),
            title: title,
            body: body,
            status: status,
            displayOrder: displayOrder,
            archived: archived,
            allowAuthorNoteEdits: allowAuthorNoteEdits,
            shared: shared,
            fullAccess: fullAccess,
            creatorUserId: try creatorUserID.map(uuid),
            creatorEmail: creatorEmail,
            creatorName: creatorName,
            version: version,
            createdAt: try date(createdAt),
            updatedAt: try date(updatedAt)
        )
    }
}

struct IdeaNoteRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "idea_notes"

    var id: String
    var remoteID: String?
    var ideaID: String
    var eventType: String
    var body: String
    var metadataJSON: Data
    var authorUserID: String?
    var authorEmail: String?
    var authorName: String?
    var version: Int64
    var createdAt: String
    var updatedAt: String

    init(draft: IdeaNoteDraft, now: Date) throws {
        id = draft.id.uuidString.lowercased()
        remoteID = nil
        ideaID = draft.ideaID.uuidString.lowercased()
        eventType = draft.eventType
        body = draft.body
        metadataJSON = try WireJSON.encoder().encode(draft.metadata)
        authorUserID = nil
        authorEmail = nil
        authorName = nil
        version = 0
        createdAt = WireDateCodec.encode(now)
        updatedAt = WireDateCodec.encode(now)
    }

    init(dto: IdeaNoteDTO, ideaLocalID: UUID? = nil) throws {
        id = dto.id.uuidString.lowercased()
        remoteID = dto.id.uuidString.lowercased()
        ideaID = (ideaLocalID ?? dto.ideaId).uuidString.lowercased()
        eventType = dto.eventType
        body = dto.body
        metadataJSON = try WireJSON.encoder().encode(dto.metadata)
        authorUserID = dto.authorUserId?.uuidString.lowercased()
        authorEmail = dto.authorEmail
        authorName = dto.authorName
        version = dto.version
        createdAt = WireDateCodec.encode(dto.createdAt)
        updatedAt = WireDateCodec.encode(dto.updatedAt)
    }

    func dto() throws -> IdeaNoteDTO {
        IdeaNoteDTO(
            id: try uuid(id),
            ideaId: try uuid(ideaID),
            eventType: eventType,
            body: body,
            metadata: try WireJSON.decoder().decode([String: JSONValue].self, from: metadataJSON),
            authorUserId: try authorUserID.map(uuid),
            authorEmail: authorEmail,
            authorName: authorName,
            version: version,
            createdAt: try date(createdAt),
            updatedAt: try date(updatedAt)
        )
    }
}

struct NoteRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "notes"

    var id: String
    var remoteID: String?
    var folderID: String
    var title: String
    var body: String
    var displayOrder: Int
    var archived: Bool
    var shared: Bool
    var fullAccess: Bool
    var authorUserID: String?
    var authorEmail: String?
    var authorName: String?
    var version: Int64
    var syncState: SyncState
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    init(draft: NoteDraft, now: Date) {
        id = draft.id.uuidString.lowercased()
        remoteID = nil
        folderID = draft.folderID.uuidString.lowercased()
        title = draft.title
        body = draft.body
        displayOrder = draft.displayOrder
        archived = false
        shared = false
        fullAccess = true
        authorUserID = nil
        authorEmail = nil
        authorName = nil
        version = 0
        syncState = .pendingCreate
        createdAt = WireDateCodec.encode(now)
        updatedAt = WireDateCodec.encode(now)
        deletedAt = nil
    }

    init(dto: NoteDTO, localID: UUID? = nil, folderLocalID: UUID? = nil) {
        id = (localID ?? dto.id).uuidString.lowercased()
        remoteID = dto.id.uuidString.lowercased()
        folderID = (folderLocalID ?? dto.folderId).uuidString.lowercased()
        title = dto.title
        body = dto.body
        displayOrder = dto.displayOrder
        archived = dto.archived
        shared = dto.shared
        fullAccess = dto.fullAccess
        authorUserID = dto.authorUserId?.uuidString.lowercased()
        authorEmail = dto.authorEmail
        authorName = dto.authorName
        version = dto.version
        syncState = .synced
        createdAt = WireDateCodec.encode(dto.createdAt)
        updatedAt = WireDateCodec.encode(dto.updatedAt)
        deletedAt = nil
    }

    func dto() throws -> NoteDTO {
        NoteDTO(
            id: try uuid(id),
            folderId: try uuid(folderID),
            title: title,
            body: body,
            displayOrder: displayOrder,
            archived: archived,
            shared: shared,
            fullAccess: fullAccess,
            authorUserId: try authorUserID.map(uuid),
            authorEmail: authorEmail,
            authorName: authorName,
            version: version,
            createdAt: try date(createdAt),
            updatedAt: try date(updatedAt)
        )
    }
}

struct EntityLinkRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "entity_links"

    var id: String
    var remoteID: String?
    var sourceType: LinkedEntityType
    var sourceID: String
    var targetType: LinkedEntityType
    var targetID: String
    var relationType: EntityRelationType
    var payloadJSON: Data
    var version: Int64
    var syncState: SyncState
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    init(dto: EntityLinkDTO, localID: UUID? = nil) throws {
        id = (localID ?? dto.id).uuidString.lowercased()
        remoteID = dto.id.uuidString.lowercased()
        sourceType = dto.source.type
        sourceID = dto.source.id.uuidString.lowercased()
        targetType = dto.target.type
        targetID = dto.target.id.uuidString.lowercased()
        relationType = dto.relationType
        payloadJSON = try WireJSON.encoder().encode(dto)
        version = dto.version
        syncState = .synced
        createdAt = WireDateCodec.encode(dto.createdAt)
        updatedAt = WireDateCodec.encode(dto.updatedAt)
        deletedAt = nil
    }

    func dto() throws -> EntityLinkDTO {
        try WireJSON.decoder().decode(EntityLinkDTO.self, from: payloadJSON)
    }
}

struct PendingMutationRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "pending_mutations"

    var id: String
    var dedupeKey: String
    var entityType: PlanningEntityKind
    var entityID: String
    var operation: MutationOperation
    var payloadJSON: Data
    var baseVersion: Int64?
    var attemptCount: Int
    var nextRetryAt: String?
    var lastErrorCode: String?
    var state: MutationState
    var createdAt: String
    var updatedAt: String
}

struct PendingMutationDependencyRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "pending_mutation_dependencies"
    var mutationID: String
    var entityID: String
}

struct SyncConflictRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "sync_conflicts"

    var id: String
    var mutationID: String
    var entityType: PlanningEntityKind
    var entityID: String
    var operation: MutationOperation
    var localPayloadJSON: Data
    var serverPayloadJSON: Data?
    var baseVersion: Int64?
    var serverVersion: Int64?
    var serverDeleted: Bool
    var errorCode: String
    var createdAt: String
    var updatedAt: String
}

struct IDMappingRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "id_mappings"
    var entityType: PlanningEntityKind
    var localID: String
    var remoteID: String
    var createdAt: String
}

func uuid(_ value: String) throws -> UUID {
    guard let id = UUID(uuidString: value) else {
        throw PersistenceMappingError.invalidUUID(value)
    }
    return id
}

func date(_ value: String) throws -> Date {
    do {
        return try WireDateCodec.decode(value)
    } catch {
        throw PersistenceMappingError.invalidDate(value)
    }
}
