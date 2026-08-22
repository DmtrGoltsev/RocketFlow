import XCTest

final class RocketFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAuthScreenLaunches() {
        let app = XCUIApplication()
        app.launch()

        let authScreen = app.scrollViews["auth.screen"]
        XCTAssertTrue(authScreen.waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields["auth.email"].exists)
        XCTAssertTrue(app.secureTextFields["auth.password"].exists)
        XCTAssertTrue(app.buttons["auth.submit"].exists)
    }
}
