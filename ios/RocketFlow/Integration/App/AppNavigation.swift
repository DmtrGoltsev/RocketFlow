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

    func path(for tab: AppTab) -> [AppRoute] {
        switch tab {
        case .planner: plannerPath
        case .calendar: calendarPath
        case .focus: focusPath
        }
    }

    mutating func setPath(_ path: [AppRoute], for tab: AppTab) {
        switch tab {
        case .planner: plannerPath = path
        case .calendar: calendarPath = path
        case .focus: focusPath = path
        }
    }

    mutating func select(_ tab: AppTab) {
        selectedTab = tab
    }

    mutating func open(_ reference: DetailEntityReference, origin: DetailOriginTab) {
        let tab = AppTab(origin: origin)
        selectedTab = tab
        append(.detail(reference, origin: origin), to: tab)
    }

    mutating func openSettings() {
        selectedTab = .planner
        append(.settings, to: .planner)
    }

    mutating func openLinks(_ reference: DetailEntityReference, origin: DetailOriginTab) {
        let tab = AppTab(origin: origin)
        selectedTab = tab
        append(.links(reference, origin: origin), to: tab)
    }

    mutating func present(_ route: AppPresentationRoute) {
        presentation = AppPresentation(route: route)
    }

    mutating func dismissPresentation() {
        presentation = nil
    }

    mutating func handle(_ result: DetailNavigationResult) {
        switch result {
        case let .open(reference, origin):
            presentation = nil
            open(reference, origin: origin)
        case let .present(route, origin):
            if case let .links(reference) = route {
                presentation = nil
                openLinks(reference, origin: origin)
            } else {
                present(detailPresentation(route, origin: origin))
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
                return
            }
            let origin: DetailOriginTab
            switch navigationOrigin {
            case .planner: origin = .home
            case .calendar: origin = .calendar
            case .focus: origin = .focus
            }
            open(
                DetailEntityReference(kind: .task, id: localTaskID),
                origin: origin
            )
        }
    }

    mutating func resetForAccountTransition() {
        selectedTab = .planner
        plannerPath = []
        calendarPath = []
        focusPath = []
        presentation = nil
        notice = nil
    }

    private mutating func append(_ route: AppRoute, to tab: AppTab) {
        var path = path(for: tab)
        if path.last != route { path.append(route) }
        setPath(path, for: tab)
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
            setPath([], for: tab)
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
        setPath(path, for: tab)
    }
}
