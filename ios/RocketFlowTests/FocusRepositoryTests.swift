import Foundation
import XCTest
@testable import RocketFlow

private enum FocusTestFailure: Error, Sendable {
    case offline
    case missingStub
}

private enum FocusOutcome<Value: Sendable>: Sendable {
    case value(Value)
    case api(APIError)
    case offline

    func get() throws -> Value {
        switch self {
        case let .value(value): return value
        case let .api(error): throw error
        case .offline: throw FocusTestFailure.offline
        }
    }
}

private actor FocusRemoteStub: FocusRemoteServing {
    struct PeriodCall: Equatable, Sendable {
        let kind: FocusPendingActionKind
        let taskID: UUID?
        let taskIDs: [UUID]
        let sourcePeriodID: UUID?
        let version: Int64?
        let idempotencyKey: String
    }

    struct SettingsCall: Equatable, Sendable {
        let values: FocusCadenceValues
        let version: Int64
    }

    private var currentOutcomes: [FocusOutcome<FocusPeriodDTO>]
    private var mutationOutcomes: [FocusOutcome<FocusPeriodDTO>]
    private var settingsOutcomes: [FocusOutcome<FocusNotificationSettingsDTO>]
    private var settingsMutationOutcomes: [FocusOutcome<FocusNotificationSettingsDTO>]
    private var currentFallback: FocusPeriodDTO
    private var settingsFallback: FocusNotificationSettingsDTO
    private let candidatePage: FocusCandidateListResponseDTO
    private let historyResponse: FocusHistoryResponseDTO
    private let mutationDelayNanoseconds: UInt64
    private var periodCalls: [PeriodCall] = []
    private var settingsCalls: [SettingsCall] = []

    init(
        current: FocusPeriodDTO,
        currentOutcomes: [FocusOutcome<FocusPeriodDTO>] = [],
        mutationOutcomes: [FocusOutcome<FocusPeriodDTO>] = [],
        settings: FocusNotificationSettingsDTO = focusTestSettings(version: 1),
        settingsOutcomes: [FocusOutcome<FocusNotificationSettingsDTO>] = [],
        settingsMutationOutcomes: [FocusOutcome<FocusNotificationSettingsDTO>] = [],
        candidatePage: FocusCandidateListResponseDTO = .init(items: [], nextCursor: nil),
        history: FocusHistoryResponseDTO = .init(items: []),
        mutationDelayNanoseconds: UInt64 = 0
    ) {
        currentFallback = current
        self.currentOutcomes = currentOutcomes
        self.mutationOutcomes = mutationOutcomes
        settingsFallback = settings
        self.settingsOutcomes = settingsOutcomes
        self.settingsMutationOutcomes = settingsMutationOutcomes
        self.candidatePage = candidatePage
        historyResponse = history
        self.mutationDelayNanoseconds = mutationDelayNanoseconds
    }

    func current() throws -> FocusPeriodDTO {
        guard !currentOutcomes.isEmpty else { return currentFallback }
        let value = try currentOutcomes.removeFirst().get()
        currentFallback = value
        return value
    }

    func candidates(
        query: String?, folderID: UUID?, goalID: UUID?, cursor: String?, limit: Int
    ) -> FocusCandidateListResponseDTO {
        candidatePage
    }

    func add(taskID: UUID, version: Int64?, idempotencyKey: String) async throws -> FocusPeriodDTO {
        try await mutate(.init(
            kind: .add, taskID: taskID, taskIDs: [], sourcePeriodID: nil,
            version: version, idempotencyKey: idempotencyKey
        ))
    }

    func remove(taskID: UUID, version: Int64?, idempotencyKey: String) async throws -> FocusPeriodDTO {
        try await mutate(.init(
            kind: .remove, taskID: taskID, taskIDs: [], sourcePeriodID: nil,
            version: version, idempotencyKey: idempotencyKey
        ))
    }

    func reorder(taskIDs: [UUID], version: Int64?, idempotencyKey: String) async throws -> FocusPeriodDTO {
        try await mutate(.init(
            kind: .reorder, taskID: nil, taskIDs: taskIDs, sourcePeriodID: nil,
            version: version, idempotencyKey: idempotencyKey
        ))
    }

    func resolveRollover(
        sourcePeriodID: UUID,
        taskIDs: [UUID],
        version: Int64?,
        idempotencyKey: String
    ) async throws -> FocusPeriodDTO {
        try await mutate(.init(
            kind: .rollover, taskID: nil, taskIDs: taskIDs, sourcePeriodID: sourcePeriodID,
            version: version, idempotencyKey: idempotencyKey
        ))
    }

    func history() -> FocusHistoryResponseDTO { historyResponse }
    func historyDetail(periodID: UUID) -> FocusPeriodDTO { currentFallback }

    func settings() throws -> FocusNotificationSettingsDTO {
        guard !settingsOutcomes.isEmpty else { return settingsFallback }
        let value = try settingsOutcomes.removeFirst().get()
        settingsFallback = value
        return value
    }

    func updateSettings(
        _ values: FocusCadenceValues,
        version: Int64
    ) throws -> FocusNotificationSettingsDTO {
        settingsCalls.append(SettingsCall(values: values, version: version))
        guard !settingsMutationOutcomes.isEmpty else { return settingsFallback }
        let value = try settingsMutationOutcomes.removeFirst().get()
        settingsFallback = value
        return value
    }

    func capturedPeriodCalls() -> [PeriodCall] { periodCalls }
    func capturedSettingsCalls() -> [SettingsCall] { settingsCalls }

    private func mutate(_ call: PeriodCall) async throws -> FocusPeriodDTO {
        periodCalls.append(call)
        if mutationDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: mutationDelayNanoseconds)
        }
        guard !mutationOutcomes.isEmpty else { throw FocusTestFailure.missingStub }
        let value = try mutationOutcomes.removeFirst().get()
        currentFallback = value
        return value
    }
}

