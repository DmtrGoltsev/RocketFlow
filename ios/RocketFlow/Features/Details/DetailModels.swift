import Foundation

enum DetailEntityKind: String, Codable, CaseIterable, Hashable, Sendable {
    case folder
    case goal
    case task
    case idea
    case note
}

struct DetailEntityReference: Codable, Equatable, Hashable, Sendable {
    let kind: DetailEntityKind
    let id: UUID
}

enum DetailTaskStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case todo
    case inProgress = "in_progress"
    case done
    case cancelled
}

enum DetailTaskType: String, Codable, CaseIterable, Hashable, Sendable {
    case green
    case red
}

enum DetailRecurrenceMode: String, Codable, CaseIterable, Hashable, Sendable {
    case daily
    case weekly
    case monthly
}

enum DetailWeekday: String, Codable, CaseIterable, Hashable, Sendable {
    case monday = "MONDAY"
    case tuesday = "TUESDAY"
    case wednesday = "WEDNESDAY"
    case thursday = "THURSDAY"
    case friday = "FRIDAY"
    case saturday = "SATURDAY"
    case sunday = "SUNDAY"
}

enum DetailRelationKind: String, Codable, CaseIterable, Hashable, Sendable {
    case related
    case dependency
}

enum DetailCapability: String, CaseIterable, Hashable, Sendable {
    case edit
    case move
    case clone
    case delete
    case share
    case manageLinks
    case createFolder
    case createGoal
    case createTask
    case createIdea
    case createNote
    case updateTaskStatus
    case manageChecklist
    case manageTags
    case manageRecurrence
    case reschedule
    case manageFocus
    case createIdeaHistory
}

struct DetailCapabilitySet: Equatable, Sendable {
    private(set) var values: Set<DetailCapability>

    init(_ values: Set<DetailCapability> = []) {
        self.values = values
    }

    func contains(_ capability: DetailCapability) -> Bool {
        values.contains(capability)
    }
}

enum DetailCapabilityPolicy {
    static func folder(shared: Bool, fullAccess: Bool) -> DetailCapabilitySet {
        guard !shared || fullAccess else { return DetailCapabilitySet() }
        return DetailCapabilitySet([
            .edit, .move, .clone, .delete, .share,
            .createFolder, .createGoal, .createIdea, .createNote
        ])
    }

    static func goal(
        shared: Bool,
        fullAccess: Bool,
        canCreateTask: Bool = false
    ) -> DetailCapabilitySet {
        var values: Set<DetailCapability> = []
        if canCreateTask { values.insert(.createTask) }
        guard !shared || fullAccess else { return DetailCapabilitySet(values) }
        values.formUnion([.edit, .move, .clone, .delete, .share, .manageLinks, .createTask])
        return DetailCapabilitySet(values)
    }

    static func task(
        shared: Bool,
        fullAccess: Bool,
        isOwner: Bool
    ) -> DetailCapabilitySet {
        var values: Set<DetailCapability> = [.updateTaskStatus, .manageFocus]
        guard !shared || fullAccess else { return DetailCapabilitySet(values) }
        values.formUnion([
            .edit, .move, .clone, .delete, .share, .manageLinks,
            .manageChecklist, .manageTags, .reschedule
        ])
        if isOwner { values.insert(.manageRecurrence) }
        return DetailCapabilitySet(values)
    }

    static func idea(
        shared: Bool,
        fullAccess: Bool,
        isCreator: Bool
    ) -> DetailCapabilitySet {
        var values: Set<DetailCapability> = [.createIdeaHistory]
        if !shared || fullAccess {
            values.formUnion([.edit, .move, .clone, .share, .manageLinks])
        }
        if isCreator { values.insert(.delete) }
        return DetailCapabilitySet(values)
    }

    static func note(shared: Bool, fullAccess: Bool) -> DetailCapabilitySet {
        guard !shared || fullAccess else { return DetailCapabilitySet() }
        return DetailCapabilitySet([.edit, .move, .clone, .delete, .manageLinks])
    }
}

struct DetailChildViewData: Equatable, Identifiable, Sendable {
    let reference: DetailEntityReference
    let title: String
    let subtitle: String
    let createdAt: Date

    var id: DetailEntityReference { reference }
}

struct DetailLinkViewData: Equatable, Identifiable, Sendable {
    let id: UUID
    let target: DetailEntityReference?
    let title: String
    let subtitle: String
    let relation: DetailRelationKind
    let redacted: Bool
}

struct DetailTagViewData: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let colorHex: String?
    let assigned: Bool
}

