import Foundation
import XCTest
@testable import RocketFlow

@MainActor
final class DependencyContainerTests: XCTestCase {
    func testUsesInjectedAPIBaseURL() {
        let expectedURL = URL(string: "https://example.test/rocket-api")!

        let container = DependencyContainer(apiBaseURL: expectedURL)

        XCTAssertEqual(container.apiBaseURL, expectedURL)
        XCTAssertNotNil(container.databaseQueue)
    }

    func testConfiguredAPIBaseURLAcceptsProductionHTTPURL() {
        let url = DependencyContainer.configuredAPIBaseURL(
            from: "http://45.10.110.42/rocket-api"
        )

        XCTAssertEqual(url.absoluteString, "http://45.10.110.42/rocket-api")
    }

    func testConfiguredAPIBaseURLFallsBackForInvalidValue() {
        let url = DependencyContainer.configuredAPIBaseURL(from: "not a URL")

        XCTAssertEqual(url.absoluteString, "http://45.10.110.42/rocket-api")
    }
}
