import Foundation
import XCTest
@testable import RocketFlow

private actor EngineTestRepository: SyncRepository {
    private var pending: [PendingMutation]
    private var conflictTotal = 0
    private var pullRequired: Bool
    private var ready = true
    private(set) var acknowledged = 0
    private(set) var retries = 0
    private(set) var returned = 0
    private(set) var applied = 0
    private(set) var completedRequiredPull = 0

    init(pending: [PendingMutation] = [], pullRequired: Bool = false) {
        self.pending = pending
        self.pullRequired = pullRequired
    }

    func pendingCount() -> Int { pending.count }
    func conflictCount() -> Int { conflictTotal }

    func nextReadyMutation(at date: Date) -> PendingMutation? {
        ready ? pending.first : nil
    }

    func returnToQueue(_ mutation: PendingMutation, errorCode: String?, at date: Date) {
        returned += 1
    }

    func acknowledge(_ mutation: PendingMutation, ack: RemoteMutationAck, at date: Date) {
        acknowledged += 1
        pending.removeAll { $0.id == mutation.id }
    }

    func scheduleRetry(
        _ mutation: PendingMutation,
        at nextRetryAt: Date,
        errorCode: String,
        updatedAt: Date
    ) {
        retries += 1
        ready = false
    }

    func recordConflict(
        _ mutation: PendingMutation,
        code: String,
        serverVersion: Int64?,
        serverPayloadJSON: Data?,
        serverDeleted: Bool,
        at date: Date
    ) {
        conflictTotal += 1
        ready = false
    }

    func applyRemote(_ snapshot: RemotePlanningSnapshot) { applied += 1 }
    func conflicts() -> [SyncConflict] { [] }
    func resolve(_ conflictID: UUID, with resolution: ConflictResolution, at date: Date) {}
    func pullBeforePushRequired() -> Bool { pullRequired }

    func didCompleteRequiredPull(_ snapshot: RemotePlanningSnapshot, at date: Date) {
        pullRequired = false
        completedRequiredPull += 1
    }
}

private actor EngineTestRemote: SyncRemote {
    private let pushFailure: SyncRemoteFailure?
    private let pullFailure: SyncRemoteFailure?
    private let pullDelayNanoseconds: UInt64
    private(set) var events: [String] = []
    private var pullStarted = false
    private var pullStartWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        pushFailure: SyncRemoteFailure? = nil,
        pullFailure: SyncRemoteFailure? = nil,
        pullDelayNanoseconds: UInt64 = 0
    ) {
        self.pushFailure = pushFailure
        self.pullFailure = pullFailure
        self.pullDelayNanoseconds = pullDelayNanoseconds
    }

    func push(_ mutation: PendingMutation) async throws -> RemoteMutationAck {
        events.append("push")
        if let pushFailure { throw pushFailure }
        return RemoteMutationAck(remoteID: UUID(), version: 1, serverPayloadJSON: nil)
    }

    func pull() async throws -> RemotePlanningSnapshot {
        events.append("pull")
        pullStarted = true
        let waiters = pullStartWaiters
        pullStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if pullDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: pullDelayNanoseconds)
        }
        if let pullFailure { throw pullFailure }
        return RemotePlanningSnapshot()
    }

    func waitUntilPullStarted() async {
        guard !pullStarted else { return }
        await withCheckedContinuation { continuation in
            pullStartWaiters.append(continuation)
        }
    }
}

private actor EngineTestNetwork: NetworkMonitoring {
    let connected: Bool
    init(_ connected: Bool) { self.connected = connected }
    func isConnected() -> Bool { connected }

    func changes() async -> AsyncStream<Bool> {
        let initial = connected
        return AsyncStream { continuation in
            continuation.yield(initial)
            continuation.finish()
        }
    }
}

private struct EngineTestClock: SyncClock {
    let value = Date(timeIntervalSince1970: 1_700_000_000)
    func now() -> Date { value }
}

private struct EngineTestRandom: SyncRandom {
    func unitInterval() -> Double { 0.5 }
}

final class SyncEngineTests: XCTestCase {
    func testSuccessfulPushAcknowledgesThenPulls() async {
        let repository = EngineTestRepository(pending: [mutation()])
        let remote = EngineTestRemote()
        let engine = makeEngine(repository: repository, remote: remote)

        let status = await engine.syncManually()

        let acknowledged = await repository.acknowledged
        let events = await remote.events
        XCTAssertEqual(status.phase, .idle)
        XCTAssertEqual(acknowledged, 1)
        XCTAssertEqual(events, ["push", "pull"])
    }

    func testConcurrentSyncCallsShareSingleFlight() async {
        let repository = EngineTestRepository()
        let remote = EngineTestRemote(pullDelayNanoseconds: 100_000_000)
        let engine = makeEngine(repository: repository, remote: remote)

        async let first = engine.syncManually()
        async let second = engine.syncOnForeground()
        _ = await (first, second)

        let events = await remote.events
        XCTAssertEqual(events, ["pull"])
    }

