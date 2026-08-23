import Foundation

protocol FocusRequestSending: Sendable {
    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response
}

extension AuthSession: FocusRequestSending {}

protocol FocusRemoteServing: Sendable {
    func current() async throws -> FocusPeriodDTO
    func candidates(
        query: String?,
        folderID: UUID?,
        goalID: UUID?,
        cursor: String?,
        limit: Int
    ) async throws -> FocusCandidateListResponseDTO
    func add(taskID: UUID, version: Int64?, idempotencyKey: String) async throws -> FocusPeriodDTO
    func remove(taskID: UUID, version: Int64?, idempotencyKey: String) async throws -> FocusPeriodDTO
    func reorder(taskIDs: [UUID], version: Int64?, idempotencyKey: String) async throws -> FocusPeriodDTO
    func resolveRollover(
        sourcePeriodID: UUID,
        taskIDs: [UUID],
        version: Int64?,
        idempotencyKey: String
    ) async throws -> FocusPeriodDTO
    func history() async throws -> FocusHistoryResponseDTO
    func historyDetail(periodID: UUID) async throws -> FocusPeriodDTO
    func settings() async throws -> FocusNotificationSettingsDTO
    func updateSettings(_ values: FocusCadenceValues, version: Int64) async throws -> FocusNotificationSettingsDTO
}

protocol FocusTaskIDMapping: Sendable {
    func localTaskID(forBackendTaskID backendTaskID: UUID) async throws -> UUID?
}

struct PersistedFocusTaskIDMappingAdapter: FocusTaskIDMapping {
    typealias MappingLookup = @Sendable (UUID) async throws -> UUID?
    typealias LocalIdentityLookup = @Sendable (UUID) async throws -> Bool

    private let mappedLocalID: MappingLookup
    private let isKnownLocalID: LocalIdentityLookup

    init(
        mappedLocalID: @escaping MappingLookup,
        isKnownLocalID: @escaping LocalIdentityLookup
    ) {
        self.mappedLocalID = mappedLocalID
        self.isKnownLocalID = isKnownLocalID
    }

    func localTaskID(forBackendTaskID backendTaskID: UUID) async throws -> UUID? {
        if let localID = try await mappedLocalID(backendTaskID) {
            return localID
        }
        return try await isKnownLocalID(backendTaskID) ? backendTaskID : nil
    }
}

struct UnavailableFocusTaskIDMapping: FocusTaskIDMapping {
    func localTaskID(forBackendTaskID backendTaskID: UUID) -> UUID? { nil }
}

struct AuthenticatedFocusRemote: FocusRemoteServing {
    private let sender: any FocusRequestSending

    init(sender: any FocusRequestSending) {
        self.sender = sender
    }

    func current() async throws -> FocusPeriodDTO {
        try await sender.send(FocusEndpoints.current)
    }

    func candidates(
        query: String?,
        folderID: UUID?,
        goalID: UUID?,
        cursor: String?,
        limit: Int
    ) async throws -> FocusCandidateListResponseDTO {
        try await sender.send(
            FocusEndpoints.candidates(
                query: query,
                folderID: folderID,
                goalID: goalID,
                cursor: cursor,
                limit: limit
            )
        )
    }

    func add(taskID: UUID, version: Int64?, idempotencyKey: String) async throws -> FocusPeriodDTO {
        try await sender.send(
            Endpoint(
                method: .put,
                path: ["focus", "current", "items", taskID.uuidString.lowercased()],
                body: FocusMutationRequestDTO(periodVersion: version, idempotencyKey: idempotencyKey)
            )
        )
    }

    func remove(taskID: UUID, version: Int64?, idempotencyKey: String) async throws -> FocusPeriodDTO {
        try await sender.send(
            Endpoint(
                method: .delete,
                path: ["focus", "current", "items", taskID.uuidString.lowercased()],
                body: FocusMutationRequestDTO(periodVersion: version, idempotencyKey: idempotencyKey)
            )
        )
    }

    func reorder(taskIDs: [UUID], version: Int64?, idempotencyKey: String) async throws -> FocusPeriodDTO {
        try await sender.send(
            Endpoint(
                method: .patch,
                path: ["focus", "current", "items", "order"],
                body: FocusReorderRequestDTO(
                    taskIds: taskIDs,
                    periodVersion: version,
                    idempotencyKey: idempotencyKey
                )
            )
        )
    }

    func resolveRollover(
        sourcePeriodID: UUID,
        taskIDs: [UUID],
        version: Int64?,
        idempotencyKey: String
    ) async throws -> FocusPeriodDTO {
        try await sender.send(
            Endpoint(
                method: .post,
                path: ["focus", "rollovers", sourcePeriodID.uuidString.lowercased(), "resolve"],
                body: FocusResolveRolloverRequestDTO(
                    taskIds: taskIDs,
                    periodVersion: version,
                    idempotencyKey: idempotencyKey
                )
            )
        )
    }

    func history() async throws -> FocusHistoryResponseDTO {
        try await sender.send(Endpoint(method: .get, path: ["focus", "history"]))
    }

    func historyDetail(periodID: UUID) async throws -> FocusPeriodDTO {
        try await sender.send(
            Endpoint(method: .get, path: ["focus", "history", periodID.uuidString.lowercased()])
        )
    }

    func settings() async throws -> FocusNotificationSettingsDTO {
        try await sender.send(FocusEndpoints.settings)
    }

