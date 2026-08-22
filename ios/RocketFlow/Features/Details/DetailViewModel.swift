import Combine
import Foundation

enum DetailScreenPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case offline
    case pending
    case error
}

@MainActor
final class DetailViewModel: ObservableObject {
    @Published private(set) var phase: DetailScreenPhase = .idle
    @Published private(set) var content: DetailContent?
    @Published private(set) var issue: DetailIssue?
    @Published private(set) var isPerformingAction = false
    @Published private(set) var isOffline = false
    @Published private(set) var hasPendingChanges = false

    let reference: DetailEntityReference
    let origin: DetailOriginTab

    private let loader: any DetailLoading
    private let mutationPerformer: any DetailMutationPerforming
    private let onNavigate: @MainActor (DetailNavigationResult) -> Void
    private var generation: UInt64 = 0

    init(
        reference: DetailEntityReference,
        origin: DetailOriginTab,
        loader: any DetailLoading,
        mutationPerformer: any DetailMutationPerforming,
        onNavigate: @escaping @MainActor (DetailNavigationResult) -> Void
    ) {
        self.reference = reference
        self.origin = origin
        self.loader = loader
        self.mutationPerformer = mutationPerformer
        self.onNavigate = onNavigate
    }

    var menuActions: [DetailMenuAction] {
        content.map { DetailActionCatalog.actions(for: $0) } ?? []
    }

    func loadIfNeeded() async {
        guard content == nil, phase != .loading else { return }
        await reload()
    }

    func reload() async {
        generation &+= 1
        let currentGeneration = generation
        let previousPhase = phase
        let previousOffline = isOffline
        let previousPending = hasPendingChanges
        phase = .loading
        issue = nil
        do {
            let result = try await loader.loadDetail(reference)
            guard currentGeneration == generation else { return }
            content = result.content.normalized()
            isOffline = result.source == .offlineCache
            hasPendingChanges = result.hasPendingChanges
            if result.hasPendingChanges {
                phase = .pending
            } else {
                phase = result.source == .offlineCache ? .offline : .loaded
            }
        } catch is CancellationError {
            guard currentGeneration == generation else { return }
            phase = content == nil ? .idle : previousPhase
            isOffline = previousOffline
            hasPendingChanges = previousPending
        } catch {
            guard currentGeneration == generation else { return }
            issue = .unavailable
            phase = .error
            isOffline = previousOffline
            hasPendingChanges = previousPending
        }
    }

    func open(_ child: DetailChildViewData) {
        onNavigate(.open(child.reference, origin: origin))
    }

    func handle(_ action: DetailMenuAction) {
        guard let content, menuActions.contains(action) else { return }
        switch action {
        case let .create(kind):
            let afterSave: DetailAfterSaveRoute = kind == .task
                ? .goalDetail(content.reference.id)
                : .stayOnCurrentDetail
            onNavigate(
                .present(
                    .create(kind: kind, parent: content.reference, afterSave: afterSave),
                    origin: origin
                )
            )
        case .edit:
            onNavigate(.present(.edit(content.reference), origin: origin))
        case .move:
            onNavigate(.present(.move(content.reference), origin: origin))
        case .clone:
            onNavigate(.present(.clone(content.reference), origin: origin))
        case .share:
            onNavigate(.present(.share(content.reference), origin: origin))
        case .links:
            onNavigate(.present(.links(content.reference), origin: origin))
        case .reschedule:
            onNavigate(.present(.reschedule(content.reference), origin: origin))
        case .delete:
            break
        }
    }

    func delete() async {
        guard let content, content.capabilities.contains(.delete) else { return }
        let destination = DetailDeleteReturnPolicy.destination(for: content, origin: origin)
        await perform(.delete(content.reference), optimisticContent: nil) { _ in
            .deleted(destination)
        }
    }

    func updateTaskStatus(_ status: DetailTaskStatus) async {
        guard
            case var .task(task) = content,
            task.capabilities.contains(.updateTaskStatus)
        else {
            return
        }
        task.status = status
        await perform(
            .updateTaskStatus(taskID: task.id, status: status, version: task.version),
            optimisticContent: .task(task)
        ) { $0.navigation }
    }