private actor FocusRequestSenderSpy: FocusRequestSending {
    struct Request: Sendable {
        let method: HTTPMethod
        let path: [String]
        let query: [String: String]
        let body: Data?
    }

    private let period: FocusPeriodDTO
    private let settings: FocusNotificationSettingsDTO
    private var requests: [Request] = []

    init(period: FocusPeriodDTO, settings: FocusNotificationSettingsDTO) {
        self.period = period
        self.settings = settings
    }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) throws -> Response {
        requests.append(Request(
            method: endpoint.method,
            path: endpoint.pathSegments,
            query: Dictionary(uniqueKeysWithValues: endpoint.queryItems.compactMap { item in
                item.value.map { (item.name, $0) }
            }),
            body: endpoint.body
        ))
        let value: Any
        if Response.self == FocusPeriodDTO.self {
            value = period
        } else if Response.self == FocusNotificationSettingsDTO.self {
            value = settings
        } else if Response.self == FocusCandidateListResponseDTO.self {
            value = FocusCandidateListResponseDTO(items: [], nextCursor: "opaque +/=")
        } else {
            throw FocusTestFailure.missingStub
        }
        guard let response = value as? Response else { throw FocusTestFailure.missingStub }
        return response
    }

    func captured() -> [Request] { requests }
}

private final class FocusIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]

    init(_ values: [UUID]) { self.values = values }

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        return values.removeFirst()
    }
}

private actor RestartableFocusStore {
    private var currentByAccount: [UUID: FocusPeriodDTO] = [:]
    private var historyByAccount: [UUID: [FocusHistorySummaryDTO]] = [:]
    private var detailsByAccount: [UUID: [UUID: FocusPeriodDTO]] = [:]
    private var settingsByAccount: [UUID: FocusNotificationSettingsDTO] = [:]
    private var actions: [UUID: [FocusPendingAction]] = [:]
    private var issues: [UUID: [FocusTerminalIssue]] = [:]

    func current(accountID: UUID) -> FocusPeriodDTO? { currentByAccount[accountID] }
    func saveCurrent(_ value: FocusPeriodDTO, accountID: UUID) { currentByAccount[accountID] = value }
    func history(accountID: UUID) -> [FocusHistorySummaryDTO]? { historyByAccount[accountID] }
    func saveHistory(_ value: [FocusHistorySummaryDTO], accountID: UUID) { historyByAccount[accountID] = value }
    func detail(accountID: UUID, periodID: UUID) -> FocusPeriodDTO? { detailsByAccount[accountID]?[periodID] }
    func saveDetail(_ value: FocusPeriodDTO, accountID: UUID) {
        detailsByAccount[accountID, default: [:]][value.id] = value
    }
    func settings(accountID: UUID) -> FocusNotificationSettingsDTO? { settingsByAccount[accountID] }
    func saveSettings(_ value: FocusNotificationSettingsDTO, accountID: UUID) {
        settingsByAccount[accountID] = value
    }

    func enqueue(_ action: FocusPendingAction) {
        guard !actions[action.accountID, default: []].contains(where: { $0.id == action.id }) else { return }
        actions[action.accountID, default: []].append(action)
    }
    func pending(accountID: UUID) -> [FocusPendingAction] { actions[accountID, default: []] }
    func acknowledge(accountID: UUID, actionID: UUID) {
        actions[accountID]?.removeAll { $0.id == actionID }
    }
    func incrementConflict(accountID: UUID, actionID: UUID) throws -> FocusPendingAction {
        var accountActions = actions[accountID, default: []]
        guard let index = accountActions.firstIndex(where: { $0.id == actionID }) else {
            throw FocusRepositoryError.pendingActionMissing
        }
        accountActions[index].conflictAttempts += 1
        actions[accountID] = accountActions
        return accountActions[index]
    }
    func terminalize(accountID: UUID, actionID: UUID, code: String, at: Date) throws {
        guard let action = actions[accountID]?.first(where: { $0.id == actionID }) else {
            throw FocusRepositoryError.pendingActionMissing
        }
        issues[accountID, default: []].append(FocusTerminalIssue(
            id: UUID(), actionID: action.id, kind: action.kind, code: code,
            conflictAttempts: action.conflictAttempts, createdAt: at
        ))
        actions[accountID]?.removeAll { $0.id == actionID }
    }
    func terminalIssues(accountID: UUID) -> [FocusTerminalIssue] { issues[accountID, default: []] }

    func clear(accountID: UUID) {
        currentByAccount.removeValue(forKey: accountID)
        historyByAccount.removeValue(forKey: accountID)
        detailsByAccount.removeValue(forKey: accountID)
        settingsByAccount.removeValue(forKey: accountID)
        actions.removeValue(forKey: accountID)
        issues.removeValue(forKey: accountID)
    }
}

private struct RestartableFocusCacheAdapter: FocusCaching {
    let store: RestartableFocusStore