    func updateSettings(_ values: FocusCadenceValues, version: Int64) async throws -> FocusNotificationSettingsDTO {
        try await sender.send(
            Endpoint(
                method: .patch,
                path: ["focus", "notification-settings"],
                body: FocusNotificationSettingsRequestDTO(
                    intervalMinutes: values.intervalMinutes,
                    quietHoursStart: values.quietHoursStart,
                    quietHoursEnd: values.quietHoursEnd,
                    version: version
                )
            )
        )
    }
}

struct FocusCadenceValues: Codable, Equatable, Sendable {
    let intervalMinutes: Int?
    let quietHoursStart: String?
    let quietHoursEnd: String?

    static let defaults = FocusCadenceValues(
        intervalMinutes: 120,
        quietHoursStart: "22:00",
        quietHoursEnd: "08:00"
    )
}

enum FocusCadenceValidationError: Error, Equatable, Sendable {
    case unsupportedInterval
    case quietHoursPairRequired
    case invalidQuietHours
}

enum FocusCadenceValidator {
    static let allowedIntervals: Set<Int> = [30, 60, 120, 240]

    static func validate(_ values: FocusCadenceValues) throws {
        if let interval = values.intervalMinutes, !allowedIntervals.contains(interval) {
            throw FocusCadenceValidationError.unsupportedInterval
        }
        guard (values.quietHoursStart == nil) == (values.quietHoursEnd == nil) else {
            throw FocusCadenceValidationError.quietHoursPairRequired
        }
        if let start = values.quietHoursStart, let end = values.quietHoursEnd {
            guard isStrictTime(start), isStrictTime(end) else {
                throw FocusCadenceValidationError.invalidQuietHours
            }
        }
    }

    private static func isStrictTime(_ value: String) -> Bool {
        guard value.count == 5 else { return false }
        let characters = Array(value)
        guard characters[2] == ":",
              let hour = Int(String(characters[0...1])),
              let minute = Int(String(characters[3...4])) else {
            return false
        }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }
}

enum FocusPendingActionKind: String, Codable, Equatable, Sendable {
    case add
    case remove
    case reorder
    case rollover
    case settings
}

struct FocusPendingAction: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let accountID: UUID
    let kind: FocusPendingActionKind
    let taskID: UUID?
    let taskIDs: [UUID]
    let sourcePeriodID: UUID?
    let expectedVersion: Int64
    let candidate: FocusCandidateDTO?
    let cadence: FocusCadenceValues?
    var conflictAttempts: Int
    let createdAt: Date
}

struct FocusTerminalIssue: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let actionID: UUID
    let kind: FocusPendingActionKind
    let code: String
    let conflictAttempts: Int
    let createdAt: Date
}

protocol FocusActionQueuing: Sendable {
    func enqueue(_ action: FocusPendingAction) async throws
    /// Must return actions in durable enqueue order for the requested account.
    func pending(accountID: UUID) async throws -> [FocusPendingAction]
    func acknowledge(accountID: UUID, actionID: UUID) async throws
    func incrementConflict(accountID: UUID, actionID: UUID) async throws -> FocusPendingAction
    func terminalize(accountID: UUID, actionID: UUID, code: String, at: Date) async throws
    func terminalIssues(accountID: UUID) async throws -> [FocusTerminalIssue]
    func clear(accountID: UUID) async throws
}

#if DEBUG
/// Explicit preview/test adapter. Production composition must inject durable storage.
actor InMemoryFocusActionQueue: FocusActionQueuing {
    private var actions: [UUID: [FocusPendingAction]] = [:]
    private var issues: [UUID: [FocusTerminalIssue]] = [:]

    func enqueue(_ action: FocusPendingAction) {
        var accountActions = actions[action.accountID, default: []]
        guard !accountActions.contains(where: { $0.id == action.id }) else { return }
        accountActions.append(action)
        actions[action.accountID] = accountActions
    }

    func pending(accountID: UUID) -> [FocusPendingAction] {
        actions[accountID, default: []]
    }

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
        issues[accountID, default: []].append(
            FocusTerminalIssue(
                id: UUID(),
                actionID: action.id,
                kind: action.kind,
                code: code,
                conflictAttempts: action.conflictAttempts,
                createdAt: at
            )
        )
        actions[accountID]?.removeAll { $0.id == actionID }
    }

    func terminalIssues(accountID: UUID) -> [FocusTerminalIssue] {
        issues[accountID, default: []]
    }

    func clear(accountID: UUID) {
        actions.removeValue(forKey: accountID)
        issues.removeValue(forKey: accountID)
    }
}
#endif

protocol FocusCaching: Sendable {
    func current(accountID: UUID) async throws -> FocusPeriodDTO?
    func saveCurrent(_ period: FocusPeriodDTO, accountID: UUID) async throws
    func history(accountID: UUID) async throws -> [FocusHistorySummaryDTO]?
    func saveHistory(_ history: [FocusHistorySummaryDTO], accountID: UUID) async throws
    func historyDetail(accountID: UUID, periodID: UUID) async throws -> FocusPeriodDTO?
    func saveHistoryDetail(_ period: FocusPeriodDTO, accountID: UUID) async throws
    func settings(accountID: UUID) async throws -> FocusNotificationSettingsDTO?
    func saveSettings(_ settings: FocusNotificationSettingsDTO, accountID: UUID) async throws
    func clear(accountID: UUID) async throws
}

