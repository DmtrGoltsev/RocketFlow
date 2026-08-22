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
}
