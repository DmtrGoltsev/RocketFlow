import SwiftUI

@MainActor
struct AppRootView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        Group {
            switch appStore.state {
            case .launching:
                ProgressView("Загрузка…")
                    .accessibilityIdentifier("app.launching")
            case let .configurationError(message):
                blockingState(
                    title: "Ошибка конфигурации",
                    message: message,
                    symbol: "wrench.and.screwdriver",
                    actionTitle: nil,
                    action: nil
                )
                .accessibilityIdentifier("app.configuration.error")
            case let .cleanupRequired(message):
                blockingState(
                    title: "Требуется очистка локальных данных",
                    message: message,
                    symbol: "lock.shield",
                    actionTitle: "Повторить очистку",
                    action: { Task { await appStore.retryPrivacyCleanup() } }
                )
                .accessibilityIdentifier("app.cleanup.required")
            case .signedOut:
                AuthView(submitter: appStore)
            case let .authenticated(user):
                authenticated(user: user, offline: false)
            case let .offline(user):
                authenticated(user: user, offline: true)
            }
        }
        .task { await appStore.restoreIfNeeded() }
    }

    private func blockingState(
        title: String,
        message: String,
        symbol: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private func authenticated(user: UserDTO, offline: Bool) -> some View {
        let copy = AppIntegrationCopy(language: user.language)
        if appStore.runtimeReady,
           let runtime = dependencies.activeRuntime,
           runtime.user.id == user.id {
            AuthenticatedAppView(
                appStore: appStore,
                runtime: runtime,
                offline: offline
            )
            .id(user.id)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text(copy.preparingData)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if appStore.persistenceError != nil {
                    Button {
                        Task { await appStore.retryPersistence() }
                    } label: {
                        Label(copy.retry, systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .accessibilityIdentifier("app.runtime.loading")
        }
    }
}
