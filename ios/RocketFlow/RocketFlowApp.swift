import SwiftUI

@main
struct RocketFlowApp: App {
    @StateObject private var dependencies: DependencyContainer
    @StateObject private var appStore: AppStore

    @MainActor
    init() {
        let dependencies = DependencyContainer()
        _dependencies = StateObject(wrappedValue: dependencies)
        _appStore = StateObject(wrappedValue: AppStore(authSession: dependencies.authSession))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(dependencies)
                .environmentObject(appStore)
        }
    }
}
