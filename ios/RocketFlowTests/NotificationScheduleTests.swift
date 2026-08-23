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

    func testBoundedOccurrenceHorizonEncodesExactOneShotTriggersForEveryCadence() {
        let anchor = date(2026, 8, 24, 9, 45)
        let accountID = UUID()
        let taskID = UUID()

        let oneShot = TaskReminderSchedule.notificationTrigger(
            for: reminder(
                accountID: accountID,
                taskID: taskID,
                trigger: anchor,
                repeatRule: .none
            ),
            fireDate: anchor,
            timeZone: utc
        )
        XCTAssertFalse(oneShot.repeats)
        XCTAssertEqual(oneShot.year, 2026)
        XCTAssertEqual(oneShot.month, 8)
        XCTAssertEqual(oneShot.day, 24)
        XCTAssertEqual(oneShot.hour, 9)
        XCTAssertEqual(oneShot.minute, 45)

        for repeatRule in [
            TaskReminderRepeat.hourly,
            .daily,
            .weekly,
            .monthly
        ] {
            let value = reminder(
                accountID: accountID,
                taskID: taskID,
                trigger: anchor,
                repeatRule: repeatRule
            )
            let dates = TaskReminderSchedule.occurrenceDates(
                for: value,
                now: date(2026, 8, 23, 9, 45),
                timeZone: utc,
                limit: 3
            )
            XCTAssertEqual(dates.count, 3)
            XCTAssertEqual(dates.first, anchor)
            XCTAssertTrue(dates.allSatisfy { $0 >= anchor })
            for fireDate in dates {
                let trigger = TaskReminderSchedule.notificationTrigger(
                    for: value,
                    fireDate: fireDate,
                    timeZone: utc
                )
                XCTAssertFalse(trigger.repeats)
                XCTAssertNotNil(trigger.year)
                XCTAssertNotNil(trigger.month)
                XCTAssertNotNil(trigger.day)
                XCTAssertEqual(trigger.timeZoneIdentifier, utc.identifier)
            }
        }
    }

    func testFutureRecurringReminderNeverSchedulesBeforeSelectedFirstDate() {
        let first = date(2026, 9, 10, 13, 30)
        let value = reminder(
            accountID: UUID(),
            taskID: UUID(),
            trigger: first,
            repeatRule: .hourly
        )

        let dates = TaskReminderSchedule.occurrenceDates(
            for: value,
            now: date(2026, 9, 1),
            timeZone: utc,
            limit: 4
        )

        XCTAssertEqual(dates.first, first)
        XCTAssertTrue(dates.allSatisfy { $0 >= first })
        XCTAssertEqual(dates.dropFirst().first, first.addingTimeInterval(60 * 60))
    }

    func testMonthlyOccurrenceHorizonClampsJanuary31ThenRestoresAnchorDay() {
        let anchor = date(2025, 1, 31, 10, 15)
        let value = reminder(
            accountID: UUID(),
            taskID: UUID(),
            trigger: anchor,
            repeatRule: .monthly
        )

        let dates = TaskReminderSchedule.occurrenceDates(
            for: value,
            now: date(2025, 1, 1),
            timeZone: utc,
            limit: 3
        )

        XCTAssertEqual(dates.map { components($0) }, [
            DateComponents(year: 2025, month: 1, day: 31, hour: 10, minute: 15),
            DateComponents(year: 2025, month: 2, day: 28, hour: 10, minute: 15),
            DateComponents(year: 2025, month: 3, day: 31, hour: 10, minute: 15)
        ])
    }

    func testDailyTriggerKeepsAccountLocalWallClockAcrossDST() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = newYork
        let anchor = try XCTUnwrap(localCalendar.date(
            from: DateComponents(year: 2026, month: 3, day: 7, hour: 9)
        ))
        let now = try XCTUnwrap(localCalendar.date(
            from: DateComponents(year: 2026, month: 3, day: 7, hour: 10)
        ))
        let value = reminder(
            accountID: UUID(),
            taskID: UUID(),
            trigger: anchor,
            repeatRule: .daily
        )

        let next = try XCTUnwrap(
            TaskReminderSchedule.nextFireDate(for: value, now: now, timeZone: newYork)
        )
        let local = localCalendar.dateComponents([.year, .month, .day, .hour], from: next)
        let trigger = TaskReminderSchedule.notificationTrigger(
            for: value,
            fireDate: next,
            timeZone: newYork
        )

        XCTAssertEqual(local, DateComponents(year: 2026, month: 3, day: 8, hour: 9))
        XCTAssertEqual(trigger.timeZoneIdentifier, newYork.identifier)
        XCTAssertEqual(trigger.hour, 9)
        XCTAssertFalse(trigger.repeats)
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

    func testSchedulerUsesInjectedLocalizedNotificationBody() async throws {
        let now = date(2026, 8, 23, 8)
        let accountID = UUID()
        let taskID = UUID()
        let store = InMemoryTaskReminderStore()
        let center = NotificationCenterSpy()
        let scheduler = TaskReminderScheduler(
            center: center,
            store: store,
            now: { now },
            notificationBody: { "Открыть задачу в RocketFlow." }
        )

        _ = try await scheduler.schedule(
            reminder(accountID: accountID, taskID: taskID),
            taskState: .active,
            timeZone: utc
        )

        let request = await center.requests().single
        XCTAssertEqual(request?.body, "Открыть задачу в RocketFlow.")
        XCTAssertEqual(request?.calendarTrigger?.repeats, false)
    }

    func testSchedulerInstallsMultipleExactOccurrencesForEveryRecurringCadence() async throws {
        let now = date(2026, 8, 23, 8)
        for repeatRule in [
            TaskReminderRepeat.hourly,
            .daily,
            .weekly,
            .monthly
        ] {
            let store = InMemoryTaskReminderStore()
            let center = NotificationCenterSpy()
            let scheduler = TaskReminderScheduler(center: center, store: store, now: { now })
            let value = reminder(
                accountID: UUID(),
                taskID: UUID(),
                trigger: date(2026, 8, 24, 9),
                repeatRule: repeatRule
            )

            _ = try await scheduler.schedule(
                value,
                taskState: .active,
                timeZone: utc,
                occurrenceLimit: 3
            )

            let requests = await center.requests()
            XCTAssertEqual(requests.count, 3)
            XCTAssertTrue(requests.allSatisfy { ($0.fireDate ?? .distantPast) >= value.triggerAt })
            XCTAssertTrue(requests.allSatisfy { $0.calendarTrigger?.repeats == false })
        }
    }

    func testSchedulerPersistsReminderAndReportsDeniedAuthorization() async throws {
        let accountID = UUID()
        let store = InMemoryTaskReminderStore()
        let center = NotificationCenterSpy(state: .denied)
        let now = date(2026, 8, 23, 8)
        let scheduler = TaskReminderScheduler(
            center: center,
            store: store,
            now: { now }
        )
        let value = reminder(accountID: accountID, taskID: UUID())

        do {
            _ = try await scheduler.schedule(value, taskState: .active, timeZone: utc)
            XCTFail("Expected notification authorization denial")
        } catch let error as TaskReminderSchedulingError {
            XCTAssertEqual(error, .authorizationDenied)
        }

        let stored = try await store.reminders(accountID: accountID)
        XCTAssertEqual(stored, [value])
        let requests = await center.requests()
        XCTAssertTrue(requests.isEmpty)
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
        XCTAssertEqual(requests.count, TaskReminderSchedule.occurrenceLimit(for: .daily))
        XCTAssertTrue(requests.allSatisfy {
            $0.identifier.hasPrefix(TaskReminderScheduler.identifier(for: value) + ".")
        })
        XCTAssertTrue(requests.allSatisfy { $0.calendarTrigger?.repeats == false })
        let removed = await center.removedIdentifiers()
        XCTAssertTrue(removed.contains(TaskReminderScheduler.accountPrefix(accountID) + "obsolete"))
    }

    func testReconcileSharesRollingHorizonWithinReservedPendingBudget() async throws {
        let now = date(2026, 8, 23, 8)
        let accountID = UUID()
        let store = InMemoryTaskReminderStore()
        let center = NotificationCenterSpy()
        let scheduler = TaskReminderScheduler(center: center, store: store, now: { now })
        for hour in 9..<13 {
            try await store.save(
                reminder(
                    accountID: accountID,
                    taskID: UUID(),
                    trigger: date(2026, 8, 24, hour),
                    repeatRule: .daily
                ),
                taskState: .active
            )
        }

        _ = try await scheduler.reconcile(
            accountID: accountID,
            timeZone: utc,
            reason: .launch
        )

        let pending = await center.pendingIdentifiers()
        XCTAssertEqual(pending.count, TaskReminderSchedule.maximumPendingTaskRequests)
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

    func testCancelTaskRemovesOnlyThatTaskStoredPendingAndDeliveredIdentifiers() async throws {
        let accountID = UUID()
        let taskID = UUID()
        let otherTaskID = UUID()
        let store = InMemoryTaskReminderStore()
        let center = NotificationCenterSpy()
        let scheduler = TaskReminderScheduler(center: center, store: store)
        let scoped = reminder(accountID: accountID, taskID: taskID)
        let other = reminder(accountID: accountID, taskID: otherTaskID)
        try await store.save(scoped, taskState: .active)
        try await store.save(other, taskState: .active)
        await center.seedIdentifier(TaskReminderScheduler.identifier(for: scoped))
        await center.seedDeliveredIdentifier(TaskReminderScheduler.identifier(for: scoped))
        await center.seedIdentifier(TaskReminderScheduler.identifier(for: other))

        try await scheduler.cancelTask(accountID: accountID, taskID: taskID)

        let stored = try await store.reminders(accountID: accountID)
        XCTAssertEqual(stored.map(\.id), [other.id])
        let pending = await center.pendingIdentifiers()
        XCTAssertEqual(pending, [TaskReminderScheduler.identifier(for: other)])
        let delivered = await center.deliveredIdentifiers()
        XCTAssertFalse(delivered.contains(TaskReminderScheduler.identifier(for: scoped)))
    }

    func testCancellingRecurringReminderRemovesWholeOccurrenceHorizon() async throws {
        let now = date(2026, 8, 23, 8)
        let accountID = UUID()
        let store = InMemoryTaskReminderStore()
        let center = NotificationCenterSpy()
        let scheduler = TaskReminderScheduler(center: center, store: store, now: { now })
        let value = reminder(
            accountID: accountID,
            taskID: UUID(),
            trigger: date(2026, 8, 24, 9),
            repeatRule: .weekly
        )

        _ = try await scheduler.schedule(value, taskState: .active, timeZone: utc)
        let scheduled = await center.pendingIdentifiers()
        XCTAssertEqual(scheduled.count, TaskReminderSchedule.occurrenceLimit(for: .weekly))

        try await scheduler.cancel(value)

        let pending = await center.pendingIdentifiers()
        let stored = try await store.reminders(accountID: accountID)
        XCTAssertTrue(pending.isEmpty)
        XCTAssertTrue(stored.isEmpty)
    }

    func testAccountSwitchSuspendsWithoutErasingAndResumeDoesNotLeakTitles() async throws {
        let now = date(2026, 8, 23, 8)
        let accountA = UUID()
        let accountB = UUID()
        let store = InMemoryTaskReminderStore()
        let center = NotificationCenterSpy()
        let scheduler = TaskReminderScheduler(center: center, store: store, now: { now })
        let reminderA = LocalTaskReminder(
            id: UUID(),
            accountID: accountA,
            taskID: UUID(),
            taskTitle: "Account A title",
            triggerAt: date(2026, 8, 24, 9),
            repeatRule: .daily
        )
        let reminderB = LocalTaskReminder(
            id: UUID(),
            accountID: accountB,
            taskID: UUID(),
            taskTitle: "Account B title",
            triggerAt: date(2026, 8, 24, 10),
            repeatRule: .daily
        )
        try await store.saveDefault(DefaultTaskReminder(
            accountID: accountA,
            offsetMinutes: 30,
            repeatRule: .weekly,
            enabled: true
        ))

        _ = try await scheduler.schedule(reminderA, taskState: .active, timeZone: utc)
        await scheduler.suspendNotifications(accountID: accountA)
        let suspendedRows = try await store.reminders(accountID: accountA)
        let suspendedDefault = try await store.defaultReminder(accountID: accountA)
        let suspendedRequests = await center.requests()
        XCTAssertEqual(suspendedRows, [reminderA])
        XCTAssertNotNil(suspendedDefault)
        XCTAssertTrue(suspendedRequests.isEmpty)

        _ = try await scheduler.schedule(reminderB, taskState: .active, timeZone: utc)
        var requests = await center.requests()
        XCTAssertTrue(requests.allSatisfy { $0.title == "Account B title" })
        XCTAssertFalse(requests.contains { $0.title == "Account A title" })

        await scheduler.suspendNotifications(accountID: accountB)
        try await scheduler.resumeNotifications(accountID: accountA, timeZone: utc)
        requests = await center.requests()
        XCTAssertTrue(requests.allSatisfy { $0.title == "Account A title" })
        XCTAssertFalse(requests.contains { $0.title == "Account B title" })
    }

    func testPlanningReconcileRefreshesTitleAndRemovesTerminalOrMissingTasks() async throws {
        let now = date(2026, 8, 23, 8)
        let accountID = UUID()
        let taskID = UUID()
        let store = InMemoryTaskReminderStore()
        let center = NotificationCenterSpy()
        let planning = TaskReminderPlanningStub()
        let scheduler = TaskReminderScheduler(
            center: center,
            store: store,
            planning: planning,
            now: { now }
        )
        let value = LocalTaskReminder(
            id: UUID(),
            accountID: accountID,
            taskID: taskID,
            taskTitle: "Stale title",
            triggerAt: date(2026, 8, 24, 9),
            repeatRule: .daily
        )
        try await store.save(value, taskState: .active)
        await planning.set(TaskReminderPlanningSnapshot(
            taskID: taskID,
            title: "Synced title",
            taskState: .active
        ))

        _ = try await scheduler.reconcile(
            accountID: accountID,
            timeZone: utc,
            reason: .foreground
        )
        var requests = await center.requests()
        var stored = try await store.reminders(accountID: accountID)
        XCTAssertTrue(requests.allSatisfy { $0.title == "Synced title" })
        XCTAssertEqual(stored.single?.taskTitle, "Synced title")

        await planning.set(TaskReminderPlanningSnapshot(
            taskID: taskID,
            title: "Synced title",
            taskState: .done
        ))
        let terminal = try await scheduler.reconcile(
            accountID: accountID,
            timeZone: utc,
            reason: .launch
        )
        XCTAssertEqual(terminal[value.id], .removedForTaskState(.done))
        requests = await center.requests()
        stored = try await store.reminders(accountID: accountID)
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(stored.isEmpty)

        try await store.save(value, taskState: .active)
        await planning.set(TaskReminderPlanningSnapshot(
            taskID: taskID,
            title: "Restored",
            taskState: .active
        ))
        _ = try await scheduler.reconcile(
            accountID: accountID,
            timeZone: utc,
            reason: .foreground
        )
        await planning.remove(taskID: taskID)
        let missing = try await scheduler.reconcile(
            accountID: accountID,
            timeZone: utc,
            reason: .foreground
        )
        XCTAssertEqual(missing[value.id], .removedForTaskState(.missing))
        requests = await center.requests()
        stored = try await store.reminders(accountID: accountID)
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(stored.isEmpty)
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
        let addedRequests = await center.addedRequests()
        let pendingRequestCount = await center.requests().count
        XCTAssertEqual(addedRequests.count, 2)
        XCTAssertEqual(Set(addedRequests.map(\.identifier)).count, 1)
        XCTAssertEqual(pendingRequestCount, 1)
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
    private var state: NotificationAuthorizationState
    private var values: [String: UserNotificationRequestValue] = [:]
    private var additions: [UserNotificationRequestValue] = []
    private var delivered: Set<String> = []
    private var removed: [String] = []

    init(state: NotificationAuthorizationState = .authorized) {
        self.state = state
    }

    func authorizationState() -> NotificationAuthorizationState { state }
    func requestAuthorization() -> Bool { state != .denied }
    func pendingIdentifiers() -> Set<String> { Set(values.keys) }
    func deliveredIdentifiers() -> Set<String> { delivered }
    func add(_ request: UserNotificationRequestValue) {
        additions.append(request)
        values[request.identifier] = request
    }
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

    func addedRequests() -> [UserNotificationRequestValue] { additions }

    func removedIdentifiers() -> [String] { removed }
}

private actor TaskReminderPlanningStub: TaskReminderPlanningSnapshotProviding {
    private var values: [UUID: TaskReminderPlanningSnapshot] = [:]

    func planningTask(
        accountID: UUID,
        taskID: UUID
    ) -> TaskReminderPlanningSnapshot? {
        _ = accountID
        return values[taskID]
    }

    func set(_ value: TaskReminderPlanningSnapshot) {
        values[value.taskID] = value
    }

    func remove(taskID: UUID) {
        values.removeValue(forKey: taskID)
    }
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