#if DEBUG
/// Explicit preview/test adapter. Production composition must inject durable storage.
actor InMemoryFocusCache: FocusCaching {
    private var currentPeriods: [UUID: FocusPeriodDTO] = [:]
    private var histories: [UUID: [FocusHistorySummaryDTO]] = [:]
    private var historyDetails: [UUID: [UUID: FocusPeriodDTO]] = [:]
    private var notificationSettings: [UUID: FocusNotificationSettingsDTO] = [:]

    func current(accountID: UUID) -> FocusPeriodDTO? { currentPeriods[accountID] }
    func saveCurrent(_ period: FocusPeriodDTO, accountID: UUID) { currentPeriods[accountID] = period }
    func history(accountID: UUID) -> [FocusHistorySummaryDTO]? { histories[accountID] }
    func saveHistory(_ history: [FocusHistorySummaryDTO], accountID: UUID) { histories[accountID] = history }
    func historyDetail(accountID: UUID, periodID: UUID) -> FocusPeriodDTO? {
        historyDetails[accountID]?[periodID]
    }
    func saveHistoryDetail(_ period: FocusPeriodDTO, accountID: UUID) {
        historyDetails[accountID, default: [:]][period.id] = period
    }
    func settings(accountID: UUID) -> FocusNotificationSettingsDTO? { notificationSettings[accountID] }
    func saveSettings(_ settings: FocusNotificationSettingsDTO, accountID: UUID) {
        notificationSettings[accountID] = settings
    }

    func clear(accountID: UUID) {
        currentPeriods.removeValue(forKey: accountID)
        histories.removeValue(forKey: accountID)
        historyDetails.removeValue(forKey: accountID)
        notificationSettings.removeValue(forKey: accountID)
    }
}
#endif

enum FocusLoadSource: Equatable, Sendable {
    case network
    case cache
    case optimistic
    case emptyOffline
}

struct FocusFailure: Equatable, Sendable {
    let code: String
    let statusCode: Int?

    init(_ error: Error) {
        if let api = error as? APIError {
            code = api.code
            statusCode = api.statusCode
        } else if let repository = error as? FocusRepositoryError {
            code = repository.code
            statusCode = nil
        } else {
            code = "focus_unavailable"
            statusCode = nil
        }
    }
}

struct FocusCurrentResult: Equatable, Sendable {
    let period: FocusPeriodDTO?
    let source: FocusLoadSource
    let pendingCount: Int
    let terminalIssues: [FocusTerminalIssue]
    let failure: FocusFailure?
    let localTaskIDsByBackendID: [UUID: UUID]

    init(
        period: FocusPeriodDTO?,
        source: FocusLoadSource,
        pendingCount: Int,
        terminalIssues: [FocusTerminalIssue],
        failure: FocusFailure?,
        localTaskIDsByBackendID: [UUID: UUID] = [:]
    ) {
        self.period = period
        self.source = source
        self.pendingCount = pendingCount
        self.terminalIssues = terminalIssues
        self.failure = failure
        self.localTaskIDsByBackendID = localTaskIDsByBackendID
    }
}

struct FocusHistoryResult: Equatable, Sendable {
    let items: [FocusHistorySummaryDTO]
    let source: FocusLoadSource
    let failure: FocusFailure?
}

struct FocusHistoryDetailResult: Equatable, Sendable {
    let period: FocusPeriodDTO?
    let source: FocusLoadSource
    let failure: FocusFailure?
    let localTaskIDsByBackendID: [UUID: UUID]

    init(
        period: FocusPeriodDTO?,
        source: FocusLoadSource,
        failure: FocusFailure?,
        localTaskIDsByBackendID: [UUID: UUID] = [:]
    ) {
        self.period = period
        self.source = source
        self.failure = failure
        self.localTaskIDsByBackendID = localTaskIDsByBackendID
    }
}

struct FocusSettingsResult: Equatable, Sendable {
    let settings: FocusNotificationSettingsDTO
    let source: FocusLoadSource
    let failure: FocusFailure?
}

struct FocusSyncResult: Equatable, Sendable {
    let current: FocusPeriodDTO?
    let settings: FocusNotificationSettingsDTO?
    let pendingCount: Int
    let terminalIssues: [FocusTerminalIssue]
    let acknowledgedCount: Int
    let localTaskIDsByBackendID: [UUID: UUID]

    init(
        current: FocusPeriodDTO?,
        settings: FocusNotificationSettingsDTO?,
        pendingCount: Int,
        terminalIssues: [FocusTerminalIssue],
        acknowledgedCount: Int,
        localTaskIDsByBackendID: [UUID: UUID] = [:]
    ) {
        self.current = current
        self.settings = settings
        self.pendingCount = pendingCount
        self.terminalIssues = terminalIssues
        self.acknowledgedCount = acknowledgedCount
        self.localTaskIDsByBackendID = localTaskIDsByBackendID
    }
}

enum FocusRepositoryError: Error, Equatable, Sendable {
    case currentPeriodMissing
    case invalidOrder
    case invalidRolloverSelection
    case pendingActionMissing
    case retryable(code: String, statusCode: Int?)

    var code: String {
        switch self {
        case .currentPeriodMissing: "focus_current_missing"
        case .invalidOrder: "focus_order_invalid"
        case .invalidRolloverSelection: "focus_rollover_invalid"
        case .pendingActionMissing: "focus_pending_missing"
        case let .retryable(code, _): code
        }
    }
}

enum FocusProgressCalculator {
    static func current(_ items: [FocusItemDTO]) -> FocusProgressDTO {
        calculate(items.filter { !$0.historyOnly })
    }

    static func history(_ items: [FocusItemDTO]) -> FocusProgressDTO {
        calculate(items)
    }

