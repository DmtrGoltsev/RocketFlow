import SwiftUI

@main
struct RocketFlowApp: App {
    @UIApplicationDelegateAdaptor(RocketFlowAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dependencies: DependencyContainer
    @StateObject private var appStore: AppStore

    @MainActor
    init() {
        let launchConfiguration = AppLaunchConfiguration.current()
        let dependencies: DependencyContainer
        switch launchConfiguration {
        case .production:
            dependencies = DependencyContainer(registerBackgroundTasks: true)
        case .authenticatedUITest:
            dependencies = DependencyContainer(
                apiBaseURL: URL(string: "https://ui-test.invalid/rocket-api")!,
                sessionStore: InMemorySessionStore(),
                databaseOpener: { _ in try AppDatabase.inMemory() },
                networkMonitor: FixedNetworkMonitor(connected: false),
                notificationCenter: AppUITestNotificationCenter(),
                fcmTokenProvider: ManualFCMRegistrationTokenProvider(configured: false),
                registerBackgroundTasks: false
            )
        }
        _dependencies = StateObject(wrappedValue: dependencies)
        _appStore = StateObject(
            wrappedValue: dependencies.makeAppStore(
                launchUser: launchConfiguration.launchUser
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                AppRootView()
                    .environmentObject(dependencies)
                    .environmentObject(appStore)

                if appStore.shouldShowPersistenceRecovery,
                   let error = appStore.persistenceError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Локальные данные недоступны", systemImage: "externaldrive.badge.exclamationmark")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                        Button {
                            Task { await appStore.retryPersistence() }
                        } label: {
                            Label("Повторить", systemImage: "arrow.clockwise")
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
            .onOpenURL { url in
                Task { await appStore.receiveDeepLink(url) }
            }
        }
    }
}
