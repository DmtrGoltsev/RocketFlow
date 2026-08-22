import Foundation

enum PlanningStatus: String, Codable, CaseIterable, Sendable {
    case todo
    case inProgress = "in_progress"
    case done
    case cancelled
}

enum TaskType: String, Codable, CaseIterable, Sendable {
    case green
    case red
}

enum RecurrenceMode: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
}

enum Weekday: String, Codable, CaseIterable, Sendable {
    case monday = "MONDAY"
    case tuesday = "TUESDAY"
    case wednesday = "WEDNESDAY"
    case thursday = "THURSDAY"
    case friday = "FRIDAY"
    case saturday = "SATURDAY"
    case sunday = "SUNDAY"
}

enum TaskPriorityCompatibility {
    static let defaultShadow = 5
}

struct FolderDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let parentFolderId: UUID?
    let name: String
    let description: String
    let displayOrder: Int
    let archived: Bool
    let shared: Bool
    let fullAccess: Bool
    let version: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct FolderListResponseDTO: Codable, Equatable, Sendable {
    let items: [FolderDTO]
}

struct CreateFolderRequestDTO: Codable, Equatable, Sendable {
    let name: String
    let description: String?
    let parentFolderId: UUID?
}

struct UpdateFolderRequestDTO: Codable, Equatable, Sendable {
    let name: String
    let description: String?
    let displayOrder: Int
    let archived: Bool
    let version: Int64
}

struct MoveFolderRequestDTO: Codable, Equatable, Sendable {
    let targetFolderId: UUID?
    let version: Int64
}

struct CloneFolderRequestDTO: Codable, Equatable, Sendable {
    let targetFolderId: UUID?
    let name: String?
    let includeChildren: Bool?
}

struct GoalDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let folderId: UUID
    let name: String
    let description: String
    let status: PlanningStatus
    let archived: Bool
    let shared: Bool
    let fullAccess: Bool
    let version: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct GoalListResponseDTO: Codable, Equatable, Sendable {
    let items: [GoalDTO]
}

struct CreateGoalRequestDTO: Codable, Equatable, Sendable {
    let name: String
    let description: String?
    let status: PlanningStatus?
}

struct UpdateGoalRequestDTO: Codable, Equatable, Sendable {
    let name: String
    let description: String?
    let status: PlanningStatus?
    let archived: Bool
    let version: Int64
}

struct MoveGoalRequestDTO: Codable, Equatable, Sendable {
    let targetFolderId: UUID
    let version: Int64
}

struct CloneGoalRequestDTO: Codable, Equatable, Sendable {
    let targetFolderId: UUID
    let name: String?
}

struct TaskTagDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let color: String?
}

struct ChecklistItemDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let taskId: UUID
    let text: String
    let checked: Bool
    let displayOrder: Int
    let version: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct RecurrenceDTO: Codable, Equatable, Sendable {
    let mode: RecurrenceMode
    let interval: Int
    let daysOfWeek: [Weekday]
    let dayOfMonth: Int?
    let startAt: Date
    let endAt: Date?
    let active: Bool
}

struct ReminderDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let mode: String
    let offsetMinutes: Int
    let active: Bool
}

