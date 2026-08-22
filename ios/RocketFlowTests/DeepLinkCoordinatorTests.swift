import Foundation
import XCTest
@testable import RocketFlow

final class DeepLinkCoordinatorTests: XCTestCase {
    func testParserAcceptsOnlyExactTaskAndFocusURLs() {
        let taskID = UUID()
        XCTAssertEqual(
            DeepLinkParser.parse(
                URL(string: "rocketflow://task/\(taskID.uuidString)")!,
                origin: .calendar
            ),
            .task(taskID: taskID, origin: .calendar)
        )
        XCTAssertEqual(
            DeepLinkParser.parse(URL(string: "rocketflow://focus")!),
            .focus
        )
        for invalid in [
            "https://task/\(taskID.uuidString)",
            "rocketflow://task/not-a-uuid",
            "rocketflow://task/\(taskID.uuidString)/extra",
            "rocketflow://focus/extra",
            "rocketflow://focus?source=push"
        ] {
            XCTAssertNil(DeepLinkParser.parse(URL(string: invalid)!))
        }
    }

    func testWarmTaskLinkPreservesOriginAndResolvesImmediately() async {
        let taskID = UUID()
        let coordinator = DeepLinkCoordinator(
            accessChecker: DeepLinkAccessStub(values: [taskID: .accessible])
        )

        let result = await coordinator.receive(
            URL(string: "rocketflow://task/\(taskID.uuidString)")!,
            authenticated: true,
            origin: .focus,
            language: .en
        )

        XCTAssertEqual(
            result,
            .resolved(DeepLinkResolution(
                destination: .task(taskID: taskID, origin: .focus),
                errorMessage: nil
            ))
        )
    }

    func testColdLinkWaitsForAuthAndIsConsumedExactlyOnce() async {
        let taskID = UUID()
        let coordinator = DeepLinkCoordinator(
            accessChecker: DeepLinkAccessStub(values: [taskID: .accessible])
        )

        let received = await coordinator.receive(
            URL(string: "rocketflow://task/\(taskID.uuidString)")!,
            authenticated: false,
            origin: .planner,
            language: .en
        )
        XCTAssertEqual(received, .waitingForAuthentication)
        let resolution = await coordinator.authenticationDidSucceed(language: .en)
        XCTAssertEqual(
            resolution,
            DeepLinkResolution(
                destination: .task(taskID: taskID, origin: .planner),
                errorMessage: nil
            )
        )
        let secondResolution = await coordinator.authenticationDidSucceed(language: .en)
        XCTAssertNil(secondResolution)
    }