    func current(accountID: UUID) async -> FocusPeriodDTO? { await store.current(accountID: accountID) }
    func saveCurrent(_ period: FocusPeriodDTO, accountID: UUID) async {
        await store.saveCurrent(period, accountID: accountID)
    }
    func history(accountID: UUID) async -> [FocusHistorySummaryDTO]? { await store.history(accountID: accountID) }
    func saveHistory(_ history: [FocusHistorySummaryDTO], accountID: UUID) async {
        await store.saveHistory(history, accountID: accountID)
    }
    func historyDetail(accountID: UUID, periodID: UUID) async -> FocusPeriodDTO? {
        await store.detail(accountID: accountID, periodID: periodID)
    }
    func saveHistoryDetail(_ period: FocusPeriodDTO, accountID: UUID) async {
        await store.saveDetail(period, accountID: accountID)
    }
    func settings(accountID: UUID) async -> FocusNotificationSettingsDTO? {
        await store.settings(accountID: accountID)
    }
    func saveSettings(_ settings: FocusNotificationSettingsDTO, accountID: UUID) async {
        await store.saveSettings(settings, accountID: accountID)
    }
    func clear(accountID: UUID) async { await store.clear(accountID: accountID) }
}

private struct RestartableFocusQueueAdapter: FocusActionQueuing {
    let store: RestartableFocusStore

    func enqueue(_ action: FocusPendingAction) async { await store.enqueue(action) }
    func pending(accountID: UUID) async -> [FocusPendingAction] { await store.pending(accountID: accountID) }
    func acknowledge(accountID: UUID, actionID: UUID) async {
        await store.acknowledge(accountID: accountID, actionID: actionID)
    }
    func incrementConflict(accountID: UUID, actionID: UUID) async throws -> FocusPendingAction {
        try await store.incrementConflict(accountID: accountID, actionID: actionID)
    }
    func terminalize(accountID: UUID, actionID: UUID, code: String, at: Date) async throws {
        try await store.terminalize(accountID: accountID, actionID: actionID, code: code, at: at)
    }
    func terminalIssues(accountID: UUID) async -> [FocusTerminalIssue] {
        await store.terminalIssues(accountID: accountID)
    }
    func clear(accountID: UUID) async { await store.clear(accountID: accountID) }
}

final class FocusRepositoryTests: XCTestCase {
    private let accountID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

    func testEndpointAdapterUsesActualRoutesOpaqueCursorAndSettingsVersionOnly() async throws {
        let period = focusTestPeriod(version: 7)
        let settings = focusTestSettings(version: 9)
        let sender = FocusRequestSenderSpy(period: period, settings: settings)
        let remote = AuthenticatedFocusRemote(sender: sender)
        let taskID = UUID()

        _ = try await remote.reorder(taskIDs: [taskID], version: 7, idempotencyKey: "action-1")
        _ = try await remote.candidates(
            query: "query", folderID: nil, goalID: nil, cursor: "opaque +/=", limit: 100
        )
        _ = try await remote.updateSettings(
            FocusCadenceValues(intervalMinutes: 60, quietHoursStart: "22:00", quietHoursEnd: "08:00"),
            version: 9
        )
        let requests = await sender.captured()
        let reorderBody = try jsonObject(requests[0].body)
        let settingsBody = try jsonObject(requests[2].body)

        XCTAssertEqual(requests[0].method, .patch)
        XCTAssertEqual(requests[0].path, ["focus", "current", "items", "order"])
        XCTAssertEqual(reorderBody["periodVersion"] as? Int, 7)
        XCTAssertEqual(reorderBody["idempotencyKey"] as? String, "action-1")
        XCTAssertEqual(requests[1].query["cursor"], "opaque +/=")
        XCTAssertEqual(requests[1].query["q"], "query")
        XCTAssertEqual(settingsBody["version"] as? Int, 9)
        XCTAssertNil(settingsBody["idempotencyKey"])
        XCTAssertNil(settingsBody["periodVersion"])
    }

    func testPersistedTaskIDMappingResolvesMappedKnownAndUnresolvedIDs() async throws {
        let backendID = UUID()
        let localID = UUID()
        let knownLocalID = UUID()
        let unresolvedID = UUID()
        let mapping = PersistedFocusTaskIDMappingAdapter(
            mappedLocalID: { $0 == backendID ? localID : nil },
            isKnownLocalID: { $0 == knownLocalID }
        )

        let mapped = try await mapping.localTaskID(forBackendTaskID: backendID)
        let known = try await mapping.localTaskID(forBackendTaskID: knownLocalID)
        let unresolved = try await mapping.localTaskID(forBackendTaskID: unresolvedID)
        XCTAssertEqual(mapped, localID)
        XCTAssertEqual(known, knownLocalID)
        XCTAssertNil(unresolved)
    }

    func testCurrentResultPublishesOnlyResolvedLocalTaskIDs() async throws {
        let mappedBackendID = UUID()
        let localID = UUID()
        let unresolvedBackendID = UUID()
        let period = focusTestPeriod(
            version: 1,
            items: [
                focusTestItem(taskID: mappedBackendID, title: "Mapped", position: 0),
                focusTestItem(taskID: unresolvedBackendID, title: "Unresolved", position: 1)
            ]
        )
        let repository = FocusRepository(
            remote: FocusRemoteStub(current: period),
            cache: InMemoryFocusCache(),
            queue: InMemoryFocusActionQueue(),
            taskIDMapping: PersistedFocusTaskIDMappingAdapter(
                mappedLocalID: { $0 == mappedBackendID ? localID : nil },
                isKnownLocalID: { _ in false }
            )
        )

        let result = try await repository.loadCurrent(accountID: accountID, timezone: "Europe/Moscow")

        XCTAssertEqual(result.localTaskIDsByBackendID, [mappedBackendID: localID])
    }

