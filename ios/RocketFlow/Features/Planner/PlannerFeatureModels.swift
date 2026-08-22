import Foundation

enum PlannerItemKind: String, Codable, CaseIterable, Hashable, Sendable {
    case folder
    case goal
    case task
    case idea
    case note

    var scrollResourceType: PlannerResourceType {
        switch self {
        case .folder: .folder
        case .goal: .goal
        case .task: .task
        case .idea: .idea
        case .note: .note
        }
    }
}

struct PlannerItemReference: Codable, Equatable, Hashable, Sendable {
    let kind: PlannerItemKind
    let id: UUID

    var scrollAnchor: PlannerScrollAnchor {
        PlannerScrollAnchor(resourceType: kind.scrollResourceType, resourceID: id)
    }
}

enum PlannerCapability: String, CaseIterable, Hashable, Sendable {
    case openDetail
    case createFolder
    case createGoal
    case createTask
    case createIdea
    case createNote
    case edit
    case move
    case clone
    case delete
    case share
    case updateTaskStatus
}

struct PlannerCapabilitySet: Equatable, Sendable {
    private(set) var values: Set<PlannerCapability>

    init(_ values: Set<PlannerCapability> = []) {
        self.values = values
    }

    func contains(_ capability: PlannerCapability) -> Bool {
        values.contains(capability)
    }

    func inserting(_ capability: PlannerCapability) -> PlannerCapabilitySet {
        var updated = values
        updated.insert(capability)
        return PlannerCapabilitySet(updated)
    }

    func removing(_ capability: PlannerCapability) -> PlannerCapabilitySet {
        var updated = values
        updated.remove(capability)
        return PlannerCapabilitySet(updated)
    }
}

enum PlannerCapabilityPolicy {
    static func capabilities(
        for kind: PlannerItemKind,
        shared: Bool,
        fullAccess: Bool,
        legacyCreateTaskAllowed: Bool = false,
        canDelete: Bool? = nil
    ) -> PlannerCapabilitySet {
        var capabilities: Set<PlannerCapability> = [.openDetail]
        let canFullyMutate = !shared || fullAccess
        let deleteAllowed = canDelete ?? (kind != .idea)

        if kind == .task {
            // The existing collaboration contract permits status-only task updates.
            capabilities.insert(.updateTaskStatus)
        }
        if kind == .goal, legacyCreateTaskAllowed {
            capabilities.insert(.createTask)
        }
        if kind == .idea, deleteAllowed {
            capabilities.insert(.delete)
        }
        guard canFullyMutate else {
            return PlannerCapabilitySet(capabilities)
        }

        capabilities.formUnion([.edit, .move, .clone])
        if kind != .idea, deleteAllowed {
            capabilities.insert(.delete)
        }
        switch kind {
        case .folder:
            capabilities.formUnion([.createFolder, .createGoal, .createIdea, .createNote, .share])
        case .goal:
            capabilities.formUnion([.createTask, .share])
        case .task, .idea:
            capabilities.insert(.share)
        case .note:
            // Notes inherit folder sharing and have no direct share endpoint.
            break
        }
        return PlannerCapabilitySet(capabilities)
    }
}

struct PlannerItemViewData: Equatable, Identifiable, Sendable {
    let reference: PlannerItemReference
    let parent: PlannerItemReference?
    let title: String
    let subtitle: String
    let searchText: String
    let status: PlanningStatus?
    let createdAt: Date
    let isArchived: Bool
    let isShared: Bool
    let fullAccess: Bool
    let canDelete: Bool
    let capabilities: PlannerCapabilitySet

    var id: PlannerItemReference { reference }

    init(
        reference: PlannerItemReference,
        parent: PlannerItemReference? = nil,
        title: String,
        subtitle: String = "",
        searchText: String = "",
        status: PlanningStatus? = nil,
        createdAt: Date,
        isArchived: Bool = false,
        isShared: Bool = false,
        fullAccess: Bool = true,
        canDelete: Bool? = nil,
        capabilities: PlannerCapabilitySet? = nil
    ) {
        let resolvedCanDelete = canDelete ?? (reference.kind != .idea)
        self.reference = reference
        self.parent = parent
        self.title = title
        self.subtitle = subtitle
        self.searchText = searchText
        self.status = status
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.isShared = isShared
        self.fullAccess = fullAccess
        let resolvedCapabilities = capabilities ?? PlannerCapabilityPolicy.capabilities(
            for: reference.kind,
            shared: isShared,
            fullAccess: fullAccess,
            canDelete: resolvedCanDelete
        )
        let gatedCapabilities = resolvedCanDelete
            ? resolvedCapabilities
            : resolvedCapabilities.removing(.delete)
        self.capabilities = gatedCapabilities
        self.canDelete = gatedCapabilities.contains(.delete)
    }

