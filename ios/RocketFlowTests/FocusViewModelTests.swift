import Foundation
import XCTest
@testable import RocketFlow

@MainActor
final class FocusViewModelTests: XCTestCase {
    private let accountID = UUID()

    func testNewerCurrentGenerationWinsWhenOlderRequestFinishesLast() async {
        let repository = FocusViewModelRepositoryStub(suspendCurrent: true)
        let model = makeModel(repository: repository)
        let old = focusVMPeriod(version: 1, items: [focusVMItem(title: "Old", position: 0)])
        let fresh = focusVMPeriod(version: 2, items: [focusVMItem(title: "Fresh", position: 0)])

        let first = Task { await model.reloadCurrent() }
        let firstArrived = await repository.waitForCurrentRequestCount(1)
        XCTAssertTrue(firstArrived)
        let second = Task { await model.reloadCurrent() }
        let secondArrived = await repository.waitForCurrentRequestCount(2)
        XCTAssertTrue(secondArrived)

        await repository.completeCurrent(
            at: 1,
            with: FocusCurrentResult(
                period: fresh, source: .network, pendingCount: 0,
                terminalIssues: [], failure: nil
            )
        )
        await second.value
        await repository.completeCurrent(
            at: 0,
            with: FocusCurrentResult(
                period: old, source: .network, pendingCount: 0,
                terminalIssues: [], failure: nil
            )
        )
        await first.value

        XCTAssertEqual(model.period?.version, 2)
        XCTAssertEqual(model.activeItems.first?.title, "Fresh")
    }

    func testTaskTapMapsBackendIDToPersistedLocalIDAndIgnoresUnresolved() async {
        let backendID = UUID()
        let localID = UUID()
        let unresolvedID = UUID()
        let period = focusVMPeriod(
            version: 1,
            items: [focusVMItem(taskID: backendID, title: "Mapped", position: 0)]
        )
        let repository = FocusViewModelRepositoryStub(
            currentResponses: [focusVMCurrent(period, localTaskIDs: [backendID: localID])]
        )
        var opened: UUID?
        let model = makeModel(repository: repository) { opened = $0 }

        await model.reloadCurrent()
        model.openTask(backendID)
        XCTAssertEqual(opened, localID)

        opened = nil
        model.openTask(unresolvedID)
        XCTAssertNil(opened)
        XCTAssertEqual(model.taskNavigationHint(for: unresolvedID), FocusCopy(language: .en).taskUnavailable)
    }

    func testCandidatePagingPreservesOpaqueCursorDeduplicatesAndExcludesSelected() async {
        let selectedID = UUID()
        let duplicateID = UUID()
        let cursor = "opaque:+/=cursor"
        let period = focusVMPeriod(
            version: 1,
            items: [focusVMItem(taskID: selectedID, title: "Selected", position: 0)]
        )
        let repository = FocusViewModelRepositoryStub(
            currentResponses: [focusVMCurrent(period)],
            candidateResponses: [
                FocusCandidateListResponseDTO(
                    items: [
                        focusVMCandidate(taskID: selectedID, title: "Selected"),
                        focusVMCandidate(taskID: duplicateID, title: "Old title")
                    ],
                    nextCursor: cursor
                ),
                FocusCandidateListResponseDTO(
                    items: [
                        focusVMCandidate(taskID: duplicateID, title: "Fresh title"),
                        focusVMCandidate(title: "Another", shared: true, canWrite: false)
                    ],
                    nextCursor: nil
                )
            ]
        )
        let model = makeModel(repository: repository)
        await model.reloadCurrent()
        model.candidateQuery = "  launch  "

        await model.reloadCandidates()
        XCTAssertEqual(model.candidateCursor, cursor)
        await model.loadMoreCandidates()

        let requests = await repository.candidateRequests()
        let byID = Dictionary(uniqueKeysWithValues: model.candidates.map { ($0.taskId, $0) })
        XCTAssertEqual(requests.map(\.query), ["launch", "launch"])
        XCTAssertEqual(requests.map(\.cursor), [nil, cursor])
        XCTAssertNil(byID[selectedID])
        XCTAssertEqual(byID[duplicateID]?.title, "Fresh title")
        XCTAssertEqual(model.candidates.count, 2)
        XCTAssertTrue(model.candidates.contains { $0.shared && !$0.canWrite })
    }