    func testPullBeforePushIsHonoredAndCleared() async {
        let repository = EngineTestRepository(pending: [mutation()], pullRequired: true)
        let remote = EngineTestRemote()
        let engine = makeEngine(repository: repository, remote: remote)

        let status = await engine.syncManually()

        let events = await remote.events
        let completed = await repository.completedRequiredPull
        XCTAssertEqual(status.phase, .idle)
        XCTAssertEqual(events, ["pull", "push", "pull"])
        XCTAssertEqual(completed, 1)
    }

    func testUnauthorizedStopsAndReturnsMutationToQueue() async {
        let repository = EngineTestRepository(pending: [mutation()])
        let remote = EngineTestRemote(pushFailure: .unauthorized)
        let engine = makeEngine(repository: repository, remote: remote)

        let status = await engine.syncManually()

        let returned = await repository.returned
        XCTAssertEqual(status.phase, .unauthorized)
        XCTAssertEqual(status.lastErrorCode, "unauthorized")
        XCTAssertEqual(returned, 1)
    }

    func testTransientFailureSchedulesRetry() async {
        let repository = EngineTestRepository(pending: [mutation()])
        let remote = EngineTestRemote(pushFailure: .transient(code: "offline"))
        let engine = makeEngine(repository: repository, remote: remote)

        let status = await engine.syncManually()

        let retries = await repository.retries
        XCTAssertEqual(status.phase, .waitingForRetry)
        XCTAssertEqual(retries, 1)
    }

    func testRetryExhaustionCreatesConflict() async {
        let repository = EngineTestRepository(pending: [mutation(attemptCount: 0)])
        let remote = EngineTestRemote(pushFailure: .transient(code: "offline"))
        let engine = makeEngine(
            repository: repository,
            remote: remote,
            policy: SyncPolicy(maxAttempts: 1)
        )

        let status = await engine.syncManually()

        let conflicts = await repository.conflictCount()
        XCTAssertEqual(status.phase, .conflicted)
        XCTAssertEqual(conflicts, 1)
    }

    func testServerConflictIsPersisted() async {
        let repository = EngineTestRepository(pending: [mutation()])
        let remote = EngineTestRemote(
            pushFailure: .conflict(
                code: "version",
                serverVersion: 9,
                serverPayloadJSON: Data(),
                serverDeleted: false
            )
        )
        let engine = makeEngine(repository: repository, remote: remote)

        let status = await engine.syncManually()

        let conflicts = await repository.conflictCount()
        XCTAssertEqual(status.phase, .conflicted)
        XCTAssertEqual(conflicts, 1)
    }

    func testNoNetworkDoesNotCallRemote() async {
        let repository = EngineTestRepository(pending: [mutation()])
        let remote = EngineTestRemote()
        let engine = makeEngine(repository: repository, remote: remote, connected: false)

        let status = await engine.syncManually()

        let events = await remote.events
        XCTAssertEqual(status.phase, .waitingForNetwork)
        XCTAssertTrue(events.isEmpty)
    }

    func testCancellationReturnsCancelledStatus() async {
        let repository = EngineTestRepository()
        let remote = EngineTestRemote(pullDelayNanoseconds: 5_000_000_000)
        let engine = makeEngine(repository: repository, remote: remote)
        let task = Task { await engine.syncManually() }
        await remote.waitUntilPullStarted()

        await engine.cancel()
        let status = await task.value

        XCTAssertEqual(status.phase, .cancelled)
    }

    func testPullUnauthorizedReturnsUnauthorizedStatus() async {
        let repository = EngineTestRepository()
        let remote = EngineTestRemote(pullFailure: .unauthorized)
        let engine = makeEngine(repository: repository, remote: remote)

        let status = await engine.syncManually()

        XCTAssertEqual(status.phase, .unauthorized)
    }

    private func makeEngine(
        repository: EngineTestRepository,
        remote: EngineTestRemote,
        connected: Bool = true,
        policy: SyncPolicy = SyncPolicy()
    ) -> SyncEngine {
        SyncEngine(
            repository: repository,
            remote: remote,
            network: EngineTestNetwork(connected),
            clock: EngineTestClock(),
            random: EngineTestRandom(),
            policy: policy
        )
    }

    private func mutation(attemptCount: Int = 0) -> PendingMutation {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return PendingMutation(
            id: UUID(),
            entityType: .folder,
            entityID: UUID(),
            operation: .update,
            payloadJSON: Data("{}".utf8),
            baseVersion: 1,
            attemptCount: attemptCount,
            nextRetryAt: nil,
            lastErrorCode: nil,
            state: .inFlight,
            dependencies: [],
            createdAt: now,
            updatedAt: now
        )
    }
}
