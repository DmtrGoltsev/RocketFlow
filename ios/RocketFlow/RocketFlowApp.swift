import SwiftUI

@main
struct RocketFlowApp: App {
    @UIApplicationDelegateAdaptor(RocketFlowAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var languageStore: AppLanguageStore
    @StateObject private var dependencies: DependencyContainer
    @StateObject private var appStore: AppStore

    @MainActor
    init() {
        let launchConfiguration = AppLaunchConfiguration.current()
        let languageStore = AppLanguageStore()
        let dependencies: DependencyContainer
        let restorationPersistence: any AppRestorationPersisting
        switch launchConfiguration {
        case .production:
            restorationPersistence = AppRestorationUserDefaultsStore()
            dependencies = DependencyContainer(
                languageStore: languageStore,
                registerBackgroundTasks: true
            )
        case .authenticatedUITest:
            let defaults = UserDefaults(
                suiteName: "rocketflow.ui-test-restoration.\(UUID().uuidString)"
            ) ?? .standard
            restorationPersistence = AppRestorationUserDefaultsStore(defaults: defaults)
            dependencies = DependencyContainer(
                apiBaseURL: URL(string: "https://ui-test.invalid/rocket-api")!,
                languageStore: languageStore,
                sessionStore: InMemorySessionStore(),
                databaseOpener: { _ in try AppDatabase.inMemory() },
                networkMonitor: FixedNetworkMonitor(connected: false),
                notificationCenter: AppUITestNotificationCenter(),
                fcmTokenProvider: ManualFCMRegistrationTokenProvider(configured: false),
                registerBackgroundTasks: false
            )
        }
        _languageStore = StateObject(wrappedValue: languageStore)
        _dependencies = StateObject(wrappedValue: dependencies)
        _appStore = StateObject(
            wrappedValue: dependencies.makeAppStore(
                launchUser: launchConfiguration.launchUser,
                restorationPersistence: restorationPersistence
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                AppRootView()
                    .environmentObject(dependencies)
                    .environmentObject(appStore)
                    .environmentObject(languageStore)
                    .environment(\.locale, Locale(identifier: languageStore.localeIdentifier))

                if appStore.shouldShowPersistenceRecovery,
                   let error = appStore.persistenceError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            AppIntegrationCopy(language: languageStore.language).localDataUnavailable,
                            systemImage: "externaldrive.badge.exclamationmark"
                        )
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                        Button {
                            Task { await appStore.retryPersistence() }
                        } label: {
                            Label(
                                AppIntegrationCopy(language: languageStore.language).retry,
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(12)
                    .frame(maxWidth: 520, alignment: .leading)
                    .background(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.red.opacity(0.35), lineWidth: 1)
                    }
                    .padding(12)
                    .accessibilityIdentifier("app.persistence.error")
                }
            }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .active:
                    appStore.scheduleLifecycle(.foreground)
                case .background:
                    appStore.scheduleLifecycle(.background)
                case .inactive:
                    appStore.scheduleLifecycle(.inactive)
                @unknown default:
                    appStore.scheduleLifecycle(.inactive)
                }
            }
            .onChange(of: languageStore.language) { language in
                appStore.appLanguageDidChange(language)
            }
            .onOpenURL { url in
                Task { await appStore.receiveDeepLink(url) }
            }
        }
    }
}
