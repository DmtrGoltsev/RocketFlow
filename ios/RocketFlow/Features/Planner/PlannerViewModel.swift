import Combine
import Foundation

enum PlannerScreenPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case offline
    case error
}

struct PlannerCopy: Sendable {
    let title: String
    let owned: String
    let shared: String
    let searchPrompt: String
    let loading: String
    let offline: String
    let unavailable: String
    let empty: String
    let noSearchResults: String
    let retry: String
    let refresh: String
    let settings: String
    let create: String
    let createFolder: String
    let createChildFolder: String
    let createGoal: String
    let createTask: String
    let createIdea: String
    let createNote: String
    let open: String
    let edit: String
    let move: String
    let clone: String
    let delete: String
    let share: String
    let cancel: String
    let deleteConfirmation: String
    let actionFailed: String
    let fullAccess: String
    let readOnly: String
    let statusTodo: String
    let statusInProgress: String
    let statusDone: String
    let statusCancelled: String
    let completeTask: String
    let reopenTask: String
    let expand: String
    let collapse: String
    let moreActions: String

    init(language: AppLanguage) {
        if language == .ru {
            title = "Главная"
            owned = "Мои"
            shared = "Общие"
            searchPrompt = "Папка, цель, задача, идея или заметка"
            loading = "Загрузка плана"
            offline = "Нет сети. Показаны сохраненные данные"
            unavailable = "План сейчас недоступен"
            empty = "Создайте папку, чтобы начать планирование"
            noSearchResults = "Ничего не найдено"
            retry = "Повторить"
            refresh = "Обновить"
            settings = "Настройки"
            create = "Создать"
            createFolder = "Папку"
            createChildFolder = "Вложенную папку"
            createGoal = "Цель"
            createTask = "Задачу"
            createIdea = "Идею"
            createNote = "Заметку"
            open = "Открыть"
            edit = "Изменить"
            move = "Переместить"
            clone = "Клонировать"
            delete = "Удалить"
            share = "Поделиться"
            cancel = "Отмена"
            deleteConfirmation = "Элемент и вложенные данные будут удалены."
            actionFailed = "Не удалось выполнить действие"
            fullAccess = "Полный доступ"
            readOnly = "Только просмотр"
            statusTodo = "К выполнению"
            statusInProgress = "В работе"
            statusDone = "Выполнено"
            statusCancelled = "Отменено"
            completeTask = "Отметить задачу выполненной"
            reopenTask = "Вернуть задачу к выполнению"
            expand = "Развернуть"
            collapse = "Свернуть"
            moreActions = "Другие действия"
        } else {
            title = "Home"
            owned = "Mine"
            shared = "Shared"
            searchPrompt = "Folder, goal, task, idea, or note"
            loading = "Loading plan"
            offline = "Offline. Showing saved data"
            unavailable = "Planner is currently unavailable"
            empty = "Create a folder to start planning"
            noSearchResults = "No results"
            retry = "Retry"
            refresh = "Refresh"
            settings = "Settings"
            create = "Create"
            createFolder = "Folder"
            createChildFolder = "Child folder"
            createGoal = "Goal"
            createTask = "Task"
            createIdea = "Idea"
            createNote = "Note"
            open = "Open"
            edit = "Edit"
            move = "Move"
            clone = "Clone"
            delete = "Delete"
            share = "Share"
            cancel = "Cancel"
            deleteConfirmation = "The item and its nested data will be deleted."
            actionFailed = "The action could not be completed"
            fullAccess = "Full access"
            readOnly = "View only"
            statusTodo = "To do"
            statusInProgress = "In progress"
            statusDone = "Done"
            statusCancelled = "Cancelled"
            completeTask = "Mark task as complete"
            reopenTask = "Reopen task"
            expand = "Expand"
            collapse = "Collapse"
            moreActions = "More actions"
        }
    }

