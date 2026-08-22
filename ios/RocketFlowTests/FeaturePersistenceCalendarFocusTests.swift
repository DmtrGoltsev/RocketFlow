import Foundation
import GRDB
import XCTest
@testable import RocketFlow

final class FeaturePersistenceCalendarFocusTests: XCTestCase {
    func testCalendarCacheRequiresExactAccountTimezoneAndBounds() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        let cache = try GRDBCalendarRangeCache(database: database, accountID: accountID)
        let key = CalendarRangeKey(
            accountID: accountID,
            timezoneID: "Europe/Moscow",
            from: LocalDate(rawValue: "2026-08-01")!,
            toExclusive: LocalDate(rawValue: "2026-09-01")!
        )
        let response = featureCalendarResponse(
            timezone: key.timezoneID,
            from: key.from,
            toExclusive: key.toExclusive
        )
        try await cache.save(response, for: key)

        let exact = try await cache.load(key)
        let otherAccountID = UUID()
        do {
            _ = try await cache.load(CalendarRangeKey(
                accountID: otherAccountID,
                timezoneID: key.timezoneID,
                from: key.from,
                toExclusive: key.toExclusive
            ))
            XCTFail("Expected scoped cache account mismatch")
        } catch {
            XCTAssertEqual(error as? FeaturePersistenceError, .accountMismatch)
        }
        let otherCache = try GRDBCalendarRangeCache(database: database, accountID: otherAccountID)
        let otherAccount = try await otherCache.load(CalendarRangeKey(
            accountID: otherAccountID,
            timezoneID: key.timezoneID,
            from: key.from,
            toExclusive: key.toExclusive
        ))
        let otherTimezone = try await cache.load(CalendarRangeKey(
            accountID: accountID, timezoneID: "UTC", from: key.from, toExclusive: key.toExclusive
        ))
        let otherBounds = try await cache.load(CalendarRangeKey(
            accountID: accountID,
            timezoneID: key.timezoneID,
            from: LocalDate(rawValue: "2026-08-02")!,
            toExclusive: key.toExclusive
        ))
        XCTAssertEqual(exact, response)
        XCTAssertNil(otherAccount)
        XCTAssertNil(otherTimezone)
        XCTAssertNil(otherBounds)

