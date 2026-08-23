import XCTest

final class AppNavigationUITests: XCTestCase {
    func testAuthenticatedTabsAndSettingsNavigation() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing-authenticated")
        app.launch()

        XCTAssertTrue(app.otherElements["app.authenticated"].waitForExistence(timeout: 8))
        let plannerTab = app.buttons["tab.planner"]
        let calendarTab = app.buttons["tab.calendar"]
        let focusTab = app.buttons["tab.focus"]
        XCTAssertTrue(plannerTab.waitForExistence(timeout: 3))
        XCTAssertTrue(calendarTab.exists)
        XCTAssertTrue(focusTab.exists)

        calendarTab.tap()
        XCTAssertTrue(app.scrollViews["calendar.screen"].waitForExistence(timeout: 5))

        focusTab.tap()
        XCTAssertTrue(app.scrollViews["focus.screen"].waitForExistence(timeout: 5))

        plannerTab.tap()
        let plannerScreen = app.descendants(matching: .any)["planner.screen"]
        XCTAssertTrue(plannerScreen.waitForExistence(timeout: 5))
        let settingsButton = app.buttons["planner.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()
        let settingsScreen = app.descendants(matching: .any)["settings.screen"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
    }
}
