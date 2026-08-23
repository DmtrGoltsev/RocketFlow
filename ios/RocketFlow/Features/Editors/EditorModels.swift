import Foundation

enum EditorMode: Equatable, Sendable {
    case create
    case edit(DetailEntityReference)
    case editIdeaHistory(ideaID: UUID, noteID: UUID)
}

enum EditorField: String, CaseIterable, Hashable, Sendable {
    case name
    case title
    case description
    case body
    case status
    case effort
    case recurrence
    case recurrenceInterval
    case recurrenceWeekdays
    case recurrenceDayOfMonth
    case recurrenceEnd
    case reminder
    case checklist
    case tagName
    case tagColor
    case eventType
}

enum EditorValidationIssue: Equatable, Sendable {
    case required
    case tooLong(maximum: Int)
    case mustBeNonnegative
    case recurrenceAnchorRequired
    case recurrenceIntervalInvalid
    case recurrenceWeekdayRequired
    case recurrenceAnchorWeekdayRequired
    case recurrenceDayInvalid
    case recurrenceAnchorDayRequired
    case reminderOneShotInPast
    case recurrenceEndInvalid
}

struct EditorValidationResult: Equatable, Sendable {
    let errors: [EditorField: EditorValidationIssue]

    static let valid = EditorValidationResult(errors: [:])
    var isValid: Bool { errors.isEmpty }
}

enum EditorLimits {
    static let folderName = 160
    static let folderDescription = 1_000
    static let goalName = 160
    static let goalDescription = 1_000
    static let taskTitle = 200
    static let taskDescription = 2_000
    static let checklistText = 500
    static let tagName = 80
    static let tagColor = 16
    static let ideaTitle = 200
    static let ideaBody = 4_000
    static let ideaStatus = 32
    static let ideaHistoryType = 32
    static let ideaHistoryBody = 4_000
    static let noteTitle = 200
    static let noteBody = 4_000
}

struct FolderEditorDraft: Equatable, Sendable {
    var name: String
    var description: String
}

struct GoalEditorDraft: Equatable, Sendable {
    var name: String
    var description: String
    var status: DetailTaskStatus
}

enum TaskRecurrenceAnchorSource: String, CaseIterable, Equatable, Sendable {
    case planned
    case due
}

struct TaskRecurrenceEditorDraft: Equatable, Sendable {
    var mode: DetailRecurrenceMode?
    var interval: Int
    var weekdays: Set<DetailWeekday>
    var dayOfMonth: Int?
    var endAt: Date?
    var anchorSource: TaskRecurrenceAnchorSource?
    var startAt: Date?

    init(
        mode: DetailRecurrenceMode?,
        interval: Int,
        weekdays: Set<DetailWeekday>,
        dayOfMonth: Int?,
        endAt: Date?,
        anchorSource: TaskRecurrenceAnchorSource? = nil,
        startAt: Date? = nil
    ) {
        self.mode = mode
        self.interval = interval
        self.weekdays = weekdays
        self.dayOfMonth = dayOfMonth
        self.endAt = endAt
        self.anchorSource = anchorSource
        self.startAt = startAt
    }

    static let none = TaskRecurrenceEditorDraft(
        mode: nil,
        interval: 1,
        weekdays: [],
        dayOfMonth: nil,
        endAt: nil,
        anchorSource: nil,
        startAt: nil
    )

    func resolvedAnchorSource(plannedAt: Date?, dueAt: Date?) -> TaskRecurrenceAnchorSource? {
        if let anchorSource, date(for: anchorSource, plannedAt: plannedAt, dueAt: dueAt) != nil {
            return anchorSource
        }
        if let startAt {
            if let plannedAt, startAt == plannedAt { return .planned }
            if let dueAt, startAt == dueAt { return .due }
        }
        if plannedAt != nil { return .planned }
        if dueAt != nil { return .due }
        return nil
    }

    func resolvedAnchor(plannedAt: Date?, dueAt: Date?) -> Date? {
        guard let source = resolvedAnchorSource(plannedAt: plannedAt, dueAt: dueAt) else {
            return nil
        }
        let sourceDate = date(for: source, plannedAt: plannedAt, dueAt: dueAt)
        if let startAt, let sourceDate, startAt == sourceDate {
            return startAt
        }
        return sourceDate
    }

    mutating func synchronizeAnchor(plannedAt: Date?, dueAt: Date?) {
        guard mode != nil else {
            anchorSource = nil
            startAt = nil
            return
        }
        anchorSource = resolvedAnchorSource(plannedAt: plannedAt, dueAt: dueAt)
        startAt = anchorSource.flatMap { date(for: $0, plannedAt: plannedAt, dueAt: dueAt) }
    }

