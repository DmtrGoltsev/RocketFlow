import Foundation
import XCTest
@testable import RocketFlow

final class TaskReminderIntegrationTests: XCTestCase {
    private let accountID = UUID(uuidString: "81000000-0000-0000-0000-000000000001")!
    private let taskID = UUID(uuidString: "81000000-0000-0000-0000-000000000002")!
    private let reminderID = UUID(uuidString: "81000000-0000-0000-0000-000000000003")!
    private let timeZone = TimeZone(secondsFromGMT: 0)!

    func testNewTaskMaterializesAccountDefaultExactlyOnce() async throws {
        let store = InMemoryTaskReminderStore()
        try await store.saveDefault(
            DefaultTaskReminder(
                accountID: accountID,
                offsetMinutes: 60,
                repeatRule: .daily,
                enabled: true
            )
        )
        let center = TaskReminderNotificationCenterStub()
        let ids = TaskReminderIDFactory(reminderID)
        let workflow = TaskReminderWorkflow(
            accountID: accountID,
            timeZone: timeZone,
            store: store,
            scheduler: TaskReminderScheduler(
                center: center,
                store: store,
                now: { Self.date(hour: 8) }
            ),
            makeID: ids.next
        )

        for _ in 0..<2 {
            try await workflow.apply(
                taskID: taskID,
                title: "Task",
                dueAt: Self.date(hour: 10),
                mutation: .preserveOrDefault,
                taskState: .active,
                isNewTask: true
            )
        }

        let stored = try await store.reminders(accountID: accountID)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.single?.id, reminderID)
        XCTAssertEqual(stored.single?.triggerAt, Self.date(hour: 9))
        XCTAssertEqual(stored.single?.repeatRule, .daily)
        XCTAssertEqual(ids.callCount, 1)
    }

    func testManualOverrideIsIdempotentAndReplacesMaterializedDefault() async throws {
        let store = InMemoryTaskReminderStore()
        let center = TaskReminderNotificationCenterStub()
        let workflow = makeWorkflow(store: store, center: center)
        let old = LocalTaskReminder(
            id: UUID(),
            accountID: accountID,
            taskID: taskID,
            taskTitle: "Old",
            triggerAt: Self.date(hour: 9),
            repeatRule: .daily
        )
        try await store.save(old, taskState: .active)
        let draft = TaskReminderEditorDraft(
            id: reminderID,
            triggerAt: Self.date(hour: 11),
            repeatRule: .monthly
        )

        for _ in 0..<2 {
            try await workflow.apply(
                taskID: taskID,
                title: "Updated",
                dueAt: nil,
                mutation: .upsert(draft),
                taskState: .active,
                isNewTask: false
            )
        }

        let stored = try await store.reminders(accountID: accountID)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.single?.id, reminderID)
        XCTAssertEqual(stored.single?.taskTitle, "Updated")
        XCTAssertEqual(stored.single?.repeatRule, .monthly)
    }

    func testExplicitOffSuppressesAccountDefaultForNewTask() async throws {
        let store = InMemoryTaskReminderStore()
        try await store.saveDefault(
            DefaultTaskReminder(
                accountID: accountID,
                offsetMinutes: 60,
                repeatRule: .weekly,
                enabled: true
            )
        )
        let center = TaskReminderNotificationCenterStub()
        let ids = TaskReminderIDFactory(reminderID)
        let workflow = TaskReminderWorkflow(
            accountID: accountID,
            timeZone: timeZone,
            store: store,
            scheduler: TaskReminderScheduler(
                center: center,
                store: store,
                now: { Self.date(hour: 8) }
            ),
            makeID: ids.next
        )

        try await workflow.apply(
            taskID: taskID,
            title: "Task",
            dueAt: Self.date(hour: 10),
            mutation: .remove,
            taskState: .active,
            isNewTask: true
        )

        let stored = try await store.reminders(accountID: accountID)
        XCTAssertTrue(stored.isEmpty)
        XCTAssertEqual(ids.callCount, 0)
        let pending = await center.pendingIdentifiers()
        XCTAssertTrue(pending.isEmpty)
    }

    func testRemoveAndTerminalStatusCancelOnlyTheCurrentTask() async throws {
        let store = InMemoryTaskReminderStore()
        let center = TaskReminderNotificationCenterStub()
        let workflow = makeWorkflow(store: store, center: center)
        let otherTaskID = UUID()
        let current = localReminder(taskID: taskID)
        let other = localReminder(taskID: otherTaskID)
        try await store.save(current, taskState: .active)
        try await store.save(other, taskState: .active)
        await center.seed(TaskReminderScheduler.identifier(for: current))
        await center.seed(TaskReminderScheduler.identifier(for: other))

        try await workflow.apply(
            taskID: taskID,
            title: "Task",
            dueAt: nil,
            mutation: .remove,
            taskState: .active,
            isNewTask: false
        )

        var stored = try await store.reminders(accountID: accountID)
        XCTAssertEqual(stored.map(\.taskID), [otherTaskID])

        try await store.save(current, taskState: .active)
        await center.seed(TaskReminderScheduler.identifier(for: current))
        try await workflow.apply(
            taskID: taskID,
            title: "Task",
            dueAt: nil,
            mutation: .preserveOrDefault,
            taskState: .done,
            isNewTask: false
        )

        stored = try await store.reminders(accountID: accountID)
        XCTAssertEqual(stored.map(\.taskID), [otherTaskID])
        let pending = await center.pendingIdentifiers()
        XCTAssertEqual(pending, [TaskReminderScheduler.identifier(for: other)])
    }

    func testPostSaveSchedulingRetryDoesNotRepeatBaseTaskCreate() async throws {
        let store = InMemoryTaskReminderStore()
        let center = TaskReminderNotificationCenterStub(failingAdds: 1)
        let workflow = makeWorkflow(store: store, center: center)
        let base = TaskReminderEditorSaverStub(
            result: EditorSaveResult(
                reference: DetailEntityReference(kind: .task, id: taskID),
                pending: true
            )
        )
        let adapter = TaskReminderEditorSavingAdapter(
            base: base,
            reminders: workflow,
            now: { Self.date(hour: 8) }
        )
        var draft = EditorTestFixtures.taskDraft(dueAt: Self.date(hour: 12))
        draft.reminder = .upsert(
            TaskReminderEditorDraft(
                id: reminderID,
                triggerAt: Self.date(hour: 11),
                repeatRule: .none
            )
        )
        let payload = try XCTUnwrap(
            EditorValidator.payload(draft, timezone: timeZone, now: Self.date(hour: 8))
        )
        let request = EditorSaveRequest.task(
            mode: .create,
            goalID: EditorTestFixtures.goalID,
            payload: payload
        )

        do {
            _ = try await adapter.saveEditor(request)
            XCTFail("Expected first notification add to fail")
        } catch let failure as EditorReminderFailure {
            XCTAssertEqual(failure, .schedulingFailed)
        }
        let result = try await adapter.saveEditor(request)

        XCTAssertEqual(result.reference.id, taskID)
        let baseCalls = await base.callCount()
        XCTAssertEqual(baseCalls, 1)
        let stored = try await store.reminders(accountID: accountID)
        XCTAssertEqual(stored.map(\.id), [reminderID])
        let addCalls = await center.addCallCount()
        XCTAssertEqual(addCalls, 2)
    }

    func testPastOneShotFailsBeforeBaseTaskSave() async throws {
        let store = InMemoryTaskReminderStore()
        let center = TaskReminderNotificationCenterStub()
        let workflow = makeWorkflow(store: store, center: center)
        let base = TaskReminderEditorSaverStub(
            result: EditorSaveResult(
                reference: DetailEntityReference(kind: .task, id: taskID),
                pending: true
            )
        )
        let adapter = TaskReminderEditorSavingAdapter(
            base: base,
            reminders: workflow,
            now: { Self.date(hour: 8) }
        )
        var draft = EditorTestFixtures.taskDraft()
        draft.reminder = .upsert(
            TaskReminderEditorDraft(
                id: reminderID,
                triggerAt: Self.date(hour: 7),
                repeatRule: .none
            )
        )
        let payload = try XCTUnwrap(
            EditorValidator.payload(
                draft,
                timezone: timeZone,
                now: Self.date(hour: 6)
            )
        )

        do {
            _ = try await adapter.saveEditor(
                .task(mode: .create, goalID: EditorTestFixtures.goalID, payload: payload)
            )
            XCTFail("Expected past one-shot validation failure")
        } catch let failure as EditorReminderFailure {
            XCTAssertEqual(failure, .oneShotInPast)
        }

        let baseCalls = await base.callCount()
        let stored = try await store.reminders(accountID: accountID)
        XCTAssertEqual(baseCalls, 0)
        XCTAssertTrue(stored.isEmpty)
    }

    func testOneShotExpiringDuringBaseSaveCanRetryReminderOnlyWithoutRepeatingBase() async throws {
        let store = InMemoryTaskReminderStore()
        let center = TaskReminderNotificationCenterStub()
        let clock = TaskReminderClock(Self.date(hour: 7))
        let scheduler = TaskReminderScheduler(
            center: center,
            store: store,
            now: { clock.now() }
        )
        let workflow = TaskReminderWorkflow(
            accountID: accountID,
            timeZone: timeZone,
            store: store,
            scheduler: scheduler
        )
        let base = TaskReminderEditorSaverStub(
            result: EditorSaveResult(
                reference: DetailEntityReference(kind: .task, id: taskID),
                pending: true
            ),
            onSave: { clock.set(Self.date(hour: 9)) }
        )
        let adapter = TaskReminderEditorSavingAdapter(
            base: base,
            reminders: workflow,
            now: { clock.now() }
        )
        var draft = EditorTestFixtures.taskDraft()
        draft.reminder = .upsert(TaskReminderEditorDraft(
            id: reminderID,
            triggerAt: Self.date(hour: 8),
            repeatRule: .none
        ))
        let firstPayload = try XCTUnwrap(EditorValidator.payload(
            draft,
            timezone: timeZone,
            now: Self.date(hour: 7)
        ))

        do {
            _ = try await adapter.saveEditor(
                .task(mode: .create, goalID: EditorTestFixtures.goalID, payload: firstPayload)
            )
            XCTFail("Expected reminder to expire after base save")
        } catch let failure as EditorReminderFailure {
            XCTAssertEqual(failure, .oneShotInPast)
        }
        let callsAfterExpiration = await base.callCount()
        XCTAssertEqual(callsAfterExpiration, 1)

        draft.reminder = .upsert(TaskReminderEditorDraft(
            id: reminderID,
            triggerAt: Self.date(hour: 10),
            repeatRule: .none
        ))
        let correctedPayload = try XCTUnwrap(EditorValidator.payload(
            draft,
            timezone: timeZone,
            now: Self.date(hour: 9)
        ))
        let result = try await adapter.saveEditor(
            .task(mode: .create, goalID: EditorTestFixtures.goalID, payload: correctedPayload)
        )

        let baseCalls = await base.callCount()
        let stored = try await store.reminders(accountID: accountID)
        XCTAssertEqual(result.reference.id, taskID)
        XCTAssertEqual(baseCalls, 1)
        XCTAssertEqual(stored.single?.triggerAt, Self.date(hour: 10))
    }

    func testAbandonedRecoveryCannotReturnPreviousIdenticalCreateResult() async throws {
        let store = InMemoryTaskReminderStore()
        let center = TaskReminderNotificationCenterStub(failingAdds: 1)
        let workflow = makeWorkflow(store: store, center: center)
        let firstTaskID = UUID()
        let secondTaskID = UUID()
        let base = TaskReminderEditorSaverStub(
            results: [firstTaskID, secondTaskID].map {
                EditorSaveResult(
                    reference: DetailEntityReference(kind: .task, id: $0),
                    pending: true
                )
            }
        )
        let adapter = TaskReminderEditorSavingAdapter(
            base: base,
            reminders: workflow,
            now: { Self.date(hour: 8) }
        )
        var firstDraft = EditorTestFixtures.taskDraft(dueAt: Self.date(hour: 12))
        firstDraft.reminder = .upsert(
            TaskReminderEditorDraft(
                id: reminderID,
                triggerAt: Self.date(hour: 11),
                repeatRule: .none
            )
        )
        let firstPayload = try XCTUnwrap(
            EditorValidator.payload(firstDraft, timezone: timeZone, now: Self.date(hour: 8))
        )
        let firstRequest = EditorSaveRequest.task(
            mode: .create,
            goalID: EditorTestFixtures.goalID,
            payload: firstPayload
        )

        do {
            _ = try await adapter.saveEditor(firstRequest)
            XCTFail("Expected reminder scheduling failure")
        } catch let failure as EditorReminderFailure {
            XCTAssertEqual(failure, .schedulingFailed)
        }
        await adapter.abandonEditorOperation(firstPayload.operationID)

        var secondDraft = firstDraft
        secondDraft.operationID = UUID()
        let secondPayload = try XCTUnwrap(
            EditorValidator.payload(secondDraft, timezone: timeZone, now: Self.date(hour: 8))
        )
        let secondResult = try await adapter.saveEditor(
            .task(
                mode: .create,
                goalID: EditorTestFixtures.goalID,
                payload: secondPayload
            )
        )

        XCTAssertEqual(secondResult.reference.id, secondTaskID)
        XCTAssertNotEqual(secondResult.reference.id, firstTaskID)
        let baseCalls = await base.callCount()
        XCTAssertEqual(baseCalls, 2)
    }

    func testClearEditorOperationsDropsCachedBaseResultForLogoutCleanup() async throws {
        let store = InMemoryTaskReminderStore()
        let center = TaskReminderNotificationCenterStub(failingAdds: 1)
        let workflow = makeWorkflow(store: store, center: center)
        let firstTaskID = UUID()
        let secondTaskID = UUID()
        let base = TaskReminderEditorSaverStub(
            results: [firstTaskID, secondTaskID].map {
                EditorSaveResult(
                    reference: DetailEntityReference(kind: .task, id: $0),
                    pending: true
                )
            }
        )
        let adapter = TaskReminderEditorSavingAdapter(
            base: base,
            reminders: workflow,
            now: { Self.date(hour: 8) }
        )
        var draft = EditorTestFixtures.taskDraft()
        draft.reminder = .upsert(TaskReminderEditorDraft(
            id: reminderID,
            triggerAt: Self.date(hour: 11),
            repeatRule: .none
        ))
        let payload = try XCTUnwrap(EditorValidator.payload(
            draft,
            timezone: timeZone,
            now: Self.date(hour: 8)
        ))
        let request = EditorSaveRequest.task(
            mode: .create,
            goalID: EditorTestFixtures.goalID,
            payload: payload
        )
        do {
            _ = try await adapter.saveEditor(request)
            XCTFail("Expected notification failure")
        } catch let failure as EditorReminderFailure {
            XCTAssertEqual(failure, .schedulingFailed)
        }

        await adapter.clearEditorOperations()
        let retried = try await adapter.saveEditor(request)

        let baseCalls = await base.callCount()
        XCTAssertEqual(retried.reference.id, secondTaskID)
        XCTAssertEqual(baseCalls, 2)
    }

    func testOperationIdentityCannotBeReusedForDifferentTaskPayload() async throws {
        let store = InMemoryTaskReminderStore()
        let center = TaskReminderNotificationCenterStub(failingAdds: 1)
        let workflow = makeWorkflow(store: store, center: center)
        let base = TaskReminderEditorSaverStub(
            result: EditorSaveResult(
                reference: DetailEntityReference(kind: .task, id: taskID),
                pending: true
            )
        )
        let adapter = TaskReminderEditorSavingAdapter(
            base: base,
            reminders: workflow,
            now: { Self.date(hour: 8) }
        )
        var draft = EditorTestFixtures.taskDraft(dueAt: Self.date(hour: 12))
        draft.reminder = .upsert(
            TaskReminderEditorDraft(
                id: reminderID,
                triggerAt: Self.date(hour: 11),
                repeatRule: .none
            )
        )
        let firstPayload = try XCTUnwrap(
            EditorValidator.payload(draft, timezone: timeZone, now: Self.date(hour: 8))
        )
        do {
            _ = try await adapter.saveEditor(
                .task(mode: .create, goalID: EditorTestFixtures.goalID, payload: firstPayload)
            )
            XCTFail("Expected reminder scheduling failure")
        } catch let failure as EditorReminderFailure {
            XCTAssertEqual(failure, .schedulingFailed)
        }

        draft.title = "Changed after partial save"
        let changedPayload = try XCTUnwrap(
            EditorValidator.payload(draft, timezone: timeZone, now: Self.date(hour: 8))
        )
        do {
            _ = try await adapter.saveEditor(
                .task(mode: .create, goalID: EditorTestFixtures.goalID, payload: changedPayload)
            )
            XCTFail("Expected operation identity rejection")
        } catch let failure as EditorReminderFailure {
            XCTAssertEqual(failure, .operationIdentityReused)
        }
        let baseCalls = await base.callCount()
        XCTAssertEqual(baseCalls, 1)
    }

    func testDeniedAuthorizationPropagatesAsEditorReminderFailure() async throws {
        let store = InMemoryTaskReminderStore()
        let center = TaskReminderNotificationCenterStub(state: .denied)
        let workflow = makeWorkflow(store: store, center: center)
        let base = TaskReminderEditorSaverStub(
            result: EditorSaveResult(
                reference: DetailEntityReference(kind: .task, id: taskID),
                pending: true
            )
        )
        let adapter = TaskReminderEditorSavingAdapter(
            base: base,
            reminders: workflow,
            now: { Self.date(hour: 8) }
        )
        var draft = EditorTestFixtures.taskDraft()
        draft.reminder = .upsert(
            TaskReminderEditorDraft(
                id: reminderID,
                triggerAt: Self.date(hour: 11),
                repeatRule: .daily
            )
        )
        let payload = try XCTUnwrap(
            EditorValidator.payload(draft, timezone: timeZone, now: Self.date(hour: 8))
        )

        do {
            _ = try await adapter.saveEditor(
                .task(
                    mode: .edit(DetailEntityReference(kind: .task, id: taskID)),
                    goalID: EditorTestFixtures.goalID,
                    payload: payload
                )
            )
            XCTFail("Expected authorization failure")
        } catch let failure as EditorReminderFailure {
            XCTAssertEqual(failure, .authorizationDenied)
        }

        let baseCalls = await base.callCount()
        let stored = try await store.reminders(accountID: accountID)
        XCTAssertEqual(baseCalls, 1)
        XCTAssertEqual(stored.single?.id, reminderID)
    }

    func testDetailTerminalStatusAndTaskDeleteCancelReminderAfterBaseSuccess() async throws {
        let store = InMemoryTaskReminderStore()
        let center = TaskReminderNotificationCenterStub()
        let workflow = makeWorkflow(store: store, center: center)
        let reminder = localReminder(taskID: taskID)
        try await store.save(reminder, taskState: .active)
        await center.seed(TaskReminderScheduler.identifier(for: reminder))
        let base = TaskReminderDetailMutationStub(result: DetailMutationResult())
        let adapter = TaskReminderDetailMutationAdapter(base: base, reminders: workflow)

        _ = try await adapter.performDetailMutation(
            .updateTaskStatus(taskID: taskID, status: .done, version: 3)
        )

        let stored = try await store.reminders(accountID: accountID)
        XCTAssertTrue(stored.isEmpty)
        let pending = await center.pendingIdentifiers()
        XCTAssertTrue(pending.isEmpty)

        try await store.save(reminder, taskState: .active)
        await center.seed(TaskReminderScheduler.identifier(for: reminder))
        _ = try await adapter.performDetailMutation(
            .delete(DetailEntityReference(kind: .task, id: taskID))
        )

        let afterDelete = try await store.reminders(accountID: accountID)
        XCTAssertTrue(afterDelete.isEmpty)
        let baseCalls = await base.callCount()
        XCTAssertEqual(baseCalls, 2)
    }

    func testEditorSeedLoadsDurableReminderForRoundTrip() async throws {
        let store = InMemoryTaskReminderStore()
        let center = TaskReminderNotificationCenterStub()
        let workflow = makeWorkflow(store: store, center: center)
        let reminder = localReminder(taskID: taskID)
        try await store.save(reminder, taskState: .active)
        let base = TaskReminderEditorSeedStub(
            seed: .task(
                EditorTestFixtures.taskDraft(),
                goalID: EditorTestFixtures.goalID,
                access: .fullOwner,
                isInFocus: false
            )
        )
        let loader = TaskReminderEditorSeedLoader(base: base, reminders: workflow)

        let seed = try await loader.editorSeed(
            for: .edit(DetailEntityReference(kind: .task, id: taskID))
        )

        guard case let .task(draft, _, _, _) = seed else {
            return XCTFail("Expected task editor seed")
        }
        XCTAssertEqual(
            draft.reminder,
            .upsert(
                TaskReminderEditorDraft(
                    id: reminder.id,
                    triggerAt: reminder.triggerAt,
                    repeatRule: reminder.repeatRule,
                    anchorAt: reminder.anchorAt
                )
            )
        )
    }

    private func makeWorkflow(
        store: InMemoryTaskReminderStore,
        center: TaskReminderNotificationCenterStub
    ) -> TaskReminderWorkflow {
        let generatedReminderID = reminderID
        return TaskReminderWorkflow(
            accountID: accountID,
            timeZone: timeZone,
            store: store,
            scheduler: TaskReminderScheduler(
                center: center,
                store: store,
                now: { Self.date(hour: 8) }
            ),
            makeID: { generatedReminderID }
        )
    }

    private func localReminder(taskID: UUID) -> LocalTaskReminder {
        LocalTaskReminder(
            id: taskID == self.taskID ? reminderID : UUID(),
            accountID: accountID,
            taskID: taskID,
            taskTitle: "Task",
            triggerAt: Self.date(hour: 11),
            repeatRule: .weekly
        )
    }

    private static func date(hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 24, hour: hour)
        )!
    }
}