    func testDebouncedSearchIgnoresStaleResponse() async {
        let repository = FocusViewModelRepositoryStub(suspendCandidates: true)
        let model = makeModel(repository: repository)

        model.scheduleCandidateSearch("old")
        let oldArrived = await repository.waitForCandidateRequestCount(1)
        XCTAssertTrue(oldArrived)
        model.scheduleCandidateSearch("new")
        let newArrived = await repository.waitForCandidateRequestCount(2)
        XCTAssertTrue(newArrived)

        await repository.completeCandidate(
            at: 1,
            with: FocusCandidateListResponseDTO(
                items: [focusVMCandidate(title: "New result")], nextCursor: nil
            )
        )
        let newApplied = await waitUntil { model.candidates.map(\.title) == ["New result"] }
        XCTAssertTrue(newApplied)
        await repository.completeCandidate(
            at: 0,
            with: FocusCandidateListResponseDTO(
                items: [focusVMCandidate(title: "Old result")], nextCursor: nil
            )
        )
        try? await Task.sleep(nanoseconds: 20_000_000)

        let requests = await repository.candidateRequests()
        XCTAssertEqual(requests.map(\.query), ["old", "new"])
        XCTAssertEqual(model.candidates.map(\.title), ["New result"])
        XCTAssertEqual(model.candidatePhase, .loaded)
    }

    func testCandidateRemainsVisibleWhenOptimisticAddCannotBeQueued() async {
        let candidate = focusVMCandidate(title: "Keep me")
        let repository = FocusViewModelRepositoryStub(
            candidateResponses: [.init(items: [candidate], nextCursor: nil)],
            mutationError: .currentPeriodMissing
        )
        let model = makeModel(repository: repository)
        await model.reloadCandidates()

        await model.add(candidate)

        XCTAssertEqual(model.candidates.map(\.taskId), [candidate.taskId])
        XCTAssertEqual(model.phase, .error)
    }

    func testUnauthorizedCurrentClearsContentAndInvokesSessionHook() async {
        let repository = FocusViewModelRepositoryStub(
            currentError: APIError(
                statusCode: 401, code: "unauthorized", message: "unauthorized",
                details: [], traceID: nil, requestID: UUID()
            )
        )
        var unauthorizedCount = 0
        let model = FocusViewModel(
            accountID: accountID,
            timezone: "Europe/Moscow",
            language: .en,
            repository: repository,
            onOpenTask: { _ in },
            onUnauthorized: { unauthorizedCount += 1 }
        )

        await model.reloadCurrent()

        XCTAssertEqual(model.phase, .unauthorized)
        XCTAssertNil(model.period)
        XCTAssertEqual(unauthorizedCount, 1)
    }

    func testUnauthorizedClearsCandidatesHistoryDetailSettingsAndMappings() async {
        let candidate = focusVMCandidate(title: "Candidate")
        let summary = focusVMHistory(id: UUID(), weekStart: "2026-08-17")
        let historyTaskID = UUID()
        let localTaskID = UUID()
        let detail = focusVMPeriod(
            version: 2,
            items: [focusVMItem(taskID: historyTaskID, title: "History", position: 0)]
        )
        let repository = FocusViewModelRepositoryStub(
            currentError: APIError(
                statusCode: 401, code: "unauthorized", message: "unauthorized",
                details: [], traceID: nil, requestID: UUID()
            ),
            candidateResponses: [.init(items: [candidate], nextCursor: nil)],
            history: [summary],
            historyDetail: detail,
            historyDetailLocalTaskIDs: [historyTaskID: localTaskID]
        )
        var unauthorizedCount = 0
        let model = FocusViewModel(
            accountID: accountID,
            timezone: "Europe/Moscow",
            language: .en,
            repository: repository,
            onOpenTask: { _ in },
            onUnauthorized: { unauthorizedCount += 1 }
        )
        model.candidateQuery = "private search"
        await model.reloadCandidates()
        await model.loadHistory()
        await model.loadHistoryDetail(periodID: summary.id)
        await model.loadSettings()
        XCTAssertFalse(model.candidates.isEmpty)
        XCTAssertFalse(model.history.isEmpty)
        XCTAssertNotNil(model.selectedHistoryPeriod)
        XCTAssertNotNil(model.settings)
        XCTAssertEqual(model.localTaskID(for: historyTaskID), localTaskID)

        await model.reloadCurrent()

        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertTrue(model.candidateQuery.isEmpty)
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertNil(model.selectedHistoryPeriod)
        XCTAssertNil(model.settings)
        XCTAssertTrue(model.localTaskIDsByBackendID.isEmpty)
        XCTAssertEqual(model.phase, .unauthorized)
        XCTAssertEqual(model.candidatePhase, .unauthorized)
        XCTAssertEqual(model.historyPhase, .unauthorized)
        XCTAssertEqual(model.settingsPhase, .unauthorized)
        XCTAssertEqual(unauthorizedCount, 1)
    }