    private func date(
        for source: TaskRecurrenceAnchorSource,
        plannedAt: Date?,
        dueAt: Date?
    ) -> Date? {
        switch source {
        case .planned: plannedAt
        case .due: dueAt
        }
    }
}

struct ChecklistEditorItemDraft: Equatable, Identifiable, Sendable {
    let id: UUID
    let serverID: UUID?
    var text: String
    var checked: Bool

    init(
        id: UUID = UUID(),
        serverID: UUID? = nil,
        text: String,
        checked: Bool = false
    ) {
        self.id = id
        self.serverID = serverID
        self.text = text
        self.checked = checked
    }
}

struct TagEditorItemDraft: Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var colorHex: String?
    var assigned: Bool
}

struct TaskReminderEditorDraft: Equatable, Sendable {
    let id: UUID
    var triggerAt: Date
    var repeatRule: TaskReminderRepeat
    var anchorAt: Date

    init(
        id: UUID = UUID(),
        triggerAt: Date,
        repeatRule: TaskReminderRepeat = .none,
        anchorAt: Date? = nil
    ) {
        self.id = id
        self.triggerAt = triggerAt
        self.repeatRule = repeatRule
        self.anchorAt = anchorAt ?? triggerAt
    }
}

enum TaskReminderEditorMutation: Equatable, Sendable {
    case preserveOrDefault
    case remove
    case upsert(TaskReminderEditorDraft)
}

struct TaskEditorDraft: Equatable, Sendable {
    var title: String
    var description: String
    var status: DetailTaskStatus
    var type: DetailTaskType
    var effort: Int
    var plannedAt: Date?
    var dueAt: Date?
    var recurrence: TaskRecurrenceEditorDraft
    var checklist: [ChecklistEditorItemDraft]
    var tags: [TagEditorItemDraft]
    var reminder: TaskReminderEditorMutation
    var operationID: UUID

    init(
        title: String,
        description: String,
        status: DetailTaskStatus,
        type: DetailTaskType,
        effort: Int,
        plannedAt: Date?,
        dueAt: Date?,
        recurrence: TaskRecurrenceEditorDraft,
        checklist: [ChecklistEditorItemDraft],
        tags: [TagEditorItemDraft],
        reminder: TaskReminderEditorMutation = .preserveOrDefault,
        operationID: UUID = UUID()
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.type = type
        self.effort = effort
        self.plannedAt = plannedAt
        self.dueAt = dueAt
        self.recurrence = recurrence
        self.checklist = checklist
        self.tags = tags
        self.reminder = reminder
        self.operationID = operationID
    }

    mutating func addChecklistItem(text: String = "") {
        checklist.append(ChecklistEditorItemDraft(text: text))
    }

    mutating func removeChecklistItem(id: UUID) {
        checklist.removeAll { $0.id == id }
    }

    mutating func toggleChecklistItem(id: UUID) {
        guard let index = checklist.firstIndex(where: { $0.id == id }) else { return }
        checklist[index].checked.toggle()
    }

    mutating func moveChecklistItem(from source: Int, to destination: Int) {
        guard
            checklist.indices.contains(source),
            destination >= 0,
            destination <= checklist.count,
            source != destination,
            source + 1 != destination
        else {
            return
        }
        let item = checklist.remove(at: source)
        let adjustedDestination = destination > source ? destination - 1 : destination
        checklist.insert(item, at: min(adjustedDestination, checklist.count))
    }

    mutating func setTagAssigned(id: UUID, assigned: Bool) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[index].assigned = assigned
    }
}

enum TaskEditorMutationScope: Equatable, Sendable {
    case full
    case statusOnly
}

struct TaskEditorAccess: Equatable, Sendable {
    let mutationScope: TaskEditorMutationScope
    let canManageRecurrence: Bool
    let canManageChecklist: Bool
    let canManageTags: Bool

    static let fullOwner = TaskEditorAccess(
        mutationScope: .full,
        canManageRecurrence: true,
        canManageChecklist: true,
        canManageTags: true
    )

    static let statusOnly = TaskEditorAccess(
        mutationScope: .statusOnly,
        canManageRecurrence: false,
        canManageChecklist: false,
        canManageTags: false
    )
}

struct IdeaEditorDraft: Equatable, Sendable {
    var title: String
    var body: String
    var status: String
    var allowAuthorHistoryEdits: Bool
}

struct IdeaHistoryEditorDraft: Equatable, Sendable {
    var eventType: String
    var body: String
    var metadata: [String: String]
}

struct NoteEditorDraft: Equatable, Sendable {
    var title: String
    var body: String
}