private enum TaskReminderTestError: Error, Sendable {
    case expected
}

private actor TaskReminderNotificationCenterStub: UserNotificationCenterServing {
    private var requests: [String: UserNotificationRequestValue] = [:]
    private var remainingFailingAdds: Int
    private var addCalls = 0
    private let state: NotificationAuthorizationState

    init(
        failingAdds: Int = 0,
        state: NotificationAuthorizationState = .authorized
    ) {
        remainingFailingAdds = failingAdds
        self.state = state
    }

    func authorizationState() -> NotificationAuthorizationState { state }
    func requestAuthorization() -> Bool { state != .denied }
    func pendingIdentifiers() -> Set<String> { Set(requests.keys) }
    func add(_ request: UserNotificationRequestValue) throws {
        addCalls += 1
        if remainingFailingAdds > 0 {
            remainingFailingAdds -= 1
            throw TaskReminderTestError.expected
        }
        requests[request.identifier] = request
    }
    func remove(identifiers: [String]) {
        for identifier in identifiers { requests.removeValue(forKey: identifier) }
    }
    func seed(_ identifier: String) {
        requests[identifier] = UserNotificationRequestValue(
            identifier: identifier,
            title: "",
            body: "",
            fireDate: nil,
            timeZoneIdentifier: nil,
            userInfo: [:],
            timeSensitive: false
        )
    }
    func addCallCount() -> Int { addCalls }
}

