import SwiftUI

@main
struct RocketFlowApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dependencies: DependencyContainer
    @StateObject private var appStore: AppStore

    @MainActor
    init() {
        let dependencies = DependencyContainer()
        _dependencies = StateObject(wrappedValue: dependencies)
        _appStore = StateObject(wrappedValue: dependencies.makeAppStore())
    }

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                AppRootView()
                    .environmentObject(dependencies)
                    .environmentObject(appStore)

                if let error = appStore.persistenceError {
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
                Task {
                    switch phase {
                    case .active:
                        await appStore.handleLifecycle(.foreground)
                    case .background:
                        await appStore.handleLifecycle(.background)
                    case .inactive:
                        await appStore.handleLifecycle(.inactive)
                    @unknown default:
                        await appStore.handleLifecycle(.inactive)
                    }
                }
            }
        }
    }
}
