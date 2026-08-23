import Foundation

enum AppTab: String, CaseIterable, Codable, Hashable, Sendable {
    case planner
    case calendar
    case focus

    var origin: DetailOriginTab {
        switch self {
        case .planner: .home
        case .calendar: .calendar
        case .focus: .focus
        }
    }

    init(origin: DetailOriginTab) {
        switch origin {
        case .home: self = .planner
        case .calendar: self = .calendar
        case .focus: self = .focus
        }
    }
}

enum AppRoute: Hashable, Sendable {
    case detail(DetailEntityReference, origin: DetailOriginTab)
    case settings
    case links(DetailEntityReference, origin: DetailOriginTab)
}

enum AppCommandKind: String, Equatable, Sendable {
    case move
    case clone
    case reschedule
}

enum AppEditorPresentationRoute: Equatable, Sendable {
    case create(
        kind: DetailCreateKind,
        parent: DetailEntityReference?,
        afterSave: DetailAfterSaveRoute
    )
    case edit(DetailEntityReference)
    case editIdeaHistory(ideaID: UUID, noteID: UUID)
}

enum AppPresentationRoute: Equatable, Sendable {
    case editor(AppEditorPresentationRoute, origin: DetailOriginTab)
    case sharing(DetailEntityReference, origin: DetailOriginTab)
    case command(AppCommandKind, DetailEntityReference, origin: DetailOriginTab)
    case focusCadence
}

struct AppPresentation: Identifiable, Equatable, Sendable {
    let id: UUID
    let route: AppPresentationRoute

    init(id: UUID = UUID(), route: AppPresentationRoute) {
        self.id = id
        self.route = route
    }
}

struct AppNavigationState: Equatable, Sendable {
    var selectedTab: AppTab = .planner
    var plannerPath: [AppRoute] = []
    var calendarPath: [AppRoute] = []
    var focusPath: [AppRoute] = []
    var presentation: AppPresentation?
    var notice: String?
    private var restorationMutationHandler: (@Sendable (AppNavigationState) -> Void)?

    init(
        selectedTab: AppTab = .planner,
        plannerPath: [AppRoute] = [],
        calendarPath: [AppRoute] = [],
        focusPath: [AppRoute] = [],
        presentation: AppPresentation? = nil,
        notice: String? = nil
    ) {
        self.selectedTab = selectedTab
        self.plannerPath = plannerPath
        self.calendarPath = calendarPath
        self.focusPath = focusPath
        self.presentation = presentation
        self.notice = notice
    }

    static func == (lhs: AppNavigationState, rhs: AppNavigationState) -> Bool {
        lhs.selectedTab == rhs.selectedTab
            && lhs.plannerPath == rhs.plannerPath
            && lhs.calendarPath == rhs.calendarPath
            && lhs.focusPath == rhs.focusPath
            && lhs.presentation == rhs.presentation
            && lhs.notice == rhs.notice
    }

    func path(for tab: AppTab) -> [AppRoute] {
        switch tab {
        case .planner: plannerPath
        case .calendar: calendarPath
        case .focus: focusPath
        }
    }

    mutating func setPath(_ path: [AppRoute], for tab: AppTab) {
        assignPath(path, to: tab)
        persistRestorationMutation()
    }

    mutating func select(_ tab: AppTab) {
        selectedTab = tab
        persistRestorationMutation()
    }

    mutating func open(_ reference: DetailEntityReference, origin: DetailOriginTab) {
        openWithoutPersisting(reference, origin: origin)
        persistRestorationMutation()
    }

    mutating func openSettings() {
        selectedTab = .planner
        append(.settings, to: .planner)
        persistRestorationMutation()
    }

    mutating func openLinks(_ reference: DetailEntityReference, origin: DetailOriginTab) {
        openLinksWithoutPersisting(reference, origin: origin)
        persistRestorationMutation()
    }

    mutating func present(_ route: AppPresentationRoute) {
        presentation = AppPresentation(route: route)
        persistRestorationMutation()
    }

    mutating func dismissPresentation() {
        presentation = nil
        persistRestorationMutation()
    }

    mutating func handle(_ result: DetailNavigationResult) {
        switch result {
        case let .open(reference, origin):
            presentation = nil
            openWithoutPersisting(reference, origin: origin)
        case let .present(route, origin):
            if case let .links(reference) = route {
                presentation = nil
                openLinksWithoutPersisting(reference, origin: origin)
            } else {
                presentation = AppPresentation(route: detailPresentation(route, origin: origin))
            }
        case let .deleted(destination):
            presentation = nil
            returnAfterDeletion(destination)
        case let .taskCreated(_, goalID, origin):
            presentation = nil
            replaceTopWithGoal(goalID, origin: origin)
        case let .dismissToOrigin(origin):
            presentation = nil
            selectedTab = AppTab(origin: origin)
        }
        persistRestorationMutation()
    }