    func createTitle(_ kind: PlannerCreateKind, nested: Bool = false) -> String {
        switch kind {
        case .folder: nested ? createChildFolder : createFolder
        case .goal: createGoal
        case .task: createTask
        case .idea: createIdea
        case .note: createNote
        }
    }

    func statusTitle(_ status: PlanningStatus?) -> String? {
        switch status {
        case .todo: statusTodo
        case .inProgress: statusInProgress
        case .done: statusDone
        case .cancelled: statusCancelled
        case nil: nil
        }
    }

    func taskStatusActionHint(_ status: PlanningStatus?) -> String {
        status == .done ? reopenTask : completeTask
    }
}

@MainActor
final class PlannerViewModel: ObservableObject {
    @Published private(set) var phase: PlannerScreenPhase = .idle
    @Published private(set) var snapshot: PlannerSnapshot?
    @Published private(set) var tree: PlannerTree = .empty
    @Published private(set) var searchQuery = ""
    @Published private(set) var expandedFolderIDs: Set<UUID> = []
    @Published private(set) var expandedGoalIDs: Set<UUID> = []
    @Published private(set) var restorationRequest: PlannerScrollRestorationRequest?
    @Published private(set) var warning: String?
    @Published private(set) var actionError: String?
    @Published private(set) var isPerformingAction = false

    let language: AppLanguage

    private let loader: any PlannerLoading
    private let actionPerformer: any PlannerActionPerforming
    private let onNavigate: @MainActor (PlannerNavigationIntent) -> Void
    private let scrollState: PlannerScrollStateController
    private var visibleRows: [PlannerScrollRowGeometry] = []
    private var viewport = PlannerScrollViewport(
        absoluteY: 0,
        maximumOffsetY: 0,
        contentHeight: 0,
        viewportHeight: 0
    )
    private var pendingRestoration = false
    private var hasInitializedExpansion: Bool
    private var requestGeneration: UInt64 = 0
    private var phaseBeforeCurrentLoad: PlannerScreenPhase = .idle

    init(
        accountID: UUID,
        language: AppLanguage,
        loader: any PlannerLoading,
        actionPerformer: any PlannerActionPerforming,
        scrollState: PlannerScrollStateController = PlannerScrollStateController(),
        processScrollState: PlannerScrollRestorableState? = nil,
        onNavigate: @escaping @MainActor (PlannerNavigationIntent) -> Void
    ) {
        self.language = language
        self.loader = loader
        self.actionPerformer = actionPerformer
        self.scrollState = scrollState
        self.onNavigate = onNavigate

        let restored = scrollState.activate(
            accountID: accountID,
            processState: processScrollState
        )
        expandedFolderIDs = restored?.expandedFolderIDs ?? []
        expandedGoalIDs = restored?.expandedGoalIDs ?? []
        hasInitializedExpansion = restored != nil
    }

    var copy: PlannerCopy { PlannerCopy(language: language) }
    var isInitialLoading: Bool { phase == .loading && snapshot == nil }
    var showsOfflineState: Bool { phase == .offline }
    var showsErrorState: Bool { phase == .error }

    func loadIfNeeded() async {
        guard snapshot == nil, phase != .loading else { return }
        await load()
    }

    func refresh() async {
        captureScroll(before: .snapshotRefresh)
        await load()
    }

    func applyExternalSnapshot(
        _ snapshot: PlannerSnapshot,
        reason: PlannerScrollCaptureReason
    ) {
        invalidateInFlightLoad()
        captureScroll(before: reason)
        apply(snapshot)
        if phase == .idle || phase == .loading || phase == .error {
            phase = .loaded
        }
    }

    func updateSearchQuery(_ value: String) {
        guard value != searchQuery else { return }
        captureScroll(before: .mutation)
        searchQuery = value
        rebuildTree()
        prepareRestoration()
    }

