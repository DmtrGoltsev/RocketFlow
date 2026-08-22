import SwiftUI

@main
struct RocketFlowApp: App {
    @StateObject private var dependencies = DependencyContainer()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(dependencies)
        }
    }
}

