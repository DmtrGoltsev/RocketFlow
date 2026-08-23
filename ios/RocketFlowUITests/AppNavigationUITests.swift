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
        XCTAssertTrue(app.otherElements["planner.screen"].waitForExistence(timeout: 5))
        let settingsButton = app.buttons["Настройки"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()
        XCTAssertTrue(app.otherElements["settings.screen"].waitForExistence(timeout: 5))
    }
}
