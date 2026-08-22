import Combine
import Foundation
import GRDB

@MainActor
final class DependencyContainer: ObservableObject {
    static let apiBaseURLInfoKey = "RocketFlowAPIBaseURL"

    let apiBaseURL: URL
    let databaseQueue: DatabaseQueue?

    init(
        apiBaseURL: URL? = nil,
        databasePath: String = ":memory:"
    ) {
        let configuredValue = Bundle.main.object(forInfoDictionaryKey: Self.apiBaseURLInfoKey) as? String
        self.apiBaseURL = apiBaseURL ?? Self.configuredAPIBaseURL(from: configuredValue)
        databaseQueue = try? DatabaseQueue(path: databasePath)
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
