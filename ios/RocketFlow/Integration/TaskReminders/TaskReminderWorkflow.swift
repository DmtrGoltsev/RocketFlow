import Foundation

protocol TaskReminderWorkflowServing: TaskReminderReading {
    func apply(
        taskID: UUID,
        title: String,
        dueAt: Date?,
        mutation: TaskReminderEditorMutation,
        taskState: ReminderTaskState,
        isNewTask: Bool
    ) async throws
    func taskStateDidChange(taskID: UUID, taskState: ReminderTaskState) async throws
}

protocol TaskReminderRecoveryClearing: Sendable {
    func clearReminderRecoveries() async
}

actor TaskReminderWorkflow: TaskReminderWorkflowServing {
    private let accountID: UUID
    private let timeZone: TimeZone
    private let store: any TaskReminderStoreServing
    private let scheduler: TaskReminderScheduler
    private let makeID: @Sendable () -> UUID

    init(
        accountID: UUID,
        timeZone: TimeZone,
        store: any TaskReminderStoreServing,
        scheduler: TaskReminderScheduler,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.accountID = accountID
        self.timeZone = timeZone
        self.store = store
        self.scheduler = scheduler
        self.makeID = makeID
    }

    func reminder(taskID: UUID) async throws -> LocalTaskReminder? {
        try await taskReminders(taskID: taskID).first
    }

    func apply(
        taskID: UUID,
        title: String,
        dueAt: Date?,
        mutation: TaskReminderEditorMutation,
        taskState: ReminderTaskState,
        isNewTask: Bool
    ) async throws {
        guard taskState.canNotify else {
            try await scheduler.cancelTask(accountID: accountID, taskID: taskID)
            return
        }

        switch mutation {
        case .remove:
            try await scheduler.cancelTask(accountID: accountID, taskID: taskID)
        case let .upsert(draft):
            try await replaceReminder(
                taskID: taskID,
                title: title,
                draft: draft,
                taskState: taskState
            )
        case .preserveOrDefault:
            let existing = try await taskReminders(taskID: taskID)
            if let current = existing.first {
                try await cancel(Array(existing.dropFirst()))
                try await schedule(
                    LocalTaskReminder(
                        id: current.id,
                        accountID: accountID,
                        taskID: taskID,
                        taskTitle: title,
                        triggerAt: current.triggerAt,
                        repeatRule: current.repeatRule,
                        enabled: current.enabled,
                        anchorAt: current.anchorAt
                    ),
                    taskState: taskState
                )
            } else if isNewTask {
                let setting = try await store.defaultReminder(accountID: accountID)
                if let dueAt, let setting, setting.enabled,
                   let reminder = TaskReminderSchedule.materializeDefault(
                       accountID: accountID,
                       taskID: taskID,
                       title: title,
                       dueAt: dueAt,
                       setting: setting,
                       reminderID: makeID()
                   ) {
                    try await schedule(reminder, taskState: taskState)
                }
            }
        }
    }

    func taskStateDidChange(taskID: UUID, taskState: ReminderTaskState) async throws {
        guard taskState.canNotify else {
            try await scheduler.cancelTask(accountID: accountID, taskID: taskID)
            return
        }
        let existing = try await taskReminders(taskID: taskID)
        if let current = existing.first {
            try await cancel(Array(existing.dropFirst()))
            try await schedule(current, taskState: taskState)
        }
    }

    private func replaceReminder(
        taskID: UUID,
        title: String,
        draft: TaskReminderEditorDraft,
        taskState: ReminderTaskState
    ) async throws {
        let existing = try await taskReminders(taskID: taskID)
        try await cancel(existing.filter { $0.id != draft.id })
        try await schedule(
            LocalTaskReminder(
                id: draft.id,
                accountID: accountID,
                taskID: taskID,
                taskTitle: title,
                triggerAt: draft.triggerAt,
                repeatRule: draft.repeatRule,
                anchorAt: draft.anchorAt
            ),
            taskState: taskState
        )
    }

    private func schedule(
        _ reminder: LocalTaskReminder,
        taskState: ReminderTaskState
    ) async throws {
        let result = try await scheduler.schedule(
            reminder,
            taskState: taskState,
            timeZone: timeZone
        )
        if result == .expired {
            throw TaskReminderSchedulingError.expired
        }
    }

    private func cancel(_ reminders: [LocalTaskReminder]) async throws {
        for reminder in reminders {
            try await scheduler.cancel(reminder)
        }
    }

    private func taskReminders(taskID: UUID) async throws -> [LocalTaskReminder] {
        try await store.reminders(accountID: accountID)
            .filter { $0.taskID == taskID }
            .sorted {
                if $0.triggerAt != $1.triggerAt { return $0.triggerAt < $1.triggerAt }
                return $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
            }
    }
}