    func testWarmFocusLinkRoutesToFocusWithoutTaskLookup() async {
        let checker = DeepLinkAccessStub(values: [:])
        let coordinator = DeepLinkCoordinator(accessChecker: checker)

        let result = await coordinator.receive(
            URL(string: "rocketflow://focus")!,
            authenticated: true,
            language: .ru
        )

        XCTAssertEqual(
            result,
            .resolved(DeepLinkResolution(destination: .focus, errorMessage: nil))
        )
        let callCount = await checker.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testInaccessibleAndMissingTasksFallBackToPlannerWithLocalizedError() async {
        let inaccessible = UUID()
        let missing = UUID()
        let coordinator = DeepLinkCoordinator(
            accessChecker: DeepLinkAccessStub(values: [
                inaccessible: .inaccessible,
                missing: .missing
            ])
        )

        let denied = await coordinator.receive(
            URL(string: "rocketflow://task/\(inaccessible.uuidString)")!,
            authenticated: true,
            origin: .calendar,
            language: .ru
        )
        let gone = await coordinator.receive(
            URL(string: "rocketflow://task/\(missing.uuidString)")!,
            authenticated: true,
            origin: .focus,
            language: .en
        )

        XCTAssertEqual(denied.resolution?.destination, .planner)
        XCTAssertEqual(denied.resolution?.errorMessage, "У вас нет доступа к этой задаче")
        XCTAssertEqual(gone.resolution?.destination, .planner)
        XCTAssertEqual(gone.resolution?.errorMessage, "This task no longer exists")
    }

    func testFailedAuthenticationClearsColdLink() async {
        let taskID = UUID()
        let coordinator = DeepLinkCoordinator(
            accessChecker: DeepLinkAccessStub(values: [taskID: .accessible])
        )
        _ = await coordinator.receive(
            URL(string: "rocketflow://task/\(taskID.uuidString)")!,
            authenticated: false,
            language: .en
        )

        await coordinator.authenticationDidFail()

        let resolution = await coordinator.authenticationDidSucceed(language: .en)
        XCTAssertNil(resolution)
    }

    func testUnauthorizedAccessPreservesColdIntentForReauthThenConsumesOnce() async {
        let taskID = UUID()
        let access = SequencedDeepLinkAccessStub(outcomes: [
            .failure(APIError(
                statusCode: 401,
                code: "unauthorized",
                message: "unauthorized",
                details: [],
                traceID: nil,
                requestID: UUID()
            )),
            .success(.accessible)
        ])
        let unauthorized = DeepLinkUnauthorizedHandlerSpy()
        let coordinator = DeepLinkCoordinator(
            accessChecker: access,
            unauthorizedHandler: unauthorized
        )
        let url = URL(string: "rocketflow://task/\(taskID.uuidString)")!

        let received = await coordinator.receive(url, authenticated: false, language: .en)
        let firstAuth = await coordinator.authenticationDidSucceed(language: .en)
        let unauthorizedCount = await unauthorized.count()
        let secondAuth = await coordinator.authenticationDidSucceed(language: .en)
        let thirdAuth = await coordinator.authenticationDidSucceed(language: .en)

        XCTAssertEqual(received, .waitingForAuthentication)
        XCTAssertNil(firstAuth)
        XCTAssertEqual(unauthorizedCount, 1)
        XCTAssertEqual(
            secondAuth,
            DeepLinkResolution(
                destination: .task(taskID: taskID, origin: .planner),
                errorMessage: nil
            )
        )
        XCTAssertNil(thirdAuth)
    }

    func testWarmUnauthorizedEmitsResultAndRetainsIntent() async {
        let taskID = UUID()
        let access = SequencedDeepLinkAccessStub(outcomes: [
            .failure(APIError(
                statusCode: 401,
                code: "unauthorized",
                message: "unauthorized",
                details: [],
                traceID: nil,
                requestID: UUID()
            )),
            .success(.accessible)
        ])
        let unauthorized = DeepLinkUnauthorizedHandlerSpy()
        let coordinator = DeepLinkCoordinator(
            accessChecker: access,
            unauthorizedHandler: unauthorized
        )

        let result = await coordinator.receive(
            URL(string: "rocketflow://task/\(taskID.uuidString)")!,
            authenticated: true,
            origin: .calendar,
            language: .ru
        )
        let retried = await coordinator.authenticationDidSucceed(language: .ru)
        let unauthorizedCount = await unauthorized.count()

        XCTAssertEqual(result, .unauthorized)
        XCTAssertEqual(retried?.destination, .task(taskID: taskID, origin: .calendar))
        XCTAssertEqual(unauthorizedCount, 1)
    }
}

private actor DeepLinkAccessStub: TaskDeepLinkAccessChecking {
    private let values: [UUID: TaskDeepLinkAccess]
    private var calls = 0

    init(values: [UUID: TaskDeepLinkAccess]) { self.values = values }

    func access(taskID: UUID) -> TaskDeepLinkAccess {
        calls += 1
        return values[taskID] ?? .missing
    }

    func callCount() -> Int { calls }
}

private actor SequencedDeepLinkAccessStub: TaskDeepLinkAccessChecking {
    private var outcomes: [Result<TaskDeepLinkAccess, APIError>]

    init(outcomes: [Result<TaskDeepLinkAccess, APIError>]) {
        self.outcomes = outcomes
    }

    func access(taskID: UUID) throws -> TaskDeepLinkAccess {
        guard !outcomes.isEmpty else { return .missing }
        return try outcomes.removeFirst().get()
    }
}

private actor DeepLinkUnauthorizedHandlerSpy: DeepLinkUnauthorizedHandling {
    private var value = 0
    func handleDeepLinkUnauthorized() { value += 1 }
    func count() -> Int { value }
}

private extension DeepLinkReceiveResult {
    var resolution: DeepLinkResolution? {
        if case let .resolved(value) = self { return value }
        return nil
    }
}