    private static func calculate(_ items: [FocusItemDTO]) -> FocusProgressDTO {
        let totalWeight = items.reduce(0) { $0 + max($1.effectiveWeight, 1) }
        let completed = items.filter { $0.status == .done }
        let completedWeight = completed.reduce(0) { $0 + max($1.effectiveWeight, 1) }
        let percent = totalWeight == 0
            ? 0
            : min(max(Int((Double(completedWeight) * 100.0 / Double(totalWeight)).rounded()), 0), 100)
        return FocusProgressDTO(
            completedWeight: completedWeight,
            totalWeight: totalWeight,
            percent: percent,
            completedCount: completed.count,
            totalCount: items.count
        )
    }
}

protocol FocusRepositoryServing: Sendable {
    func loadCurrent(accountID: UUID, timezone: String) async throws -> FocusCurrentResult
    func loadCandidates(
        accountID: UUID, query: String?, folderID: UUID?, goalID: UUID?, cursor: String?, limit: Int
    ) async throws -> FocusCandidateListResponseDTO
    func add(accountID: UUID, candidate: FocusCandidateDTO) async throws -> FocusCurrentResult
    func remove(accountID: UUID, taskID: UUID) async throws -> FocusCurrentResult
    func reorder(accountID: UUID, taskIDs: [UUID]) async throws -> FocusCurrentResult
    func resolveRollover(accountID: UUID, selectedTaskIDs: [UUID]) async throws -> FocusCurrentResult
    func loadHistory(accountID: UUID) async throws -> FocusHistoryResult
    func loadHistoryDetail(accountID: UUID, periodID: UUID) async throws -> FocusHistoryDetailResult
    func loadSettings(accountID: UUID) async throws -> FocusSettingsResult
    func updateSettings(accountID: UUID, values: FocusCadenceValues) async throws -> FocusSettingsResult
    func syncPending(accountID: UUID, timezone: String) async throws -> FocusSyncResult
    func cancelAndAwaitPendingSync(accountID: UUID) async
}

extension FocusRepositoryServing {
    func cancelAndAwaitPendingSync(accountID: UUID) async {}
}