    func addingCapability(_ capability: PlannerCapability) -> PlannerItemViewData {
        PlannerItemViewData(
            reference: reference,
            parent: parent,
            title: title,
            subtitle: subtitle,
            searchText: searchText,
            status: status,
            createdAt: createdAt,
            isArchived: isArchived,
            isShared: isShared,
            fullAccess: fullAccess,
            canDelete: canDelete,
            capabilities: capabilities.inserting(capability)
        )
    }
}

extension PlannerItemViewData {
    init(folder: FolderDTO) {
        self.init(
            reference: PlannerItemReference(kind: .folder, id: folder.id),
            parent: folder.parentFolderId.map { PlannerItemReference(kind: .folder, id: $0) },
            title: folder.name,
            subtitle: folder.description,
            searchText: folder.description,
            createdAt: folder.createdAt,
            isArchived: folder.archived,
            isShared: folder.shared,
            fullAccess: folder.fullAccess
        )
    }

    init(goal: GoalDTO, legacyCreateTaskAllowed: Bool = false) {
        self.init(
            reference: PlannerItemReference(kind: .goal, id: goal.id),
            parent: PlannerItemReference(kind: .folder, id: goal.folderId),
            title: goal.name,
            subtitle: goal.description,
            searchText: goal.description,
            status: goal.status,
            createdAt: goal.createdAt,
            isArchived: goal.archived,
            isShared: goal.shared,
            fullAccess: goal.fullAccess,
            capabilities: PlannerCapabilityPolicy.capabilities(
                for: .goal,
                shared: goal.shared,
                fullAccess: goal.fullAccess,
                legacyCreateTaskAllowed: legacyCreateTaskAllowed
            )
        )
    }

    init(task: TaskDTO) {
        self.init(
            reference: PlannerItemReference(kind: .task, id: task.id),
            parent: PlannerItemReference(kind: .goal, id: task.goalId),
            title: task.title,
            subtitle: task.description,
            searchText: task.description,
            status: task.status,
            createdAt: task.createdAt,
            isArchived: task.archived,
            isShared: task.shared,
            fullAccess: task.fullAccess
        )
    }

    init(idea: IdeaDTO, currentUserID: UUID? = nil) {
        self.init(
            reference: PlannerItemReference(kind: .idea, id: idea.id),
            parent: PlannerItemReference(kind: .folder, id: idea.folderId),
            title: idea.title,
            subtitle: idea.body,
            searchText: "\(idea.body) \(idea.status)",
            createdAt: idea.createdAt,
            isArchived: idea.archived,
            isShared: idea.shared,
            fullAccess: idea.fullAccess,
            canDelete: currentUserID.flatMap { currentUserID in
                idea.creatorUserId.map { $0 == currentUserID }
            } ?? false
        )
    }

    init(note: NoteDTO) {
        self.init(
            reference: PlannerItemReference(kind: .note, id: note.id),
            parent: PlannerItemReference(kind: .folder, id: note.folderId),
            title: note.title,
            subtitle: note.body,
            searchText: note.body,
            createdAt: note.createdAt,
            isArchived: note.archived,
            isShared: note.shared,
            fullAccess: note.fullAccess
        )
    }
}

struct PlannerSnapshot: Equatable, Sendable {
    let items: [PlannerItemViewData]
    let createTaskGoalIDs: Set<UUID>

    init(
        items: [PlannerItemViewData] = [],
        createTaskGoalIDs: Set<UUID> = []
    ) {
        self.items = items
        self.createTaskGoalIDs = createTaskGoalIDs
    }

