import Combine
import Foundation
import GRDB

@MainActor
final class DependencyContainer: ObservableObject {
    static let apiBaseURLInfoKey = "RocketFlowAPIBaseURL"

    let apiBaseURL: URL
    let databaseQueue: DatabaseQueue?
    let apiClient: APIClient
    let sessionStore: any SessionStore
    let authService: AuthService
    let authSession: AuthSession

    init(
        apiBaseURL: URL? = nil,
        databasePath: String = ":memory:",
        transport: (any HTTPTransport)? = nil,
        sessionStore: (any SessionStore)? = nil
    ) {
        let configuredValue = Bundle.main.object(forInfoDictionaryKey: Self.apiBaseURLInfoKey) as? String
        let resolvedURL = apiBaseURL ?? Self.configuredAPIBaseURL(from: configuredValue)
        let resolvedStore = sessionStore ?? KeychainSessionStore()
        let client = APIClient(
            baseURL: resolvedURL,
            transport: transport ?? URLSessionTransport()
        )
        let service = AuthService(client: client)

        self.apiBaseURL = resolvedURL
        databaseQueue = try? DatabaseQueue(path: databasePath)
        apiClient = client
        self.sessionStore = resolvedStore
        authService = service
        authSession = AuthSession(service: service, store: resolvedStore)
    }

    nonisolated static func configuredAPIBaseURL(from value: String?) -> URL {
        guard
            let value,
            let url = URL(string: value),
            let scheme = url.scheme,
            ["http", "https"].contains(scheme.lowercased()),
            url.host != nil
        else {
            return URL(string: "http://45.10.110.42/rocket-api")!
        }

        return url
    }
}
