import Foundation
import XCTest
@testable import RocketFlow

final class BackgroundRefreshTests: XCTestCase {
    func testScheduleUsesRegisteredIdentifierAndAtLeastFifteenMinuteDelay() async throws {
        let now = Date(timeIntervalSince1970: 1_787_001_200)
        let scheduler = BackgroundSchedulerSpy()
        let coordinator = BackgroundRefreshCoordinator(
            scheduler: scheduler,
            sync: ImmediateCoreSyncHook(),
            now: { now },
            minimumDelay: 60
        )

        try await coordinator.scheduleNext()

        let requests = await scheduler.requests()
        let cancellations = await scheduler.cancellations()
        XCTAssertEqual(requests.single?.identifier, BackgroundRefreshCoordinator.defaultIdentifier)
        XCTAssertEqual(requests.single?.earliestBeginDate, now.addingTimeInterval(15 * 60))
        XCTAssertEqual(cancellations, [BackgroundRefreshCoordinator.defaultIdentifier])
    }

    func testSuccessfulRefreshCompletesAndReschedules() async {
        let scheduler = BackgroundSchedulerSpy()
        let hook = ImmediateCoreSyncHook()
        let handle = BackgroundTaskHandleSpy()
        let coordinator = BackgroundRefreshCoordinator(scheduler: scheduler, sync: hook)

        await coordinator.handle(handle)

        XCTAssertEqual(handle.completions(), [true])
        let triggers = await hook.triggers()
        let requestCount = await scheduler.requests().count
        XCTAssertEqual(triggers, [.backgroundRefresh])
        XCTAssertEqual(requestCount, 1)
    }

    func testExpirationCancelsSyncCompletesFailureAndReschedules() async {
        let scheduler = BackgroundSchedulerSpy()
        let hook = BlockingCoreSyncHook()
        let handle = BackgroundTaskHandleSpy()
        let coordinator = BackgroundRefreshCoordinator(scheduler: scheduler, sync: hook)
        let run = Task { await coordinator.handle(handle) }
        let started = await hook.waitUntilStarted()
        XCTAssertTrue(started)

        handle.expire()
        await run.value

        XCTAssertEqual(handle.completions(), [false])
        let cancelled = await hook.wasCancelled()
        let requestCount = await scheduler.requests().count
        XCTAssertTrue(cancelled)
        XCTAssertEqual(requestCount, 1)
    }

    func testForegroundAndNetworkTransitionsInvokeSharedSyncHook() async {
        let hook = ImmediateCoreSyncHook()
        let coordinator = ApplicationSyncTriggerCoordinator(sync: hook)
        let monitor = ManualNetworkMonitor(connected: false)
        await coordinator.startNetworkObservation(monitor)
        await coordinator.foreground()
        await monitor.setConnected(true)
        let networkObserved = await waitUntil {
            await hook.triggers().contains(.networkAvailable)
        }
        XCTAssertTrue(networkObserved)

        await coordinator.stopNetworkObservation()

        let triggers = await hook.triggers()
        XCTAssertTrue(triggers.contains(.foreground))
        XCTAssertTrue(triggers.contains(.networkAvailable))
    }

    func testRescheduleFailureIsSurfacedThroughCompletionAndReturnValue() async {
        let scheduler = BackgroundSchedulerSpy(submitFailures: 1)
        let handle = BackgroundTaskHandleSpy()
        let coordinator = BackgroundRefreshCoordinator(
            scheduler: scheduler,
            sync: ImmediateCoreSyncHook()
        )

        let result = await coordinator.handle(handle)

        XCTAssertFalse(result)
        XCTAssertEqual(handle.completions(), [false])
        let cancellations = await scheduler.cancellations()
        XCTAssertEqual(cancellations, [BackgroundRefreshCoordinator.defaultIdentifier])
    }

    func testLateExpirationAfterCompletionCannotCancelOrCompleteTwice() async {
        let scheduler = BackgroundSchedulerSpy()
        let hook = ImmediateCoreSyncHook()
        let handle = BackgroundTaskHandleSpy()
        let coordinator = BackgroundRefreshCoordinator(scheduler: scheduler, sync: hook)

        let result = await coordinator.handle(handle)
        handle.expire()

        XCTAssertTrue(result)
        XCTAssertEqual(handle.completions(), [true])
        let triggers = await hook.triggers()
        XCTAssertEqual(triggers, [.backgroundRefresh])
    }

    private func waitUntil(
        _ predicate: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<500 {
            if await predicate() { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }
}

private actor BackgroundSchedulerSpy: BackgroundRefreshScheduling {
    struct Request: Equatable, Sendable {
        let identifier: String
        let earliestBeginDate: Date
    }

    private var values: [Request] = []
    private var cancelled: [String] = []
    private var submitFailures: Int

    init(submitFailures: Int = 0) {
        self.submitFailures = submitFailures
    }

    func submit(identifier: String, earliestBeginDate: Date) throws {
        if submitFailures > 0 {
            submitFailures -= 1
            throw BackgroundRefreshTestError.submitFailed
        }
        values.append(Request(identifier: identifier, earliestBeginDate: earliestBeginDate))
    }

    func cancel(identifier: String) { cancelled.append(identifier) }
    func requests() -> [Request] { values }
    func cancellations() -> [String] { cancelled }
}

private actor ImmediateCoreSyncHook: CoreSyncHook {
    private var values: [CoreSyncTrigger] = []

    func synchronize(trigger: CoreSyncTrigger) {
        values.append(trigger)
    }

    func triggers() -> [CoreSyncTrigger] { values }
}

private actor BlockingCoreSyncHook: CoreSyncHook {
    private var started = false
    private var cancelled = false

    func synchronize(trigger: CoreSyncTrigger) async throws {
        started = true
        do {
            while true {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        } catch is CancellationError {
            cancelled = true
            throw CancellationError()
        }
    }

    func waitUntilStarted() async -> Bool {
        for _ in 0..<500 {
            if started { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    func wasCancelled() -> Bool { cancelled }
}

private final class BackgroundTaskHandleSpy: BackgroundRefreshTaskHandling, @unchecked Sendable {
    private let lock = NSLock()
    private var expiration: (@Sendable () -> Void)?
    private var values: [Bool] = []

    func setExpirationHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        expiration = handler
        lock.unlock()
    }

    func complete(success: Bool) {
        lock.lock()
        values.append(success)
        lock.unlock()
    }

    func expire() {
        lock.lock()
        let handler = expiration
        lock.unlock()
        handler?()
    }

    func completions() -> [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private enum BackgroundRefreshTestError: Error {
    case submitFailed
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