    func testOptimisticAddUsesCandidateSnapshotAndQueuesExpectedVersion() async throws {
        let period = focusTestPeriod(version: 4)
        let cache = InMemoryFocusCache()
        let queue = InMemoryFocusActionQueue()
        try await cache.saveCurrent(period, accountID: accountID)
        let fixedID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let repository = FocusRepository(
            remote: FocusRemoteStub(current: period), cache: cache, queue: queue,
            actionID: { fixedID }
        )
        let candidate = focusTestCandidate(title: "Candidate", effort: 0, shared: true, canWrite: false)

        let result = try await repository.add(accountID: accountID, candidate: candidate)
        let pending = try await queue.pending(accountID: accountID)

        XCTAssertEqual(result.source, .optimistic)
        XCTAssertEqual(result.period?.items.last?.taskId, candidate.taskId)
        XCTAssertEqual(result.period?.items.last?.effectiveWeight, 1)
        XCTAssertEqual(result.pendingCount, 1)
        XCTAssertEqual(pending.single?.id, fixedID)
        XCTAssertEqual(pending.single?.expectedVersion, 4)
        XCTAssertEqual(pending.single?.candidate?.title, "Candidate")
    }

    func testInjectedDurableAdaptersPreservePendingActionAcrossRepositoryRecreation() async throws {
        let initial = focusTestPeriod(version: 1)
        let candidate = focusTestCandidate(title: "Persisted")
        let applied = focusTestPeriod(
            version: 2,
            items: [focusTestItem(taskID: candidate.taskId, title: candidate.title, position: 0)]
        )
        let store = RestartableFocusStore()
        let firstCache = RestartableFocusCacheAdapter(store: store)
        let firstQueue = RestartableFocusQueueAdapter(store: store)
        try await firstCache.saveCurrent(initial, accountID: accountID)
        let firstRepository = FocusRepository(
            remote: FocusRemoteStub(current: initial),
            cache: firstCache,
            queue: firstQueue
        )
        _ = try await firstRepository.add(accountID: accountID, candidate: candidate)

        let recreatedCache = RestartableFocusCacheAdapter(store: store)
        let recreatedQueue = RestartableFocusQueueAdapter(store: store)
        let remote = FocusRemoteStub(current: initial, mutationOutcomes: [.value(applied)])
        let recreatedRepository = FocusRepository(
            remote: remote,
            cache: recreatedCache,
            queue: recreatedQueue
        )
        let beforeSync = try await recreatedQueue.pending(accountID: accountID)
        let result = try await recreatedRepository.syncPending(
            accountID: accountID,
            timezone: "Europe/Moscow"
        )
        let afterSync = try await recreatedQueue.pending(accountID: accountID)
        let calls = await remote.capturedPeriodCalls()

        XCTAssertEqual(beforeSync.count, 1)
        XCTAssertTrue(afterSync.isEmpty)
        XCTAssertEqual(result.current?.version, 2)
        XCTAssertEqual(calls.count, 1)
    }

    func testReorderRequiresEveryActiveTaskExactlyOnce() async throws {
        let first = focusTestItem(title: "First", position: 0)
        let second = focusTestItem(title: "Second", position: 1)
        let history = focusTestItem(title: "History", position: 2, historyOnly: true)
        let period = focusTestPeriod(version: 1, items: [first, second, history])
        let cache = InMemoryFocusCache()
        let queue = InMemoryFocusActionQueue()
        try await cache.saveCurrent(period, accountID: accountID)
        let repository = FocusRepository(remote: FocusRemoteStub(current: period), cache: cache, queue: queue)

        await XCTAssertThrowsErrorAsync(
            try await repository.reorder(accountID: accountID, taskIDs: [first.taskId, first.taskId])
        ) { XCTAssertEqual($0 as? FocusRepositoryError, .invalidOrder) }

        let result = try await repository.reorder(
            accountID: accountID,
            taskIDs: [second.taskId, first.taskId]
        )
        XCTAssertEqual(result.period?.items.filter { !$0.historyOnly }.map(\.taskId), [second.taskId, first.taskId])
        XCTAssertEqual(result.period?.items.last?.taskId, history.taskId)
    }

    func testSequentialMutationsChainReturnedVersionsAndActionIDs() async throws {
        let first = focusTestItem(title: "First", position: 0)
        let second = focusTestItem(title: "Second", position: 1)
        let initial = focusTestPeriod(version: 1, items: [first, second])
        let afterRemove = focusTestPeriod(version: 2, items: [focusTestCopy(second, position: 0)])
        let afterOrder = focusTestPeriod(version: 3, items: [focusTestCopy(second, position: 0)])
        let remote = FocusRemoteStub(
            current: initial,
            mutationOutcomes: [.value(afterRemove), .value(afterOrder)]
        )
        let cache = InMemoryFocusCache()
        let queue = InMemoryFocusActionQueue()
        try await cache.saveCurrent(initial, accountID: accountID)
        let ids = [
            UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        ]
        let sequence = FocusIDSequence(ids)
        let repository = FocusRepository(
            remote: remote,
            cache: cache,
            queue: queue,
            now: { Date(timeIntervalSince1970: 1_787_001_200) },
            actionID: { sequence.next() }
        )

        _ = try await repository.remove(accountID: accountID, taskID: first.taskId)
        _ = try await repository.reorder(accountID: accountID, taskIDs: [second.taskId])
        let result = try await repository.syncPending(accountID: accountID, timezone: "Europe/Moscow")
        let calls = await remote.capturedPeriodCalls()

        XCTAssertEqual(calls.map(\.version), [1, 2])
        XCTAssertEqual(calls.map(\.idempotencyKey), ids.map { $0.uuidString.lowercased() })
        XCTAssertEqual(result.current?.version, 3)
        XCTAssertEqual(result.pendingCount, 0)
        XCTAssertEqual(result.acknowledgedCount, 2)
    }

