import SwiftUI
import UIKit

@MainActor
enum AppSystemSharePresenter {
    static func present(text: String) {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController else {
            return
        }
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        let controller = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }
}

@MainActor
struct AppPresentationHost: View {
    let route: AppPresentationRoute
    let runtime: AppUserRuntime
    @ObservedObject var appStore: AppStore
    @ObservedObject var languageStore: AppLanguageStore

    @ViewBuilder
    var body: some View {
        switch route {
        case let .editor(editorRoute, origin):
            AppEditorHost(
                route: editorRoute,
                origin: origin,
                runtime: runtime,
                appStore: appStore,
                languageStore: languageStore
            )
        case let .sharing(reference, _):
            AppSharingHost(
                reference: reference,
                runtime: runtime,
                appStore: appStore,
                languageStore: languageStore
            )
        case let .command(kind, reference, origin):
            AppCommandHost(
                kind: kind,
                reference: reference,
                origin: origin,
                runtime: runtime,
                appStore: appStore,
                languageStore: languageStore
            )
        case .focusCadence:
            AppFocusCadenceHost(
                runtime: runtime,
                appStore: appStore,
                languageStore: languageStore
            )
        }
    }
}

private enum AppEditorResolution: Sendable {
    case folder(EditorMode, UUID?, FolderEditorDraft)
    case goal(EditorMode, UUID, GoalEditorDraft)
    case task(EditorMode, UUID, TaskEditorDraft, TaskEditorAccess, Bool)
    case idea(EditorMode, UUID, IdeaEditorDraft)
    case ideaHistory(EditorMode, UUID, IdeaHistoryEditorDraft)
    case note(EditorMode, UUID, NoteEditorDraft)
}

private enum AppEditorHostError: Error, LocalizedError {
    case parentRequired(DetailCreateKind)
    case parentKindMismatch

    var errorDescription: String? {
        switch self {
        case let .parentRequired(kind): "A parent is required to create \(kind.rawValue)."
        case .parentKindMismatch: "The selected parent cannot contain this resource."
        }
    }
}

@MainActor
private struct AppEditorHost: View {
    let route: AppEditorPresentationRoute
    let origin: DetailOriginTab
    let runtime: AppUserRuntime
    @ObservedObject var appStore: AppStore
    @ObservedObject var languageStore: AppLanguageStore

    @State private var resolution: AppEditorResolution?
    @State private var isOnline = false
    @State private var errorText: String?
    private var copy: AppIntegrationCopy { AppIntegrationCopy(language: languageStore.language) }