        do {
            try await cache.save(
                featureCalendarResponse(
                    timezone: "UTC",
                    from: key.from,
                    toExclusive: key.toExclusive
                ),
                for: key
            )
            XCTFail("Expected exact timezone key validation")
        } catch {
            XCTAssertEqual(error as? FeaturePersistenceError, .snapshotKeyMismatch)
        }
    }

    func testFocusCachePersistsCurrentHistoryDetailAndSettingsByAccount() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        let cache = try GRDBFocusCache(database: database, accountID: accountID)
        let otherAccountID = UUID()
        let period = featureFocusPeriod(version: 4)
        let history = [featureFocusHistory(period)]
        let settings = FocusNotificationSettingsDTO(
            intervalMinutes: 120,
            quietHoursStart: "22:00",
            quietHoursEnd: "08:00",
            version: 3
        )

        try await cache.saveCurrent(period, accountID: accountID)
        try await cache.saveHistory(history, accountID: accountID)
        try await cache.saveHistoryDetail(period, accountID: accountID)
        try await cache.saveSettings(settings, accountID: accountID)

        let storedCurrent = try await cache.current(accountID: accountID)
        let storedHistory = try await cache.history(accountID: accountID)
        let storedDetail = try await cache.historyDetail(accountID: accountID, periodID: period.id)
        let storedSettings = try await cache.settings(accountID: accountID)
        do {
            _ = try await cache.current(accountID: otherAccountID)
            XCTFail("Expected scoped cache account mismatch")
        } catch {
            XCTAssertEqual(error as? FeaturePersistenceError, .accountMismatch)
        }
        let otherCache = try GRDBFocusCache(database: database, accountID: otherAccountID)
        let otherCurrent = try await otherCache.current(accountID: otherAccountID)
        XCTAssertEqual(storedCurrent, period)
        XCTAssertEqual(storedHistory, history)
        XCTAssertEqual(storedDetail, period)
        XCTAssertEqual(storedSettings, settings)
        XCTAssertNil(otherCurrent)
    }

    func testFocusProtocolClearConformanceRemovesScopedCacheQueueAndIssues() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        let concreteCache = try GRDBFocusCache(database: database, accountID: accountID)
        let concreteQueue = try GRDBFocusActionQueue(database: database, accountID: accountID)
        let cache: any FocusCaching = concreteCache
        let queue: any FocusActionQueuing = concreteQueue
        let period = featureFocusPeriod(version: 1)
        let action = featureFocusAction(accountID: accountID, id: UUID(), version: 1, offset: 0)
        try await cache.saveCurrent(period, accountID: accountID)
        try await queue.enqueue(action)
        try await queue.terminalize(
            accountID: accountID,
            actionID: action.id,
            code: "terminal",
            at: Date(timeIntervalSince1970: 1_787_001_200)
        )

        try await cache.clear(accountID: accountID)
        try await queue.clear(accountID: accountID)

        let current = try await cache.current(accountID: accountID)
        let pending = try await queue.pending(accountID: accountID)
        let issues = try await queue.terminalIssues(accountID: accountID)
        XCTAssertNil(current)
        XCTAssertTrue(pending.isEmpty)
        XCTAssertTrue(issues.isEmpty)
    }

    func testFocusQueueIsFIFOIdempotentAndSurvivesReopen() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let accountID = UUID()
        let first = featureFocusAction(accountID: accountID, id: UUID(), version: 1, offset: 0)
        let second = featureFocusAction(accountID: accountID, id: UUID(), version: 2, offset: 1)
        do {
            let database = try fileDatabase(at: url)
            let queue = try GRDBFocusActionQueue(
                database: database,
                accountID: accountID,
                now: { Date(timeIntervalSince1970: 1_787_003_000) }
            )
            try await queue.enqueue(first)
            try await queue.enqueue(second)
            try await queue.enqueue(first)
            _ = try await queue.recordRetry(
                accountID: accountID,
                actionID: first.id,
                nextRetryAt: Date(timeIntervalSince1970: 1_787_002_000),
                errorCode: "offline"
            )
            let initialPending = try await queue.pending(accountID: accountID)
            XCTAssertEqual(initialPending.map(\.id), [first.id, second.id])
        }

        let reopened = try fileDatabase(at: url)
        let queue = try GRDBFocusActionQueue(
            database: reopened,
            accountID: accountID,
            now: { Date(timeIntervalSince1970: 1_787_003_000) }
        )
        let pending = try await queue.pending(accountID: accountID)
        let retry = try await queue.retryMetadata(accountID: accountID, actionID: first.id)
        XCTAssertEqual(pending, [first, second])
        XCTAssertEqual(pending.map(\.expectedVersion), [1, 2])
        XCTAssertEqual(retry, FeatureFocusRetryMetadata(
            retryCount: 1,
            nextRetryAt: Date(timeIntervalSince1970: 1_787_002_000),
            lastErrorCode: "offline"
        ))
    }

    func testFocusRetryHeadBlocksFIFOUntilInjectedClockIsDue() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        let start = Date(timeIntervalSince1970: 1_787_001_200)
        let retryAt = start.addingTimeInterval(600)
        let first = featureFocusAction(accountID: accountID, id: UUID(), version: 1, offset: 0)
        let second = featureFocusAction(accountID: accountID, id: UUID(), version: 2, offset: 1)
        let early = try GRDBFocusActionQueue(
            database: database,
            accountID: accountID,
            now: { start }
        )
        try await early.enqueue(first)
        try await early.enqueue(second)
        let metadata = try await early.recordRetry(
            accountID: accountID,
            actionID: first.id,
            nextRetryAt: retryAt,
            errorCode: "offline"
        )

        let blocked = try await early.pending(accountID: accountID)
        XCTAssertTrue(blocked.isEmpty)
        XCTAssertEqual(metadata.retryCount, 1)

        let due = try GRDBFocusActionQueue(
            database: database,
            accountID: accountID,
            now: { retryAt }
        )
        let released = try await due.pending(accountID: accountID)
        XCTAssertEqual(released.map(\.id), [first.id, second.id])
    }

    func testFocusQueueAtomicReplaceRetryConflictAndTerminalIssue() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        let issueID = UUID()
        let queue = try GRDBFocusActionQueue(
            database: database,
            accountID: accountID,
            now: { Date(timeIntervalSince1970: 1_787_001_260) },
            issueID: { issueID }
        )
        let first = featureFocusAction(accountID: accountID, id: UUID(), version: 9, offset: 0)
        let second = featureFocusAction(accountID: accountID, id: UUID(), version: 10, offset: 1)
        try await queue.replacePending([second, first], accountID: accountID)
        let replaced = try await queue.pending(accountID: accountID)
        XCTAssertEqual(replaced.map(\.id), [second.id, first.id])

        let retryAt = Date(timeIntervalSince1970: 1_787_001_200)
        let retry = try await queue.recordRetry(
            accountID: accountID,
            actionID: second.id,
            nextRetryAt: retryAt,
            errorCode: "temporarily_unavailable"
        )
        XCTAssertEqual(retry, FeatureFocusRetryMetadata(
            retryCount: 1, nextRetryAt: retryAt, lastErrorCode: "temporarily_unavailable"
        ))
        try await queue.replacePending([first, second], accountID: accountID)
        let reordered = try await queue.pending(accountID: accountID)
        let retainedRetry = try await queue.retryMetadata(accountID: accountID, actionID: second.id)
        XCTAssertEqual(reordered.map(\.id), [first.id, second.id])
        XCTAssertEqual(retainedRetry, retry)

        let conflicted = try await queue.incrementConflict(accountID: accountID, actionID: second.id)
        XCTAssertEqual(conflicted.conflictAttempts, 1)
        let terminalAt = Date(timeIntervalSince1970: 1_787_002_000)
        try await queue.terminalize(
            accountID: accountID,
            actionID: second.id,
            code: "version_conflict",
            at: terminalAt
        )
        let remaining = try await queue.pending(accountID: accountID)
        let issues = try await queue.terminalIssues(accountID: accountID)
        XCTAssertEqual(remaining, [first])
        XCTAssertEqual(issues, [
            FocusTerminalIssue(
                id: issueID,
                actionID: second.id,
                kind: second.kind,
                code: "version_conflict",
                conflictAttempts: 1,
                createdAt: terminalAt
            )
        ])
    }

    func testFocusQueueConcurrentWritesPreserveAllUniqueActions() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        let queue = try GRDBFocusActionQueue(database: database, accountID: accountID)
        let actions = (0..<24).map {
            featureFocusAction(accountID: accountID, id: UUID(), version: Int64($0), offset: $0)
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for action in actions {
                group.addTask { try await queue.enqueue(action) }
            }
            try await group.waitForAll()
        }

        let persisted = try await queue.pending(accountID: accountID)
        XCTAssertEqual(persisted.count, actions.count)
        XCTAssertEqual(Set(persisted.map(\.id)), Set(actions.map(\.id)))
    }

    func testCorruptCachesMissButCorruptQueueHeadBlocksUntilExplicitQuarantine() async throws {
        let database = try AppDatabase.inMemory()
        let accountID = UUID()
        let corruptActionKey = "corrupt-action-id"
        let from = LocalDate(rawValue: "2026-08-01")!
        let to = LocalDate(rawValue: "2026-09-01")!
        try database.write { db in
            try FeaturePersistenceAccount.ensure(accountID, in: db)
            try db.execute(
                sql: """
                    INSERT INTO feature_calendar_ranges
                    (accountID, timezoneID, fromDate, toExclusive, payloadJSON, updatedAt)
                    VALUES (?, 'UTC', ?, ?, ?, ?)
                    """,
                arguments: [
                    accountID.featurePersistenceKey, from.rawValue, to.rawValue,
                    Data("not-json".utf8), WireDateCodec.encode(Date())
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO feature_focus_snapshots
                    (accountID, cacheKind, entityID, payloadJSON, updatedAt)
                    VALUES (?, 'current', '', ?, ?)
                    """,
                arguments: [
                    accountID.featurePersistenceKey,
                    Data("not-json".utf8),
                    WireDateCodec.encode(Date())
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO feature_focus_actions (
                        accountID, actionID, kind, payloadJSON, expectedVersion,
                        conflictAttempts, retryCount, nextRetryAt, lastErrorCode,
                        sequence, createdAt, updatedAt
                    ) VALUES (?, ?, 'reorder', ?, 1, 0, 0, NULL, NULL, 0, ?, ?)
                    """,
                arguments: [
                    accountID.featurePersistenceKey,
                    corruptActionKey,
                    Data("not-json".utf8),
                    WireDateCodec.encode(Date()),
                    WireDateCodec.encode(Date())
                ]
            )
        }

        let calendar = try GRDBCalendarRangeCache(database: database, accountID: accountID)
        let focus = try GRDBFocusCache(database: database, accountID: accountID)
        let queue = try GRDBFocusActionQueue(database: database, accountID: accountID)
        let valid = featureFocusAction(accountID: accountID, id: UUID(), version: 2, offset: 1)
        try await queue.enqueue(valid)
        let calendarValue = try await calendar.load(CalendarRangeKey(
            accountID: accountID, timezoneID: "UTC", from: from, toExclusive: to
        ))
        XCTAssertNil(calendarValue)
        let focusValue = try await focus.current(accountID: accountID)
        XCTAssertNil(focusValue)
        do {
            _ = try await queue.pending(accountID: accountID)
            XCTFail("Expected corrupt head to block FIFO")
        } catch {
            XCTAssertEqual(
                error as? FeaturePersistenceError,
                .corruptRecord(
                    table: "feature_focus_actions",
                    key: corruptActionKey
                )
            )
        }
        let issues = try await queue.corruptionIssues(accountID: accountID)
        XCTAssertEqual(issues.map(\.recordKey), [corruptActionKey])

        let quarantinedKey = try await queue.quarantineCorruptHead(accountID: accountID)
        let recovered = try await queue.pending(accountID: accountID)
        XCTAssertEqual(quarantinedKey, corruptActionKey)
        XCTAssertEqual(recovered, [valid])
    }
}

