import Foundation
import XCTest
@testable import RocketFlow

enum EditorTestFixtures {
    static let timezone = TimeZone(secondsFromGMT: 0)!
    static let goalID = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!
    static let taskID = UUID(uuidString: "70000000-0000-0000-0000-000000000002")!

    static var anchor: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 24, hour: 9)
        )!
    }

    static func taskDraft(
        plannedAt: Date? = nil,
        dueAt: Date? = nil,
        recurrence: TaskRecurrenceEditorDraft = .none,
        checklist: [ChecklistEditorItemDraft] = [],
        tags: [TagEditorItemDraft] = []
    ) -> TaskEditorDraft {
        TaskEditorDraft(
            title: " Task ",
            description: " Description ",
            status: .todo,
            type: .green,
            effort: 3,
            plannedAt: plannedAt,
            dueAt: dueAt,
            recurrence: recurrence,
            checklist: checklist,
            tags: tags
        )
    }
}

final class EditorValidationTests: XCTestCase {
    func testFolderRequiresNameAndHonorsBothLimits() {
        XCTAssertEqual(
            EditorValidator.validate(FolderEditorDraft(name: " ", description: "")).errors[.name],
            .required
        )
        let invalid = FolderEditorDraft(
            name: String(repeating: "n", count: EditorLimits.folderName + 1),
            description: String(repeating: "d", count: EditorLimits.folderDescription + 1)
        )
        XCTAssertEqual(
            EditorValidator.validate(invalid).errors,
            [
                .name: .tooLong(maximum: EditorLimits.folderName),
                .description: .tooLong(maximum: EditorLimits.folderDescription)
            ]
        )
    }

    func testGoalTrimsPayloadAndPreservesOpaqueStatusEnum() {
        let draft = GoalEditorDraft(name: " Goal ", description: " Body ", status: .inProgress)
        XCTAssertTrue(EditorValidator.validate(draft).isValid)
        XCTAssertEqual(
            EditorValidator.payload(draft),
            GoalEditorPayload(name: "Goal", description: "Body", status: .inProgress)
        )
    }

    func testTaskRequiresTitleAndNonnegativeEffort() {
        var draft = EditorTestFixtures.taskDraft()
        draft.title = ""
        draft.effort = -1
        let result = EditorValidator.validate(draft, timezone: EditorTestFixtures.timezone)
        XCTAssertEqual(result.errors[.title], .required)
        XCTAssertEqual(result.errors[.effort], .mustBeNonnegative)
    }

    func testPastOneShotReminderFailsBeforePayloadButRecurringAnchorCanAdvance() {
        let now = EditorTestFixtures.anchor
        var draft = EditorTestFixtures.taskDraft()
        let reminder = TaskReminderEditorDraft(
            triggerAt: now.addingTimeInterval(-60),
            repeatRule: .none
        )
        draft.reminder = .upsert(reminder)

        let invalid = EditorValidator.validate(
            draft,
            timezone: EditorTestFixtures.timezone,
            now: now
        )
        XCTAssertEqual(invalid.errors[.reminder], .reminderOneShotInPast)
        XCTAssertNil(EditorValidator.payload(
            draft,
            timezone: EditorTestFixtures.timezone,
            now: now
        ))

        draft.reminder = .upsert(
            TaskReminderEditorDraft(
                id: reminder.id,
                triggerAt: reminder.triggerAt,
                repeatRule: .daily,
                anchorAt: reminder.anchorAt
            )
        )
        XCTAssertTrue(EditorValidator.validate(
            draft,
            timezone: EditorTestFixtures.timezone,
            now: now
        ).isValid)
    }

    func testTaskDescriptionLimitMatchesBackendContract() {
        var draft = EditorTestFixtures.taskDraft()
        draft.description = String(repeating: "x", count: EditorLimits.taskDescription + 1)
        XCTAssertEqual(
            EditorValidator.validate(draft, timezone: EditorTestFixtures.timezone).errors[.description],
            .tooLong(maximum: EditorLimits.taskDescription)
        )
    }

