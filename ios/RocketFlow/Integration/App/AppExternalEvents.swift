import Foundation

enum AppRemoteNotificationFetchResult: Equatable, Sendable {
    case newData
    case noData
    case failed
}

@MainActor
final class AppExternalEventHub {
    typealias DeepLinkHandler = @MainActor (URL) async -> Void
    typealias RemoteDataHandler = @MainActor (
        [String: String],
        Bool
    ) async -> AppRemoteNotificationFetchResult

    static let shared = AppExternalEventHub()

    private var deepLinkHandler: DeepLinkHandler?
    private var remoteDataHandler: RemoteDataHandler?
    private var pendingURLs: [URL] = []
    private var pendingRemoteData: [([String: String], Bool)] = []

    func bind(
        deepLinks: @escaping DeepLinkHandler,
        remoteData: @escaping RemoteDataHandler
    ) async {
        deepLinkHandler = deepLinks
        remoteDataHandler = remoteData

        let urls = pendingURLs
        let payloads = pendingRemoteData
        pendingURLs.removeAll()
        pendingRemoteData.removeAll()
        for url in urls { await deepLinks(url) }
        for (data, hasNotificationPayload) in payloads {
            _ = await remoteData(data, hasNotificationPayload)
        }
    }

    func unbind() {
        deepLinkHandler = nil
        remoteDataHandler = nil
    }

    func receive(_ url: URL) async {
        guard let deepLinkHandler else {
            pendingURLs.append(url)
            return
        }
        await deepLinkHandler(url)
    }

    func receiveRemoteData(
        _ data: [String: String],
        hasNotificationPayload: Bool
    ) async -> AppRemoteNotificationFetchResult {
        guard let remoteDataHandler else {
            pendingRemoteData.append((data, hasNotificationPayload))
            return .noData
        }
        return await remoteDataHandler(data, hasNotificationPayload)
    }
}

enum AppLaunchConfiguration: Equatable, Sendable {
    case production
    case authenticatedUITest(UserDTO)

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        now: Date = Date()
    ) -> AppLaunchConfiguration {
#if DEBUG
        guard arguments.contains("-ui-testing-authenticated") else { return .production }
        return .authenticatedUITest(
            UserDTO(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                email: "ui-test@rocketflow.local",
                displayName: "UI Test",
                timezone: "Europe/Moscow",
                language: .ru,
                createdAt: now
            )
        )
#else
        _ = arguments
        _ = now
        return .production
#endif
    }

    var launchUser: UserDTO? {
        if case let .authenticatedUITest(user) = self { return user }
        return nil
    }

    var isAuthenticatedUITest: Bool {
        if case .authenticatedUITest = self { return true }
        return false
    }
}