    func toggleExpanded(_ row: PlannerTreeRow) {
        guard row.item.reference.kind == .folder || row.item.reference.kind == .goal else {
            return
        }
        captureScroll(before: .expandCollapse)
        let id = row.item.reference.id
        switch row.item.reference.kind {
        case .folder:
            if expandedFolderIDs.remove(id) == nil {
                expandedFolderIDs.insert(id)
            }
        case .goal:
            if expandedGoalIDs.remove(id) == nil {
                expandedGoalIDs.insert(id)
            }
        case .task, .idea, .note:
            return
        }
        scrollState.updateExpandedState(
            folderIDs: expandedFolderIDs,
            goalIDs: expandedGoalIDs
        )
        rebuildTree()
        prepareRestoration()
    }

    func open(_ item: PlannerItemViewData) {
        guard !isPerformingAction, item.capabilities.contains(.openDetail) else { return }
        captureScroll(before: .openDetail)
        onNavigate(.openDetail(item.reference))
    }

    func openSettings() {
        guard !isPerformingAction else { return }
        captureScroll(before: .openDetail)
        onNavigate(.openSettings)
    }

    func create(
        _ kind: PlannerCreateKind,
        in parent: PlannerItemViewData? = nil
    ) {
        guard !isPerformingAction else { return }
        if let parent {
            guard parent.capabilities.contains(capability(for: kind)) else { return }
        }
        captureScroll(before: .openEditor)
        let parentReference = parent?.reference
        let postSave: PlannerPostSaveNavigation
        if kind == .task, let parentReference, parentReference.kind == .goal {
            postSave = .openDetail(parentReference)
        } else {
            postSave = .openCreatedItem
        }
        onNavigate(
            .create(
                PlannerCreateIntent(
                    kind: kind,
                    parent: parentReference,
                    afterSuccessfulSave: postSave
                )
            )
        )
    }

    func handle(_ action: PlannerContextAction, for item: PlannerItemViewData) {
        guard !isPerformingAction else { return }
        switch action {
        case .openDetail:
            open(item)
        case let .create(kind):
            create(kind, in: item)
        case .edit:
            navigate(.edit(item.reference), capability: .edit, item: item, reason: .openEditor)
        case .move:
            navigate(.move(item.reference), capability: .move, item: item, reason: .mutation)
        case .clone:
            navigate(.clone(item.reference), capability: .clone, item: item, reason: .openEditor)
        case .share:
            navigate(.share(item.reference), capability: .share, item: item, reason: .openEditor)
        case .delete:
            break
        }
    }

    func delete(_ item: PlannerItemViewData) async {
        guard item.capabilities.contains(.delete) else { return }
        await performMutation(.delete(item.reference))
    }

    func toggleTaskStatus(_ item: PlannerItemViewData) async {
        guard
            item.reference.kind == .task,
            item.capabilities.contains(.updateTaskStatus)
        else {
            return
        }
        let updatedStatus: PlanningStatus = item.status == .done ? .todo : .done
        await performMutation(.updateTaskStatus(item.reference, updatedStatus))
    }

    func contextActions(for item: PlannerItemViewData) -> [PlannerContextAction] {
        PlannerActionCatalog.actions(for: item)
    }

    func receiveVisibleRows(_ rows: [PlannerScrollRowGeometry]) {
        visibleRows = rows
        requestRestorationIfReady()
    }

    func receiveViewport(_ viewport: PlannerScrollViewport) {
        self.viewport = viewport
        requestRestorationIfReady()
    }

    func captureForBackground() {
        captureScroll(before: .background)
    }

    func captureForRotation() {
        captureScroll(before: .rotation)
        prepareRestoration()
    }

    func processRestorableScrollState() -> PlannerScrollRestorableState? {
        scrollState.processRestorableState()
    }

    func resetScroll(_ reason: PlannerScrollResetReason) {
        scrollState.reset(reason)
        restorationRequest = nil
        pendingRestoration = false
    }