    func testConflictFetchesServerAndRebasesAgainstFreshVersion() async throws {
        let candidate = focusTestCandidate(title: "Candidate")
        let initial = focusTestPeriod(version: 1)
        let fresh = focusTestPeriod(version: 5)
        let applied = focusTestPeriod(
            version: 6,
            items: [focusTestItem(taskID: candidate.taskId, title: candidate.title, position: 0)]
        )
        let remote = FocusRemoteStub(
            current: initial,
            currentOutcomes: [.value(fresh)],
            mutationOutcomes: [.api(apiError(409, code: "version_conflict")), .value(applied)]
        )
        let cache = InMemoryFocusCache()
        let queue = InMemoryFocusActionQueue()
        try await cache.saveCurrent(initial, accountID: accountID)
        let repository = FocusRepository(remote: remote, cache: cache, queue: queue)
        _ = try await repository.add(accountID: accountID, candidate: candidate)

        let result = try await repository.syncPending(accountID: accountID, timezone: "Europe/Moscow")
        let calls = await remote.capturedPeriodCalls()

        XCTAssertEqual(calls.map(\.version), [1, 5])
        XCTAssertEqual(result.current?.version, 6)
        XCTAssertEqual(result.pendingCount, 0)
        XCTAssertTrue(result.terminalIssues.isEmpty)
    }

    func testThirdConflictTerminalizesAndKeepsServerState() async throws {
        let candidate = focusTestCandidate(title: "Candidate")
        let initial = focusTestPeriod(version: 1)
        let server2 = focusTestPeriod(version: 2)
        let server3 = focusTestPeriod(version: 3)
        let server4 = focusTestPeriod(version: 4)
        let conflict = FocusOutcome<FocusPeriodDTO>.api(apiError(409, code: "version_conflict"))
        let remote = FocusRemoteStub(
            current: initial,
            currentOutcomes: [.value(server2), .value(server3), .value(server4)],
            mutationOutcomes: [conflict, conflict, conflict]
        )
        let cache = InMemoryFocusCache()
        let queue = InMemoryFocusActionQueue()
        try await cache.saveCurrent(initial, accountID: accountID)
        let repository = FocusRepository(remote: remote, cache: cache, queue: queue)
        _ = try await repository.add(accountID: accountID, candidate: candidate)

        let result = try await repository.syncPending(accountID: accountID, timezone: "Europe/Moscow")

        XCTAssertEqual(result.current?.version, 4)
        XCTAssertEqual(result.pendingCount, 0)
        XCTAssertEqual(result.terminalIssues.single?.conflictAttempts, 3)
        XCTAssertEqual(result.terminalIssues.single?.code, "version_conflict")
    }

    func testTransientConflictRefreshFailureRetainsActionForRetry() async throws {
        let candidate = focusTestCandidate(title: "Candidate")
        let initial = focusTestPeriod(version: 1)
        let remote = FocusRemoteStub(
            current: initial,
            currentOutcomes: [.api(apiError(503, code: "refresh_unavailable"))],
            mutationOutcomes: [.api(apiError(409, code: "version_conflict"))]
        )
        let cache = InMemoryFocusCache()
        let queue = InMemoryFocusActionQueue()
        try await cache.saveCurrent(initial, accountID: accountID)
        let repository = FocusRepository(remote: remote, cache: cache, queue: queue)
        _ = try await repository.add(accountID: accountID, candidate: candidate)

        await XCTAssertThrowsErrorAsync(
            try await repository.syncPending(accountID: accountID, timezone: "Europe/Moscow")
        ) {
            XCTAssertEqual(
                $0 as? FocusRepositoryError,
                .retryable(code: "refresh_unavailable", statusCode: 503)
            )
        }
        let pending = try await queue.pending(accountID: accountID)
        XCTAssertEqual(pending.single?.conflictAttempts, 1)
    }

    func testRetryableFailureLeavesActionQueued() async throws {
        let initial = focusTestPeriod(version: 1, items: [focusTestItem(title: "Task", position: 0)])
        let remote = FocusRemoteStub(
            current: initial,
            mutationOutcomes: [.api(apiError(503, code: "unavailable"))]
        )
        let cache = InMemoryFocusCache()
        let queue = InMemoryFocusActionQueue()
        try await cache.saveCurrent(initial, accountID: accountID)
        let repository = FocusRepository(remote: remote, cache: cache, queue: queue)
        _ = try await repository.remove(accountID: accountID, taskID: initial.items[0].taskId)

        await XCTAssertThrowsErrorAsync(
            try await repository.syncPending(accountID: accountID, timezone: "Europe/Moscow")
        ) {
            XCTAssertEqual($0 as? FocusRepositoryError, .retryable(code: "unavailable", statusCode: 503))
        }
        let retryPending = try await queue.pending(accountID: accountID)
        XCTAssertEqual(retryPending.count, 1)
    }

    func testRateLimitLeavesActionQueuedForLaterRetry() async throws {
        let initial = focusTestPeriod(version: 1, items: [focusTestItem(title: "Task", position: 0)])
        let remote = FocusRemoteStub(
            current: initial,
            mutationOutcomes: [.api(apiError(429, code: "rate_limited"))]
        )
        let cache = InMemoryFocusCache()
        let queue = InMemoryFocusActionQueue()
        try await cache.saveCurrent(initial, accountID: accountID)
        let repository = FocusRepository(remote: remote, cache: cache, queue: queue)
        _ = try await repository.remove(accountID: accountID, taskID: initial.items[0].taskId)

        await XCTAssertThrowsErrorAsync(
            try await repository.syncPending(accountID: accountID, timezone: "Europe/Moscow")
        ) {
            XCTAssertEqual($0 as? FocusRepositoryError, .retryable(code: "rate_limited", statusCode: 429))
        }
        let pending = try await queue.pending(accountID: accountID)
        XCTAssertEqual(pending.count, 1)
    }

