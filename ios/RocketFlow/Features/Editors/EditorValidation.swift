import Foundation

enum EditorValidator {
    static func validate(_ draft: FolderEditorDraft) -> EditorValidationResult {
        result([
            .name: requiredLimited(draft.name, maximum: EditorLimits.folderName),
            .description: limited(draft.description, maximum: EditorLimits.folderDescription)
        ])
    }

    static func validate(_ draft: GoalEditorDraft) -> EditorValidationResult {
        result([
            .name: requiredLimited(draft.name, maximum: EditorLimits.goalName),
            .description: limited(draft.description, maximum: EditorLimits.goalDescription)
        ])
    }

    static func validate(
        _ draft: TaskEditorDraft,
        timezone: TimeZone,
        scope: TaskEditorMutationScope = .full
    ) -> EditorValidationResult {
        if scope == .statusOnly { return .valid }
        var errors: [EditorField: EditorValidationIssue?] = [
            .title: requiredLimited(draft.title, maximum: EditorLimits.taskTitle),
            .description: limited(draft.description, maximum: EditorLimits.taskDescription),
            .effort: draft.effort < 0 ? .mustBeNonnegative : nil,
            .checklist: checklistIssue(draft.checklist)
        ]
        errors.merge(recurrenceIssues(draft, timezone: timezone)) { current, _ in current }
        return result(errors)
    }

    static func validate(_ draft: IdeaEditorDraft) -> EditorValidationResult {
        result([
            .title: requiredLimited(draft.title, maximum: EditorLimits.ideaTitle),
            .body: limited(draft.body, maximum: EditorLimits.ideaBody),
            .status: requiredLimited(draft.status, maximum: EditorLimits.ideaStatus)
        ])
    }

    static func validate(_ draft: IdeaHistoryEditorDraft) -> EditorValidationResult {
        result([
            .eventType: requiredLimited(draft.eventType, maximum: EditorLimits.ideaHistoryType),
            .body: limited(draft.body, maximum: EditorLimits.ideaHistoryBody)
        ])
    }

    static func validate(_ draft: NoteEditorDraft) -> EditorValidationResult {
        result([
            .title: requiredLimited(draft.title, maximum: EditorLimits.noteTitle),
            .body: limited(draft.body, maximum: EditorLimits.noteBody)
        ])
    }

    static func validate(_ draft: TagEditorDraft) -> EditorValidationResult {
        result([
            .tagName: requiredLimited(draft.name, maximum: EditorLimits.tagName),
            .tagColor: limited(draft.colorHex, maximum: EditorLimits.tagColor)
        ])
    }

