import Foundation
import XCTest
@testable import RocketFlow

final class NotificationScheduleTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testPastOneShotExpiresButFutureOneShotIsPreserved() {
        let accountID = UUID()
        let taskID = UUID()
        let past = reminder(
            accountID: accountID,
            taskID: taskID,
            trigger: date(2026, 1, 1, 9),
            repeatRule: .none
        )
        let future = reminder(
            accountID: accountID,
            taskID: taskID,
            trigger: date(2026, 1, 2, 9),
            repeatRule: .none
        )
        let now = date(2026, 1, 1, 12)

        XCTAssertNil(TaskReminderSchedule.nextFireDate(for: past, now: now, timeZone: utc))
        XCTAssertEqual(
            TaskReminderSchedule.nextFireDate(for: future, now: now, timeZone: utc),
            future.triggerAt
        )
    }

    func testRecurringRulesAdvanceAcrossLongMissedGap() throws {
        let anchor = date(2020, 1, 6, 8, 30)
        let now = date(2026, 8, 23, 12)
        let accountID = UUID()
        let taskID = UUID()

        for repeatRule in [TaskReminderRepeat.hourly, .daily, .weekly] {
            let value = reminder(
                accountID: accountID,
                taskID: taskID,
                trigger: anchor,
                repeatRule: repeatRule
            )
            let next = try XCTUnwrap(
                TaskReminderSchedule.nextFireDate(for: value, now: now, timeZone: utc)
            )
            XCTAssertGreaterThan(next, now)
            switch repeatRule {
            case .hourly:
                XCTAssertEqual(calendar.component(.minute, from: next), 30)
            case .daily:
                XCTAssertEqual(calendar.component(.hour, from: next), 8)
                XCTAssertEqual(calendar.component(.minute, from: next), 30)
            case .weekly:
                XCTAssertEqual(calendar.component(.weekday, from: next), 2)
                XCTAssertEqual(calendar.component(.hour, from: next), 8)
            default:
                XCTFail("Unexpected repeat rule")
            }
        }
    }

    func testMonthlyRuleClampsShortMonthAndReturnsToOriginalAnchorDay() throws {
        let anchor = date(2024, 1, 31, 10, 15)
        let value = reminder(
            accountID: UUID(),
            taskID: UUID(),
            trigger: anchor,
            repeatRule: .monthly
        )

        let february = try XCTUnwrap(TaskReminderSchedule.nextFireDate(
            for: value,
            now: date(2024, 2, 1),
            timeZone: utc
        ))
        let march = try XCTUnwrap(TaskReminderSchedule.nextFireDate(
            for: value,
            now: date(2024, 3, 1),
            timeZone: utc
        ))

        XCTAssertEqual(components(february), DateComponents(year: 2024, month: 2, day: 29, hour: 10, minute: 15))
        XCTAssertEqual(components(march), DateComponents(year: 2024, month: 3, day: 31, hour: 10, minute: 15))
    }

    func testIdentifiersAreScopedByAccountTaskAndReminder() {
        let reminderID = UUID()
        let taskID = UUID()
        let first = reminder(accountID: UUID(), taskID: taskID, reminderID: reminderID)
        let second = reminder(accountID: UUID(), taskID: taskID, reminderID: reminderID)
        let third = reminder(accountID: first.accountID, taskID: UUID(), reminderID: reminderID)
        let fourth = reminder(accountID: first.accountID, taskID: taskID, reminderID: UUID())

        XCTAssertEqual(Set([first, second, third, fourth].map(TaskReminderScheduler.identifier)).count, 4)
    }

    func testSchedulerExpiresOneShotAndRemovesTerminalTaskStates() async throws {
        let now = date(2026, 8, 23, 12)
        let accountID = UUID()
        let center = NotificationCenterSpy()
        let store = InMemoryTaskReminderStore()
        let scheduler = TaskReminderScheduler(center: center, store: store, now: { now })
        let expired = reminder(
            accountID: accountID,
            taskID: UUID(),
            trigger: date(2026, 8, 22, 12),
            repeatRule: .none
        )
        try await store.save(expired, taskState: .active)

        let expiredResult = try await scheduler.schedule(expired, taskState: .active, timeZone: utc)
        XCTAssertEqual(expiredResult, .expired)
        let afterExpiration = try await store.reminders(accountID: accountID)
        XCTAssertTrue(afterExpiration.isEmpty)

        for state in [ReminderTaskState.done, .cancelled, .archived, .missing] {
            let value = reminder(accountID: accountID, taskID: UUID())
            try await store.save(value, taskState: state)
            let result = try await scheduler.schedule(value, taskState: state, timeZone: utc)
            XCTAssertEqual(result, .removedForTaskState(state))
        }
        let afterTerminalStates = try await store.reminders(accountID: accountID)
        XCTAssertTrue(afterTerminalStates.isEmpty)
    }

    func testReconcileAdvancesRecurringReminderAndRemovesObsoleteScopedRequest() async throws {
        let now = date(2026, 8, 23, 12)
        let accountID = UUID()
        let center = NotificationCenterSpy()
        let store = InMemoryTaskReminderStore()
        let value = reminder(
            accountID: accountID,
            taskID: UUID(),
            trigger: date(2026, 8, 1, 8),
            repeatRule: .daily
        )
        try await store.save(value, taskState: .active)
        await center.seedIdentifier(TaskReminderScheduler.accountPrefix(accountID) + "obsolete")
        let scheduler = TaskReminderScheduler(center: center, store: store, now: { now })

        let results = try await scheduler.reconcile(
            accountID: accountID,
            timeZone: utc,
            reason: .foreground
        )

        let fireDate = try XCTUnwrap(results[value.id]?.scheduledDate)
        XCTAssertGreaterThan(fireDate, now)
        let requests = await center.requests()
        XCTAssertEqual(requests.single?.identifier, TaskReminderScheduler.identifier(for: value))
        let removed = await center.removedIdentifiers()
        XCTAssertTrue(removed.contains(TaskReminderScheduler.accountPrefix(accountID) + "obsolete"))
    }

    func testCancelAllClearsScopedStoreDefaultAndEveryPendingAccountRequest() async throws {
        let accountID = UUID()
        let otherAccountID = UUID()
        let center = NotificationCenterSpy()
        let store = InMemoryTaskReminderStore()
        let value = reminder(accountID: accountID, taskID: UUID())
        let other = reminder(accountID: otherAccountID, taskID: UUID())
        try await store.save(value, taskState: .active)
        try await store.save(other, taskState: .active)
        try await store.saveDefault(DefaultTaskReminder(
            accountID: accountID,
            offsetMinutes: 30,
            repeatRule: .none,
            enabled: true
        ))
        let staleIdentifier = TaskReminderScheduler.accountPrefix(accountID) + "stale"
        let deliveredIdentifier = TaskReminderScheduler.accountPrefix(accountID) + "delivered"
        let otherIdentifier = TaskReminderScheduler.identifier(for: other)
        await center.seedIdentifier(TaskReminderScheduler.identifier(for: value))
        await center.seedIdentifier(staleIdentifier)
        await center.seedDeliveredIdentifier(deliveredIdentifier)
        await center.seedIdentifier(otherIdentifier)
        let scheduler = TaskReminderScheduler(center: center, store: store)

        try await scheduler.cancelAll(accountID: accountID)

        let cleared = try await store.reminders(accountID: accountID)
        let clearedDefault = try await store.defaultReminder(accountID: accountID)
        let retained = try await store.reminders(accountID: otherAccountID)
        XCTAssertTrue(cleared.isEmpty)
        XCTAssertNil(clearedDefault)
        XCTAssertEqual(retained, [other])
        let pending = await center.pendingIdentifiers()
        XCTAssertEqual(pending, Set([otherIdentifier]))
        let removed = Set(await center.removedIdentifiers())
        XCTAssertTrue(removed.contains(staleIdentifier))
        XCTAssertTrue(removed.contains(deliveredIdentifier))
        XCTAssertTrue(removed.contains(TaskReminderScheduler.identifier(for: value)))
    }

    func testRemoteParserRejectsMalformedAndAllNotificationBackedPayloads() {
        let taskID = UUID()
        XCTAssertNil(RemoteNotificationPayloadParser.parse(data: ["type": "task_reminder"]))
        XCTAssertNil(RemoteNotificationPayloadParser.parse(data: [
            "type": "focus_reminder", "periodId": UUID().uuidString, "eventId": "bad"
        ]))
        XCTAssertNil(RemoteNotificationPayloadParser.parse(
            data: [
                "type": "focus_reminder",
                "periodId": UUID().uuidString,
                "eventId": UUID().uuidString
            ],
            hasNotificationPayload: true
        ))
        XCTAssertNil(RemoteNotificationPayloadParser.parse(
            data: ["type": "task_reminder", "taskId": taskID.uuidString],
            hasNotificationPayload: true
        ))
        XCTAssertNil(RemoteNotificationPayloadParser.parse(data: ["type": "unknown"]))
    }

    func testNotificationBackedTaskAndFocusNeverScheduleSecondLocalNotification() async throws {
        let center = NotificationCenterSpy()
        let handler = RemoteNotificationHandler(
            center: center,
            dedupe: InMemoryFocusNotificationEventStore()
        )

        let taskResult = try await handler.handle(
            data: ["type": "task_reminder", "taskId": UUID().uuidString],
            hasNotificationPayload: true
        )
        let focusResult = try await handler.handle(
            data: [
                "type": "focus_reminder",
                "periodId": UUID().uuidString,
                "eventId": UUID().uuidString
            ],
            hasNotificationPayload: true
        )

        XCTAssertEqual(taskResult, .rejected)
        XCTAssertEqual(focusResult, .rejected)
        let requests = await center.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testFocusRemoteNotificationDeduplicatesForFourteenDaysThenPresentsAgain() async throws {
        let now = date(2026, 8, 23, 12)
        let clock = NotificationClock(now)
        let center = NotificationCenterSpy()
        let dedupe = InMemoryFocusNotificationEventStore()
        let handler = RemoteNotificationHandler(center: center, dedupe: dedupe, now: { clock.now() })
        let eventID = UUID()
        let periodID = UUID()
        let payload = [
            "type": "focus_reminder",
            "periodId": periodID.uuidString,
            "eventId": eventID.uuidString,
            "title": "Focus",
            "body": "Open focus"
        ]

        let firstResult = try await handler.handle(data: payload)
        XCTAssertEqual(firstResult, .presented(URL(string: "rocketflow://focus")!))
        let duplicateResult = try await handler.handle(data: payload)
        XCTAssertEqual(duplicateResult, .duplicate)
        clock.set(now.addingTimeInterval(14 * 24 * 60 * 60 + 1))
        let afterRetention = try await handler.handle(data: payload)
        XCTAssertEqual(afterRetention, .presented(URL(string: "rocketflow://focus")!))
        let requestCount = await center.requests().count
        XCTAssertEqual(requestCount, 2)
    }

    func testFocusDedupeSurvivesStoreRecreation() async throws {
        let suite = "rocketflow.notification-tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let eventID = UUID()
        let now = date(2026, 8, 23, 12)

        let first = UserDefaultsFocusNotificationEventStore(suiteName: suite)
        let accepted = try await first.markIfNew(eventID: eventID, now: now)
        let recreated = UserDefaultsFocusNotificationEventStore(suiteName: suite)
        let duplicate = try await recreated.markIfNew(eventID: eventID, now: now)
        XCTAssertTrue(accepted)
        XCTAssertFalse(duplicate)
    }

    func testTaskRemoteNotificationRequiresTaskIDAndCarriesTaskDeepLink() async throws {
        let center = NotificationCenterSpy()
        let handler = RemoteNotificationHandler(
            center: center,
            dedupe: InMemoryFocusNotificationEventStore()
        )
        let taskID = UUID()

        let result = try await handler.handle(data: [
            "type": "task_reminder", "taskId": taskID.uuidString
        ])

        XCTAssertEqual(result, .presented(URL(string: "rocketflow://task/\(taskID.uuidString.lowercased())")!))
        let request = await center.requests().single
        XCTAssertEqual(request?.userInfo["taskId"], taskID.uuidString.lowercased())
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = utc
        return value
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    private func components(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    private func reminder(
        accountID: UUID,
        taskID: UUID,
        reminderID: UUID = UUID(),
        trigger: Date? = nil,
        repeatRule: TaskReminderRepeat = .none
    ) -> LocalTaskReminder {
        let value = trigger ?? date(2026, 9, 1, 9)
        return LocalTaskReminder(
            id: reminderID,
            accountID: accountID,
            taskID: taskID,
            taskTitle: "Task",
            triggerAt: value,
            repeatRule: repeatRule,
            anchorAt: value
        )
    }
}

private actor NotificationCenterSpy: UserNotificationCenterServing {
    private var state: NotificationAuthorizationState = .authorized
    private var values: [String: UserNotificationRequestValue] = [:]
    private var delivered: Set<String> = []
    private var removed: [String] = []

    func authorizationState() -> NotificationAuthorizationState { state }
    func requestAuthorization() -> Bool { state != .denied }
    func pendingIdentifiers() -> Set<String> { Set(values.keys) }
    func deliveredIdentifiers() -> Set<String> { delivered }
    func add(_ request: UserNotificationRequestValue) { values[request.identifier] = request }
    func remove(identifiers: [String]) {
        identifiers.forEach { values.removeValue(forKey: $0) }
        identifiers.forEach { delivered.remove($0) }
        removed.append(contentsOf: identifiers)
    }

    func seedIdentifier(_ identifier: String) {
        values[identifier] = UserNotificationRequestValue(
            identifier: identifier, title: "", body: "", fireDate: nil,
            timeZoneIdentifier: nil, userInfo: [:], timeSensitive: false
        )
    }

    func seedDeliveredIdentifier(_ identifier: String) {
        delivered.insert(identifier)
    }

    func requests() -> [UserNotificationRequestValue] {
        values.values.sorted { $0.identifier < $1.identifier }
    }

    func removedIdentifiers() -> [String] { removed }
}

private final class NotificationClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }
    func now() -> Date { lock.withLock { value } }
    func set(_ value: Date) { lock.withLock { self.value = value } }
}

private extension TaskReminderScheduleResult {
    var scheduledDate: Date? {
        if case let .scheduled(date) = self { return date }
        return nil
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