    func testRequestTimeoutLeavesActionQueuedForLaterRetry() async throws {
        let initial = focusTestPeriod(version: 1, items: [focusTestItem(title: "Task", position: 0)])
        let remote = FocusRemoteStub(
            current: initial,
            mutationOutcomes: [.api(apiError(408, code: "request_timeout"))]
        )
        let cache = InMemoryFocusCache()
        let queue = InMemoryFocusActionQueue()
        try await cache.saveCurrent(initial, accountID: accountID)
        let repository = FocusRepository(remote: remote, cache: cache, queue: queue)
        _ = try await repository.remove(accountID: accountID, taskID: initial.items[0].taskId)

        await XCTAssertThrowsErrorAsync(
            try await repository.syncPending(accountID: accountID, timezone: "Europe/Moscow")
        ) {
            XCTAssertEqual($0 as? FocusRepositoryError, .retryable(code: "request_timeout", statusCode: 408))
        }
        let pending = try await queue.pending(accountID: accountID)
        XCTAssertEqual(pending.count, 1)
    }

    func testUnauthorizedStopsSyncAndClearsAction() async throws {
        let initial = focusTestPeriod(version: 1, items: [focusTestItem(title: "Task", position: 0)])
        let remote = FocusRemoteStub(
            current: initial,
            mutationOutcomes: [.api(apiError(401, code: "unauthorized"))]
        )
        let cache = InMemoryFocusCache()
        let queue = InMemoryFocusActionQueue()
        try await cache.saveCurrent(initial, accountID: accountID)
        let repository = FocusRepository(remote: remote, cache: cache, queue: queue)
        _ = try await repository.remove(accountID: accountID, taskID: initial.items[0].taskId)

        await XCTAssertThrowsErrorAsync(
            try await repository.syncPending(accountID: accountID, timezone: "Europe/Moscow")
        ) { XCTAssertEqual(($0 as? APIError)?.statusCode, 401) }
        let unauthorizedPending = try await queue.pending(accountID: accountID)
        XCTAssertTrue(unauthorizedPending.isEmpty)
    }

    func testTerminalUnauthorizedClearsAllAccountScopedCacheQueueAndIssues() async throws {
        let otherAccountID = UUID()
        let period = focusTestPeriod(version: 1, items: [focusTestItem(title: "Task", position: 0)])
        let detail = focusTestPeriod(version: 2, status: "completed", items: period.items)
        let cache = InMemoryFocusCache()
        let queue = InMemoryFocusActionQueue()
        try await cache.saveCurrent(period, accountID: accountID)
        try await cache.saveHistory([], accountID: accountID)
        try await cache.saveHistoryDetail(detail, accountID: accountID)
        try await cache.saveSettings(focusTestSettings(version: 3), accountID: accountID)
        try await cache.saveCurrent(period, accountID: otherAccountID)
        let terminalAction = focusTestPendingAction(accountID: accountID, kind: .remove)
        try await queue.enqueue(terminalAction)
        try await queue.terminalize(
            accountID: accountID,
            actionID: terminalAction.id,
            code: "old_issue",
            at: Date(timeIntervalSince1970: 1)
        )
        try await queue.enqueue(focusTestPendingAction(accountID: accountID, kind: .add))
        try await queue.enqueue(focusTestPendingAction(accountID: otherAccountID, kind: .add))
        let repository = FocusRepository(
            remote: FocusRemoteStub(
                current: period,
                mutationOutcomes: [.api(apiError(401, code: "unauthorized"))]
            ),
            cache: cache,
            queue: queue
        )

        await XCTAssertThrowsErrorAsync(
            try await repository.loadCurrent(accountID: accountID, timezone: "Europe/Moscow")
        ) { XCTAssertEqual(($0 as? APIError)?.statusCode, 401) }

        let cachedCurrent = try await cache.current(accountID: accountID)
        let cachedHistory = try await cache.history(accountID: accountID)
        let cachedDetail = try await cache.historyDetail(accountID: accountID, periodID: detail.id)
        let cachedSettings = try await cache.settings(accountID: accountID)
        let pending = try await queue.pending(accountID: accountID)
        let issues = try await queue.terminalIssues(accountID: accountID)
        let otherCurrent = try await cache.current(accountID: otherAccountID)
        let otherPending = try await queue.pending(accountID: otherAccountID)
        XCTAssertNil(cachedCurrent)
        XCTAssertNil(cachedHistory)
        XCTAssertNil(cachedDetail)
        XCTAssertNil(cachedSettings)
        XCTAssertTrue(pending.isEmpty)
        XCTAssertTrue(issues.isEmpty)
        XCTAssertNotNil(otherCurrent)
        XCTAssertEqual(otherPending.count, 1)
    }

