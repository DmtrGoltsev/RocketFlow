import SwiftUI

@MainActor
struct AuthenticatedAppView: View {
    @ObservedObject var appStore: AppStore
    let runtime: AppUserRuntime
    @ObservedObject var languageStore: AppLanguageStore
    let offline: Bool
    private var copy: AppIntegrationCopy { AppIntegrationCopy(language: languageStore.language) }

    var body: some View {
        TabView(selection: tabSelection) {
            navigationStack(for: .planner) {
                AppPlannerRoot(
                    runtime: runtime,
                    appStore: appStore,
                    languageStore: languageStore
                )
            }
            .tabItem {
                Label(copy.planner, systemImage: "list.bullet")
                    .accessibilityIdentifier("tab.planner")
            }
            .tag(AppTab.planner)

            navigationStack(for: .calendar) {
                AppCalendarRoot(
                    runtime: runtime,
                    appStore: appStore,
                    languageStore: languageStore
                )
            }
            .tabItem {
                Label(copy.calendar, systemImage: "calendar")
                    .accessibilityIdentifier("tab.calendar")
            }
            .tag(AppTab.calendar)

            navigationStack(for: .focus) {
                AppFocusRoot(
                    runtime: runtime,
                    appStore: appStore,
                    languageStore: languageStore
                )
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
                appStore: appStore,
                languageStore: languageStore
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
                    let visibleDiagnostic = AppFirebaseMessagingRuntime.userFacingDiagnostic(
                        diagnostic,
                        language: languageStore.language
                    )
                    Label(visibleDiagnostic, systemImage: "bell.slash")
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.bar)
                        .accessibilityLabel(visibleDiagnostic)
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
                        appStore: appStore,
                        languageStore: languageStore
                    )
                }
        }
    }
}

@MainActor
private struct AppPlannerRoot: View {
    @StateObject private var model: PlannerViewModel
    @ObservedObject private var languageStore: AppLanguageStore

    init(
        runtime: AppUserRuntime,
        appStore: AppStore,
        languageStore: AppLanguageStore
    ) {
        _languageStore = ObservedObject(wrappedValue: languageStore)
        _model = StateObject(
            wrappedValue: PlannerViewModel(
                accountID: runtime.user.id,
                language: languageStore.language,
                loader: runtime.plannerDetailsActions,
                actionPerformer: runtime.plannerDetailsActions,
                scrollState: appStore.plannerScrollState,
                onNavigate: appStore.handlePlannerNavigation
            )
        )
    }

    var body: some View {
        PlannerView(model: model)
            .onChange(of: languageStore.language) { model.setLanguage($0) }
    }
}

@MainActor
private struct AppCalendarRoot: View {
    @StateObject private var model: CalendarViewModel
    @ObservedObject private var languageStore: AppLanguageStore
    private let onOpenTask: (UUID) -> Void

    init(
        runtime: AppUserRuntime,
        appStore: AppStore,
        languageStore: AppLanguageStore
    ) {
        _languageStore = ObservedObject(wrappedValue: languageStore)
        _model = StateObject(
            wrappedValue: CalendarViewModel(
                accountID: runtime.user.id,
                accountTimezone: runtime.user.timezone,
                language: languageStore.language,
                loader: runtime.calendarActions,
                onUnauthorized: { Task { await appStore.handleUnauthorized(for: runtime.lease) } },
                restorationState: appStore.calendarRestorationState(for: runtime.lease),
                onRestorationStateChanged: {
                    appStore.calendarRestorationDidChange($0, for: runtime.lease)
                }
            )
        )
        onOpenTask = { appStore.openTask($0, origin: .calendar) }
    }

    var body: some View {
        CalendarView(model: model, onOpenTask: onOpenTask)
            .onChange(of: languageStore.language) { model.setLanguage($0) }
    }
}

@MainActor
private struct AppFocusRoot: View {
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
        FocusView(model: model)
            .onChange(of: languageStore.language) { model.setLanguage($0) }
    }
}

@MainActor
private struct AppRouteDestination: View {
    let route: AppRoute
    let runtime: AppUserRuntime
    @ObservedObject var appStore: AppStore
    @ObservedObject var languageStore: AppLanguageStore

    @ViewBuilder
    var body: some View {
        switch route {
        case let .detail(reference, origin):
            AppDetailHost(
                reference: reference,
                origin: origin,
                runtime: runtime,
                appStore: appStore,
                languageStore: languageStore
            )
        case .settings:
            AppSettingsHost(
                runtime: runtime,
                appStore: appStore,
                languageStore: languageStore
            )
        case let .links(reference, origin):
            AppLinksHost(
                reference: reference,
                origin: origin,
                runtime: runtime,
                appStore: appStore,
                languageStore: languageStore
            )
        }
    }
}

@MainActor
private struct AppDetailHost: View {
    let reference: DetailEntityReference
    @StateObject private var model: DetailViewModel
    @ObservedObject private var languageStore: AppLanguageStore
    private let reminderReader: any TaskReminderReading

    init(
        reference: DetailEntityReference,
        origin: DetailOriginTab,
        runtime: AppUserRuntime,
        appStore: AppStore,
        languageStore: AppLanguageStore
    ) {
        self.reference = reference
        _languageStore = ObservedObject(wrappedValue: languageStore)
        reminderReader = runtime.reminderWorkflow
        _model = StateObject(
            wrappedValue: DetailViewModel(
                reference: reference,
                origin: origin,
                loader: runtime.plannerDetailsActions,
                mutationPerformer: runtime.reminderDetailActions,
                onNavigate: appStore.handleDetailNavigation
            )
        )
    }

    @ViewBuilder
    var body: some View {
        switch reference.kind {
        case .folder: FolderDetailView(model: model, language: languageStore.language)
        case .goal: GoalDetailView(model: model, language: languageStore.language)
        case .task:
            TaskDetailView(
                model: model,
                language: languageStore.language,
                reminderReader: reminderReader
            )
        case .idea: IdeaDetailView(model: model, language: languageStore.language)
        case .note: NoteDetailView(model: model, language: languageStore.language)
        }
    }

}

@MainActor
private struct AppSettingsHost: View {
    @StateObject private var model: SettingsViewModel
    @ObservedObject private var languageStore: AppLanguageStore

    init(
        runtime: AppUserRuntime,
        appStore: AppStore,
        languageStore: AppLanguageStore
    ) {
        _languageStore = ObservedObject(wrappedValue: languageStore)
        _model = StateObject(
            wrappedValue: SettingsViewModel(
                accountID: runtime.user.id,
                initialLanguage: languageStore.language,
                repository: runtime.settingsActions,
                notificationCenter: runtime.notificationCenter,
                reminderStore: runtime.settingsReminderStore,
                registration: runtime.deviceRegistration,
                notificationCleaner: runtime.notificationActions,
                deviceName: AppDeviceInfo.name,
                onOpenFocusCadence: {
                    appStore.navigation.present(.focusCadence)
                },
                onUnauthorized: { Task { await appStore.handleUnauthorized(for: runtime.lease) } },
                onLanguageChanged: { languageStore.setLanguage($0) }
            )
        )
    }

    var body: some View {
        SettingsView(model: model)
            .onChange(of: languageStore.language) {
                model.reconcileExternalLanguage($0)
            }
    }
}