    private func load() async {
        requestGeneration &+= 1
        let generation = requestGeneration
        let previousPhase = phase == .loading ? phaseBeforeCurrentLoad : phase
        phaseBeforeCurrentLoad = previousPhase
        phase = .loading
        actionError = nil

        do {
            let result = try await loader.loadPlanner()
            guard generation == requestGeneration else { return }
            apply(result.snapshot)
            warning = result.warning
            phase = result.source == .offlineCache ? .offline : .loaded
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            phase = snapshot == nil ? .idle : previousPhase
        } catch {
            guard generation == requestGeneration else { return }
            warning = nil
            phase = .error
        }
    }

    private func apply(_ snapshot: PlannerSnapshot) {
        self.snapshot = snapshot
        if !hasInitializedExpansion {
            expandedFolderIDs = Set(
                snapshot.resolvedItems
                    .filter { $0.reference.kind == .folder && !$0.isArchived }
                    .map { $0.reference.id }
            )
            expandedGoalIDs = Set(
                snapshot.resolvedItems
                    .filter { $0.reference.kind == .goal && !$0.isArchived }
                    .map { $0.reference.id }
            )
            hasInitializedExpansion = true
            scrollState.updateExpandedState(
                folderIDs: expandedFolderIDs,
                goalIDs: expandedGoalIDs
            )
        }
        rebuildTree()
        prepareRestoration()
    }

    private func rebuildTree() {
        tree = PlannerTreeBuilder.build(
            snapshot: snapshot ?? PlannerSnapshot(),
            expandedFolderIDs: expandedFolderIDs,
            expandedGoalIDs: expandedGoalIDs,
            searchQuery: searchQuery
        )
    }

    private func performMutation(_ action: PlannerMutationAction) async {
        guard !isPerformingAction else { return }
        captureScroll(before: .mutation)
        isPerformingAction = true
        actionError = nil
        defer { isPerformingAction = false }

        do {
            let result = try await actionPerformer.perform(action)
            invalidateInFlightLoad()
            if let updatedSnapshot = result.snapshot {
                apply(updatedSnapshot)
            }
            if phase == .idle, snapshot != nil {
                phase = .loaded
            }
            if let navigation = result.navigation {
                onNavigate(navigation)
            }
        } catch is CancellationError {
            return
        } catch {
            actionError = copy.actionFailed
        }
    }

    private func navigate(
        _ intent: PlannerNavigationIntent,
        capability: PlannerCapability,
        item: PlannerItemViewData,
        reason: PlannerScrollCaptureReason
    ) {
        guard !isPerformingAction, item.capabilities.contains(capability) else { return }
        captureScroll(before: reason)
        onNavigate(intent)
    }

    private func capability(for kind: PlannerCreateKind) -> PlannerCapability {
        switch kind {
        case .folder: .createFolder
        case .goal: .createGoal
        case .task: .createTask
        case .idea: .createIdea
        case .note: .createNote
        }
    }

    private func captureScroll(before reason: PlannerScrollCaptureReason) {
        guard viewport.viewportHeight > 0 else { return }
        _ = scrollState.captureBefore(
            reason,
            rows: visibleRows,
            viewport: viewport,
            expandedFolderIDs: expandedFolderIDs,
            expandedGoalIDs: expandedGoalIDs
        )
    }

    private func invalidateInFlightLoad() {
        requestGeneration &+= 1
        guard phase == .loading else { return }
        guard snapshot != nil else {
            phase = .idle
            return
        }
        phase = phaseBeforeCurrentLoad == .offline ? .offline : .loaded
    }

    private func prepareRestoration() {
        visibleRows = []
        pendingRestoration = true
    }

    private func requestRestorationIfReady() {
        guard
            pendingRestoration,
            viewport.viewportHeight > 0,
            tree.isEmpty || !visibleRows.isEmpty
        else {
            return
        }
        restorationRequest = scrollState.makeRestorationRequest(
            rows: visibleRows,
            viewport: viewport
        )
        pendingRestoration = false
    }
}