    var body: some View {
        Group {
            if let resolution {
                AppResolvedEditorView(
                    resolution: resolution,
                    context: editorContext,
                    isOnline: isOnline,
                    runtime: runtime,
                    appStore: appStore,
                    languageStore: languageStore
                )
            } else if let errorText {
                NavigationStack {
                    AppUnavailableContent(title: copy.editorUnavailable, text: errorText)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(copy.close) { appStore.dismissPresentation() }
                        }
                    }
                }
            } else {
                ProgressView(copy.loading)
                    .accessibilityIdentifier("editor.loading")
            }
        }
        .task { await resolve() }
    }

    private var editorContext: EditorContext {
        switch route {
        case let .create(_, parent, afterSave):
            EditorContext(origin: origin, parent: parent, afterSave: afterSave)
        case .edit, .editIdeaHistory:
            EditorContext(origin: origin, parent: nil, afterSave: .openCreated)
        }
    }

    private func resolve() async {
        guard resolution == nil, errorText == nil else { return }
        do {
            isOnline = await runtime.plannerDetails.network.isConnected()
            switch route {
            case let .create(kind, parent, _):
                resolution = try await createResolution(kind: kind, parent: parent)
            case let .edit(reference):
                resolution = try await editResolution(reference)
            case let .editIdeaHistory(ideaID, noteID):
                let seed = try await runtime.reminderEditorSeedLoader.editorSeed(
                    for: .editIdeaHistory(ideaID: ideaID, noteID: noteID)
                )
                guard case let .ideaHistory(draft, loadedIdeaID) = seed else {
                    throw AppEditorHostError.parentKindMismatch
                }
                resolution = .ideaHistory(
                    .editIdeaHistory(ideaID: ideaID, noteID: noteID),
                    loadedIdeaID,
                    draft
                )
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func createResolution(
        kind: DetailCreateKind,
        parent: DetailEntityReference?
    ) async throws -> AppEditorResolution {
        switch kind {
        case .folder:
            guard parent == nil || parent?.kind == .folder else {
                throw AppEditorHostError.parentKindMismatch
            }
            return .folder(.create, parent?.id, FolderEditorDraft(name: "", description: ""))
        case .goal:
            guard let parent, parent.kind == .folder else {
                throw AppEditorHostError.parentRequired(kind)
            }
            return .goal(
                .create,
                parent.id,
                GoalEditorDraft(name: "", description: "", status: .todo)
            )
        case .task:
            guard let parent, parent.kind == .goal else {
                throw AppEditorHostError.parentRequired(kind)
            }
            let tags = (try await runtime.plannerDetails.persistence.allTags()).map {
                TagEditorItemDraft(id: $0.id, name: $0.name, colorHex: $0.color, assigned: false)
            }
            return .task(
                .create,
                parent.id,
                TaskEditorDraft(
                    title: "",
                    description: "",
                    status: .todo,
                    type: .green,
                    effort: 0,
                    plannedAt: nil,
                    dueAt: nil,
                    recurrence: .none,
                    checklist: [],
                    tags: tags
                ),
                .fullOwner,
                false
            )
        case .idea:
            guard let parent, parent.kind == .folder else {
                throw AppEditorHostError.parentRequired(kind)
            }
            return .idea(
                .create,
                parent.id,
                IdeaEditorDraft(
                    title: "",
                    body: "",
                    status: "active",
                    allowAuthorHistoryEdits: true
                )
            )
        case .note:
            guard let parent, parent.kind == .folder else {
                throw AppEditorHostError.parentRequired(kind)
            }
            return .note(.create, parent.id, NoteEditorDraft(title: "", body: ""))
        case .ideaHistory:
            guard let parent, parent.kind == .idea else {
                throw AppEditorHostError.parentRequired(kind)
            }
            return .ideaHistory(
                .create,
                parent.id,
                IdeaHistoryEditorDraft(eventType: "note", body: "", metadata: [:])
            )
        }
    }

    private func editResolution(_ reference: DetailEntityReference) async throws -> AppEditorResolution {
        let seed = try await runtime.reminderEditorSeedLoader.editorSeed(for: .edit(reference))
        switch seed {
        case let .folder(draft, parentID): return .folder(.edit(reference), parentID, draft)
        case let .goal(draft, folderID): return .goal(.edit(reference), folderID, draft)
        case let .task(draft, goalID, access, focused):
            return .task(.edit(reference), goalID, draft, access, focused)
        case let .idea(draft, folderID): return .idea(.edit(reference), folderID, draft)
        case let .ideaHistory(draft, ideaID):
            return .ideaHistory(.edit(reference), ideaID, draft)
        case let .note(draft, folderID): return .note(.edit(reference), folderID, draft)
        }
    }
}

@MainActor
private struct AppResolvedEditorView: View {
    let resolution: AppEditorResolution
    let runtime: AppUserRuntime
    @ObservedObject var appStore: AppStore
    @ObservedObject private var languageStore: AppLanguageStore
    @StateObject private var coordinator: EditorSaveCoordinator

    init(
        resolution: AppEditorResolution,
        context: EditorContext,
        isOnline: Bool,
        runtime: AppUserRuntime,
        appStore: AppStore,
        languageStore: AppLanguageStore
    ) {
        self.resolution = resolution
        self.runtime = runtime
        self.appStore = appStore
        _languageStore = ObservedObject(wrappedValue: languageStore)
        _coordinator = StateObject(
            wrappedValue: EditorSaveCoordinator(
                context: context,
                isOnline: isOnline,
                saver: runtime.reminderEditorActions,
                onComplete: appStore.handleDetailNavigation
            )
        )
    }

    @ViewBuilder
    var body: some View {
        NavigationStack {
            switch resolution {
            case let .folder(mode, parentID, draft):
                FolderEditorView(
                    mode: mode,
                    parentFolderID: parentID,
                    initialDraft: draft,
                    language: languageStore.language,
                    coordinator: coordinator,
                    onCancel: appStore.dismissPresentation
                )
            case let .goal(mode, folderID, draft):
                GoalEditorView(
                    mode: mode,
                    folderID: folderID,
                    initialDraft: draft,
                    language: languageStore.language,
                    coordinator: coordinator,
                    onCancel: appStore.dismissPresentation
                )
            case let .task(mode, goalID, draft, access, focused):
                TaskEditorView(
                    mode: mode,
                    goalID: goalID,
                    initialDraft: draft,
                    initialIsInFocus: focused,
                    access: access,
                    timezone: TimeZone(identifier: runtime.user.timezone) ?? TimeZone(secondsFromGMT: 0)!,
                    language: languageStore.language,
                    coordinator: coordinator,
                    tagCreator: runtime.plannerDetailsActions,
                    focusUpdater: runtime.plannerDetailsActions,
                    onCancel: appStore.dismissPresentation
                )
            case let .idea(mode, folderID, draft):
                IdeaEditorView(
                    mode: mode,
                    folderID: folderID,
                    initialDraft: draft,
                    language: languageStore.language,
                    coordinator: coordinator,
                    onCancel: appStore.dismissPresentation
                )
            case let .ideaHistory(mode, ideaID, draft):
                IdeaHistoryEditorView(
                    mode: mode,
                    ideaID: ideaID,
                    initialDraft: draft,
                    language: languageStore.language,
                    coordinator: coordinator,
                    onCancel: appStore.dismissPresentation
                )
            case let .note(mode, folderID, draft):
                NoteEditorView(
                    mode: mode,
                    folderID: folderID,
                    initialDraft: draft,
                    language: languageStore.language,
                    coordinator: coordinator,
                    onCancel: appStore.dismissPresentation
                )
            }
        }
        .accessibilityIdentifier("editor.screen")
    }
}

@MainActor
private struct AppFocusCadenceHost: View {
    @StateObject private var model: FocusViewModel
    @ObservedObject private var languageStore: AppLanguageStore

    init(
        runtime: AppUserRuntime,
        appStore: AppStore,
        languageStore: AppLanguageStore
    ) {
        _languageStore = ObservedObject(wrappedValue: languageStore)
        _model = StateObject(
            wrappedValue: FocusViewModel(
                accountID: runtime.user.id,
                timezone: runtime.user.timezone,
                language: languageStore.language,
                repository: runtime.focusActions,
                onOpenTask: { appStore.openTask($0, origin: .focus) },
                onUnauthorized: { Task { await appStore.handleUnauthorized(for: runtime.lease) } }
            )
        )
    }

    var body: some View {
        FocusCadenceSettingsView(model: model)
            .onChange(of: languageStore.language) { model.setLanguage($0) }
    }
}

@MainActor
private struct AppSharingHost: View {
    let reference: DetailEntityReference
    let runtime: AppUserRuntime
    @ObservedObject var appStore: AppStore
    @ObservedObject var languageStore: AppLanguageStore
    @State private var model: ResourceSharingViewModel?
    @State private var errorText: String?
    private var copy: AppIntegrationCopy { AppIntegrationCopy(language: languageStore.language) }

    var body: some View {
        Group {
            if let model {
                ResourceSharingSheet(model: model)
            } else if let errorText {
                AppUnavailableSheet(
                    title: copy.unavailable,
                    close: copy.close,
                    text: errorText,
                    onClose: appStore.dismissPresentation
                )
            } else {
                ProgressView(copy.loading)
            }
        }
        .task { await load() }
        .onChange(of: languageStore.language) { model?.setLanguage($0) }
    }

    private func load() async {
        guard model == nil, errorText == nil else { return }
        do {
            let content = (try await runtime.plannerDetailsActions.loadDetail(reference)).content
            let serverID = try await runtime.plannerDetailsActions.serverID(
                kind: reference.kind,
                localID: reference.id
            )
            let isOwner = try await runtime.sharingOwnership.isOwner(of: reference)
            let context = try sharingContext(
                content: content,
                serverID: serverID,
                isOwner: isOwner
            )
            model = ResourceSharingViewModel(
                context: context,
                language: languageStore.language,
                service: runtime.sharingActions,
                onCopyToken: { UIPasteboard.general.string = $0 },
                onShareToken: { AppSystemSharePresenter.present(text: $0) },
                onAccepted: { _ in Task { await appStore.manualSync() } },
                onUnauthorized: { Task { await appStore.handleUnauthorized(for: runtime.lease) } }
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func sharingContext(
        content: DetailContent,
        serverID: UUID,
        isOwner: Bool
    ) throws -> SharingResourceContext {
        switch content {
        case let .folder(value):
            return SharingResourceContext(
                kind: .folder, id: serverID, title: value.name,
                isOwner: isOwner, shared: value.shared, fullAccess: value.fullAccess
            )
        case let .goal(value):
            return SharingResourceContext(
                kind: .goal, id: serverID, title: value.name,
                isOwner: isOwner, shared: value.shared, fullAccess: value.fullAccess
            )
        case let .task(value):
            return SharingResourceContext(
                kind: .task, id: serverID, title: value.title,
                isOwner: isOwner, shared: value.shared, fullAccess: value.fullAccess
            )
        case let .idea(value):
            return SharingResourceContext(
                kind: .idea, id: serverID, title: value.title,
                isOwner: isOwner, shared: value.shared, fullAccess: value.fullAccess
            )
        case .note:
            throw PlannerDetailsIntegrationError.unsupported(operation: "note.direct_share")
        }
    }
}

@MainActor
private struct AppCommandHost: View {
    let kind: AppCommandKind
    let reference: DetailEntityReference
    let origin: DetailOriginTab
    let runtime: AppUserRuntime
    @ObservedObject var appStore: AppStore
    @ObservedObject var languageStore: AppLanguageStore

    @State private var candidates: [AppCommandCandidate] = []
    @State private var selectedParentID: UUID?
    @State private var plannedAt = Date()
    @State private var isWorking = false
    @State private var errorText: String?
    private var copy: AppIntegrationCopy { AppIntegrationCopy(language: languageStore.language) }

    var body: some View {
        NavigationStack {
            Form {
                if kind == .reschedule {
                    DatePicker(copy.plannedDate, selection: $plannedAt)
                } else {
                    Picker(copy.destination, selection: $selectedParentID) {
                        if reference.kind == .folder {
                            Text(copy.root).tag(UUID?.none)
                        }
                        ForEach(candidates) { candidate in
                            Text(candidate.title).tag(UUID?.some(candidate.id))
                        }
                    }
                }
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.cancel) { appStore.dismissPresentation() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy.done) { Task { await execute() } }
                        .disabled(isWorking || (kind != .reschedule && selectedParentID == nil && reference.kind != .folder))
                }
            }
            .task { await loadCandidates() }
            .accessibilityIdentifier("command.\(kind.rawValue)")
        }
    }

    private var title: String {
        switch kind {
        case .move: copy.move
        case .clone: copy.clone
        case .reschedule: copy.reschedule
        }
    }

    private func loadCandidates() async {
        guard kind != .reschedule else { return }
        do {
            let snapshot = try await runtime.planningRepository.snapshot()
            switch reference.kind {
            case .folder:
                candidates = snapshot.folders.filter { $0.id != reference.id }
                    .map { AppCommandCandidate(id: $0.id, title: $0.name) }
            case .goal, .idea, .note:
                candidates = snapshot.folders.map { AppCommandCandidate(id: $0.id, title: $0.name) }
            case .task:
                candidates = snapshot.goals.map { AppCommandCandidate(id: $0.id, title: $0.name) }
            }
            candidates.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func execute() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: DetailEntityReference
            switch kind {
            case .move:
                result = try await runtime.plannerDetailsActions.move(
                    reference,
                    toParentID: selectedParentID
                )
            case .clone:
                result = try await runtime.plannerDetailsActions.clone(
                    reference,
                    toParentID: selectedParentID
                )
            case .reschedule:
                try await runtime.plannerDetailsActions.rescheduleTask(
                    localID: reference.id,
                    plannedAt: plannedAt
                )
                result = reference
            }
            appStore.handleDetailNavigation(.open(result, origin: origin))
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct AppCommandCandidate: Identifiable {
    let id: UUID
    let title: String
}

@MainActor
private struct AppUnavailableSheet: View {
    let title: String
    let close: String
    let text: String
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            AppUnavailableContent(title: title, text: text)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(close, action: onClose)
                }
            }
        }
    }
}

@MainActor
private struct AppUnavailableContent: View {
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}