private func featureCalendarResponse(
    timezone: String,
    from: LocalDate,
    toExclusive: LocalDate
) -> CalendarMarkersResponseDTO {
    CalendarMarkersResponseDTO(
        timezone: timezone,
        from: from,
        toExclusive: toExclusive,
        markers: [
            CalendarMarkerDTO(
                markerId: UUID(),
                occurrenceId: UUID(),
                taskId: UUID(),
                goalId: nil,
                title: "Exact",
                status: .todo,
                effort: 1,
                kind: .deadline,
                at: Date(timeIntervalSince1970: 1_787_001_200),
                localDate: from,
                recurring: true
            )
        ]
    )
}

private func featureFocusPeriod(version: Int64) -> FocusPeriodDTO {
    FocusPeriodDTO(
        id: UUID(),
        weekStart: LocalDate(rawValue: "2026-08-17")!,
        weekEndExclusive: LocalDate(rawValue: "2026-08-24")!,
        startsAt: Date(timeIntervalSince1970: 1_787_001_200),
        endsAt: Date(timeIntervalSince1970: 1_787_606_000),
        timezone: "Europe/Moscow",
        status: "active",
        version: version,
        progress: FocusProgressDTO(
            completedWeight: 0, totalWeight: 0, percent: 0, completedCount: 0, totalCount: 0
        ),
        items: [],
        rolloverOffer: nil
    )
}

private func featureFocusHistory(_ period: FocusPeriodDTO) -> FocusHistorySummaryDTO {
    FocusHistorySummaryDTO(
        id: period.id,
        weekStart: period.weekStart,
        weekEndExclusive: period.weekEndExclusive,
        startsAt: period.startsAt,
        endsAt: period.endsAt,
        timezone: period.timezone,
        status: period.status,
        version: period.version,
        progress: period.progress
    )
}

private func featureFocusAction(
    accountID: UUID,
    id: UUID,
    version: Int64,
    offset: Int
) -> FocusPendingAction {
    FocusPendingAction(
        id: id,
        accountID: accountID,
        kind: .reorder,
        taskID: nil,
        taskIDs: [UUID()],
        sourcePeriodID: nil,
        expectedVersion: version,
        candidate: nil,
        cadence: nil,
        conflictAttempts: 0,
        createdAt: Date(timeIntervalSince1970: 1_787_001_200 + TimeInterval(offset))
    )
}

private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("RocketFlowFeaturePersistence-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("RocketFlow.sqlite")
}

private func fileDatabase(at url: URL) throws -> AppDatabase {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    return try AppDatabase(writer: DatabaseQueue(path: url.path, configuration: configuration))
}