    func toggleChecklistItem(_ itemID: UUID) async {
        guard
            case var .task(task) = content,
            task.capabilities.contains(.manageChecklist),
            let index = task.checklist.firstIndex(where: { $0.id == itemID })
        else {
            return
        }
        task.checklist[index].checked.toggle()
        await perform(
            .replaceChecklist(taskID: task.id, items: task.checklist),
            optimisticContent: .task(task)
        ) { $0.navigation }
    }

    func setFocus(_ focused: Bool) async {
        guard
            case var .task(task) = content,
            task.capabilities.contains(.manageFocus)
        else {
            return
        }
        task.isInFocus = focused
        await perform(
            .setFocus(taskID: task.id, focused: focused),
            optimisticContent: .task(task)
        ) { $0.navigation }
    }

    func createIdeaHistory(eventType: String, body: String, metadata: [String: String]) async {
        guard
            case let .idea(idea) = content,
            idea.capabilities.contains(.createIdeaHistory)
        else {
            return
        }
        guard !isOffline else {
            issue = .networkRequired
            return
        }
        await perform(
            .createIdeaHistory(
                ideaID: idea.id,
                eventType: eventType,
                body: body,
                metadata: metadata
            ),
            optimisticContent: nil
        ) { $0.navigation }
    }

    func updateIdeaHistory(_ note: DetailIdeaHistoryViewData) async {
        guard
            case let .idea(idea) = content,
            note.ideaID == idea.id,
            DetailIdeaHistoryPolicy.canEdit(note)
        else {
            return
        }
        guard !isOffline else {
            issue = .networkRequired
            return
        }
        await perform(
            .updateIdeaHistory(ideaID: idea.id, note: note),
            optimisticContent: nil
        ) { $0.navigation }
    }

    func deleteIdeaHistory(_ note: DetailIdeaHistoryViewData) async {
        guard
            case let .idea(idea) = content,
            DetailIdeaHistoryPolicy.canDelete(from: idea),
            note.ideaID == idea.id
        else {
            return
        }
        guard !isOffline else {
            issue = .networkRequired
            return
        }
        await perform(
            .deleteIdeaHistory(ideaID: idea.id, noteID: note.id),
            optimisticContent: nil
        ) { $0.navigation }
    }

    func editIdeaHistory(_ note: DetailIdeaHistoryViewData) {
        guard
            case let .idea(idea) = content,
            note.ideaID == idea.id,
            DetailIdeaHistoryPolicy.canEdit(note)
        else {
            return
        }
        onNavigate(
            .present(
                .editIdeaHistory(ideaID: idea.id, noteID: note.id),
                origin: origin
            )
        )
    }

    func clearIssue() {
        issue = nil
    }

    private func perform(
        _ mutation: DetailMutation,
        optimisticContent: DetailContent?,
        navigation: (DetailMutationResult) -> DetailNavigationResult?
    ) async {
        guard !isPerformingAction else { return }
        let previousContent = content
        let previousPhase = phase
        let previousOffline = isOffline
        let previousPending = hasPendingChanges
        if let optimisticContent {
            content = optimisticContent.normalized()
        }
        isPerformingAction = true
        issue = nil
        phase = .pending
        defer { isPerformingAction = false }

        do {
            let result = try await mutationPerformer.performDetailMutation(mutation)
            if let updated = result.content {
                content = updated.normalized()
            }
            hasPendingChanges = result.pending
            phase = result.pending ? .pending : (isOffline ? .offline : .loaded)
            if let destination = navigation(result) {
                onNavigate(destination)
            }
        } catch is CancellationError {
            content = previousContent
            phase = previousPhase
            isOffline = previousOffline
            hasPendingChanges = previousPending
        } catch let failure as DetailServiceFailure {
            content = previousContent
            isOffline = previousOffline
            hasPendingChanges = previousPending
            phase = previousOffline ? .offline : .error
            issue = failure.statusCode == 409 && failure.code == "dependency_blocked"
                ? .dependencyBlocked
                : .unavailable
        } catch {
            content = previousContent
            isOffline = previousOffline
            hasPendingChanges = previousPending
            phase = previousOffline ? .offline : .error
            issue = .unavailable
        }
    }
}
