import XCTest
@testable import RocketFlow

final class AppIntegrationNavigationTests: XCTestCase {
    private let folderID = UUID(uuidString: "10000000-0000-0000-0000-000000000010")!
    private let goalID = UUID(uuidString: "10000000-0000-0000-0000-000000000020")!
    private let taskID = UUID(uuidString: "10000000-0000-0000-0000-000000000030")!

    func testAuthenticatedTabsAreExactlyPlannerCalendarFocus() {
        XCTAssertEqual(AppTab.allCases, [.planner, .calendar, .focus])
    }

    func testCalendarTaskKeepsCalendarOrigin() {
        var state = AppNavigationState()
        state.open(
            DetailEntityReference(kind: .task, id: taskID),
            origin: .calendar
        )

        XCTAssertEqual(state.selectedTab, .calendar)
        XCTAssertEqual(
            state.calendarPath,
            [.detail(DetailEntityReference(kind: .task, id: taskID), origin: .calendar)]
        )
        XCTAssertTrue(state.plannerPath.isEmpty)
    }

    func testFocusTaskKeepsFocusOrigin() {
        var state = AppNavigationState()
        state.open(
            DetailEntityReference(kind: .task, id: taskID),
            origin: .focus
        )
        XCTAssertEqual(state.selectedTab, .focus)
        XCTAssertEqual(state.focusPath.count, 1)
    }

    func testTaskCreateReturnsToSameGoalDetail() {
        var state = AppNavigationState()
        state.open(DetailEntityReference(kind: .goal, id: goalID), origin: .home)
        state.present(
            .editor(
                .create(
                    kind: .task,
                    parent: DetailEntityReference(kind: .goal, id: goalID),
                    afterSave: .goalDetail(goalID)
                ),
                origin: .home
            )
        )

        state.handle(.taskCreated(taskID: taskID, returnToGoalID: goalID, origin: .home))

        XCTAssertNil(state.presentation)
        XCTAssertEqual(
            state.plannerPath,
            [.detail(DetailEntityReference(kind: .goal, id: goalID), origin: .home)]
        )
    }

    func testDeleteReturnsToParentFolder() {
        var state = AppNavigationState()
        state.open(DetailEntityReference(kind: .folder, id: folderID), origin: .home)
        state.open(DetailEntityReference(kind: .goal, id: goalID), origin: .home)

        state.handle(.deleted(.folder(folderID, origin: .home)))

        XCTAssertEqual(
            state.plannerPath,
            [.detail(DetailEntityReference(kind: .folder, id: folderID), origin: .home)]
        )
    }

    func testDeepLinkUsesResolvedLocalTaskAndRequestedOrigin() {
        let serverID = UUID(uuidString: "10000000-0000-0000-0000-000000000099")!
        var state = AppNavigationState()
        state.applyDeepLink(
            DeepLinkResolution(
                destination: .task(taskID: serverID, origin: .focus),
                errorMessage: nil
            ),
            localTaskID: taskID
        )

        XCTAssertEqual(state.selectedTab, .focus)
        XCTAssertEqual(
            state.focusPath,
            [.detail(DetailEntityReference(kind: .task, id: taskID), origin: .focus)]
        )
    }

    func testFocusDeepLinkClearsStaleFocusPathAndPresentation() {
        var state = AppNavigationState()
        state.open(DetailEntityReference(kind: .task, id: taskID), origin: .focus)
        state.present(.focusCadence)

        state.applyDeepLink(
            DeepLinkResolution(destination: .focus, errorMessage: nil),
            localTaskID: nil
        )

        XCTAssertEqual(state.selectedTab, .focus)
        XCTAssertTrue(state.focusPath.isEmpty)
        XCTAssertNil(state.presentation)
    }

    func testPlannerFallbackDeepLinkClearsStalePlannerPath() {
        var state = AppNavigationState()
        state.open(DetailEntityReference(kind: .goal, id: goalID), origin: .home)

        state.applyDeepLink(
            DeepLinkResolution(destination: .planner, errorMessage: "Unavailable"),
            localTaskID: nil
        )

        XCTAssertEqual(state.selectedTab, .planner)
        XCTAssertTrue(state.plannerPath.isEmpty)
        XCTAssertEqual(state.notice, "Unavailable")
    }

    func testAccountTransitionClearsEveryRoute() {
        var state = AppNavigationState()
        state.openSettings()
        state.select(.focus)
        state.present(.focusCadence)

        state.resetForAccountTransition()

        XCTAssertEqual(state, AppNavigationState())
    }

    func testRestorationMutationHandlerReceivesDeepLinkAndPathChanges() {
        let recorder = AppNavigationMutationRecorder()
        let serverID = UUID(uuidString: "10000000-0000-0000-0000-000000000099")!
        var state = AppNavigationState()
        state.installRestorationMutationHandler { recorder.capture($0) }

        state.setPath(
            [.detail(DetailEntityReference(kind: .goal, id: goalID), origin: .home)],
            for: .planner
        )
        state.applyDeepLink(
            DeepLinkResolution(
                destination: .task(taskID: serverID, origin: .calendar),
                errorMessage: nil
            ),
            localTaskID: taskID
        )

        let mutations = recorder.values()
        XCTAssertEqual(mutations.count, 2)
        XCTAssertEqual(mutations.last?.selectedTab, .calendar)
        XCTAssertEqual(
            mutations.last?.calendarPath,
            [.detail(DetailEntityReference(kind: .task, id: taskID), origin: .calendar)]
        )
    }

    func testAuthenticatedLaunchArgumentDoesNotChangeDefaultLaunch() {
        XCTAssertEqual(AppLaunchConfiguration.current(arguments: []), .production)
        XCTAssertNotNil(
            AppLaunchConfiguration.current(arguments: ["app", "-ui-testing-authenticated"]).launchUser
        )
    }

    @MainActor
    func testNotificationTapCompletesBeforeAsyncNavigationFinishes() async {
        let url = URL(string: "rocketflow://focus")!
        let navigationStarted = expectation(description: "navigation started")
        let navigationFinished = expectation(description: "navigation finished")
        let gate = AppIntegrationAsyncGate()
        var completionCalled = false

        RocketFlowAppDelegate.handOffNotificationTap(
            url,
            navigate: { receivedURL in
                XCTAssertEqual(receivedURL, url)
                navigationStarted.fulfill()
                await gate.wait()
                navigationFinished.fulfill()
            },
            completionHandler: { completionCalled = true }
        )

        XCTAssertTrue(completionCalled)
        await fulfillment(of: [navigationStarted], timeout: 1)
        await gate.release()
        await fulfillment(of: [navigationFinished], timeout: 1)
    }
}

private final class AppNavigationMutationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [AppNavigationState] = []

    func capture(_ state: AppNavigationState) {
        lock.lock()
        states.append(state)
        lock.unlock()
    }

    func values() -> [AppNavigationState] {
        lock.lock()
        defer { lock.unlock() }
        return states
    }
}

private actor AppIntegrationAsyncGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