    func testMutationInvalidatesOlderCurrentReloadFinishingLast() async {
        let item = focusVMItem(title: "Task", position: 0)
        let initial = focusVMPeriod(version: 1, items: [item])
        let mutated = focusVMPeriod(version: 2)
        let repository = FocusViewModelRepositoryStub(
            currentResponses: [focusVMCurrent(initial)],
            suspendCurrent: true,
            mutationResult: focusVMCurrent(mutated)
        )
        let model = makeModel(repository: repository)
        await model.reloadCurrent()

        let staleReload = Task { await model.reloadCurrent() }
        let requestStarted = await repository.waitForCurrentRequestCount(1)
        XCTAssertTrue(requestStarted)
        await model.remove(taskID: item.taskId)
        await repository.completeCurrent(at: 0, with: focusVMCurrent(initial))
        await staleReload.value

        XCTAssertEqual(model.period?.version, 2)
        XCTAssertTrue(model.activeItems.isEmpty)
    }

    func testRemoveRefreshesCandidatePickerContents() async {
        let item = focusVMItem(title: "Return me", position: 0)
        let candidate = focusVMCandidate(taskID: item.taskId, title: item.title)
        let initial = focusVMPeriod(version: 1, items: [item])
        let removed = focusVMPeriod(version: 2)
        let repository = FocusViewModelRepositoryStub(
            currentResponses: [focusVMCurrent(initial)],
            candidateResponses: [.init(items: [candidate], nextCursor: nil)],
            mutationResult: focusVMCurrent(removed)
        )
        let model = makeModel(repository: repository)
        await model.reloadCurrent()

        await model.remove(taskID: item.taskId)

        let requests = await repository.candidateRequests()
        XCTAssertEqual(model.candidates.map(\.taskId), [item.taskId])
        XCTAssertEqual(requests.count, 1)
    }

    func testRolloverStartsSelectedAndSubmitsOnlyExplicitSelectionInOfferOrder() async {
        let first = focusVMItem(title: "First", position: 0)
        let second = focusVMItem(title: "Second", position: 1)
        let period = focusVMPeriod(
            version: 4,
            rollover: FocusRolloverOfferDTO(sourcePeriodId: UUID(), items: [first, second])
        )
        let resolved = focusVMPeriod(version: 5, items: [second])
        let repository = FocusViewModelRepositoryStub(
            currentResponses: [focusVMCurrent(period)],
            mutationResult: focusVMCurrent(resolved)
        )
        let model = makeModel(repository: repository)
        await model.reloadCurrent()
        XCTAssertEqual(model.rolloverSelection, Set([first.taskId, second.taskId]))

        model.toggleRollover(taskID: first.taskId)
        await model.resolveRollover()

        let selections = await repository.rolloverSelections()
        XCTAssertEqual(selections, [[second.taskId]])
        XCTAssertEqual(model.activeItems.map(\.taskId), [second.taskId])
    }

    func testHistoryIsNewestFirstAndDetailIsLoadedAsReadOnlySnapshot() async {
        let older = focusVMHistory(id: UUID(), weekStart: "2026-08-03")
        let newer = focusVMHistory(id: UUID(), weekStart: "2026-08-17")
        let detail = focusVMPeriod(version: 9, items: [focusVMItem(title: "Snapshot", position: 0)])
        let repository = FocusViewModelRepositoryStub(
            history: [older, newer],
            historyDetail: detail
        )
        let model = makeModel(repository: repository)

        await model.loadHistory()
        await model.loadHistoryDetail(periodID: newer.id)

        XCTAssertEqual(model.history.map(\.id), [newer.id, older.id])
        XCTAssertEqual(model.selectedHistoryPeriod, detail)
        XCTAssertEqual(model.historyPhase, .loaded)
    }

