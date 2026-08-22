import Combine
import Foundation

@MainActor
final class FocusViewModel: ObservableObject {
    @Published private(set) var phase: FocusScreenPhase = .idle
    @Published private(set) var period: FocusPeriodDTO?
    @Published private(set) var pendingCount = 0
    @Published private(set) var terminalIssues: [FocusTerminalIssue] = []
    @Published private(set) var failure: FocusFailure?
    @Published private(set) var isMutating = false
    @Published private(set) var localTaskIDsByBackendID: [UUID: UUID] = [:]

    @Published var candidateQuery = ""
    @Published private(set) var candidatePhase: FocusScreenPhase = .idle
    @Published private(set) var candidates: [FocusCandidateDTO] = []
    @Published private(set) var candidateCursor: String?
    @Published private(set) var candidateFailure: FocusFailure?

    @Published private(set) var historyPhase: FocusScreenPhase = .idle
    @Published private(set) var history: [FocusHistorySummaryDTO] = []
    @Published private(set) var historyFailure: FocusFailure?
    @Published private(set) var selectedHistoryPeriod: FocusPeriodDTO?

    @Published private(set) var settingsPhase: FocusScreenPhase = .idle
    @Published private(set) var settings: FocusNotificationSettingsDTO?
    @Published private(set) var settingsFailure: FocusFailure?
    @Published private(set) var cadenceValidationMessage: String?

    @Published private(set) var rolloverSelection: Set<UUID> = []

    let language: AppLanguage
    let timezone: String

    private let accountID: UUID
    private let repository: any FocusRepositoryServing
    private let onOpenTask: (UUID) -> Void
    private let onUnauthorized: () -> Void
    private var currentGeneration: UInt64 = 0
    private var candidateGeneration: UInt64 = 0
    private var historyGeneration: UInt64 = 0
    private var settingsGeneration: UInt64 = 0
    private var candidateSearchTask: Task<Void, Never>?
    private var activeRolloverSourceID: UUID?
    private var didHandleUnauthorized = false

    init(
        accountID: UUID,
        timezone: String,
        language: AppLanguage,
        repository: any FocusRepositoryServing,
        onOpenTask: @escaping (UUID) -> Void,
        onUnauthorized: @escaping () -> Void = {}
    ) {
        self.accountID = accountID
        self.timezone = timezone
        self.language = language
        self.repository = repository
        self.onOpenTask = onOpenTask
        self.onUnauthorized = onUnauthorized
    }

    var copy: FocusCopy { FocusCopy(language: language) }

    var activeItems: [FocusItemDTO] {
        period?.items.filter { !$0.historyOnly }.sorted { lhs, rhs in
            lhs.position == rhs.position
                ? lhs.taskId.uuidString.lowercased() < rhs.taskId.uuidString.lowercased()
                : lhs.position < rhs.position
        } ?? []
    }

    var progress: FocusProgressDTO {
        FocusProgressCalculator.current(period?.items ?? [])
    }

    var candidateGroups: [FocusCandidateFolderGroup] {
        FocusCandidateCollection.hierarchy(candidates, language: language)
    }

    var isOffline: Bool { phase == .offline }
    var hasPendingWork: Bool { pendingCount > 0 }

    func loadIfNeeded() async {
        guard period == nil, phase != .loading else { return }
        await reloadCurrent()
    }

    func reloadCurrent() async {
        currentGeneration &+= 1
        let generation = currentGeneration
        phase = .loading
        failure = nil
        do {
            let result = try await repository.loadCurrent(accountID: accountID, timezone: timezone)
            guard generation == currentGeneration else { return }
            apply(result)
        } catch is CancellationError {
            guard generation == currentGeneration else { return }
            phase = period == nil ? .idle : .loaded
        } catch {
            guard generation == currentGeneration else { return }
            handleCurrentError(error)
        }
    }

    func localTaskID(for backendTaskID: UUID) -> UUID? {
        localTaskIDsByBackendID[backendTaskID]
    }

    func openTask(_ backendTaskID: UUID) {
        guard let localTaskID = localTaskID(for: backendTaskID) else { return }
        onOpenTask(localTaskID)
    }

    func taskNavigationHint(for backendTaskID: UUID) -> String {
        localTaskID(for: backendTaskID) == nil ? copy.taskUnavailable : copy.openTask
    }

    func add(_ candidate: FocusCandidateDTO) async {
        let applied = await mutate {
            try await repository.add(accountID: accountID, candidate: candidate)
        }
        if applied {
            candidates.removeAll { $0.taskId == candidate.taskId }
        }
    }

    func remove(taskID: UUID) async {
        let applied = await mutate {
            try await repository.remove(accountID: accountID, taskID: taskID)
        }
        if applied, phase != .unauthorized {
            await reloadCandidates()
        }
    }