    func testChecklistRejectsBlankAndOverlongText() {
        var draft = EditorTestFixtures.taskDraft(
            checklist: [ChecklistEditorItemDraft(text: " ")]
        )
        XCTAssertEqual(
            EditorValidator.validate(draft, timezone: EditorTestFixtures.timezone).errors[.checklist],
            .required
        )
        draft.checklist = [
            ChecklistEditorItemDraft(
                text: String(repeating: "x", count: EditorLimits.checklistText + 1)
            )
        ]
        XCTAssertEqual(
            EditorValidator.validate(draft, timezone: EditorTestFixtures.timezone).errors[.checklist],
            .tooLong(maximum: EditorLimits.checklistText)
        )
    }

    func testStatusOnlyPayloadPreservesEveryHiddenFieldExactly() {
        let tag = TagEditorItemDraft(id: UUID(), name: "Shared", colorHex: nil, assigned: true)
        let planned = EditorTestFixtures.anchor.addingTimeInterval(-3_600)
        let due = EditorTestFixtures.anchor
        var draft = EditorTestFixtures.taskDraft()
        draft.title = "  Shared task\r\n"
        draft.description = "  Preserve me byte-for-byte \r\n"
        draft.status = .done
        draft.type = .red
        draft.effort = 8
        draft.plannedAt = planned
        draft.dueAt = due
        draft.recurrence = TaskRecurrenceEditorDraft(
            mode: .daily,
            interval: 2,
            weekdays: [],
            dayOfMonth: nil,
            endAt: nil,
            anchorSource: .due,
            startAt: due
        )
        draft.checklist = [ChecklistEditorItemDraft(text: "  Existing item \r\n")]
        draft.tags = [tag]
        let result = EditorValidator.validate(
            draft,
            timezone: EditorTestFixtures.timezone,
            scope: .statusOnly
        )
        let payload = EditorValidator.payload(
            draft,
            timezone: EditorTestFixtures.timezone,
            scope: .statusOnly
        )
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(payload?.mutationScope, .statusOnly)
        XCTAssertEqual(payload?.status, .done)
        XCTAssertEqual(payload?.title, draft.title)
        XCTAssertEqual(payload?.description, draft.description)
        XCTAssertEqual(payload?.type, draft.type)
        XCTAssertEqual(payload?.effort, draft.effort)
        XCTAssertEqual(payload?.plannedAt, planned)
        XCTAssertEqual(payload?.dueAt, due)
        XCTAssertEqual(payload?.recurrence?.anchor, due)
        XCTAssertEqual(payload?.checklist.first?.text, draft.checklist.first?.text)
        XCTAssertEqual(payload?.tagIDs, [tag.id])
    }

    func testRecurrenceRequiresPlannedOrDueAnchor() {
        let recurrence = TaskRecurrenceEditorDraft(
            mode: .daily,
            interval: 1,
            weekdays: [],
            dayOfMonth: nil,
            endAt: nil
        )
        let result = EditorValidator.validate(
            EditorTestFixtures.taskDraft(recurrence: recurrence),
            timezone: EditorTestFixtures.timezone
        )
        XCTAssertEqual(result.errors[.recurrence], .recurrenceAnchorRequired)
    }

    func testRecurrenceStillEnforcesLowerIntervalBound() {
        let recurrence = TaskRecurrenceEditorDraft(
            mode: .daily,
            interval: 0,
            weekdays: [],
            dayOfMonth: nil,
            endAt: nil,
            anchorSource: .planned,
            startAt: EditorTestFixtures.anchor
        )
        let result = EditorValidator.validate(
            EditorTestFixtures.taskDraft(
                plannedAt: EditorTestFixtures.anchor,
                recurrence: recurrence
            ),
            timezone: EditorTestFixtures.timezone
        )
        XCTAssertEqual(result.errors[.recurrenceInterval], .recurrenceIntervalInvalid)
    }

