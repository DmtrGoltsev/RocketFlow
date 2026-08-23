import Foundation

enum AppRestorableRoute: Codable, Equatable, Hashable, Sendable {
    case detail(DetailEntityReference, origin: DetailOriginTab)
    case settings
    case links(DetailEntityReference, origin: DetailOriginTab)

    init(_ route: AppRoute) {
        switch route {
        case let .detail(reference, origin):
            self = .detail(reference, origin: origin)
        case .settings:
            self = .settings
        case let .links(reference, origin):
            self = .links(reference, origin: origin)
        }
    }

    var appRoute: AppRoute {
        switch self {
        case let .detail(reference, origin):
            return .detail(reference, origin: origin)
        case .settings:
            return .settings
        case let .links(reference, origin):
            return .links(reference, origin: origin)
        }
    }
}

struct AppNavigationRestorationState: Codable, Equatable, Sendable {
    let selectedTab: AppTab
    let plannerPath: [AppRestorableRoute]
    let calendarPath: [AppRestorableRoute]
    let focusPath: [AppRestorableRoute]

    init(navigation: AppNavigationState) {
        selectedTab = navigation.selectedTab
        plannerPath = navigation.plannerPath.map(AppRestorableRoute.init)
        calendarPath = navigation.calendarPath.map(AppRestorableRoute.init)
        focusPath = navigation.focusPath.map(AppRestorableRoute.init)
    }

    func path(for tab: AppTab) -> [AppRestorableRoute] {
        switch tab {
        case .planner: plannerPath
        case .calendar: calendarPath
        case .focus: focusPath
        }
    }
}

struct AppRestorationVersionEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: Int
}

struct AppRestorationEnvelopeHeader: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let accountID: UUID
}

struct AppRestorationPayloadV1: Codable, Equatable, Sendable {
    let navigation: AppNavigationRestorationState
    let calendar: CalendarRestorationState?
}

struct AppRestorationSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let accountID: UUID
    let payload: AppRestorationPayloadV1

    var navigation: AppNavigationRestorationState { payload.navigation }
    var calendar: CalendarRestorationState? { payload.calendar }

    init(
        accountID: UUID,
        navigation: AppNavigationRestorationState,
        calendar: CalendarRestorationState?,
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.accountID = accountID
        payload = AppRestorationPayloadV1(
            navigation: navigation,
            calendar: calendar
        )
    }
}

enum AppRestorationDiscardReason: Equatable, Sendable {
    case corrupt
    case versionMismatch
    case accountMismatch
}

enum AppRestorationSource: Equatable, Sendable {
    case missing
    case restored
    case superseded
    case discarded(AppRestorationDiscardReason)
}

struct AppRestorationActivation: Equatable, Sendable {
    let source: AppRestorationSource
    let navigation: AppNavigationState
    let calendar: CalendarRestorationState?
    let generation: UInt64

    var shouldApplyToRuntime: Bool { source != .superseded }
}

struct AppRestorationRouteValidator: Sendable {
    let isAvailable: @Sendable (AppRestorableRoute, UUID) async -> Bool

    init(
        isAvailable: @escaping @Sendable (AppRestorableRoute, UUID) async -> Bool
    ) {
        self.isAvailable = isAvailable
    }
}
