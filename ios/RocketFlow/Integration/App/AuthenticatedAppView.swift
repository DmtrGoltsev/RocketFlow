import SwiftUI

@MainActor
struct AuthenticatedAppView: View {
    @ObservedObject var appStore: AppStore
    let runtime: AppUserRuntime
    let offline: Bool
    private var copy: AppIntegrationCopy { AppIntegrationCopy(language: runtime.user.language) }

    var body: some View {
        TabView(selection: tabSelection) {
            navigationStack(for: .planner) {
                AppPlannerRoot(runtime: runtime, appStore: appStore)
            }
            .tabItem {
                Label(copy.planner, systemImage: "list.bullet")
                    .accessibilityIdentifier("tab.planner")
            }
            .tag(AppTab.planner)

            navigationStack(for: .calendar) {
                AppCalendarRoot(runtime: runtime, appStore: appStore)
            }
            .tabItem {
                Label(copy.calendar, systemImage: "calendar")
                    .accessibilityIdentifier("tab.calendar")
            }
            .tag(AppTab.calendar)

            navigationStack(for: .focus) {
                AppFocusRoot(runtime: runtime, appStore: appStore)
            }
            .tabItem {
                Label(copy.focus, systemImage: "scope")
                    .accessibilityIdentifier("tab.focus")
            }
            .tag(AppTab.focus)
        }
        .sheet(item: presentationBinding) { presentation in
            AppPresentationHost(
                route: presentation.route,
                runtime: runtime,
                appStore: appStore
            )
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                if offline {
                    Label(copy.offline, systemImage: "wifi.slash")
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.bar)
                        .accessibilityIdentifier("app.offline")
                }
                if let diagnostic = appStore.pushConfigurationDiagnostic {
                    Label(diagnostic, systemImage: "bell.slash")
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.bar)
                        .accessibilityIdentifier("app.push.unavailable")
                }
            }
        }
        .alert(
            "RocketFlow",
            isPresented: Binding(
                get: { appStore.navigation.notice != nil },
                set: { if !$0 { appStore.navigation.notice = nil } }
            )
        ) {
            Button("OK", role: .cancel) { appStore.navigation.notice = nil }
        } message: {
            Text(appStore.navigation.notice ?? "")
        }
        .accessibilityIdentifier("app.authenticated")
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { appStore.navigation.selectedTab },
            set: { appStore.selectTab($0) }
        )
    }

    private var presentationBinding: Binding<AppPresentation?> {
        Binding(
            get: { appStore.navigation.presentation },
            set: { value in
                if value == nil { appStore.dismissPresentation() }
            }
        )
    }

    private func pathBinding(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { appStore.navigation.path(for: tab) },
            set: { appStore.setPath($0, for: tab) }
        )
    }

    private func navigationStack<Content: View>(
        for tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack(path: pathBinding(for: tab)) {
            content()
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteDestination(
                        route: route,
                        runtime: runtime,
                        appStore: appStore
                    )
                }
        }
    }
}

@MainActor
private struct AppPlannerRoot: View {
    @StateObject private var model: PlannerViewModel

    init(runtime: AppUserRuntime, appStore: AppStore) {
        _model = StateObject(
            wrappedValue: PlannerViewModel(
                accountID: runtime.user.id,
                language: runtime.user.language,
                loader: runtime.plannerDetailsActions,
                actionPerformer: runtime.plannerDetailsActions,
                scrollState: appStore.plannerScrollState,
                onNavigate: appStore.handlePlannerNavigation
            )
        )
    }

    var body: some View { PlannerView(model: model) }
}

@MainActor
private struct AppCalendarRoot: View {
    @StateObject private var model: CalendarViewModel
    private let onOpenTask: (UUID) -> Void

    init(runtime: AppUserRuntime, appStore: AppStore) {
        _model = StateObject(
            wrappedValue: CalendarViewModel(
                accountID: runtime.user.id,
                accountTimezone: runtime.user.timezone,
                language: runtime.user.language,
                loader: runtime.calendarActions,
                onUnauthorized: { Task { await appStore.handleUnauthorized(for: runtime.lease) } }
            )
        )
        onOpenTask = { appStore.openTask($0, origin: .calendar) }
    }

    var body: some View { CalendarView(model: model, onOpenTask: onOpenTask) }
}

@MainActor
private struct AppFocusRoot: View {
    @StateObject private var model: FocusViewModel

    init(runtime: AppUserRuntime, appStore: AppStore) {
        _model = StateObject(
            wrappedValue: FocusViewModel(
                accountID: runtime.user.id,
                timezone: runtime.user.timezone,
                language: runtime.user.language,
                repository: runtime.focusActions,
                onOpenTask: { appStore.openTask($0, origin: .focus) },
                onUnauthorized: { Task { await appStore.handleUnauthorized(for: runtime.lease) } }
            )
        )
    }

    var body: some View { FocusView(model: model) }
}

@MainActor
private struct AppRouteDestination: View {
    let route: AppRoute
    let runtime: AppUserRuntime
    @ObservedObject var appStore: AppStore

    @ViewBuilder
    var body: some View {
        switch route {
        case let .detail(reference, origin):
            AppDetailHost(
                reference: reference,
                origin: origin,
                runtime: runtime,
                appStore: appStore
            )
        case .settings:
            AppSettingsHost(runtime: runtime, appStore: appStore)
        case let .links(reference, origin):
            AppLinksHost(
                reference: reference,
                origin: origin,
                runtime: runtime,
                appStore: appStore
            )
        }
    }
}

@MainActor
private struct AppDetailHost: View {
    let reference: DetailEntityReference
    @StateObject private var model: DetailViewModel
    private let language: AppLanguage

    init(
        reference: DetailEntityReference,
        origin: DetailOriginTab,
        runtime: AppUserRuntime,
        appStore: AppStore
    ) {
        self.reference = reference
        language = runtime.user.language
        _model = StateObject(
            wrappedValue: DetailViewModel(
                reference: reference,
                origin: origin,
                loader: runtime.plannerDetailsActions,
                mutationPerformer: runtime.plannerDetailsActions,
                onNavigate: appStore.handleDetailNavigation
            )
        )
    }

    @ViewBuilder
    var body: some View {
        switch reference.kind {
        case .folder: FolderDetailView(model: model, language: language)
        case .goal: GoalDetailView(model: model, language: language)
        case .task: TaskDetailView(model: model, language: language)
        case .idea: IdeaDetailView(model: model, language: language)
        case .note: NoteDetailView(model: model, language: language)
        }
    }
}

@MainActor
private struct AppSettingsHost: View {
    @StateObject private var model: SettingsViewModel

    init(runtime: AppUserRuntime, appStore: AppStore) {
        _model = StateObject(
            wrappedValue: SettingsViewModel(
                accountID: runtime.user.id,
                initialLanguage: runtime.user.language,
                repository: runtime.settingsActions,
                notificationCenter: runtime.notificationCenter,
                reminderStore: runtime.reminderStore,
                registration: runtime.deviceRegistration,
                notificationCleaner: runtime.reminderScheduler,
                deviceName: AppDeviceInfo.name,
                onOpenFocusCadence: {
                    appStore.navigation.present(.focusCadence)
                },
                onUnauthorized: { Task { await appStore.handleUnauthorized(for: runtime.lease) } }
            )
        )
    }

    var body: some View { SettingsView(model: model) }
}