    init(
        folders: [FolderDTO],
        goals: [GoalDTO],
        tasks: [TaskDTO],
        ideas: [IdeaDTO],
        notes: [NoteDTO],
        createTaskGoalIDs: Set<UUID> = [],
        currentUserID: UUID? = nil
    ) {
        self.init(
            items: folders.map { PlannerItemViewData(folder: $0) }
                + goals.map {
                    PlannerItemViewData(
                        goal: $0,
                        legacyCreateTaskAllowed: createTaskGoalIDs.contains($0.id)
                    )
                }
                + tasks.map { PlannerItemViewData(task: $0) }
                + ideas.map { PlannerItemViewData(idea: $0, currentUserID: currentUserID) }
                + notes.map { PlannerItemViewData(note: $0) },
            createTaskGoalIDs: createTaskGoalIDs
        )
    }

    var resolvedItems: [PlannerItemViewData] {
        items.map { item in
            guard
                item.reference.kind == .goal,
                createTaskGoalIDs.contains(item.reference.id),
                !item.capabilities.contains(.createTask)
            else {
                return item
            }
            return item.addingCapability(.createTask)
        }
    }
}

enum PlannerLoadSource: Equatable, Sendable {
    case network
    case offlineCache
}

struct PlannerLoadResult: Equatable, Sendable {
    let snapshot: PlannerSnapshot
    let source: PlannerLoadSource
    let warning: String?

    init(
        snapshot: PlannerSnapshot,
        source: PlannerLoadSource,
        warning: String? = nil
    ) {
        self.snapshot = snapshot
        self.source = source
        self.warning = warning
    }
}

protocol PlannerLoading: Sendable {
    func loadPlanner() async throws -> PlannerLoadResult
}

enum PlannerMutationAction: Equatable, Sendable {
    case delete(PlannerItemReference)
    case updateTaskStatus(PlannerItemReference, PlanningStatus)
}

struct PlannerMutationResult: Equatable, Sendable {
    let snapshot: PlannerSnapshot?
    let navigation: PlannerNavigationIntent?

    init(
        snapshot: PlannerSnapshot? = nil,
        navigation: PlannerNavigationIntent? = nil
    ) {
        self.snapshot = snapshot
        self.navigation = navigation
    }
}

protocol PlannerActionPerforming: Sendable {
    func perform(_ action: PlannerMutationAction) async throws -> PlannerMutationResult
}

enum PlannerCreateKind: String, CaseIterable, Hashable, Sendable {
    case folder
    case goal
    case task
    case idea
    case note

    var requiredParentKind: PlannerItemKind? {
        switch self {
        case .folder: nil
        case .goal, .idea, .note: .folder
        case .task: .goal
        }
    }
}

enum PlannerPostSaveNavigation: Equatable, Sendable {
    case stayInPlanner
    case openCreatedItem
    case openDetail(PlannerItemReference)
}

struct PlannerCreateIntent: Equatable, Sendable {
    let kind: PlannerCreateKind
    let parent: PlannerItemReference?
    let afterSuccessfulSave: PlannerPostSaveNavigation
}

enum PlannerNavigationIntent: Equatable, Sendable {
    case openDetail(PlannerItemReference)
    case openSettings
    case create(PlannerCreateIntent)
    case edit(PlannerItemReference)
    case move(PlannerItemReference)
    case clone(PlannerItemReference)
    case share(PlannerItemReference)
}

enum PlannerContextAction: Equatable, Hashable, Sendable {
    case openDetail
    case create(PlannerCreateKind)
    case edit
    case move
    case clone
    case delete
    case share
}

enum PlannerActionCatalog {
    static func actions(for item: PlannerItemViewData) -> [PlannerContextAction] {
        var actions: [PlannerContextAction] = [.openDetail]
        let createPairs: [(PlannerCapability, PlannerCreateKind)] = [
            (.createFolder, .folder),
            (.createGoal, .goal),
            (.createTask, .task),
            (.createIdea, .idea),
            (.createNote, .note)
        ]
        actions += createPairs.compactMap { capability, kind in
            item.capabilities.contains(capability) ? .create(kind) : nil
        }
        if item.capabilities.contains(.edit) { actions.append(.edit) }
        if item.capabilities.contains(.move) { actions.append(.move) }
        if item.capabilities.contains(.clone) { actions.append(.clone) }
        if item.capabilities.contains(.share) { actions.append(.share) }
        if item.capabilities.contains(.delete) { actions.append(.delete) }
        return actions
    }
}
