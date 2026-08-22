import Combine
import Foundation
import GRDB

@MainActor
final class DependencyContainer: ObservableObject {
    static let apiBaseURLInfoKey = "RocketFlowAPIBaseURL"
    static let fallbackAPIBaseURL = URL(string: "http://45.10.110.42/rocket-api")!

    let apiBaseURL: URL
    let databaseQueue: DatabaseQueue?

    init(
        apiBaseURL: URL = DependencyContainer.configuredAPIBaseURL(),
        databasePath: String = ":memory:"
    ) {
        self.apiBaseURL = apiBaseURL
        databaseQueue = try? DatabaseQueue(path: databasePath)
    }

    private static func configuredAPIBaseURL(bundle: Bundle = .main) -> URL {
        guard
            let value = bundle.object(forInfoDictionaryKey: apiBaseURLInfoKey) as? String,
            let url = URL(string: value),
            let scheme = url.scheme,
            ["http", "https"].contains(scheme.lowercased()),
            url.host != nil
        else {
            return fallbackAPIBaseURL
        }

        return url
    }
}