    private func makeModel(
        repository: FocusViewModelRepositoryStub,
        onOpenTask: @escaping (UUID) -> Void = { _ in }
    ) -> FocusViewModel {
        FocusViewModel(
            accountID: accountID,
            timezone: "Europe/Moscow",
            language: .en,
            repository: repository,
            onOpenTask: onOpenTask
        )
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<500 {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }
}

private actor FocusViewModelRepositoryStub: FocusRepositoryServing {
    struct CandidateRequest: Sendable {
        let query: String?
        let cursor: String?
    }

    private var currentResponses: [FocusCurrentResult]
    private let currentError: APIError?
    private let suspendCurrent: Bool
    private var currentContinuations: [CheckedContinuation<FocusCurrentResult, Error>] = []
    private var candidateResponses: [FocusCandidateListResponseDTO]
    private let suspendCandidates: Bool
    private var candidateContinuations: [CheckedContinuation<FocusCandidateListResponseDTO, Error>] = []
    private var recordedCandidateRequests: [CandidateRequest] = []
    private var recordedRolloverSelections: [[UUID]] = []
    private let mutationResult: FocusCurrentResult?
    private let mutationError: FocusRepositoryError?
    private let historyItems: [FocusHistorySummaryDTO]
    private let historyDetailPeriod: FocusPeriodDTO?
    private let historyDetailLocalTaskIDs: [UUID: UUID]

    init(
        currentResponses: [FocusCurrentResult] = [],
        currentError: APIError? = nil,
        suspendCurrent: Bool = false,
        candidateResponses: [FocusCandidateListResponseDTO] = [],
        suspendCandidates: Bool = false,
        mutationResult: FocusCurrentResult? = nil,
        mutationError: FocusRepositoryError? = nil,
        history: [FocusHistorySummaryDTO] = [],
        historyDetail: FocusPeriodDTO? = nil,
        historyDetailLocalTaskIDs: [UUID: UUID] = [:]
    ) {
        self.currentResponses = currentResponses
        self.currentError = currentError
        self.suspendCurrent = suspendCurrent
        self.candidateResponses = candidateResponses
        self.suspendCandidates = suspendCandidates
        self.mutationResult = mutationResult
        self.mutationError = mutationError
        historyItems = history
        historyDetailPeriod = historyDetail
        self.historyDetailLocalTaskIDs = historyDetailLocalTaskIDs
    }

    func loadCurrent(accountID: UUID, timezone: String) async throws -> FocusCurrentResult {
        if let currentError { throw currentError }
        if !currentResponses.isEmpty { return currentResponses.removeFirst() }
        if suspendCurrent {
            return try await withCheckedThrowingContinuation { currentContinuations.append($0) }
        }
        return focusVMCurrent(nil)
    }

    func loadCandidates(
        accountID: UUID,
        query: String?, folderID: UUID?, goalID: UUID?, cursor: String?, limit: Int
    ) async throws -> FocusCandidateListResponseDTO {
        recordedCandidateRequests.append(CandidateRequest(query: query, cursor: cursor))
        if !candidateResponses.isEmpty { return candidateResponses.removeFirst() }
        if suspendCandidates {
            return try await withCheckedThrowingContinuation { candidateContinuations.append($0) }
        }
        return FocusCandidateListResponseDTO(items: [], nextCursor: nil)
    }

    func add(accountID: UUID, candidate: FocusCandidateDTO) async throws -> FocusCurrentResult {
        if let mutationError { throw mutationError }
        return mutationResult ?? focusVMCurrent(nil)
    }

    func remove(accountID: UUID, taskID: UUID) async throws -> FocusCurrentResult {
        if let mutationError { throw mutationError }
        return mutationResult ?? focusVMCurrent(nil)
    }

    func reorder(accountID: UUID, taskIDs: [UUID]) async throws -> FocusCurrentResult {
        if let mutationError { throw mutationError }
        return mutationResult ?? focusVMCurrent(nil)
    }

    func resolveRollover(
        accountID: UUID, selectedTaskIDs: [UUID]
    ) async throws -> FocusCurrentResult {
        if let mutationError { throw mutationError }
        recordedRolloverSelections.append(selectedTaskIDs)
        return mutationResult ?? focusVMCurrent(nil)
    }

    func loadHistory(accountID: UUID) async throws -> FocusHistoryResult {
        FocusHistoryResult(items: historyItems, source: .network, failure: nil)
    }

    func loadHistoryDetail(accountID: UUID, periodID: UUID) async throws -> FocusHistoryDetailResult {
        FocusHistoryDetailResult(
            period: historyDetailPeriod,
            source: .network,
            failure: nil,
            localTaskIDsByBackendID: historyDetailLocalTaskIDs
        )
    }

    func loadSettings(accountID: UUID) async throws -> FocusSettingsResult {
        FocusSettingsResult(settings: focusVMSettings(), source: .network, failure: nil)
    }

    func updateSettings(
        accountID: UUID, values: FocusCadenceValues
    ) async throws -> FocusSettingsResult {
        FocusSettingsResult(
            settings: FocusNotificationSettingsDTO(
                intervalMinutes: values.intervalMinutes,
                quietHoursStart: values.quietHoursStart,
                quietHoursEnd: values.quietHoursEnd,
                version: 2
            ),
            source: .optimistic,
            failure: nil
        )
    }

    func syncPending(accountID: UUID, timezone: String) async throws -> FocusSyncResult {
        FocusSyncResult(
            current: mutationResult?.period,
            settings: nil,
            pendingCount: 0,
            terminalIssues: [],
            acknowledgedCount: 1
        )
    }

    func waitForCurrentRequestCount(_ count: Int) async -> Bool {
        for _ in 0..<500 {
            if currentContinuations.count >= count { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    func completeCurrent(at index: Int, with result: FocusCurrentResult) {
        currentContinuations.remove(at: index).resume(returning: result)
    }

    func waitForCandidateRequestCount(_ count: Int) async -> Bool {
        for _ in 0..<1_000 {
            if candidateContinuations.count >= count { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    func completeCandidate(at index: Int, with result: FocusCandidateListResponseDTO) {
        candidateContinuations.remove(at: index).resume(returning: result)
    }

    func candidateRequests() -> [CandidateRequest] { recordedCandidateRequests }
    func rolloverSelections() -> [[UUID]] { recordedRolloverSelections }
}

private func focusVMCurrent(
    _ period: FocusPeriodDTO?,
    localTaskIDs: [UUID: UUID] = [:]
) -> FocusCurrentResult {
    FocusCurrentResult(
        period: period, source: .network, pendingCount: 0,
        terminalIssues: [], failure: nil, localTaskIDsByBackendID: localTaskIDs
    )
}

private func focusVMPeriod(
    version: Int64,
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
        status: "active",
        version: version,
        progress: FocusProgressCalculator.current(items),
        items: items,
        rolloverOffer: rollover
    )
}

private func focusVMItem(
    taskID: UUID = UUID(),
    title: String,
    status: PlanningStatus = .todo,
    effort: Int? = 1,
    position: Int
) -> FocusItemDTO {
    FocusItemDTO(
        id: UUID(), taskId: taskID, title: title, status: status,
        effort: effort, effectiveWeight: max(effort ?? 0, 1),
        plannedTime: nil, dueTime: nil, position: position,
        historyOnly: false, folderId: UUID(), folderTitle: "Folder",
        goalId: UUID(), goalTitle: "Goal", shared: false, canWrite: true
    )
}

private func focusVMCandidate(
    taskID: UUID = UUID(),
    title: String,
    shared: Bool = false,
    canWrite: Bool = true
) -> FocusCandidateDTO {
    FocusCandidateDTO(
        taskId: taskID, title: title, status: .todo, effort: 1,
        effectiveWeight: 1, plannedTime: nil, dueTime: nil,
        folderId: UUID(), folderTitle: "Folder", goalId: UUID(), goalTitle: "Goal",
        shared: shared, canWrite: canWrite, inFocus: false
    )
}

private func focusVMHistory(id: UUID, weekStart: String) -> FocusHistorySummaryDTO {
    FocusHistorySummaryDTO(
        id: id,
        weekStart: LocalDate(rawValue: weekStart)!,
        weekEndExclusive: LocalDate(rawValue: "2026-08-24")!,
        startsAt: Date(timeIntervalSince1970: 1_787_001_200),
        endsAt: Date(timeIntervalSince1970: 1_787_606_000),
        timezone: "Europe/Moscow",
        status: "completed",
        version: 1,
        progress: FocusProgressDTO(
            completedWeight: 1, totalWeight: 1, percent: 100,
            completedCount: 1, totalCount: 1
        )
    )
}

private func focusVMSettings() -> FocusNotificationSettingsDTO {
    FocusNotificationSettingsDTO(
        intervalMinutes: 120,
        quietHoursStart: "22:00",
        quietHoursEnd: "08:00",
        version: 1
    )
}
