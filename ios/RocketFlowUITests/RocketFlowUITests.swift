import XCTest

final class RocketFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBootstrapScreenLaunches() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["home.ready"].waitForExistence(timeout: 10))
    }
}