actor FocusRepository: FocusRepositoryServing {
    private static let maxConflictAttempts = 3

    private struct SyncFlight {
        let id: UUID
        let task: Task<FocusSyncResult, Error>
    }

    private let remote: any FocusRemoteServing
    private let cache: any FocusCaching
    private let queue: any FocusActionQueuing
    private let taskIDMapping: any FocusTaskIDMapping
    private let now: @Sendable () -> Date
    private let actionID: @Sendable () -> UUID
    private var syncFlights: [UUID: SyncFlight] = [:]

    init(
        remote: any FocusRemoteServing,
        cache: any FocusCaching,
        queue: any FocusActionQueuing,
        taskIDMapping: any FocusTaskIDMapping = UnavailableFocusTaskIDMapping(),
        now: @escaping @Sendable () -> Date = Date.init,
        actionID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.remote = remote
        self.cache = cache
        self.queue = queue
        self.taskIDMapping = taskIDMapping
        self.now = now
        self.actionID = actionID
    }

    init(
        sender: any FocusRequestSending,
        cache: any FocusCaching,
        queue: any FocusActionQueuing,
        taskIDMapping: any FocusTaskIDMapping = UnavailableFocusTaskIDMapping(),
        now: @escaping @Sendable () -> Date = Date.init,
        actionID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        remote = AuthenticatedFocusRemote(sender: sender)
        self.cache = cache
        self.queue = queue
        self.taskIDMapping = taskIDMapping
        self.now = now
        self.actionID = actionID
    }

    func loadCurrent(accountID: UUID, timezone: String) async throws -> FocusCurrentResult {
        do {
            if !(try await queue.pending(accountID: accountID)).isEmpty {
                _ = try await syncPending(accountID: accountID, timezone: timezone)
            }
            let period = normalizedCurrent(try await remote.current())
            if !(try await queue.pending(accountID: accountID)).isEmpty {
                let synchronized = try await syncPending(accountID: accountID, timezone: timezone)
                if let current = synchronized.current {
                    return try await currentResult(
                        accountID: accountID,
                        period: current,
                        source: .network,
                        failure: nil
                    )
                }
            }
            if let cached = try? await cache.current(accountID: accountID), cached.version > period.version {
                return try await currentResult(
                    accountID: accountID,
                    period: cached,
                    source: .cache,
                    failure: nil
                )
            }
            try? await cache.saveCurrent(period, accountID: accountID)
            return try await currentResult(accountID: accountID, period: period, source: .network, failure: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch let api as APIError where api.isUnauthorized {
            await clearAccountState(accountID)
            throw api
        } catch {
            let cached = try? await cache.current(accountID: accountID)
            return try await currentResult(
                accountID: accountID,
                period: cached,
                source: cached == nil ? .emptyOffline : .cache,
                failure: FocusFailure(error)
            )
        }
    }

    func loadCandidates(
        accountID: UUID,
        query: String?,
        folderID: UUID?,
        goalID: UUID?,
        cursor: String?,
        limit: Int
    ) async throws -> FocusCandidateListResponseDTO {
        do {
            return try await remote.candidates(
                query: query?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
                folderID: folderID,
                goalID: goalID,
                cursor: cursor,
                limit: min(max(limit, 1), 100)
            )
        } catch let api as APIError where api.isUnauthorized {
            await clearAccountState(accountID)
            throw api
        }
    }

    func add(accountID: UUID, candidate: FocusCandidateDTO) async throws -> FocusCurrentResult {
        let period = try await requireCurrent(accountID)
        if period.items.contains(where: { !$0.historyOnly && $0.taskId == candidate.taskId }) {
            return try await currentResult(accountID: accountID, period: period, source: .optimistic, failure: nil)
        }
        let action = makeAction(
            accountID: accountID,
            kind: .add,
            taskID: candidate.taskId,
            expectedVersion: period.version,
            candidate: candidate
        )
        try await queue.enqueue(action)
        let updated = replacingItems(period, items: period.items + [optimisticItem(candidate, position: period.items.count)])
        try await cache.saveCurrent(updated, accountID: accountID)
        return try await currentResult(accountID: accountID, period: updated, source: .optimistic, failure: nil)
    }

    func remove(accountID: UUID, taskID: UUID) async throws -> FocusCurrentResult {
        let period = try await requireCurrent(accountID)
        let action = makeAction(
            accountID: accountID,
            kind: .remove,
            taskID: taskID,
            expectedVersion: period.version
        )
        try await queue.enqueue(action)
        let updated = replacingItems(period, items: period.items.filter { $0.taskId != taskID })
        try await cache.saveCurrent(updated, accountID: accountID)
        return try await currentResult(accountID: accountID, period: updated, source: .optimistic, failure: nil)
    }

    func reorder(accountID: UUID, taskIDs: [UUID]) async throws -> FocusCurrentResult {
        let period = try await requireCurrent(accountID)
        let active = orderedItems(period.items).filter { !$0.historyOnly }
        guard Set(taskIDs).count == taskIDs.count,
              Set(taskIDs) == Set(active.map(\.taskId)) else {
            throw FocusRepositoryError.invalidOrder
        }
        let action = makeAction(
            accountID: accountID,
            kind: .reorder,
            taskIDs: taskIDs,
            expectedVersion: period.version
        )
        try await queue.enqueue(action)
        let byTask = Dictionary(uniqueKeysWithValues: active.map { ($0.taskId, $0) })
        let reordered = taskIDs.enumerated().compactMap { index, taskID in
            byTask[taskID].map { copyItem($0, position: index) }
        } + period.items.filter(\.historyOnly)
        let updated = replacingItems(period, items: reordered)
        try await cache.saveCurrent(updated, accountID: accountID)
        return try await currentResult(accountID: accountID, period: updated, source: .optimistic, failure: nil)
    }

    func resolveRollover(accountID: UUID, selectedTaskIDs: [UUID]) async throws -> FocusCurrentResult {
        let period = try await requireCurrent(accountID)
        guard let offer = period.rolloverOffer else { throw FocusRepositoryError.invalidRolloverSelection }
        let offered = Set(offer.items.map(\.taskId))
        guard Set(selectedTaskIDs).count == selectedTaskIDs.count,
              Set(selectedTaskIDs).isSubset(of: offered) else {
            throw FocusRepositoryError.invalidRolloverSelection
        }
        let action = makeAction(
            accountID: accountID,
            kind: .rollover,
            taskIDs: selectedTaskIDs,
            sourcePeriodID: offer.sourcePeriodId,
            expectedVersion: period.version
        )
        try await queue.enqueue(action)
        let currentTaskIDs = Set(period.items.map(\.taskId))
        let offeredByTask = Dictionary(uniqueKeysWithValues: offer.items.map { ($0.taskId, $0) })
        var items = period.items
        for taskID in selectedTaskIDs where !currentTaskIDs.contains(taskID) {
            if let offeredItem = offeredByTask[taskID] {
                items.append(copyItem(offeredItem, id: taskID, position: items.count, historyOnly: false))
            }
        }
        let updated = replacingItems(period, items: items, clearRolloverOffer: true)
        try await cache.saveCurrent(updated, accountID: accountID)
        return try await currentResult(accountID: accountID, period: updated, source: .optimistic, failure: nil)
    }

    func loadHistory(accountID: UUID) async throws -> FocusHistoryResult {
        do {
            let items = (try await remote.history()).items
            try? await cache.saveHistory(items, accountID: accountID)
            return FocusHistoryResult(items: items, source: .network, failure: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch let api as APIError where api.isUnauthorized {
            await clearAccountState(accountID)
            throw api
        } catch {
            let cached = try? await cache.history(accountID: accountID)
            return FocusHistoryResult(
                items: cached ?? [],
                source: cached == nil ? .emptyOffline : .cache,
                failure: FocusFailure(error)
            )
        }
    }

    func loadHistoryDetail(accountID: UUID, periodID: UUID) async throws -> FocusHistoryDetailResult {
        do {
            let period = normalizedHistory(try await remote.historyDetail(periodID: periodID))
            try? await cache.saveHistoryDetail(period, accountID: accountID)
            return FocusHistoryDetailResult(
                period: period,
                source: .network,
                failure: nil,
                localTaskIDsByBackendID: try await resolveLocalTaskIDs(in: period)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let api as APIError where api.isUnauthorized {
            await clearAccountState(accountID)
            throw api
        } catch {
            let cached = (try? await cache.historyDetail(accountID: accountID, periodID: periodID))
                .map { normalizedHistory($0) }
            let localTaskIDs: [UUID: UUID]
            if let cached {
                localTaskIDs = try await resolveLocalTaskIDs(in: cached)
            } else {
                localTaskIDs = [:]
            }
            return FocusHistoryDetailResult(
                period: cached,
                source: cached == nil ? .emptyOffline : .cache,
                failure: FocusFailure(error),
                localTaskIDsByBackendID: localTaskIDs
            )
        }
    }

    func loadSettings(accountID: UUID) async throws -> FocusSettingsResult {
        do {
            let settings = try await remote.settings()
            let pendingActions = try await queue.pending(accountID: accountID)
            let hasPendingSettings = pendingActions.contains { $0.kind == .settings }
            if hasPendingSettings, let cached = try? await cache.settings(accountID: accountID) {
                return FocusSettingsResult(settings: cached, source: .optimistic, failure: nil)
            }
            if let cached = try? await cache.settings(accountID: accountID), cached.version > settings.version {
                return FocusSettingsResult(settings: cached, source: .cache, failure: nil)
            }
            try? await cache.saveSettings(settings, accountID: accountID)
            return FocusSettingsResult(settings: settings, source: .network, failure: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch let api as APIError where api.isUnauthorized {
            await clearAccountState(accountID)
            throw api
        } catch {
            let cached = try? await cache.settings(accountID: accountID)
            return FocusSettingsResult(
                settings: cached ?? defaultSettings(),
                source: cached == nil ? .emptyOffline : .cache,
                failure: FocusFailure(error)
            )
        }
    }

    func updateSettings(accountID: UUID, values: FocusCadenceValues) async throws -> FocusSettingsResult {
        try FocusCadenceValidator.validate(values)
        let current = try await cache.settings(accountID: accountID) ?? defaultSettings()
        let action = makeAction(
            accountID: accountID,
            kind: .settings,
            expectedVersion: current.version,
            cadence: values
        )
        try await queue.enqueue(action)
        let optimistic = FocusNotificationSettingsDTO(
            intervalMinutes: values.intervalMinutes,
            quietHoursStart: values.quietHoursStart,
            quietHoursEnd: values.quietHoursEnd,
            version: current.version
        )
        try await cache.saveSettings(optimistic, accountID: accountID)
        return FocusSettingsResult(settings: optimistic, source: .optimistic, failure: nil)
    }

    func syncPending(accountID: UUID, timezone: String) async throws -> FocusSyncResult {
        try Task.checkCancellation()
        if let flight = syncFlights[accountID] {
            return try await awaitSyncFlight(flight, accountID: accountID)
        }

        let flightID = UUID()
        let task: Task<FocusSyncResult, Error> = Task { [self] in
            try Task.checkCancellation()
            try await performSyncPending(accountID: accountID, timezone: timezone)
        }
        let flight = SyncFlight(id: flightID, task: task)
        syncFlights[accountID] = flight
        return try await awaitSyncFlight(flight, accountID: accountID)
    }

    private func performSyncPending(accountID: UUID, timezone: String) async throws -> FocusSyncResult {
        try Task.checkCancellation()
        var current = try? await cache.current(accountID: accountID)
        var settings = try? await cache.settings(accountID: accountID)
        var acknowledged = 0
        try Task.checkCancellation()

        for original in try await queue.pending(accountID: accountID) {
            try Task.checkCancellation()
            var action = original
            while true {
                try Task.checkCancellation()
                do {
                    switch action.kind {
                    case .add, .remove, .reorder, .rollover:
                        if current == nil { current = normalizedCurrent(try await remote.current()) }
                        current = normalizedCurrent(try await sendPeriodAction(action, version: current?.version))
                        try await cache.saveCurrent(current!, accountID: accountID)
                    case .settings:
                        if settings == nil { settings = try await remote.settings() }
                        guard let cadence = action.cadence else {
                            throw FocusRepositoryError.pendingActionMissing
                        }
                        settings = try await remote.updateSettings(cadence, version: settings!.version)
                        try await cache.saveSettings(settings!, accountID: accountID)
                    }
                    try Task.checkCancellation()
                    try await queue.acknowledge(accountID: accountID, actionID: action.id)
                    acknowledged += 1
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch let api as APIError where api.isUnauthorized {
                    throw api
                } catch let api as APIError where api.statusCode == 409 || api.statusCode == 412 {
                    action = try await queue.incrementConflict(accountID: accountID, actionID: action.id)
                    if action.kind == .settings {
                        settings = try await refreshSettingsForRebase()
                        try await cache.saveSettings(settings!, accountID: accountID)
                        if settingsEffectApplied(action, settings: settings!) {
                            try await queue.acknowledge(accountID: accountID, actionID: action.id)
                            acknowledged += 1
                            break
                        }
                    } else {
                        current = try await refreshCurrentForRebase()
                        try await cache.saveCurrent(current!, accountID: accountID)
                        if periodEffectApplied(action, period: current!) {
                            try await queue.acknowledge(accountID: accountID, actionID: action.id)
                            acknowledged += 1
                            break
                        }
                    }
                    if action.conflictAttempts >= Self.maxConflictAttempts {
                        try await queue.terminalize(
                            accountID: accountID,
                            actionID: action.id,
                            code: api.code,
                            at: now()
                        )
                        break
                    }
                } catch let api as APIError where isRetryable(api) {
                    throw FocusRepositoryError.retryable(code: api.code, statusCode: api.statusCode)
                } catch let api as APIError where (400...499).contains(api.statusCode) {
                    if action.kind == .settings {
                        settings = try await refreshSettingsForRebase()
                        try await cache.saveSettings(settings!, accountID: accountID)
                    } else {
                        current = try await refreshCurrentForRebase()
                        try await cache.saveCurrent(current!, accountID: accountID)
                    }
                    try await queue.terminalize(
                        accountID: accountID,
                        actionID: action.id,
                        code: api.code,
                        at: now()
                    )
                    break
                } catch let repository as FocusRepositoryError {
                    throw repository
                } catch {
                    throw FocusRepositoryError.retryable(code: "focus_network_error", statusCode: nil)
                }
            }
        }

        try Task.checkCancellation()
        let pending = try await queue.pending(accountID: accountID)
        let issues = try await queue.terminalIssues(accountID: accountID)
        let localTaskIDs: [UUID: UUID]
        if let current {
            localTaskIDs = try await resolveLocalTaskIDs(in: current)
        } else {
            localTaskIDs = [:]
        }
        return FocusSyncResult(
            current: current,
            settings: settings,
            pendingCount: pending.count,
            terminalIssues: issues,
            acknowledgedCount: acknowledged,
            localTaskIDsByBackendID: localTaskIDs
        )
    }

    func cancelAndAwaitPendingSync(accountID: UUID) async {
        guard let flight = syncFlights.removeValue(forKey: accountID) else { return }
        flight.task.cancel()
        _ = try? await flight.task.value
    }

    private func awaitSyncFlight(_ flight: SyncFlight, accountID: UUID) async throws -> FocusSyncResult {
        do {
            let result = try await flight.task.value
            clearSyncFlight(flight, accountID: accountID)
            try Task.checkCancellation()
            return result
        } catch {
            if let api = error as? APIError, api.isUnauthorized {
                await clearAccountState(accountID)
            }
            clearSyncFlight(flight, accountID: accountID)
            throw error
        }
    }

    private func clearSyncFlight(_ flight: SyncFlight, accountID: UUID) {
        guard syncFlights[accountID]?.id == flight.id else { return }
        syncFlights.removeValue(forKey: accountID)
    }

    private func sendPeriodAction(_ action: FocusPendingAction, version: Int64?) async throws -> FocusPeriodDTO {
        let key = action.id.uuidString.lowercased()
        switch action.kind {
        case .add:
            guard let taskID = action.taskID else { throw FocusRepositoryError.pendingActionMissing }
            return try await remote.add(taskID: taskID, version: version, idempotencyKey: key)
        case .remove:
            guard let taskID = action.taskID else { throw FocusRepositoryError.pendingActionMissing }
            return try await remote.remove(taskID: taskID, version: version, idempotencyKey: key)
        case .reorder:
            return try await remote.reorder(taskIDs: action.taskIDs, version: version, idempotencyKey: key)
        case .rollover:
            guard let sourceID = action.sourcePeriodID else { throw FocusRepositoryError.pendingActionMissing }
            return try await remote.resolveRollover(
                sourcePeriodID: sourceID,
                taskIDs: action.taskIDs,
                version: version,
                idempotencyKey: key
            )
        case .settings:
            throw FocusRepositoryError.pendingActionMissing
        }
    }

    private func periodEffectApplied(_ action: FocusPendingAction, period: FocusPeriodDTO) -> Bool {
        let activeTaskIDs = orderedItems(period.items).filter { !$0.historyOnly }.map(\.taskId)
        switch action.kind {
        case .add: return action.taskID.map(activeTaskIDs.contains) == true
        case .remove: return action.taskID.map { !activeTaskIDs.contains($0) } == true
        case .reorder: return activeTaskIDs == action.taskIDs
        case .rollover:
            return period.rolloverOffer?.sourcePeriodId != action.sourcePeriodID
                && Set(action.taskIDs).isSubset(of: Set(activeTaskIDs))
        case .settings: return false
        }
    }

    private func settingsEffectApplied(
        _ action: FocusPendingAction,
        settings: FocusNotificationSettingsDTO
    ) -> Bool {
        guard let cadence = action.cadence else { return false }
        return settings.intervalMinutes == cadence.intervalMinutes
            && settings.quietHoursStart == cadence.quietHoursStart
            && settings.quietHoursEnd == cadence.quietHoursEnd
    }

    private func isRetryable(_ api: APIError) -> Bool {
        api.statusCode == 408 || api.statusCode == 429 || api.statusCode >= 500
    }

    private func refreshCurrentForRebase() async throws -> FocusPeriodDTO {
        do {
            return normalizedCurrent(try await remote.current())
        } catch is CancellationError {
            throw CancellationError()
        } catch let api as APIError where api.isUnauthorized {
            throw api
        } catch let api as APIError where isRetryable(api) {
            throw FocusRepositoryError.retryable(code: api.code, statusCode: api.statusCode)
        } catch {
            throw FocusRepositoryError.retryable(code: "focus_refresh_failed", statusCode: nil)
        }
    }

    private func refreshSettingsForRebase() async throws -> FocusNotificationSettingsDTO {
        do {
            return try await remote.settings()
        } catch is CancellationError {
            throw CancellationError()
        } catch let api as APIError where api.isUnauthorized {
            throw api
        } catch let api as APIError where isRetryable(api) {
            throw FocusRepositoryError.retryable(code: api.code, statusCode: api.statusCode)
        } catch {
            throw FocusRepositoryError.retryable(code: "focus_refresh_failed", statusCode: nil)
        }
    }

    private func requireCurrent(_ accountID: UUID) async throws -> FocusPeriodDTO {
        guard let period = try await cache.current(accountID: accountID) else {
            throw FocusRepositoryError.currentPeriodMissing
        }
        return normalizedCurrent(period)
    }

    private func currentResult(
        accountID: UUID,
        period: FocusPeriodDTO?,
        source: FocusLoadSource,
        failure: FocusFailure?
    ) async throws -> FocusCurrentResult {
        let normalizedPeriod = period.map { normalizedCurrent($0) }
        let localTaskIDs: [UUID: UUID]
        if let normalizedPeriod {
            localTaskIDs = try await resolveLocalTaskIDs(in: normalizedPeriod)
        } else {
            localTaskIDs = [:]
        }
        return FocusCurrentResult(
            period: normalizedPeriod,
            source: source,
            pendingCount: (try await queue.pending(accountID: accountID)).count,
            terminalIssues: try await queue.terminalIssues(accountID: accountID),
            failure: failure,
            localTaskIDsByBackendID: localTaskIDs
        )
    }

    private func makeAction(
        accountID: UUID,
        kind: FocusPendingActionKind,
        taskID: UUID? = nil,
        taskIDs: [UUID] = [],
        sourcePeriodID: UUID? = nil,
        expectedVersion: Int64,
        candidate: FocusCandidateDTO? = nil,
        cadence: FocusCadenceValues? = nil
    ) -> FocusPendingAction {
        FocusPendingAction(
            id: actionID(),
            accountID: accountID,
            kind: kind,
            taskID: taskID,
            taskIDs: taskIDs,
            sourcePeriodID: sourcePeriodID,
            expectedVersion: expectedVersion,
            candidate: candidate,
            cadence: cadence,
            conflictAttempts: 0,
            createdAt: now()
        )
    }

    private func defaultSettings() -> FocusNotificationSettingsDTO {
        FocusNotificationSettingsDTO(
            intervalMinutes: FocusCadenceValues.defaults.intervalMinutes,
            quietHoursStart: FocusCadenceValues.defaults.quietHoursStart,
            quietHoursEnd: FocusCadenceValues.defaults.quietHoursEnd,
            version: 0
        )
    }

    private func normalizedCurrent(_ period: FocusPeriodDTO) -> FocusPeriodDTO {
        replacingItems(period, items: orderedItems(period.items))
    }

    private func normalizedHistory(_ period: FocusPeriodDTO) -> FocusPeriodDTO {
        replacingItems(
            period,
            items: orderedItems(period.items),
            progress: FocusProgressCalculator.history(period.items)
        )
    }

    private func orderedItems(_ items: [FocusItemDTO]) -> [FocusItemDTO] {
        items.sorted { lhs, rhs in
            lhs.position == rhs.position
                ? lhs.taskId.uuidString.lowercased() < rhs.taskId.uuidString.lowercased()
                : lhs.position < rhs.position
        }
    }

    private func replacingItems(
        _ period: FocusPeriodDTO,
        items: [FocusItemDTO],
        progress: FocusProgressDTO? = nil,
        clearRolloverOffer: Bool = false
    ) -> FocusPeriodDTO {
        let normalizedItems = orderedItems(items)
        return FocusPeriodDTO(
            id: period.id,
            weekStart: period.weekStart,
            weekEndExclusive: period.weekEndExclusive,
            startsAt: period.startsAt,
            endsAt: period.endsAt,
            timezone: period.timezone,
            status: period.status,
            version: period.version,
            progress: progress ?? FocusProgressCalculator.current(normalizedItems),
            items: normalizedItems,
            rolloverOffer: clearRolloverOffer ? nil : period.rolloverOffer
        )
    }

    private func optimisticItem(_ candidate: FocusCandidateDTO, position: Int) -> FocusItemDTO {
        FocusItemDTO(
            id: candidate.taskId,
            taskId: candidate.taskId,
            title: candidate.title,
            status: candidate.status,
            effort: candidate.effort,
            effectiveWeight: max(candidate.effectiveWeight, 1),
            plannedTime: candidate.plannedTime,
            dueTime: candidate.dueTime,
            position: position,
            historyOnly: false,
            folderId: candidate.folderId,
            folderTitle: candidate.folderTitle,
            goalId: candidate.goalId,
            goalTitle: candidate.goalTitle,
            shared: candidate.shared,
            canWrite: candidate.canWrite
        )
    }

    private func copyItem(
        _ item: FocusItemDTO,
        id: UUID? = nil,
        position: Int,
        historyOnly: Bool? = nil
    ) -> FocusItemDTO {
        FocusItemDTO(
            id: id ?? item.id,
            taskId: item.taskId,
            title: item.title,
            status: item.status,
            effort: item.effort,
            effectiveWeight: max(item.effectiveWeight, 1),
            plannedTime: item.plannedTime,
            dueTime: item.dueTime,
            position: position,
            historyOnly: historyOnly ?? item.historyOnly,
            folderId: item.folderId,
            folderTitle: item.folderTitle,
            goalId: item.goalId,
            goalTitle: item.goalTitle,
            shared: item.shared,
            canWrite: item.canWrite
        )
    }

    private func resolveLocalTaskIDs(in period: FocusPeriodDTO) async throws -> [UUID: UUID] {
        var result: [UUID: UUID] = [:]
        for backendTaskID in Set(period.items.map(\.taskId)) {
            try Task.checkCancellation()
            do {
                if let localTaskID = try await taskIDMapping.localTaskID(
                    forBackendTaskID: backendTaskID
                ) {
                    result[backendTaskID] = localTaskID
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return result
    }

    private func clearAccountState(_ accountID: UUID) async {
        do {
            try await cache.clear(accountID: accountID)
        } catch {
            // Session termination must continue even if local cleanup needs later repair.
        }
        do {
            try await queue.clear(accountID: accountID)
        } catch {
            // Keep the original 401 as the externally visible terminal error.
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