struct TagEditorDraft: Equatable, Sendable {
    var name: String
    var colorHex: String
}

struct FolderEditorPayload: Equatable, Sendable {
    let name: String
    let description: String
}

struct GoalEditorPayload: Equatable, Sendable {
    let name: String
    let description: String
    let status: DetailTaskStatus
}

struct ChecklistEditorPayload: Equatable, Sendable {
    let id: UUID?
    let text: String
    let checked: Bool
    let displayOrder: Int
}

struct TaskRecurrenceEditorPayload: Equatable, Sendable {
    let mode: DetailRecurrenceMode
    let interval: Int
    let weekdays: [DetailWeekday]
    let dayOfMonth: Int?
    let anchor: Date
    let endAt: Date?
    let active: Bool
}

struct TaskEditorPayload: Equatable, Sendable {
    let mutationScope: TaskEditorMutationScope
    let title: String
    let description: String
    let status: DetailTaskStatus
    let type: DetailTaskType
    let effort: Int
    let plannedAt: Date?
    let dueAt: Date?
    let recurrence: TaskRecurrenceEditorPayload?
    let checklist: [ChecklistEditorPayload]
    let tagIDs: [UUID]
    let reminder: TaskReminderEditorMutation
    let operationID: UUID

    init(
        mutationScope: TaskEditorMutationScope,
        title: String,
        description: String,
        status: DetailTaskStatus,
        type: DetailTaskType,
        effort: Int,
        plannedAt: Date?,
        dueAt: Date?,
        recurrence: TaskRecurrenceEditorPayload?,
        checklist: [ChecklistEditorPayload],
        tagIDs: [UUID],
        reminder: TaskReminderEditorMutation = .preserveOrDefault,
        operationID: UUID = UUID()
    ) {
        self.mutationScope = mutationScope
        self.title = title
        self.description = description
        self.status = status
        self.type = type
        self.effort = effort
        self.plannedAt = plannedAt
        self.dueAt = dueAt
        self.recurrence = recurrence
        self.checklist = checklist
        self.tagIDs = tagIDs
        self.reminder = reminder
        self.operationID = operationID
    }
}

struct IdeaEditorPayload: Equatable, Sendable {
    let title: String
    let body: String
    let status: String
    let allowAuthorHistoryEdits: Bool
}

struct IdeaHistoryEditorPayload: Equatable, Sendable {
    let eventType: String
    let body: String
    let metadata: [String: String]
}

struct NoteEditorPayload: Equatable, Sendable {
    let title: String
    let body: String
}

struct TagEditorPayload: Equatable, Sendable {
    let name: String
    let colorHex: String?
}

enum EditorSaveRequest: Equatable, Sendable {
    case folder(mode: EditorMode, parentFolderID: UUID?, payload: FolderEditorPayload)
    case goal(mode: EditorMode, folderID: UUID, payload: GoalEditorPayload)
    case task(mode: EditorMode, goalID: UUID, payload: TaskEditorPayload)
    case idea(mode: EditorMode, folderID: UUID, payload: IdeaEditorPayload)
    case ideaHistory(mode: EditorMode, ideaID: UUID, payload: IdeaHistoryEditorPayload)
    case note(mode: EditorMode, folderID: UUID, payload: NoteEditorPayload)

    var requiresNetwork: Bool {
        switch self {
        case .idea, .ideaHistory, .note:
            true
        case .folder, .goal, .task:
            false
        }
    }
}

struct EditorContext: Equatable, Sendable {
    let origin: DetailOriginTab
    let parent: DetailEntityReference?
    let afterSave: DetailAfterSaveRoute
}

struct EditorSaveResult: Equatable, Sendable {
    let reference: DetailEntityReference
    let pending: Bool
}

enum EditorSaveState: Equatable, Sendable {
    case idle
    case saving
    case saved
    case pending
    case networkRequired
    case reminderError(EditorReminderFailure)
    case error
}

enum EditorReminderFailure: Error, Equatable, Sendable {
    case oneShotInPast
    case authorizationDenied
    case schedulingFailed
    case operationIdentityReused
}

protocol EditorSaving: Sendable {
    func saveEditor(_ request: EditorSaveRequest) async throws -> EditorSaveResult
}

protocol EditorOperationRecoveryManaging: Sendable {
    func abandonEditorOperation(_ operationID: UUID) async
    func clearEditorOperations() async
}

protocol EditorTagCreating: Sendable {
    func createTag(_ payload: TagEditorPayload) async throws -> TagEditorItemDraft
}

protocol EditorFocusUpdating: Sendable {
    func setTaskFocus(taskID: UUID, focused: Bool) async throws
}
