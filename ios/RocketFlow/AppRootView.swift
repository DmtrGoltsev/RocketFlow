import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var dependencies: DependencyContainer

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text("home.ready")
                    .font(.headline)
                    .accessibilityIdentifier("home.ready")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("app.title")
        }
    }
}

#Preview {
    AppRootView()
        .environmentObject(DependencyContainer())
}