    func testConcurrentSyncPendingCallsShareOneRemoteExecution() async throws {
        let item = focusTestItem(title: "Task", position: 0)
        let initial = focusTestPeriod(version: 1, items: [item])
        let applied = focusTestPeriod(version: 2)
        let remote = FocusRemoteStub(
            current: initial,
            mutationOutcomes: [.value(applied)],
            mutationDelayNanoseconds: 100_000_000
        )
        let cache = InMemoryFocusCache()
        let queue = InMemoryFocusActionQueue()
        try await cache.saveCurrent(initial, accountID: accountID)
        let repository = FocusRepository(remote: remote, cache: cache, queue: queue)
        _ = try await repository.remove(accountID: accountID, taskID: item.taskId)

        async let first = repository.syncPending(accountID: accountID, timezone: "Europe/Moscow")
        async let second = repository.syncPending(accountID: accountID, timezone: "Europe/Moscow")
        let results = try await (first, second)

        let calls = await remote.capturedPeriodCalls()
        let pending = try await queue.pending(accountID: accountID)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(results.0.current?.version, 2)
        XCTAssertEqual(results.1.current?.version, 2)
        XCTAssertTrue(pending.isEmpty)
    }

    func testCancellingOneSyncWaiterDoesNotCancelSharedExecution() async throws {
        let item = focusTestItem(title: "Task", position: 0)
        let initial = focusTestPeriod(version: 1, items: [item])
        let applied = focusTestPeriod(version: 2)
        let remote = FocusRemoteStub(
            current: initial,
            mutationOutcomes: [.value(applied)],
            mutationDelayNanoseconds: 100_000_000
        )
        let cache = InMemoryFocusCache()
        let queue = InMemoryFocusActionQueue()
        try await cache.saveCurrent(initial, accountID: accountID)
        let repository = FocusRepository(remote: remote, cache: cache, queue: queue)
        _ = try await repository.remove(accountID: accountID, taskID: item.taskId)

        let keeper = Task { try await repository.syncPending(accountID: accountID, timezone: "Europe/Moscow") }
        let joined = await waitForPeriodCallCount(1, remote: remote)
        XCTAssertTrue(joined)
        let cancelled = Task { try await repository.syncPending(accountID: accountID, timezone: "Europe/Moscow") }
        cancelled.cancel()

        let keptResult = try await keeper.value
        XCTAssertEqual(keptResult.current?.version, 2)
        await XCTAssertThrowsErrorAsync(try await cancelled.value) { error in
            XCTAssertTrue(error is CancellationError)
        }
        let calls = await remote.capturedPeriodCalls()
        XCTAssertEqual(calls.count, 1)
    }

    func testRolloverRequiresOfferedUniqueTasksAndAppliesExplicitSelection() async throws {
        let offeredA = focusTestItem(title: "A", position: 0)
        let offeredB = focusTestItem(title: "B", position: 1)
        let sourceID = UUID()
        let initial = focusTestPeriod(
            version: 2,
            rollover: FocusRolloverOfferDTO(sourcePeriodId: sourceID, items: [offeredA, offeredB])
        )
        let cache = InMemoryFocusCache()
        let queue = InMemoryFocusActionQueue()
        try await cache.saveCurrent(initial, accountID: accountID)
        let repository = FocusRepository(remote: FocusRemoteStub(current: initial), cache: cache, queue: queue)

        await XCTAssertThrowsErrorAsync(
            try await repository.resolveRollover(accountID: accountID, selectedTaskIDs: [UUID()])
        ) { XCTAssertEqual($0 as? FocusRepositoryError, .invalidRolloverSelection) }

        let result = try await repository.resolveRollover(
            accountID: accountID,
            selectedTaskIDs: [offeredB.taskId]
        )
        let pending = try await queue.pending(accountID: accountID)
        XCTAssertEqual(result.period?.items.map(\.taskId), [offeredB.taskId])
        XCTAssertNil(result.period?.rolloverOffer)
        XCTAssertEqual(pending.single?.sourcePeriodID, sourceID)
        XCTAssertEqual(pending.single?.taskIDs, [offeredB.taskId])
    }

    func testCurrentReadFallsBackToAccountCacheBut401DoesNot() async throws {
        let cached = focusTestPeriod(version: 8)
        let cache = InMemoryFocusCache()
        try await cache.saveCurrent(cached, accountID: accountID)
        let offlineRepository = FocusRepository(
            remote: FocusRemoteStub(current: cached, currentOutcomes: [.offline]),
            cache: cache,
            queue: InMemoryFocusActionQueue()
        )

        let offline = try await offlineRepository.loadCurrent(accountID: accountID, timezone: "Europe/Moscow")
        XCTAssertEqual(offline.source, .cache)
        XCTAssertEqual(offline.period?.version, 8)

        let unauthorizedRepository = FocusRepository(
            remote: FocusRemoteStub(
                current: cached,
                currentOutcomes: [.api(apiError(401, code: "unauthorized"))]
            ),
            cache: cache,
            queue: InMemoryFocusActionQueue()
        )
        await XCTAssertThrowsErrorAsync(
            try await unauthorizedRepository.loadCurrent(accountID: accountID, timezone: "Europe/Moscow")
        ) { XCTAssertEqual(($0 as? APIError)?.statusCode, 401) }
    }

    func testSettingsConflictRebasesDesiredValuesWithoutFabricatedIdempotency() async throws {
        let initial = focusTestPeriod(version: 1)
        let oldSettings = focusTestSettings(version: 2)
        let freshSettings = focusTestSettings(version: 5)
        let desired = FocusCadenceValues(
            intervalMinutes: 60, quietHoursStart: "21:30", quietHoursEnd: "06:15"
        )
        let applied = FocusNotificationSettingsDTO(
            intervalMinutes: 60, quietHoursStart: "21:30", quietHoursEnd: "06:15", version: 6
        )
        let remote = FocusRemoteStub(
            current: initial,
            settings: oldSettings,
            settingsOutcomes: [.value(freshSettings)],
            settingsMutationOutcomes: [
                .api(apiError(409, code: "version_conflict")),
                .value(applied)
            ]
        )
        let cache = InMemoryFocusCache()
        let queue = InMemoryFocusActionQueue()
        try await cache.saveSettings(oldSettings, accountID: accountID)
        let repository = FocusRepository(remote: remote, cache: cache, queue: queue)
        _ = try await repository.updateSettings(accountID: accountID, values: desired)

        let result = try await repository.syncPending(accountID: accountID, timezone: "Europe/Moscow")
        let calls = await remote.capturedSettingsCalls()

        XCTAssertEqual(calls.map(\.version), [2, 5])
        XCTAssertEqual(calls.map(\.values), [desired, desired])
        XCTAssertEqual(result.settings?.version, 6)
        XCTAssertEqual(result.pendingCount, 0)
    }