    mutating func applyDeepLink(
        _ resolution: DeepLinkResolution,
        localTaskID: UUID?
    ) {
        notice = resolution.errorMessage
        switch resolution.destination {
        case .focus:
            presentation = nil
            focusPath = []
            selectedTab = .focus
        case .planner:
            presentation = nil
            plannerPath = []
            selectedTab = .planner
        case let .task(_, navigationOrigin):
            guard let localTaskID else {
                presentation = nil
                plannerPath = []
                selectedTab = .planner
                persistRestorationMutation()
                return
            }
            let origin: DetailOriginTab
            switch navigationOrigin {
            case .planner: origin = .home
            case .calendar: origin = .calendar
            case .focus: origin = .focus
            }
            openWithoutPersisting(
                DetailEntityReference(kind: .task, id: localTaskID),
                origin: origin
            )
        }
        persistRestorationMutation()
    }

    mutating func resetForAccountTransition() {
        selectedTab = .planner
        plannerPath = []
        calendarPath = []
        focusPath = []
        presentation = nil
        notice = nil
        persistRestorationMutation()
    }

    mutating func installRestorationMutationHandler(
        _ handler: @escaping @Sendable (AppNavigationState) -> Void
    ) {
        restorationMutationHandler = handler
    }

    mutating func removeRestorationMutationHandler() {
        restorationMutationHandler = nil
    }

    private mutating func append(_ route: AppRoute, to tab: AppTab) {
        var path = path(for: tab)
        if path.last != route { path.append(route) }
        assignPath(path, to: tab)
    }

    private mutating func assignPath(_ path: [AppRoute], to tab: AppTab) {
        switch tab {
        case .planner: plannerPath = path
        case .calendar: calendarPath = path
        case .focus: focusPath = path
        }
    }

    private mutating func openWithoutPersisting(
        _ reference: DetailEntityReference,
        origin: DetailOriginTab
    ) {
        let tab = AppTab(origin: origin)
        selectedTab = tab
        append(.detail(reference, origin: origin), to: tab)
    }

    private mutating func openLinksWithoutPersisting(
        _ reference: DetailEntityReference,
        origin: DetailOriginTab
    ) {
        let tab = AppTab(origin: origin)
        selectedTab = tab
        append(.links(reference, origin: origin), to: tab)
    }

    private func persistRestorationMutation() {
        restorationMutationHandler?(self)
    }

    private func detailPresentation(
        _ route: DetailEditorRoute,
        origin: DetailOriginTab
    ) -> AppPresentationRoute {
        switch route {
        case let .create(kind, parent, afterSave):
            return .editor(
                .create(kind: kind, parent: parent, afterSave: afterSave),
                origin: origin
            )
        case let .edit(reference):
            return .editor(.edit(reference), origin: origin)
        case let .editIdeaHistory(ideaID, noteID):
            return .editor(
                .editIdeaHistory(ideaID: ideaID, noteID: noteID),
                origin: origin
            )
        case let .move(reference):
            return .command(.move, reference, origin: origin)
        case let .clone(reference):
            return .command(.clone, reference, origin: origin)
        case let .share(reference):
            return .sharing(reference, origin: origin)
        case let .links(reference):
            preconditionFailure("Links are pushed as an AppRoute before presentation mapping: \(reference.id)")
        case let .reschedule(reference):
            return .command(.reschedule, reference, origin: origin)
        }
    }

    private mutating func returnAfterDeletion(_ destination: DetailReturnDestination) {
        switch destination {
        case let .originRoot(origin):
            let tab = AppTab(origin: origin)
            selectedTab = tab
            assignPath([], to: tab)
        case let .folder(id, origin):
            replacePath(
                with: DetailEntityReference(kind: .folder, id: id),
                origin: origin
            )
        case let .goal(id, origin):
            replacePath(
                with: DetailEntityReference(kind: .goal, id: id),
                origin: origin
            )
        }
    }

    private mutating func replaceTopWithGoal(_ goalID: UUID, origin: DetailOriginTab) {
        replacePath(
            with: DetailEntityReference(kind: .goal, id: goalID),
            origin: origin
        )
    }

    private mutating func replacePath(
        with reference: DetailEntityReference,
        origin: DetailOriginTab
    ) {
        let tab = AppTab(origin: origin)
        selectedTab = tab
        var path = path(for: tab)
        if let existingIndex = path.lastIndex(where: {
            if case let .detail(value, _) = $0 { return value == reference }
            return false
        }) {
            path = Array(path.prefix(through: existingIndex))
        } else {
            if !path.isEmpty { path.removeLast() }
            path.append(.detail(reference, origin: origin))
        }
        assignPath(path, to: tab)
    }
}