actor TaskReminderEditorSavingAdapter: EditorSaving, EditorOperationRecoveryManaging,
    TaskReminderRecoveryClearing {
    private struct CompletedSave: Sendable {
        let request: EditorSaveRequest
        let result: EditorSaveResult
    }

    private let base: any EditorSaving
    private let reminders: any TaskReminderWorkflowServing
    private let now: @Sendable () -> Date
    private var completedTaskSaves: [UUID: CompletedSave] = [:]

    init(
        base: any EditorSaving,
        reminders: any TaskReminderWorkflowServing,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.base = base
        self.reminders = reminders
        self.now = now
    }

    func saveEditor(_ request: EditorSaveRequest) async throws -> EditorSaveResult {
        guard case let .task(mode, _, payload) = request else {
            return try await base.saveEditor(request)
        }
        try validateReminder(payload.reminder)

        let result: EditorSaveResult
        if let recovery = completedTaskSaves[payload.operationID] {
            guard Self.hasSameBaseMutation(recovery.request, request) else {
                throw EditorReminderFailure.operationIdentityReused
            }
            result = recovery.result
        } else {
            result = try await base.saveEditor(request)
            completedTaskSaves[payload.operationID] = CompletedSave(request: request, result: result)
        }

        do {
            try await reminders.apply(
                taskID: result.reference.id,
                title: payload.title,
                dueAt: payload.dueAt,
                mutation: payload.reminder,
                taskState: ReminderTaskState(payload.status),
                isNewTask: mode.isCreate
            )
            completedTaskSaves.removeValue(forKey: payload.operationID)
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as EditorReminderFailure {
            throw failure
        } catch TaskReminderSchedulingError.authorizationDenied {
            throw EditorReminderFailure.authorizationDenied
        } catch TaskReminderSchedulingError.authorizationRequestFailed {
            throw EditorReminderFailure.schedulingFailed
        } catch TaskReminderSchedulingError.expired {
            throw EditorReminderFailure.oneShotInPast
        } catch TaskReminderSchedulingError.pendingLimitReached {
            throw EditorReminderFailure.schedulingFailed
        } catch {
            // Keep the completed base result so retry only repeats the local reminder step.
            throw EditorReminderFailure.schedulingFailed
        }
    }

    func abandonEditorOperation(_ operationID: UUID) {
        completedTaskSaves.removeValue(forKey: operationID)
    }

    func clearEditorOperations() {
        completedTaskSaves.removeAll()
    }

    func clearReminderRecoveries() {
        completedTaskSaves.removeAll()
    }

    private func validateReminder(_ mutation: TaskReminderEditorMutation) throws {
        guard case let .upsert(reminder) = mutation,
              reminder.repeatRule == .none,
              reminder.triggerAt <= now() else {
            return
        }
        throw EditorReminderFailure.oneShotInPast
    }

    private static func hasSameBaseMutation(
        _ lhs: EditorSaveRequest,
        _ rhs: EditorSaveRequest
    ) -> Bool {
        guard case let .task(lhsMode, lhsGoalID, lhsPayload) = lhs,
              case let .task(rhsMode, rhsGoalID, rhsPayload) = rhs else {
            return lhs == rhs
        }
        return lhsMode == rhsMode
            && lhsGoalID == rhsGoalID
            && lhsPayload.mutationScope == rhsPayload.mutationScope
            && lhsPayload.title == rhsPayload.title
            && lhsPayload.description == rhsPayload.description
            && lhsPayload.status == rhsPayload.status
            && lhsPayload.type == rhsPayload.type
            && lhsPayload.effort == rhsPayload.effort
            && lhsPayload.plannedAt == rhsPayload.plannedAt
            && lhsPayload.dueAt == rhsPayload.dueAt
            && lhsPayload.recurrence == rhsPayload.recurrence
            && lhsPayload.checklist == rhsPayload.checklist
            && lhsPayload.tagIDs == rhsPayload.tagIDs
    }
}

actor TaskReminderDetailMutationAdapter: DetailMutationPerforming, TaskReminderRecoveryClearing {
    private struct CompletedMutation: Sendable {
        let mutation: DetailMutation
        let result: DetailMutationResult
    }

    private let base: any DetailMutationPerforming
    private let reminders: any TaskReminderWorkflowServing
    private var completedMutations: [CompletedMutation] = []

    init(base: any DetailMutationPerforming, reminders: any TaskReminderWorkflowServing) {
        self.base = base
        self.reminders = reminders
    }

    func performDetailMutation(_ mutation: DetailMutation) async throws -> DetailMutationResult {
        guard let taskState = mutation.reminderTaskState else {
            return try await base.performDetailMutation(mutation)
        }

        let recoveryIndex = completedMutations.firstIndex { $0.mutation == mutation }
        let result: DetailMutationResult
        if let recoveryIndex {
            result = completedMutations[recoveryIndex].result
        } else {
            result = try await base.performDetailMutation(mutation)
            completedMutations.append(CompletedMutation(mutation: mutation, result: result))
        }

        do {
            try await reminders.taskStateDidChange(
                taskID: mutation.reminderTaskID,
                taskState: taskState
            )
            completedMutations.removeAll { $0.mutation == mutation }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Preserve the completed base result so a retry only repairs local reminder state.
            throw error
        }
    }

    func clearReminderRecoveries() {
        completedMutations.removeAll()
    }
}

struct TaskReminderEditorSeedLoader: PlannerDetailsEditorSeedLoading {
    private let base: any PlannerDetailsEditorSeedLoading
    private let reminders: any TaskReminderReading

    init(base: any PlannerDetailsEditorSeedLoading, reminders: any TaskReminderReading) {
        self.base = base
        self.reminders = reminders
    }

    func editorSeed(for route: DetailEditorRoute) async throws -> PlannerDetailsEditorSeed {
        let seed = try await base.editorSeed(for: route)
        guard
            case let .edit(reference) = route,
            reference.kind == .task,
            case var .task(draft, goalID, access, isInFocus) = seed
        else {
            return seed
        }
        if let reminder = try await reminders.reminder(taskID: reference.id) {
            draft.reminder = .upsert(TaskReminderEditorDraft(reminder))
        } else {
            draft.reminder = .remove
        }
        return .task(draft, goalID: goalID, access: access, isInFocus: isInFocus)
    }
}

private extension TaskReminderEditorDraft {
    init(_ reminder: LocalTaskReminder) {
        self.init(
            id: reminder.id,
            triggerAt: reminder.triggerAt,
            repeatRule: reminder.repeatRule,
            anchorAt: reminder.anchorAt
        )
    }
}

private extension ReminderTaskState {
    init(_ status: DetailTaskStatus) {
        switch status {
        case .todo, .inProgress: self = .active
        case .done: self = .done
        case .cancelled: self = .cancelled
        }
    }
}

private extension EditorMode {
    var isCreate: Bool {
        if case .create = self { return true }
        return false
    }
}

private extension DetailMutation {
    var reminderTaskID: UUID {
        switch self {
        case let .delete(reference): reference.id
        case let .updateTaskStatus(taskID, _, _): taskID
        case let .replaceChecklist(taskID, _): taskID
        case let .setFocus(taskID, _): taskID
        case let .createIdeaHistory(ideaID, _, _, _): ideaID
        case let .updateIdeaHistory(ideaID, _): ideaID
        case let .deleteIdeaHistory(ideaID, _): ideaID
        }
    }

    var reminderTaskState: ReminderTaskState? {
        switch self {
        case let .delete(reference) where reference.kind == .task:
            .missing
        case let .updateTaskStatus(_, status, _):
            ReminderTaskState(status)
        case .delete, .replaceChecklist, .setFocus,
             .createIdeaHistory, .updateIdeaHistory, .deleteIdeaHistory:
            nil
        }
    }
}