    func testDailyRecurrenceProducesExactAnchorAndNoWeekOrMonthFields() throws {
        let recurrence = TaskRecurrenceEditorDraft(
            mode: .daily,
            interval: 2,
            weekdays: [.monday],
            dayOfMonth: 24,
            endAt: nil
        )
        let payload = try XCTUnwrap(
            EditorValidator.payload(
                EditorTestFixtures.taskDraft(
                    plannedAt: EditorTestFixtures.anchor,
                    recurrence: recurrence
                ),
                timezone: EditorTestFixtures.timezone
            )
        )
        XCTAssertEqual(payload.recurrence?.anchor, EditorTestFixtures.anchor)
        XCTAssertEqual(payload.recurrence?.interval, 2)
        XCTAssertEqual(payload.recurrence?.weekdays, [])
        XCTAssertNil(payload.recurrence?.dayOfMonth)
    }

    func testDualDateRecurrenceRoundTripsExplicitDueAnchor() throws {
        let planned = EditorTestFixtures.anchor.addingTimeInterval(-3_600)
        let due = EditorTestFixtures.anchor
        let recurrence = TaskRecurrenceEditorDraft(
            mode: .daily,
            interval: 2,
            weekdays: [],
            dayOfMonth: nil,
            endAt: nil,
            anchorSource: .due,
            startAt: due
        )

        let payload = try XCTUnwrap(
            EditorValidator.payload(
                EditorTestFixtures.taskDraft(
                    plannedAt: planned,
                    dueAt: due,
                    recurrence: recurrence
                ),
                timezone: EditorTestFixtures.timezone
            )
        )

        XCTAssertEqual(recurrence.anchorSource, .due)
        XCTAssertEqual(recurrence.startAt, due)
        XCTAssertEqual(payload.recurrence?.anchor, due)
    }

    func testWeeklyRecurrenceRequiresAnchorWeekday() {
        let recurrence = TaskRecurrenceEditorDraft(
            mode: .weekly,
            interval: 1,
            weekdays: [.tuesday],
            dayOfMonth: nil,
            endAt: nil
        )
        let result = EditorValidator.validate(
            EditorTestFixtures.taskDraft(
                plannedAt: EditorTestFixtures.anchor,
                recurrence: recurrence
            ),
            timezone: EditorTestFixtures.timezone
        )
        XCTAssertEqual(result.errors[.recurrenceWeekdays], .recurrenceAnchorWeekdayRequired)
    }

    func testMonthlyRecurrenceRequiresAnchorDay() {
        let recurrence = TaskRecurrenceEditorDraft(
            mode: .monthly,
            interval: 1,
            weekdays: [],
            dayOfMonth: 25,
            endAt: nil
        )
        let result = EditorValidator.validate(
            EditorTestFixtures.taskDraft(
                dueAt: EditorTestFixtures.anchor,
                recurrence: recurrence
            ),
            timezone: EditorTestFixtures.timezone
        )
        XCTAssertEqual(result.errors[.recurrenceDayOfMonth], .recurrenceAnchorDayRequired)
    }

    func testRecurrenceEndMustBeAfterAnchor() {
        let recurrence = TaskRecurrenceEditorDraft(
            mode: .daily,
            interval: 1,
            weekdays: [],
            dayOfMonth: nil,
            endAt: EditorTestFixtures.anchor
        )
        let result = EditorValidator.validate(
            EditorTestFixtures.taskDraft(
                plannedAt: EditorTestFixtures.anchor,
                recurrence: recurrence
            ),
            timezone: EditorTestFixtures.timezone
        )
        XCTAssertEqual(result.errors[.recurrenceEnd], .recurrenceEndInvalid)
    }

