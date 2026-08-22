import Foundation

struct ActionFolderDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let parentFolderId: UUID?
    let name: String
    let description: String?
    let displayOrder: Int
    let archived: Bool
    let shared: Bool
    let fullAccess: Bool
    let version: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct ActionGoalDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let folderId: UUID
    let name: String
    let description: String?
    let status: PlanningStatus
    let archived: Bool
    let shared: Bool
    let fullAccess: Bool
    let version: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct ActionTaskDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let goalId: UUID
    let title: String
    let description: String?
    let type: TaskType
    let priorityShadow: Int
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

    enum CodingKeys: String, CodingKey {
        case id, goalId, title, description, type, effort, status, plannedTime, dueTime
        case archived, shared, fullAccess, creatorUserId, creatorEmail, creatorName, version
        case tags, checklistItems, recurrence, createdAt, updatedAt
        case priorityShadow = "priority"
    }
}

struct ActionUpdateTaskRequestDTO: Encodable, Equatable, Sendable {
    let title: String
    let description: String?
    let type: TaskType
    private let priorityShadow: Int
    let effort: Int?
    let status: PlanningStatus
    let plannedTime: Date?
    let dueTime: Date?
    let archived: Bool
    let tagIds: [UUID]?
    let checklistItems: [ChecklistItemRequestDTO]?
    let version: Int64

    enum CodingKeys: String, CodingKey {
        case title, description, type, effort, status, plannedTime, dueTime
        case archived, tagIds, checklistItems, version
        case priorityShadow = "priority"
    }

    init(
        preservingPriorityFrom task: ActionTaskDTO,
        title: String,
        description: String?,
        type: TaskType,
        effort: Int?,
        status: PlanningStatus,
        plannedTime: Date?,
        dueTime: Date?,
        archived: Bool,
        tagIds: [UUID]?,
        checklistItems: [ChecklistItemRequestDTO]?
    ) {
        self.title = title
        self.description = description
        self.type = type
        priorityShadow = task.priorityShadow
        self.effort = effort
        self.status = status
        self.plannedTime = plannedTime
        self.dueTime = dueTime
        self.archived = archived
        self.tagIds = tagIds
        self.checklistItems = checklistItems
        version = task.version
    }

    init(
        task: ActionTaskDTO,
        tagIds: [UUID]?,
        checklistItems: [ChecklistItemRequestDTO]?
    ) {
        self.init(
            preservingPriorityFrom: task,
            title: task.title,
            description: task.description,
            type: task.type,
            effort: task.effort,
            status: task.status,
            plannedTime: task.plannedTime,
            dueTime: task.dueTime,
            archived: task.archived,
            tagIds: tagIds,
            checklistItems: checklistItems
        )
    }
}

struct ActionIdeaDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let folderId: UUID
    let title: String
    let body: String?
    let status: String
    let displayOrder: Int
    let archived: Bool
    let allowAuthorNoteEdits: Bool
    let shared: Bool
    let fullAccess: Bool
    let creatorUserId: UUID?
    let creatorEmail: String?
    let creatorName: String?
    let version: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct ActionIdeaNoteDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let ideaId: UUID
    let eventType: String
    let body: String?
    let metadata: [String: JSONValue]
    let authorUserId: UUID?
    let authorEmail: String?
    let authorName: String?
    let version: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct ActionNoteDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let folderId: UUID
    let title: String
    let body: String?
    let displayOrder: Int
    let archived: Bool
    let shared: Bool
    let fullAccess: Bool
    let authorUserId: UUID?
    let authorEmail: String?
    let authorName: String?
    let version: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct ActionIdeaNoteListResponseDTO: Codable, Equatable, Sendable {
    let items: [ActionIdeaNoteDTO]
}

struct ActionEntityReferenceDTO: Codable, Equatable, Sendable {
    struct Identity: Equatable, Sendable {
        let type: LinkedEntityType
        let id: UUID
        let title: String
    }

    let type: LinkedEntityType?
    let id: UUID?
    let title: String?
    let subtitle: String?
    let status: String?
    let path: String?
    let archived: Bool?
    let accessible: Bool
    let redacted: Bool

    var identity: Identity? {
        guard !redacted, let type, let id, let title else { return nil }
        return Identity(type: type, id: id, title: title)
    }
}

struct ActionEntityLinkDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let source: ActionEntityReferenceDTO
    let target: ActionEntityReferenceDTO
    let relationType: EntityRelationType
    let createdByUserId: UUID?
    let createdByName: String?
    let createdAt: Date
    let updatedAt: Date
    let version: Int64
}

struct ActionEntityLinkListResponseDTO: Codable, Equatable, Sendable {
    let items: [ActionEntityLinkDTO]
}