struct DetailChecklistItemViewData: Equatable, Identifiable, Sendable {
    let id: UUID
    var text: String
    var checked: Bool
    var displayOrder: Int
    let createdAt: Date
}

struct DetailRecurrenceViewData: Equatable, Sendable {
    let mode: DetailRecurrenceMode
    let interval: Int
    let weekdays: Set<DetailWeekday>
    let dayOfMonth: Int?
    let anchor: Date
    let end: Date?
    let active: Bool
}

struct DetailIdeaHistoryViewData: Equatable, Identifiable, Sendable {
    let id: UUID
    let ideaID: UUID
    let eventType: String
    let body: String
    let metadata: [String: String]
    let authorName: String?
    let authorUserID: UUID?
    let isAuthoredByCurrentUser: Bool
    let createdAt: Date
    let updatedAt: Date
    let version: Int64
}

enum DetailIdeaHistoryPolicy {
    static func canEdit(_ entry: DetailIdeaHistoryViewData) -> Bool {
        entry.isAuthoredByCurrentUser
    }

    static func canDelete(from idea: IdeaDetailViewData) -> Bool {
        idea.isCreator
    }
}

struct FolderDetailViewData: Equatable, Sendable {
    let id: UUID
    let parentFolderID: UUID?
    let name: String
    let description: String
    let activitySummary: String
    let shared: Bool
    let fullAccess: Bool
    let capabilities: DetailCapabilitySet
    let children: [DetailChildViewData]

    var reference: DetailEntityReference { DetailEntityReference(kind: .folder, id: id) }
}

struct GoalDetailViewData: Equatable, Sendable {
    let id: UUID
    let folderID: UUID
    let name: String
    let description: String
    let status: DetailTaskStatus
    let shared: Bool
    let fullAccess: Bool
    let capabilities: DetailCapabilitySet
    let tasks: [DetailChildViewData]
    let links: [DetailLinkViewData]

    var reference: DetailEntityReference { DetailEntityReference(kind: .goal, id: id) }
}

struct TaskDetailViewData: Equatable, Sendable {
    let id: UUID
    let goalID: UUID
    var title: String
    var description: String
    var status: DetailTaskStatus
    let type: DetailTaskType
    let effort: Int
    let plannedAt: Date?
    let dueAt: Date?
    let shared: Bool
    let fullAccess: Bool
    let isOwner: Bool
    let capabilities: DetailCapabilitySet
    var checklist: [DetailChecklistItemViewData]
    let tags: [DetailTagViewData]
    let recurrence: DetailRecurrenceViewData?
    let links: [DetailLinkViewData]
    var isInFocus: Bool
    let version: Int64

    var reference: DetailEntityReference { DetailEntityReference(kind: .task, id: id) }
}

struct IdeaDetailViewData: Equatable, Sendable {
    let id: UUID
    let folderID: UUID
    let title: String
    let body: String
    let status: String
    let allowAuthorHistoryEdits: Bool
    let shared: Bool
    let fullAccess: Bool
    let isCreator: Bool
    let capabilities: DetailCapabilitySet
    var history: [DetailIdeaHistoryViewData]
    let links: [DetailLinkViewData]

    var reference: DetailEntityReference { DetailEntityReference(kind: .idea, id: id) }
}

struct NoteDetailViewData: Equatable, Sendable {
    let id: UUID
    let folderID: UUID
    let title: String
    let body: String
    let authorName: String?
    let shared: Bool
    let fullAccess: Bool
    let capabilities: DetailCapabilitySet
    let links: [DetailLinkViewData]

    var reference: DetailEntityReference { DetailEntityReference(kind: .note, id: id) }
}

enum DetailContent: Equatable, Sendable {
    case folder(FolderDetailViewData)
    case goal(GoalDetailViewData)
    case task(TaskDetailViewData)
    case idea(IdeaDetailViewData)
    case note(NoteDetailViewData)

    var reference: DetailEntityReference {
        switch self {
        case let .folder(value): value.reference
        case let .goal(value): value.reference
        case let .task(value): value.reference
        case let .idea(value): value.reference
        case let .note(value): value.reference
        }
    }

    var capabilities: DetailCapabilitySet {
        switch self {
        case let .folder(value): value.capabilities
        case let .goal(value): value.capabilities
        case let .task(value): value.capabilities
        case let .idea(value): value.capabilities
        case let .note(value): value.capabilities
        }
    }