struct TaskDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let goalId: UUID
    let title: String
    let description: String
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        goalId = try container.decode(UUID.self, forKey: .goalId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        type = try container.decode(TaskType.self, forKey: .type)
        priorityShadow = try container.decodeIfPresent(Int.self, forKey: .priorityShadow)
            ?? TaskPriorityCompatibility.defaultShadow
        effort = try container.decode(Int.self, forKey: .effort)
        status = try container.decode(PlanningStatus.self, forKey: .status)
        plannedTime = try container.decodeIfPresent(Date.self, forKey: .plannedTime)
        dueTime = try container.decodeIfPresent(Date.self, forKey: .dueTime)
        archived = try container.decode(Bool.self, forKey: .archived)
        shared = try container.decode(Bool.self, forKey: .shared)
        fullAccess = try container.decode(Bool.self, forKey: .fullAccess)
        creatorUserId = try container.decodeIfPresent(UUID.self, forKey: .creatorUserId)
        creatorEmail = try container.decodeIfPresent(String.self, forKey: .creatorEmail)
        creatorName = try container.decodeIfPresent(String.self, forKey: .creatorName)
        version = try container.decode(Int64.self, forKey: .version)
        tags = try container.decode([TaskTagDTO].self, forKey: .tags)
        checklistItems = try container.decode([ChecklistItemDTO].self, forKey: .checklistItems)
        recurrence = try container.decodeIfPresent(RecurrenceDTO.self, forKey: .recurrence)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(goalId, forKey: .goalId)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(type, forKey: .type)
        try container.encode(priorityShadow, forKey: .priorityShadow)
        try container.encode(effort, forKey: .effort)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(plannedTime, forKey: .plannedTime)
        try container.encodeIfPresent(dueTime, forKey: .dueTime)
        try container.encode(archived, forKey: .archived)
        try container.encode(shared, forKey: .shared)
        try container.encode(fullAccess, forKey: .fullAccess)
        try container.encodeIfPresent(creatorUserId, forKey: .creatorUserId)
        try container.encodeIfPresent(creatorEmail, forKey: .creatorEmail)
        try container.encodeIfPresent(creatorName, forKey: .creatorName)
        try container.encode(version, forKey: .version)
        try container.encode(tags, forKey: .tags)
        try container.encode(checklistItems, forKey: .checklistItems)
        try container.encodeIfPresent(recurrence, forKey: .recurrence)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct TaskListResponseDTO: Codable, Equatable, Sendable {
    let items: [TaskDTO]
}

struct ChecklistItemRequestDTO: Codable, Equatable, Sendable {
    let id: UUID?
    let text: String
    let checked: Bool
    let displayOrder: Int
}

struct ReplaceChecklistRequestDTO: Codable, Equatable, Sendable {
    let items: [ChecklistItemRequestDTO]
}

struct TaskChecklistResponseDTO: Codable, Equatable, Sendable {
    let taskId: UUID
    let items: [ChecklistItemDTO]
}

struct CreateTaskRequestDTO: Codable, Equatable, Sendable {
    let title: String
    let description: String?
    let type: TaskType
    private let priority: Int
    let effort: Int?
    let status: PlanningStatus
    let plannedTime: Date?
    let dueTime: Date?
    let checklistItems: [ChecklistItemRequestDTO]?
    let tagIds: [UUID]?

    init(
        title: String,
        description: String?,
        type: TaskType,
        effort: Int?,
        status: PlanningStatus,
        plannedTime: Date?,
        dueTime: Date?,
        checklistItems: [ChecklistItemRequestDTO]?,
        tagIds: [UUID]?
    ) {
        self.title = title
        self.description = description
        self.type = type
        priority = TaskPriorityCompatibility.defaultShadow
        self.effort = effort
        self.status = status
        self.plannedTime = plannedTime
        self.dueTime = dueTime
        self.checklistItems = checklistItems
        self.tagIds = tagIds
    }
}

struct UpdateTaskRequestDTO: Codable, Equatable, Sendable {
    let title: String
    let description: String?
    let type: TaskType
    private let priority: Int
    let effort: Int?
    let status: PlanningStatus
    let plannedTime: Date?
    let dueTime: Date?
    let archived: Bool
    let tagIds: [UUID]?
    let checklistItems: [ChecklistItemRequestDTO]?
    let version: Int64

    init(task: TaskDTO, tagIds: [UUID]?, checklistItems: [ChecklistItemRequestDTO]?) {
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

    init(
        preservingPriorityFrom task: TaskDTO,
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
        priority = task.priorityShadow
        self.effort = effort
        self.status = status
        self.plannedTime = plannedTime
        self.dueTime = dueTime
        self.archived = archived
        self.tagIds = tagIds
        self.checklistItems = checklistItems
        version = task.version
    }
}

struct MoveTaskRequestDTO: Codable, Equatable, Sendable {
    let plannedTime: Date
}

struct MoveTaskToGoalRequestDTO: Codable, Equatable, Sendable {
    let targetGoalId: UUID
    let version: Int64
}

struct CloneTaskRequestDTO: Codable, Equatable, Sendable {
    let targetGoalId: UUID
    let title: String?
    let includeTags: Bool?
}

struct MoveTaskResponseDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let plannedTime: Date
    let priorityShadow: Int
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, plannedTime, updatedAt
        case priorityShadow = "priority"
    }
}

enum QuickReschedulePreset: String, Codable, CaseIterable, Sendable {
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case threeHours = "3h"
    case oneDay = "24h"
}

