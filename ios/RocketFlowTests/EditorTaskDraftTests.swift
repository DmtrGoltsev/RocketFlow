import XCTest
@testable import RocketFlow

final class EditorTaskDraftTests: XCTestCase {
    func testChecklistCreateToggleDeleteAndReorder() {
        let first = ChecklistEditorItemDraft(text: "First")
        let second = ChecklistEditorItemDraft(text: "Second")
        var draft = EditorTestFixtures.taskDraft(checklist: [first, second])

        draft.addChecklistItem(text: "Third")
        draft.toggleChecklistItem(id: first.id)
        draft.moveChecklistItem(from: 2, to: 0)
        draft.removeChecklistItem(id: second.id)

        XCTAssertEqual(draft.checklist.map(\.text), ["Third", "First"])
        XCTAssertTrue(draft.checklist[1].checked)
    }

    func testAdjacentForwardMoveIsStableNoOp() {
        let first = ChecklistEditorItemDraft(text: "First")
        let second = ChecklistEditorItemDraft(text: "Second")
        var draft = EditorTestFixtures.taskDraft(checklist: [first, second])
        draft.moveChecklistItem(from: 0, to: 1)
        XCTAssertEqual(draft.checklist.map(\.id), [first.id, second.id])
    }

    func testTagAssignmentAndUnassignmentUseStableIDs() {
        let first = TagEditorItemDraft(id: UUID(), name: "A", colorHex: nil, assigned: false)
        let second = TagEditorItemDraft(id: UUID(), name: "B", colorHex: nil, assigned: true)
        var draft = EditorTestFixtures.taskDraft(tags: [first, second])
        draft.setTagAssigned(id: first.id, assigned: true)
        draft.setTagAssigned(id: second.id, assigned: false)
        XCTAssertEqual(draft.tags.map(\.assigned), [true, false])
    }

    func testStatusOnlyAccessDisablesEveryExtendedMutationCapability() {
        XCTAssertEqual(TaskEditorAccess.statusOnly.mutationScope, .statusOnly)
        XCTAssertFalse(TaskEditorAccess.statusOnly.canManageRecurrence)
        XCTAssertFalse(TaskEditorAccess.statusOnly.canManageChecklist)
        XCTAssertFalse(TaskEditorAccess.statusOnly.canManageTags)
    }

    func testOwnerAccessEnablesFullTaskEditingCapabilities() {
        XCTAssertEqual(TaskEditorAccess.fullOwner.mutationScope, .full)
        XCTAssertTrue(TaskEditorAccess.fullOwner.canManageRecurrence)
        XCTAssertTrue(TaskEditorAccess.fullOwner.canManageChecklist)
        XCTAssertTrue(TaskEditorAccess.fullOwner.canManageTags)
    }

    func testRecurrenceSynchronizationKeepsExplicitDueSource() {
        let planned = EditorTestFixtures.anchor.addingTimeInterval(-3_600)
        let due = EditorTestFixtures.anchor
        var recurrence = TaskRecurrenceEditorDraft(
            mode: .daily,
            interval: 1,
            weekdays: [],
            dayOfMonth: nil,
            endAt: nil,
            anchorSource: .due,
            startAt: due
        )

        recurrence.synchronizeAnchor(plannedAt: planned.addingTimeInterval(600), dueAt: due)

        XCTAssertEqual(recurrence.anchorSource, .due)
        XCTAssertEqual(recurrence.startAt, due)
        XCTAssertEqual(recurrence.resolvedAnchor(plannedAt: planned, dueAt: due), due)
    }

    func testEditorCopyLocalizesWeekdaysAndChecklistActions() {
        let ru = EditorCopy(language: .ru)
        let en = EditorCopy(language: .en)

        XCTAssertEqual(ru.weekdayTitle(.monday), "Пн")
        XCTAssertEqual(en.weekdayTitle(.monday), "Mon")
        XCTAssertEqual(ru.checklistToggleLabel(text: "Отчет", checked: false), "Отметить «Отчет» как выполненное")
        XCTAssertEqual(en.checklistDeleteLabel(text: "Report"), "Delete Report")
    }

    func testTaskReminderDraftRoundTripsThroughPayload() throws {
        let reminder = TaskReminderEditorDraft(
            id: UUID(),
            triggerAt: EditorTestFixtures.anchor,
            repeatRule: .monthly
        )
        var draft = EditorTestFixtures.taskDraft()
        draft.reminder = .upsert(reminder)

        let payload = try XCTUnwrap(
            EditorValidator.payload(
                draft,
                timezone: EditorTestFixtures.timezone,
                now: EditorTestFixtures.anchor.addingTimeInterval(-60)
            )
        )

        XCTAssertEqual(payload.reminder, .upsert(reminder))
        XCTAssertEqual(payload.operationID, draft.operationID)
    }

    func testTaskPayloadExplicitInitializerKeepsSourceCompatibleDefaults() {
        let payload = TaskEditorPayload(
            mutationScope: .full,
            title: "Task",
            description: "",
            status: .todo,
            type: .green,
            effort: 1,
            plannedAt: nil,
            dueAt: nil,
            recurrence: nil,
            checklist: [],
            tagIDs: []
        )

        XCTAssertEqual(payload.reminder, .preserveOrDefault)
    }

    func testStatusOnlyPayloadNeverMutatesPersonalReminder() throws {
        var draft = EditorTestFixtures.taskDraft()
        draft.reminder = .remove

        let payload = try XCTUnwrap(
            EditorValidator.payload(
                draft,
                timezone: EditorTestFixtures.timezone,
                scope: .statusOnly
            )
        )

        XCTAssertEqual(payload.reminder, .preserveOrDefault)
    }

    func testTaskReminderCopyCoversRussianAndEnglishCadence() {
        let ru = TaskReminderCopy(language: .ru)
        let en = TaskReminderCopy(language: .en)

        XCTAssertEqual(ru.repeatTitle(.none), "Без повтора")
        XCTAssertEqual(ru.repeatTitle(.monthly), "Ежемесячно")
        XCTAssertEqual(en.repeatTitle(.hourly), "Hourly")
        XCTAssertEqual(en.repeatTitle(.weekly), "Weekly")
        XCTAssertEqual(EditorCopy(language: .ru).reminderPermissionDenied, "Разрешите уведомления, чтобы включить напоминание")
        XCTAssertEqual(EditorCopy(language: .en).reminderPast, "A one-time reminder must be scheduled in the future")
    }
}