    func normalized() -> DetailContent {
        switch self {
        case var .folder(value):
            value = FolderDetailViewData(
                id: value.id,
                parentFolderID: value.parentFolderID,
                name: value.name,
                description: value.description,
                activitySummary: value.activitySummary,
                shared: value.shared,
                fullAccess: value.fullAccess,
                capabilities: value.capabilities,
                children: Self.newestFirst(value.children)
            )
            return .folder(value)
        case var .goal(value):
            value = GoalDetailViewData(
                id: value.id,
                folderID: value.folderID,
                name: value.name,
                description: value.description,
                status: value.status,
                shared: value.shared,
                fullAccess: value.fullAccess,
                capabilities: value.capabilities,
                tasks: Self.newestFirst(value.tasks),
                links: value.links
            )
            return .goal(value)
        case var .task(value):
            value.checklist.sort {
                if $0.displayOrder != $1.displayOrder { return $0.displayOrder < $1.displayOrder }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
            }
            return .task(value)
        case var .idea(value):
            value.history.sort {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
            }
            return .idea(value)
        case .note:
            return self
        }
    }

    private static func newestFirst(_ items: [DetailChildViewData]) -> [DetailChildViewData] {
        items.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.reference.id.uuidString.lowercased()
                > $1.reference.id.uuidString.lowercased()
        }
    }
}

enum DetailOriginTab: String, Codable, CaseIterable, Sendable {
    case home
    case calendar
    case focus
}

enum DetailCreateKind: String, CaseIterable, Hashable, Sendable {
    case folder
    case goal
    case task
    case idea
    case note
    case ideaHistory
}

enum DetailAfterSaveRoute: Equatable, Sendable {
    case stayOnCurrentDetail
    case openCreated
    case goalDetail(UUID)
}

enum DetailEditorRoute: Equatable, Sendable {
    case create(kind: DetailCreateKind, parent: DetailEntityReference, afterSave: DetailAfterSaveRoute)
    case edit(DetailEntityReference)
    case editIdeaHistory(ideaID: UUID, noteID: UUID)
    case move(DetailEntityReference)
    case clone(DetailEntityReference)
    case share(DetailEntityReference)
    case links(DetailEntityReference)
    case reschedule(DetailEntityReference)
}

enum DetailReturnDestination: Equatable, Sendable {
    case originRoot(DetailOriginTab)
    case folder(UUID, origin: DetailOriginTab)
    case goal(UUID, origin: DetailOriginTab)
}

enum DetailNavigationResult: Equatable, Sendable {
    case open(DetailEntityReference, origin: DetailOriginTab)
    case present(DetailEditorRoute, origin: DetailOriginTab)
    case deleted(DetailReturnDestination)
    case taskCreated(taskID: UUID, returnToGoalID: UUID, origin: DetailOriginTab)
    case dismissToOrigin(DetailOriginTab)
}

enum DetailMenuAction: Equatable, Hashable, Sendable {
    case create(DetailCreateKind)
    case edit
    case move
    case clone
    case delete
    case share
    case links
    case reschedule
}

enum DetailActionCatalog {
    static func actions(for content: DetailContent) -> [DetailMenuAction] {
        let capabilities = content.capabilities
        var actions: [DetailMenuAction] = []
        let createPairs: [(DetailCapability, DetailCreateKind)] = [
            (.createFolder, .folder), (.createGoal, .goal), (.createTask, .task),
            (.createIdea, .idea), (.createNote, .note), (.createIdeaHistory, .ideaHistory)
        ]
        actions += createPairs.compactMap { capability, kind in
            capabilities.contains(capability) ? .create(kind) : nil
        }
        if capabilities.contains(.edit) { actions.append(.edit) }
        if capabilities.contains(.move) { actions.append(.move) }
        if capabilities.contains(.clone) { actions.append(.clone) }
        if capabilities.contains(.share) { actions.append(.share) }
        if capabilities.contains(.manageLinks) { actions.append(.links) }
        if capabilities.contains(.reschedule) { actions.append(.reschedule) }
        if capabilities.contains(.delete) { actions.append(.delete) }
        return actions
    }
}

enum DetailDeleteReturnPolicy {
    static func destination(
        for content: DetailContent,
        origin: DetailOriginTab
    ) -> DetailReturnDestination {
        switch content {
        case let .folder(folder):
            if let parentFolderID = folder.parentFolderID {
                return .folder(parentFolderID, origin: .home)
            }
            return .originRoot(.home)
        case let .goal(goal):
            return .folder(goal.folderID, origin: .home)
        case .task:
            return .originRoot(origin)
        case .idea, .note:
            return .originRoot(.home)
        }
    }
}