    func move(taskID: UUID, by offset: Int) async {
        guard let source = activeItems.firstIndex(where: { $0.taskId == taskID }) else { return }
        let destination = source + offset
        guard activeItems.indices.contains(destination) else { return }
        var taskIDs = activeItems.map(\.taskId)
        taskIDs.swapAt(source, destination)
        await mutate {
            try await repository.reorder(accountID: accountID, taskIDs: taskIDs)
        }
    }

    func toggleRollover(taskID: UUID) {
        if rolloverSelection.contains(taskID) {
            rolloverSelection.remove(taskID)
        } else {
            rolloverSelection.insert(taskID)
        }
    }

    func resolveRollover() async {
        let orderedSelection = period?.rolloverOffer?.items.compactMap {
            rolloverSelection.contains($0.taskId) ? $0.taskId : nil
        } ?? []
        await mutate {
            try await repository.resolveRollover(
                accountID: accountID,
                selectedTaskIDs: orderedSelection
            )
        }
    }

    func retryPending() async {
        isMutating = true
        defer { isMutating = false }
        await synchronizePending()
    }

    func reloadCandidates() async {
        candidateSearchTask?.cancel()
        candidateGeneration &+= 1
        await loadCandidatePage(reset: true, generation: candidateGeneration)
    }

    func scheduleCandidateSearch(_ value: String) {
        candidateQuery = value
        candidateSearchTask?.cancel()
        candidateGeneration &+= 1
        let generation = candidateGeneration
        candidateSearchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await self?.loadCandidatePage(reset: true, generation: generation)
            } catch {
                return
            }
        }
    }

    func loadMoreCandidates() async {
        guard candidateCursor != nil, candidatePhase != .loading else { return }
        await loadCandidatePage(reset: false, generation: candidateGeneration)
    }

    func loadHistory() async {
        historyGeneration &+= 1
        let generation = historyGeneration
        historyPhase = .loading
        historyFailure = nil
        do {
            let result = try await repository.loadHistory(accountID: accountID)
            guard generation == historyGeneration else { return }
            history = result.items.sorted { lhs, rhs in
                lhs.weekStart.rawValue == rhs.weekStart.rawValue
                    ? lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
                    : lhs.weekStart.rawValue > rhs.weekStart.rawValue
            }
            historyFailure = result.failure
            historyPhase = result.source == .network ? .loaded : .offline
        } catch is CancellationError {
            return
        } catch {
            guard generation == historyGeneration else { return }
            if handleUnauthorized(error) { return }
            historyFailure = FocusFailure(error)
            historyPhase = .error
        }
    }

    func loadHistoryDetail(periodID: UUID) async {
        historyGeneration &+= 1
        let generation = historyGeneration
        selectedHistoryPeriod = nil
        historyPhase = .loading
        do {
            let result = try await repository.loadHistoryDetail(accountID: accountID, periodID: periodID)
            guard generation == historyGeneration else { return }
            selectedHistoryPeriod = result.period
            localTaskIDsByBackendID.merge(result.localTaskIDsByBackendID) { _, new in new }
            historyFailure = result.failure
            historyPhase = result.source == .network ? .loaded : .offline
        } catch is CancellationError {
            return
        } catch {
            guard generation == historyGeneration else { return }
            if handleUnauthorized(error) { return }
            historyFailure = FocusFailure(error)
            historyPhase = .error
        }
    }

    func closeHistoryDetail() {
        historyGeneration &+= 1
        selectedHistoryPeriod = nil
        historyPhase = history.isEmpty ? .idle : .loaded
    }

    func loadSettings() async {
        settingsGeneration &+= 1
        let generation = settingsGeneration
        settingsPhase = .loading
        settingsFailure = nil
        cadenceValidationMessage = nil
        do {
            let result = try await repository.loadSettings(accountID: accountID)
            guard generation == settingsGeneration else { return }
            settings = result.settings
            settingsFailure = result.failure
            settingsPhase = result.source == .network ? .loaded : .offline
        } catch is CancellationError {
            return
        } catch {
            guard generation == settingsGeneration else { return }
            if handleUnauthorized(error) { return }
            settingsFailure = FocusFailure(error)
            settingsPhase = .error
        }
    }

    @discardableResult
    func saveSettings(_ values: FocusCadenceValues) async -> Bool {
        cadenceValidationMessage = nil
        do {
            try FocusCadenceValidator.validate(values)
        } catch let validation as FocusCadenceValidationError {
            cadenceValidationMessage = validationMessage(validation)
            return false
        } catch {
            cadenceValidationMessage = copy.unavailable
            return false
        }

        settingsPhase = .loading
        settingsGeneration &+= 1
        do {
            let result = try await repository.updateSettings(accountID: accountID, values: values)
            settings = result.settings
            settingsFailure = nil
            settingsPhase = .loaded
            await synchronizePending()
            return settingsPhase != .unauthorized && settingsPhase != .error
        } catch {
            if handleUnauthorized(error) { return false }
            settingsFailure = FocusFailure(error)
            settingsPhase = .error
            return false
        }
    }

    @discardableResult
    private func mutate(
        _ operation: () async throws -> FocusCurrentResult
    ) async -> Bool {
        guard !isMutating else { return false }
        currentGeneration &+= 1
        isMutating = true
        defer { isMutating = false }
        do {
            let optimistic = try await operation()
            apply(optimistic)
            await synchronizePending()
            return true
        } catch {
            handleCurrentError(error)
            return false
        }
    }

    private func synchronizePending() async {
        currentGeneration &+= 1
        settingsGeneration &+= 1
        do {
            let result = try await repository.syncPending(accountID: accountID, timezone: timezone)
            if let current = result.current { period = current }
            if let updatedSettings = result.settings { settings = updatedSettings }
            localTaskIDsByBackendID.merge(result.localTaskIDsByBackendID) { _, new in new }
            pendingCount = result.pendingCount
            terminalIssues = result.terminalIssues
            failure = nil
            phase = .loaded
            if settings != nil { settingsPhase = .loaded }
        } catch {
            if handleUnauthorized(error) { return }
            failure = FocusFailure(error)
            phase = .offline
            if settings != nil { settingsPhase = .offline }
            pendingCount = max(pendingCount, 1)
        }
    }

    private func loadCandidatePage(reset: Bool, generation: UInt64) async {
        guard generation == candidateGeneration else { return }
        candidatePhase = .loading
        candidateFailure = nil
        let query = candidateQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let cursor = reset ? nil : candidateCursor
        do {
            let page = try await repository.loadCandidates(
                accountID: accountID,
                query: query.isEmpty ? nil : query,
                folderID: nil,
                goalID: nil,
                cursor: cursor,
                limit: 100
            )
            guard generation == candidateGeneration else { return }
            candidates = FocusCandidateCollection.merge(
                existing: reset ? [] : candidates,
                incoming: page.items,
                selectedTaskIDs: Set(activeItems.map(\.taskId))
            )
            candidateCursor = page.nextCursor
            candidatePhase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard generation == candidateGeneration else { return }
            if handleUnauthorized(error) { return }
            candidateFailure = FocusFailure(error)
            candidatePhase = .error
        }
    }

    private func apply(_ result: FocusCurrentResult) {
        period = result.period
        localTaskIDsByBackendID.merge(result.localTaskIDsByBackendID) { _, new in new }
        pendingCount = result.pendingCount
        terminalIssues = result.terminalIssues
        failure = result.failure
        phase = result.source == .network || result.source == .optimistic ? .loaded : .offline
        didHandleUnauthorized = false
        updateRolloverSelection()
    }

    private func updateRolloverSelection() {
        let offer = period?.rolloverOffer
        guard offer?.sourcePeriodId != activeRolloverSourceID else { return }
        activeRolloverSourceID = offer?.sourcePeriodId
        rolloverSelection = Set(offer?.items.map(\.taskId) ?? [])
    }

    private func handleCurrentError(_ error: Error) {
        if handleUnauthorized(error) { return }
        failure = FocusFailure(error)
        phase = period == nil ? .error : .offline
    }

    private func handleUnauthorized(_ error: Error) -> Bool {
        guard let api = error as? APIError, api.isUnauthorized else { return false }
        currentGeneration &+= 1
        candidateGeneration &+= 1
        historyGeneration &+= 1
        settingsGeneration &+= 1
        candidateSearchTask?.cancel()
        candidateSearchTask = nil
        period = nil
        pendingCount = 0
        terminalIssues = []
        localTaskIDsByBackendID = [:]
        candidateQuery = ""
        candidates = []
        candidateCursor = nil
        candidateFailure = nil
        history = []
        historyFailure = nil
        selectedHistoryPeriod = nil
        settings = nil
        settingsFailure = nil
        cadenceValidationMessage = nil
        rolloverSelection = []
        activeRolloverSourceID = nil
        failure = FocusFailure(api)
        phase = .unauthorized
        candidatePhase = .unauthorized
        historyPhase = .unauthorized
        settingsPhase = .unauthorized
        if !didHandleUnauthorized {
            didHandleUnauthorized = true
            onUnauthorized()
        }
        return true
    }

    private func validationMessage(_ error: FocusCadenceValidationError) -> String {
        switch error {
        case .unsupportedInterval: copy.cadenceInvalid
        case .quietHoursPairRequired: copy.quietPairInvalid
        case .invalidQuietHours: copy.quietTimeInvalid
        }
    }
}
