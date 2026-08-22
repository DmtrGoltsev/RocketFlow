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
            case .signedOut:
                AuthView(submitter: appStore)
            case let .authenticated(user):
                AuthenticatedRootView(user: user, offline: false)
            case let .offline(user):
                AuthenticatedRootView(user: user, offline: true)
            }
        }
        .task { await appStore.restoreIfNeeded() }
    }
}

private struct AuthenticatedRootView: View {
    let user: UserDTO
    let offline: Bool

    var body: some View {
        TabView {
            placeholder(title: "Главная", symbol: "list.bullet")
                .tabItem { Label("Главная", systemImage: "list.bullet") }
            placeholder(title: "Календарь", symbol: "calendar")
                .tabItem { Label("Календарь", systemImage: "calendar") }
            placeholder(title: "Фокус", symbol: "scope")
                .tabItem { Label("Фокус", systemImage: "scope") }
        }
        .safeAreaInset(edge: .top) {
            if offline {
                Label("Нет соединения. Показаны сохранённые данные.", systemImage: "wifi.slash")
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.bar)
                    .accessibilityIdentifier("app.offline")
            }
        }
    }

    private func placeholder(title: String, symbol: String) -> some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                Text("Раздел готов к подключению данных.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text(user.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