    static func payload(_ draft: FolderEditorDraft) -> FolderEditorPayload {
        FolderEditorPayload(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func payload(_ draft: GoalEditorDraft) -> GoalEditorPayload {
        GoalEditorPayload(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
            status: draft.status
        )
    }

    static func payload(
        _ draft: TaskEditorDraft,
        timezone: TimeZone,
        scope: TaskEditorMutationScope = .full
    ) -> TaskEditorPayload? {
        guard validate(draft, timezone: timezone, scope: scope).isValid else { return nil }
        let recurrencePayload: TaskRecurrenceEditorPayload?
        if
            let mode = draft.recurrence.mode,
            let anchor = draft.recurrence.resolvedAnchor(
                plannedAt: draft.plannedAt,
                dueAt: draft.dueAt
            )
        {
            recurrencePayload = TaskRecurrenceEditorPayload(
                mode: mode,
                interval: draft.recurrence.interval,
                weekdays: mode == .weekly ? ordered(draft.recurrence.weekdays) : [],
                dayOfMonth: mode == .monthly ? localDay(anchor, timezone: timezone) : nil,
                anchor: anchor,
                endAt: draft.recurrence.endAt,
                active: true
            )
        } else {
            recurrencePayload = nil
        }
        let preservesHiddenFields = scope == .statusOnly
        return TaskEditorPayload(
            mutationScope: scope,
            title: preservesHiddenFields
                ? draft.title
                : draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: preservesHiddenFields
                ? draft.description
                : draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
            status: draft.status,
            type: draft.type,
            effort: draft.effort,
            plannedAt: draft.plannedAt,
            dueAt: draft.dueAt,
            recurrence: recurrencePayload,
            checklist: draft.checklist.enumerated().map { index, item in
                ChecklistEditorPayload(
                    id: item.serverID,
                    text: preservesHiddenFields
                        ? item.text
                        : item.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    checked: item.checked,
                    displayOrder: index
                )
            },
            tagIDs: draft.tags.filter(\.assigned).map(\.id)
        )
    }

    static func payload(_ draft: IdeaEditorDraft) -> IdeaEditorPayload {
        IdeaEditorPayload(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: draft.body.trimmingCharacters(in: .whitespacesAndNewlines),
            status: draft.status.trimmingCharacters(in: .whitespacesAndNewlines),
            allowAuthorHistoryEdits: draft.allowAuthorHistoryEdits
        )
    }

    static func payload(_ draft: IdeaHistoryEditorDraft) -> IdeaHistoryEditorPayload {
        IdeaHistoryEditorPayload(
            eventType: draft.eventType.trimmingCharacters(in: .whitespacesAndNewlines),
            body: draft.body.trimmingCharacters(in: .whitespacesAndNewlines),
            metadata: draft.metadata
        )
    }

    static func payload(_ draft: NoteEditorDraft) -> NoteEditorPayload {
        NoteEditorPayload(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func payload(_ draft: TagEditorDraft) -> TagEditorPayload {
        let color = draft.colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        return TagEditorPayload(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: color.isEmpty ? nil : color
        )
    }

    private static func recurrenceIssues(
        _ draft: TaskEditorDraft,
        timezone: TimeZone
    ) -> [EditorField: EditorValidationIssue?] {
        guard let mode = draft.recurrence.mode else { return [:] }
        guard let anchor = draft.recurrence.resolvedAnchor(
            plannedAt: draft.plannedAt,
            dueAt: draft.dueAt
        ) else {
            return [.recurrence: .recurrenceAnchorRequired]
        }
        var errors: [EditorField: EditorValidationIssue?] = [:]
        if draft.recurrence.interval < 1 {
            errors[.recurrenceInterval] = .recurrenceIntervalInvalid
        }
        if let end = draft.recurrence.endAt, end <= anchor {
            errors[.recurrenceEnd] = .recurrenceEndInvalid
        }
        switch mode {
        case .daily:
            break
        case .weekly:
            if draft.recurrence.weekdays.isEmpty {
                errors[.recurrenceWeekdays] = .recurrenceWeekdayRequired
            } else if !draft.recurrence.weekdays.contains(localWeekday(anchor, timezone: timezone)) {
                errors[.recurrenceWeekdays] = .recurrenceAnchorWeekdayRequired
            }
        case .monthly:
            guard let day = draft.recurrence.dayOfMonth, (1...31).contains(day) else {
                errors[.recurrenceDayOfMonth] = .recurrenceDayInvalid
                return errors
            }
            if day != localDay(anchor, timezone: timezone) {
                errors[.recurrenceDayOfMonth] = .recurrenceAnchorDayRequired
            }
        }
        return errors
    }

    private static func checklistIssue(
        _ items: [ChecklistEditorItemDraft]
    ) -> EditorValidationIssue? {
        for item in items {
            if item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .required
            }
            if wireLength(item.text) > EditorLimits.checklistText {
                return .tooLong(maximum: EditorLimits.checklistText)
            }
        }
        return nil
    }

    private static func requiredLimited(
        _ value: String,
        maximum: Int
    ) -> EditorValidationIssue? {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .required
        }
        return limited(value, maximum: maximum)
    }

    private static func limited(
        _ value: String,
        maximum: Int
    ) -> EditorValidationIssue? {
        wireLength(value) > maximum ? .tooLong(maximum: maximum) : nil
    }

    private static func result(
        _ values: [EditorField: EditorValidationIssue?]
    ) -> EditorValidationResult {
        EditorValidationResult(
            errors: values.reduce(into: [:]) { result, entry in
                if let issue = entry.value { result[entry.key] = issue }
            }
        )
    }

    private static func wireLength(_ value: String) -> Int {
        value.utf16.count
    }

    private static func localWeekday(_ date: Date, timezone: TimeZone) -> DetailWeekday {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        switch calendar.component(.weekday, from: date) {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        default: .saturday
        }
    }

    private static func localDay(_ date: Date, timezone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar.component(.day, from: date)
    }

    private static func ordered(_ weekdays: Set<DetailWeekday>) -> [DetailWeekday] {
        DetailWeekday.allCases.filter(weekdays.contains)
    }
}