private actor TaskReminderEditorSaverStub: EditorSaving {
    private let results: [EditorSaveResult]
    private let onSave: @Sendable () -> Void
    private var calls = 0

    init(
        result: EditorSaveResult,
        onSave: @escaping @Sendable () -> Void = {}
    ) {
        results = [result]
        self.onSave = onSave
    }

    init(
        results: [EditorSaveResult],
        onSave: @escaping @Sendable () -> Void = {}
    ) {
        precondition(!results.isEmpty)
        self.results = results
        self.onSave = onSave
    }

    func saveEditor(_ request: EditorSaveRequest) async throws -> EditorSaveResult {
        _ = request
        let result = results[min(calls, results.count - 1)]
        calls += 1
        onSave()
        return result
    }

    func callCount() -> Int { calls }
}

private final class TaskReminderClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }
    func now() -> Date { lock.withLock { value } }
    func set(_ value: Date) { lock.withLock { self.value = value } }
}

private actor TaskReminderDetailMutationStub: DetailMutationPerforming {
    private let result: DetailMutationResult
    private var calls = 0

    init(result: DetailMutationResult) {
        self.result = result
    }

    func performDetailMutation(_ mutation: DetailMutation) async throws -> DetailMutationResult {
        _ = mutation
        calls += 1
        return result
    }

    func callCount() -> Int { calls }
}

private struct TaskReminderEditorSeedStub: PlannerDetailsEditorSeedLoading {
    let seed: PlannerDetailsEditorSeed

    func editorSeed(for route: DetailEditorRoute) async throws -> PlannerDetailsEditorSeed {
        _ = route
        return seed
    }
}

private final class TaskReminderIDFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let value: UUID
    private var calls = 0

    init(_ value: UUID) {
        self.value = value
    }

    func next() -> UUID {
        lock.withLock {
            calls += 1
            return value
        }
    }

    var callCount: Int { lock.withLock { calls } }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