    func testTaskPayloadUsesChecklistOrderAndAssignedTags() throws {
        let firstServerID = UUID()
        let first = ChecklistEditorItemDraft(serverID: firstServerID, text: " One ")
        let second = ChecklistEditorItemDraft(text: " Two ", checked: true)
        let assigned = TagEditorItemDraft(id: UUID(), name: "A", colorHex: nil, assigned: true)
        let unassigned = TagEditorItemDraft(id: UUID(), name: "B", colorHex: nil, assigned: false)
        let payload = try XCTUnwrap(
            EditorValidator.payload(
                EditorTestFixtures.taskDraft(
                    checklist: [first, second],
                    tags: [assigned, unassigned]
                ),
                timezone: EditorTestFixtures.timezone
            )
        )
        XCTAssertEqual(payload.mutationScope, .full)
        XCTAssertEqual(payload.checklist.map(\.displayOrder), [0, 1])
        XCTAssertEqual(payload.checklist.map(\.text), ["One", "Two"])
        XCTAssertEqual(payload.checklist.first?.id, firstServerID)
        XCTAssertEqual(payload.tagIDs, [assigned.id])
    }

    func testValidationCountsUTF16CodeUnitsLikeBackend() {
        var draft = EditorTestFixtures.taskDraft()
        draft.title = String(repeating: "🚀", count: EditorLimits.taskTitle / 2)
        XCTAssertTrue(
            EditorValidator.validate(draft, timezone: EditorTestFixtures.timezone).isValid
        )

        draft.title += "🚀"
        XCTAssertEqual(
            EditorValidator.validate(draft, timezone: EditorTestFixtures.timezone).errors[.title],
            .tooLong(maximum: EditorLimits.taskTitle)
        )
    }

    func testBackendValidLargeEffortAndIntervalHaveNoFabricatedUpperBound() throws {
        let recurrence = TaskRecurrenceEditorDraft(
            mode: .daily,
            interval: 1_000,
            weekdays: [],
            dayOfMonth: nil,
            endAt: nil,
            anchorSource: .planned,
            startAt: EditorTestFixtures.anchor
        )
        var draft = EditorTestFixtures.taskDraft(
            plannedAt: EditorTestFixtures.anchor,
            recurrence: recurrence
        )
        draft.effort = 100_001

        XCTAssertTrue(EditorValidator.validate(draft, timezone: EditorTestFixtures.timezone).isValid)
        let payload = try XCTUnwrap(
            EditorValidator.payload(draft, timezone: EditorTestFixtures.timezone)
        )
        XCTAssertEqual(payload.effort, 100_001)
        XCTAssertEqual(payload.recurrence?.interval, 1_000)
    }

    func testIdeaValidationKeepsOpaqueStatusAndSetting() {
        let draft = IdeaEditorDraft(
            title: " Idea ", body: " Body ", status: " parked ",
            allowAuthorHistoryEdits: false
        )
        XCTAssertTrue(EditorValidator.validate(draft).isValid)
        XCTAssertEqual(EditorValidator.payload(draft).status, "parked")
        XCTAssertFalse(EditorValidator.payload(draft).allowAuthorHistoryEdits)
    }

    func testIdeaHistoryAndNoteRespectBackendLimits() {
        let history = IdeaHistoryEditorDraft(
            eventType: "",
            body: String(repeating: "x", count: EditorLimits.ideaHistoryBody + 1),
            metadata: [:]
        )
        let note = NoteEditorDraft(
            title: "",
            body: String(repeating: "x", count: EditorLimits.noteBody + 1)
        )
        XCTAssertEqual(EditorValidator.validate(history).errors[.eventType], .required)
        XCTAssertEqual(
            EditorValidator.validate(history).errors[.body],
            .tooLong(maximum: EditorLimits.ideaHistoryBody)
        )
        XCTAssertEqual(EditorValidator.validate(note).errors[.title], .required)
        XCTAssertEqual(
            EditorValidator.validate(note).errors[.body],
            .tooLong(maximum: EditorLimits.noteBody)
        )
    }

    func testTagRequiresNameAndNormalizesOptionalColor() {
        XCTAssertEqual(
            EditorValidator.validate(TagEditorDraft(name: "", colorHex: "")).errors[.tagName],
            .required
        )
        XCTAssertEqual(
            EditorValidator.payload(TagEditorDraft(name: " Work ", colorHex: " ")),
            TagEditorPayload(name: "Work", colorHex: nil)
        )
    }
}