    func testHistoryDetailIncludesHistoryOnlySnapshotsInProgress() async throws {
        let detail = focusTestPeriod(
            version: 7,
            status: "completed",
            items: [
                focusTestItem(title: "Visible", status: .todo, effort: 1, position: 0),
                focusTestItem(
                    title: "Historical", status: .done, effort: 3, position: 1, historyOnly: true
                )
            ]
        )
        let repository = FocusRepository(
            remote: FocusRemoteStub(current: detail),
            cache: InMemoryFocusCache(),
            queue: InMemoryFocusActionQueue()
        )

        let result = try await repository.loadHistoryDetail(accountID: accountID, periodID: detail.id)

        XCTAssertEqual(result.period?.progress.completedWeight, 3)
        XCTAssertEqual(result.period?.progress.totalWeight, 4)
        XCTAssertEqual(result.period?.progress.percent, 75)
        XCTAssertEqual(result.period?.progress.totalCount, 2)
    }

    private func waitForPeriodCallCount(_ count: Int, remote: FocusRemoteStub) async -> Bool {
        for _ in 0..<500 {
            let calls = await remote.capturedPeriodCalls()
            if calls.count >= count { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    private func jsonObject(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(data)) as? [String: Any])
    }
}

private func focusTestPeriod(
    version: Int64,
    status: String = "active",
    items: [FocusItemDTO] = [],
    rollover: FocusRolloverOfferDTO? = nil
) -> FocusPeriodDTO {
    FocusPeriodDTO(
        id: UUID(),
        weekStart: LocalDate(rawValue: "2026-08-17")!,
        weekEndExclusive: LocalDate(rawValue: "2026-08-24")!,
        startsAt: Date(timeIntervalSince1970: 1_787_001_200),
        endsAt: Date(timeIntervalSince1970: 1_787_606_000),
        timezone: "Europe/Moscow",
        status: status,
        version: version,
        progress: status == "completed"
            ? FocusProgressCalculator.history(items)
            : FocusProgressCalculator.current(items),
        items: items,
        rolloverOffer: rollover
    )
}

private func focusTestPendingAction(
    accountID: UUID,
    kind: FocusPendingActionKind
) -> FocusPendingAction {
    FocusPendingAction(
        id: UUID(),
        accountID: accountID,
        kind: kind,
        taskID: kind == .add || kind == .remove ? UUID() : nil,
        taskIDs: [],
        sourcePeriodID: nil,
        expectedVersion: 1,
        candidate: nil,
        cadence: nil,
        conflictAttempts: 0,
        createdAt: Date(timeIntervalSince1970: 1)
    )
}

private func focusTestItem(
    taskID: UUID = UUID(),
    title: String,
    status: PlanningStatus = .todo,
    effort: Int? = 1,
    position: Int,
    historyOnly: Bool = false
) -> FocusItemDTO {
    FocusItemDTO(
        id: UUID(), taskId: taskID, title: title, status: status,
        effort: effort, effectiveWeight: max(effort ?? 0, 1),
        plannedTime: nil, dueTime: nil, position: position,
        historyOnly: historyOnly, folderId: UUID(), folderTitle: "Folder",
        goalId: UUID(), goalTitle: "Goal", shared: false, canWrite: true
    )
}

private func focusTestCopy(_ item: FocusItemDTO, position: Int) -> FocusItemDTO {
    FocusItemDTO(
        id: item.id, taskId: item.taskId, title: item.title, status: item.status,
        effort: item.effort, effectiveWeight: item.effectiveWeight,
        plannedTime: item.plannedTime, dueTime: item.dueTime, position: position,
        historyOnly: item.historyOnly, folderId: item.folderId, folderTitle: item.folderTitle,
        goalId: item.goalId, goalTitle: item.goalTitle, shared: item.shared, canWrite: item.canWrite
    )
}

private func focusTestCandidate(
    title: String,
    effort: Int? = 1,
    shared: Bool = false,
    canWrite: Bool = true
) -> FocusCandidateDTO {
    FocusCandidateDTO(
        taskId: UUID(), title: title, status: .todo, effort: effort,
        effectiveWeight: max(effort ?? 0, 1), plannedTime: nil, dueTime: nil,
        folderId: UUID(), folderTitle: "Folder", goalId: UUID(), goalTitle: "Goal",
        shared: shared, canWrite: canWrite, inFocus: false
    )
}

private func focusTestSettings(version: Int64) -> FocusNotificationSettingsDTO {
    FocusNotificationSettingsDTO(
        intervalMinutes: 120, quietHoursStart: "22:00", quietHoursEnd: "08:00", version: version
    )
}

private func apiError(_ status: Int, code: String) -> APIError {
    APIError(
        statusCode: status, code: code, message: code,
        details: [], traceID: nil, requestID: UUID()
    )
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error")
    } catch {
        handler(error)
    }
}