struct QuickRescheduleRequestDTO: Codable, Equatable, Sendable {
    let preset: QuickReschedulePreset?
    let minutes: Int?
}

struct RescheduledTaskDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let plannedTime: Date
    let priorityShadow: Int
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, plannedTime, updatedAt
        case priorityShadow = "priority"
    }
}

struct RescheduleEventDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let previousPlannedTime: Date?
    let newPlannedTime: Date
    let createdAt: Date
}

struct QuickRescheduleResponseDTO: Codable, Equatable, Sendable {
    let task: RescheduledTaskDTO
    let rescheduleEvent: RescheduleEventDTO
    let priorityDecayAppliedShadow: Bool

    enum CodingKeys: String, CodingKey {
        case task, rescheduleEvent
        case priorityDecayAppliedShadow = "priorityDecayApplied"
    }
}

struct UpsertRecurrenceRequestDTO: Codable, Equatable, Sendable {
    let mode: RecurrenceMode
    let interval: Int
    let daysOfWeek: [Weekday]?
    let dayOfMonth: Int?
    let startAt: Date
    let endAt: Date?
    let active: Bool
}

struct TaskRecurrenceResponseDTO: Codable, Equatable, Sendable {
    let taskId: UUID
    let recurrence: RecurrenceDTO
}

struct UpsertReminderRequestDTO: Codable, Equatable, Sendable {
    let mode: String
    let offsetMinutes: Int
    let active: Bool
}

struct ReplaceRemindersRequestDTO: Codable, Equatable, Sendable {
    let reminders: [UpsertReminderRequestDTO]
}

struct TaskRemindersResponseDTO: Codable, Equatable, Sendable {
    let taskId: UUID
    let reminders: [ReminderDTO]
}

struct CreateTagRequestDTO: Codable, Equatable, Sendable {
    let name: String
    let color: String?
}

struct TagListResponseDTO: Codable, Equatable, Sendable {
    let items: [TaskTagDTO]
}

struct IdeaDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let folderId: UUID
    let title: String
    let body: String
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

struct IdeaNoteDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let ideaId: UUID
    let eventType: String
    let body: String
    let metadata: [String: JSONValue]
    let authorUserId: UUID?
    let authorEmail: String?
    let authorName: String?
    let version: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct NoteDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let folderId: UUID
    let title: String
    let body: String
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

struct CreateIdeaRequestDTO: Codable, Equatable, Sendable {
    let title: String
    let body: String?
    let status: String?
    let allowAuthorNoteEdits: Bool?
}

struct UpdateIdeaRequestDTO: Codable, Equatable, Sendable {
    let title: String
    let body: String?
    let status: String
    let displayOrder: Int
    let archived: Bool
    let allowAuthorNoteEdits: Bool?
    let version: Int64
}

struct CreateIdeaNoteRequestDTO: Codable, Equatable, Sendable {
    let eventType: String
    let body: String?
    let metadata: [String: JSONValue]?
}

struct UpdateIdeaNoteRequestDTO: Codable, Equatable, Sendable {
    let eventType: String
    let body: String?
    let metadata: [String: JSONValue]?
    let version: Int64
}

struct MoveIdeaRequestDTO: Codable, Equatable, Sendable {
    let targetFolderId: UUID
    let version: Int64
}

struct CloneIdeaRequestDTO: Codable, Equatable, Sendable {
    let targetFolderId: UUID
    let title: String?
}

struct CreateNoteRequestDTO: Codable, Equatable, Sendable {
    let title: String
    let body: String?
}

struct UpdateNoteRequestDTO: Codable, Equatable, Sendable {
    let title: String
    let body: String?
    let displayOrder: Int
    let archived: Bool
    let version: Int64
}

struct MoveNoteRequestDTO: Codable, Equatable, Sendable {
    let targetFolderId: UUID
    let version: Int64
}

struct CloneNoteRequestDTO: Codable, Equatable, Sendable {
    let targetFolderId: UUID
    let title: String?
}

struct IdeaListResponseDTO: Codable, Equatable, Sendable { let items: [IdeaDTO] }
struct IdeaNoteListResponseDTO: Codable, Equatable, Sendable { let items: [IdeaNoteDTO] }
struct NoteListResponseDTO: Codable, Equatable, Sendable { let items: [NoteDTO] }
