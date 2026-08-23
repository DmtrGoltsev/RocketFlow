import Foundation

extension PlannerDetailsAdapter {
    func perform(_ action: PlannerMutationAction) async throws -> PlannerMutationResult {
        do {
            switch action {
            case let .delete(reference):
                try await deleteReference(
                    DetailEntityReference(kind: detailKind(reference.kind), id: reference.id)
                )
            case let .updateTaskStatus(reference, status):
                guard reference.kind == .task else {
                    throw PlannerDetailsIntegrationError.unsupported(
                        operation: "status_update_requires_task"
                    )
                }
                try await updateTaskStatus(localID: reference.id, status: status)
            }
            let local = try await repository.snapshot()
            let goalIDs = try await persistence.cachedCreateTaskGoalIDs()
            return PlannerMutationResult(
                snapshot: plannerSnapshot(local, createTaskGoalIDs: goalIDs)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PlannerDetailsErrorTranslator.map(error)
        }
    }

    func performDetailMutation(_ mutation: DetailMutation) async throws -> DetailMutationResult {
        do {
            let reference: DetailEntityReference?
            switch mutation {
            case let .delete(value):
                try await deleteReference(value)
                return DetailMutationResult()
            case let .updateTaskStatus(taskID, status, _):
                try await updateTaskStatus(
                    localID: taskID,
                    status: PlanningStatus(rawValue: status.rawValue) ?? .todo
                )
                reference = DetailEntityReference(kind: .task, id: taskID)
            case let .replaceChecklist(taskID, items):
                try await replaceChecklist(taskID: taskID, items: items)
                reference = DetailEntityReference(kind: .task, id: taskID)
            case let .setFocus(taskID, focused):
                try await setTaskFocus(taskID: taskID, focused: focused)
                reference = DetailEntityReference(kind: .task, id: taskID)
            case let .createIdeaHistory(ideaID, eventType, body, metadata):
                _ = try await saveIdeaHistory(
                    mode: .create,
                    ideaID: ideaID,
                    payload: IdeaHistoryEditorPayload(
                        eventType: eventType,
                        body: body,
                        metadata: metadata
                    )
                )
                reference = DetailEntityReference(kind: .idea, id: ideaID)
            case let .updateIdeaHistory(ideaID, note):
                _ = try await saveIdeaHistory(
                    mode: .editIdeaHistory(ideaID: ideaID, noteID: note.id),
                    ideaID: ideaID,
                    payload: IdeaHistoryEditorPayload(
                        eventType: note.eventType,
                        body: note.body,
                        metadata: note.metadata
                    )
                )
                reference = DetailEntityReference(kind: .idea, id: ideaID)
            case let .deleteIdeaHistory(ideaID, noteID):
                try await deleteIdeaHistory(ideaID: ideaID, noteID: noteID)
                reference = DetailEntityReference(kind: .idea, id: ideaID)
            }
            guard let reference else { return DetailMutationResult() }
            let content = try await currentDetail(reference)
            let pending = try await persistence.hasPendingMutation(
                kind: PlanningEntityKind(reference.kind),
                localID: reference.id
            )
            return DetailMutationResult(content: content, pending: pending)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PlannerDetailsErrorTranslator.detailFailure(error)
        }
    }

    func saveEditor(_ request: EditorSaveRequest) async throws -> EditorSaveResult {
        do {
            switch request {
            case let .folder(mode, parentFolderID, payload):
                return try await saveFolder(
                    mode: mode,
                    parentFolderID: parentFolderID,
                    payload: payload
                )
            case let .goal(mode, folderID, payload):
                return try await saveGoal(mode: mode, folderID: folderID, payload: payload)
            case let .task(mode, goalID, payload):
                return try await saveTask(mode: mode, goalID: goalID, payload: payload)
            case let .idea(mode, folderID, payload):
                return try await saveIdea(mode: mode, folderID: folderID, payload: payload)
            case let .ideaHistory(mode, ideaID, payload):
                return try await saveIdeaHistory(mode: mode, ideaID: ideaID, payload: payload)
            case let .note(mode, folderID, payload):
                return try await saveNote(mode: mode, folderID: folderID, payload: payload)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PlannerDetailsErrorTranslator.map(error)
        }
    }

    func createTag(_ payload: TagEditorPayload) async throws -> TagEditorItemDraft {
        do {
            let remote = try await requireRemote(operation: "tag.create")
            let value = try await remote.createTag(
                CreateTagRequestDTO(name: payload.name, color: payload.colorHex)
            )
            let localID = makeID()
            try await persistence.bindAndApply(
                kind: .tag,
                localID: localID,
                remoteID: value.id,
                version: 0,
                payloadJSON: WireJSON.encoder().encode(value)
            )
            return TagEditorItemDraft(
                id: localID,
                name: value.name,
                colorHex: value.color,
                assigned: false
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PlannerDetailsErrorTranslator.map(error)
        }
    }

    func setTaskFocus(taskID: UUID, focused: Bool) async throws {
        do {
            guard let focus else {
                throw PlannerDetailsIntegrationError.unsupported(operation: "focus.adapter_missing")
            }
            let snapshot = try await repository.snapshot()
            guard let task = snapshot.tasks.first(where: { $0.id == taskID }),
                  let goal = snapshot.goals.first(where: { $0.id == task.goalId }),
                  let folder = snapshot.folders.first(where: { $0.id == goal.folderId }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .task, id: taskID)
            }
            let remoteTaskID = try await persistence.remoteID(for: .task, localID: task.id)
            let remoteGoalID = try await persistence.remoteID(for: .goal, localID: goal.id)
            let remoteFolderID = try await persistence.remoteID(for: .folder, localID: folder.id)
            let current = try await focus.loadCurrent(
                accountID: account.accountID,
                timezone: account.timezone
            )
            let alreadyFocused = current.period?.items.contains {
                !$0.historyOnly && $0.taskId == remoteTaskID
            } == true
            guard alreadyFocused != focused else { return }
            if focused {
                let candidate = FocusCandidateDTO(
                    taskId: remoteTaskID,
                    title: task.title,
                    status: task.status,
                    effort: task.effort,
                    effectiveWeight: max(task.effort, 1),
                    plannedTime: task.plannedTime,
                    dueTime: task.dueTime,
                    folderId: remoteFolderID,
                    folderTitle: folder.name,
                    goalId: remoteGoalID,
                    goalTitle: goal.name,
                    shared: task.shared,
                    canWrite: !task.shared || task.fullAccess,
                    inFocus: false
                )
                _ = try await focus.add(accountID: account.accountID, candidate: candidate)
            } else {
                _ = try await focus.remove(accountID: account.accountID, taskID: remoteTaskID)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PlannerDetailsErrorTranslator.map(error)
        }
    }

    private func saveFolder(
        mode: EditorMode,
        parentFolderID: UUID?,
        payload: FolderEditorPayload
    ) async throws -> EditorSaveResult {
        let snapshot = try await repository.snapshot()
        switch mode {
        case .create:
            if let parentFolderID {
                _ = try requireWritableFolder(parentFolderID, snapshot: snapshot)
            }
            let value = try await repository.createFolder(
                FolderDraft(
                    id: makeID(),
                    parentFolderID: parentFolderID,
                    name: payload.name,
                    description: payload.description
                )
            )
            return EditorSaveResult(
                reference: DetailEntityReference(kind: .folder, id: value.id),
                pending: true
            )
        case let .edit(reference):
            try require(reference, kind: .folder)
            _ = try requireWritableFolder(reference.id, snapshot: snapshot)
            try ensureNoActiveRemoteOperation(kind: .folder, localID: reference.id)
            try await repository.updateFolder(
                id: reference.id,
                name: payload.name,
                description: payload.description
            )
            return EditorSaveResult(reference: reference, pending: true)
        case .editIdeaHistory:
            throw PlannerDetailsIntegrationError.unsupported(operation: "folder.idea_history_mode")
        }
    }

    private func saveGoal(
        mode: EditorMode,
        folderID: UUID,
        payload: GoalEditorPayload
    ) async throws -> EditorSaveResult {
        let snapshot = try await repository.snapshot()
        _ = try requireWritableFolder(folderID, snapshot: snapshot)
        let draft = GoalDraft(
            folderID: folderID,
            name: payload.name,
            description: payload.description,
            status: PlanningStatus(rawValue: payload.status.rawValue) ?? .todo
        )
        switch mode {
        case .create:
            let value = try await repository.createGoal(
                GoalDraft(
                    id: makeID(),
                    folderID: draft.folderID,
                    name: draft.name,
                    description: draft.description,
                    status: draft.status
                )
            )
            return EditorSaveResult(
                reference: DetailEntityReference(kind: .goal, id: value.id),
                pending: true
            )
        case let .edit(reference):
            try require(reference, kind: .goal)
            _ = try requireWritableGoal(reference.id, snapshot: snapshot)
            try ensureNoActiveRemoteOperation(kind: .goal, localID: reference.id)
            try await repository.updateGoal(
                id: reference.id,
                draft: GoalDraft(
                    id: reference.id,
                    folderID: draft.folderID,
                    name: draft.name,
                    description: draft.description,
                    status: draft.status
                )
            )
            return EditorSaveResult(reference: reference, pending: true)
        case .editIdeaHistory:
            throw PlannerDetailsIntegrationError.unsupported(operation: "goal.idea_history_mode")
        }
    }

    private func saveTask(
        mode: EditorMode,
        goalID: UUID,
        payload: TaskEditorPayload
    ) async throws -> EditorSaveResult {
        let snapshot = try await repository.snapshot()
        switch mode {
        case .create:
            try await requireTaskCreationAccess(goalID: goalID, snapshot: snapshot)
            if payload.recurrence != nil {
                return try await createRemoteTask(goalID: goalID, payload: payload)
            }
            let localID = makeID()
            _ = try await persistence.saveTaskAggregate(
                draft: taskDraft(id: localID, goalID: goalID, payload: payload),
                checklist: aggregateChecklist(payload.checklist),
                tagIDs: payload.tagIDs,
                creating: true
            )
            return EditorSaveResult(
                reference: DetailEntityReference(kind: .task, id: localID),
                pending: true
            )
        case let .edit(reference):
            try require(reference, kind: .task)
            guard let current = snapshot.tasks.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .task, id: reference.id)
            }
            if payload.mutationScope == .statusOnly {
                guard current.shared && !current.fullAccess else {
                    throw PlannerDetailsIntegrationError.forbidden(
                        code: "status_only_scope_invalid",
                        message: "Status-only scope is valid only for read-only shared tasks."
                    )
                }
                try await updateTaskStatus(
                    localID: current.id,
                    status: PlanningStatus(rawValue: payload.status.rawValue) ?? .todo
                )
                return EditorSaveResult(reference: reference, pending: true)
            }
            try requireFullAccess(shared: current.shared, fullAccess: current.fullAccess)
            if goalID != current.goalId {
                _ = try requireWritableGoal(goalID, snapshot: snapshot)
            }
            if payload.recurrence != nil || current.recurrence != nil {
                return try await updateRemoteTask(current: current, payload: payload)
            }
            try ensureNoActiveRemoteOperation(kind: .task, localID: current.id)
            _ = try await persistence.saveTaskAggregate(
                draft: taskDraft(id: current.id, goalID: goalID, payload: payload),
                checklist: aggregateChecklist(payload.checklist),
                tagIDs: payload.tagIDs,
                creating: false
            )
            return EditorSaveResult(reference: reference, pending: true)
        case .editIdeaHistory:
            throw PlannerDetailsIntegrationError.unsupported(operation: "task.idea_history_mode")
        }
    }

    private func createRemoteTask(
        goalID: UUID,
        payload: TaskEditorPayload
    ) async throws -> EditorSaveResult {
        let remote = try await requireRemote(operation: "task.create_recurrence")
        let remoteGoalID = try await persistence.remoteID(for: .goal, localID: goalID)
        let remoteTags = try await remoteTagIDs(payload.tagIDs)
        let createRequest = CreateTaskRequestDTO(
            title: payload.title,
            description: payload.description,
            type: TaskType(rawValue: payload.type.rawValue) ?? .green,
            effort: payload.effort,
            status: PlanningStatus(rawValue: payload.status.rawValue) ?? .todo,
            plannedTime: payload.plannedAt,
            dueTime: payload.dueAt,
            checklistItems: payload.checklist.map {
                ChecklistItemRequestDTO(
                    id: nil,
                    text: $0.text,
                    checked: $0.checked,
                    displayOrder: $0.displayOrder
                )
            },
            tagIds: remoteTags
        )
        guard let recurrence = recurrenceRequest(payload.recurrence, current: nil) else {
            throw PlannerDetailsIntegrationError.validation(
                message: "Recurring task creation requires a recurrence rule.",
                fields: ["recurrence": "required"]
            )
        }
        let operationKey = try recurrenceCreateOperationKey(
            goalID: remoteGoalID,
            task: createRequest,
            recurrence: recurrence
        )
        if let recovery = try await persistence.recurrenceCreateRecovery(operationKey: operationKey) {
            return try await finishRecurrenceCreate(
                operationKey: operationKey,
                recovery: recovery,
                recurrence: recurrence,
                remote: remote
            )
        }

        let localID = makeID()
        let response = try await remote.createTask(goalID: remoteGoalID, request: createRequest)
        do {
            try await persistence.beginRecurrenceCreateRecovery(
                operationKey: operationKey,
                localID: localID,
                response: response
            )
        } catch {
            try? await remote.deleteTask(id: response.id)
            throw error
        }
        return try await finishRecurrenceCreate(
            operationKey: operationKey,
            recovery: PlannerDetailsRecurrenceCreateRecovery(localID: localID, response: response),
            recurrence: recurrence,
            remote: remote
        )
    }

    private func updateRemoteTask(
        current: TaskDTO,
        payload: TaskEditorPayload
    ) async throws -> EditorSaveResult {
        let remote = try await requireRemote(operation: "task.update_recurrence")
        let lease = try await beginRemoteOperation(kind: .task, localID: current.id)
        defer { endRemoteOperation(lease) }
        let remoteID = try await persistence.remoteID(for: .task, localID: current.id)
        let actionCurrent = try PlannerDetailsDTOMapper.actionTask(current)
        let checklist = try await checklistRequests(
            taskID: current.id,
            values: payload.checklist
        )
        let response = try await remote.updateTask(
            id: remoteID,
            request: ActionUpdateTaskRequestDTO(
                preservingPriorityFrom: actionCurrent,
                title: payload.title,
                description: payload.description,
                type: TaskType(rawValue: payload.type.rawValue) ?? .green,
                effort: payload.effort,
                status: PlanningStatus(rawValue: payload.status.rawValue) ?? .todo,
                plannedTime: payload.plannedAt,
                dueTime: payload.dueAt,
                archived: current.archived,
                tagIds: try await remoteTagIDs(payload.tagIDs),
                checklistItems: checklist
            )
        )
        let applyResult = try await persist(
            response,
            localID: current.id,
            expectedGeneration: lease.generation
        )
        try requireApplied(applyResult)
        let postApplyGeneration = try await persistence.mutationGeneration(
            kind: .task,
            localID: current.id
        )
        do {
            try await applyRecurrence(
                payload.recurrence,
                current: current.recurrence,
                taskLocalID: current.id,
                taskRemoteID: remoteID,
                remote: remote
            )
        } catch {
            do {
                let rollback = try await remote.updateTask(
                    id: remoteID,
                    request: ActionUpdateTaskRequestDTO(
                        preservingPriorityFrom: response,
                        title: actionCurrent.title,
                        description: actionCurrent.description,
                        type: actionCurrent.type,
                        effort: actionCurrent.effort,
                        status: actionCurrent.status,
                        plannedTime: actionCurrent.plannedTime,
                        dueTime: actionCurrent.dueTime,
                        archived: actionCurrent.archived,
                        tagIds: try await remoteTagIDs(current.tags.map(\.id)),
                        checklistItems: try await checklistRequests(
                            taskID: current.id,
                            values: current.checklistItems.map {
                                ChecklistEditorPayload(
                                    id: $0.id,
                                    text: $0.text,
                                    checked: $0.checked,
                                    displayOrder: $0.displayOrder
                                )
                            }
                        )
                    )
                )
                try requireApplied(
                    try await persist(
                        rollback,
                        localID: current.id,
                        expectedGeneration: postApplyGeneration
                    )
                )
            } catch {
                throw PlannerDetailsIntegrationError.conflict(
                    code: "recurrence_update_reconciliation_required",
                    message: "Task fields changed on the server, but recurrence failed; reload before retrying."
                )
            }
            throw error
        }
        return EditorSaveResult(
            reference: DetailEntityReference(kind: .task, id: current.id),
            pending: false
        )
    }

    private func saveIdea(
        mode: EditorMode,
        folderID: UUID,
        payload: IdeaEditorPayload
    ) async throws -> EditorSaveResult {
        let remote = try await requireRemote(operation: "idea.save")
        switch mode {
        case .create:
            _ = try requireWritableFolder(folderID, snapshot: try await repository.snapshot())
            let remoteFolderID = try await persistence.remoteID(for: .folder, localID: folderID)
            let value = try await remote.createIdea(
                folderID: remoteFolderID,
                request: CreateIdeaRequestDTO(
                    title: payload.title,
                    body: payload.body,
                    status: payload.status,
                    allowAuthorNoteEdits: payload.allowAuthorHistoryEdits
                )
            )
            let localID = makeID()
            try await persist(value, localID: localID)
            return EditorSaveResult(
                reference: DetailEntityReference(kind: .idea, id: localID),
                pending: false
            )
        case let .edit(reference):
            try require(reference, kind: .idea)
            let current = try await requireIdea(reference.id)
            try requireFullAccess(shared: current.shared, fullAccess: current.fullAccess)
            let lease = try await beginRemoteOperation(kind: .idea, localID: current.id)
            defer { endRemoteOperation(lease) }
            let remoteID = try await persistence.remoteID(for: .idea, localID: current.id)
            let value = try await remote.updateIdea(
                id: remoteID,
                request: UpdateIdeaRequestDTO(
                    title: payload.title,
                    body: payload.body,
                    status: payload.status,
                    displayOrder: current.displayOrder,
                    archived: current.archived,
                    allowAuthorNoteEdits: payload.allowAuthorHistoryEdits,
                    version: current.version
                )
            )
            try requireApplied(
                try await persist(value, localID: current.id, expectedGeneration: lease.generation)
            )
            return EditorSaveResult(reference: reference, pending: false)
        case .editIdeaHistory:
            throw PlannerDetailsIntegrationError.unsupported(operation: "idea.idea_history_mode")
        }
    }

    private func saveIdeaHistory(
        mode: EditorMode,
        ideaID: UUID,
        payload: IdeaHistoryEditorPayload
    ) async throws -> EditorSaveResult {
        let remote = try await requireRemote(operation: "idea_note.save")
        let idea = try await requireIdea(ideaID)
        switch mode {
        case .create:
            let remoteIdeaID = try await persistence.remoteID(for: .idea, localID: ideaID)
            let value = try await remote.createIdeaNote(
                ideaID: remoteIdeaID,
                request: CreateIdeaNoteRequestDTO(
                    eventType: payload.eventType,
                    body: payload.body,
                    metadata: payload.metadata.mapValues { .string($0) }
                )
            )
            let localID = makeID()
            try await persist(value, localID: localID)
        case let .editIdeaHistory(routeIdeaID, noteID):
            guard routeIdeaID == ideaID else {
                throw PlannerDetailsIntegrationError.validation(
                    message: "Idea history parent mismatch.",
                    fields: ["ideaId": "mismatch"]
                )
            }
            let notes = try await persistence.ideaNotes(ideaID: ideaID)
            guard let note = notes.first(where: { $0.id == noteID }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .ideaNote, id: noteID)
            }
            let isCreator = idea.creatorUserId.map { $0 == account.currentUserID } ?? !idea.shared
            let isAuthor = note.authorUserId == account.currentUserID
            guard isCreator || isAuthor else {
                throw PlannerDetailsIntegrationError.notFound(kind: .ideaNote, id: noteID)
            }
            let lease = try await beginRemoteOperation(kind: .ideaNote, localID: noteID)
            defer { endRemoteOperation(lease) }
            let remoteNoteID = try await persistence.remoteID(for: .ideaNote, localID: noteID)
            let value = try await remote.updateIdeaNote(
                id: remoteNoteID,
                request: UpdateIdeaNoteRequestDTO(
                    eventType: payload.eventType,
                    body: payload.body,
                    metadata: payload.metadata.mapValues { .string($0) },
                    version: note.version
                )
            )
            try requireApplied(
                try await persist(value, localID: noteID, expectedGeneration: lease.generation)
            )
        case .edit:
            throw PlannerDetailsIntegrationError.unsupported(
                operation: "idea_note_requires_editIdeaHistory_mode"
            )
        }
        return EditorSaveResult(
            reference: DetailEntityReference(kind: .idea, id: ideaID),
            pending: false
        )
    }

    private func saveNote(
        mode: EditorMode,
        folderID: UUID,
        payload: NoteEditorPayload
    ) async throws -> EditorSaveResult {
        let remote = try await requireRemote(operation: "note.save")
        switch mode {
        case .create:
            _ = try requireWritableFolder(folderID, snapshot: try await repository.snapshot())
            let remoteFolderID = try await persistence.remoteID(for: .folder, localID: folderID)
            let value = try await remote.createNote(
                folderID: remoteFolderID,
                request: CreateNoteRequestDTO(title: payload.title, body: payload.body)
            )
            let localID = makeID()
            try await persist(value, localID: localID)
            return EditorSaveResult(
                reference: DetailEntityReference(kind: .note, id: localID),
                pending: false
            )
        case let .edit(reference):
            try require(reference, kind: .note)
            let current = try await requireNote(reference.id)
            try requireFullAccess(shared: current.shared, fullAccess: current.fullAccess)
            let lease = try await beginRemoteOperation(kind: .note, localID: current.id)
            defer { endRemoteOperation(lease) }
            let remoteID = try await persistence.remoteID(for: .note, localID: current.id)
            let value = try await remote.updateNote(
                id: remoteID,
                request: UpdateNoteRequestDTO(
                    title: payload.title,
                    body: payload.body,
                    displayOrder: current.displayOrder,
                    archived: current.archived,
                    version: current.version
                )
            )
            try requireApplied(
                try await persist(value, localID: current.id, expectedGeneration: lease.generation)
            )
            return EditorSaveResult(reference: reference, pending: false)
        case .editIdeaHistory:
            throw PlannerDetailsIntegrationError.unsupported(operation: "note.idea_history_mode")
        }
    }

    private func updateTaskStatus(localID: UUID, status: PlanningStatus) async throws {
        let snapshot = try await repository.snapshot()
        guard let task = snapshot.tasks.first(where: { $0.id == localID }) else {
            throw PlannerDetailsIntegrationError.notFound(kind: .task, id: localID)
        }
        try ensureNoActiveRemoteOperation(kind: .task, localID: localID)
        try await repository.updateTask(
            id: localID,
            draft: TaskDraft(
                id: localID,
                goalID: task.goalId,
                title: task.title,
                description: task.description,
                type: task.type,
                effort: task.effort,
                status: status,
                plannedTime: task.plannedTime,
                dueTime: task.dueTime
            )
        )
    }

    private func replaceChecklist(
        taskID: UUID,
        items: [DetailChecklistItemViewData]
    ) async throws {
        let snapshot = try await repository.snapshot()
        guard let task = snapshot.tasks.first(where: { $0.id == taskID }) else {
            throw PlannerDetailsIntegrationError.notFound(kind: .task, id: taskID)
        }
        try requireFullAccess(shared: task.shared, fullAccess: task.fullAccess)
        try ensureNoActiveRemoteOperation(kind: .task, localID: taskID)
        let payload = items.enumerated().map { index, item in
            ChecklistEditorPayload(
                id: item.id,
                text: item.text,
                checked: item.checked,
                displayOrder: index
            )
        }
        _ = try await persistence.saveTaskAggregate(
            draft: TaskDraft(
                id: task.id,
                goalID: task.goalId,
                title: task.title,
                description: task.description,
                type: task.type,
                effort: task.effort,
                status: task.status,
                plannedTime: task.plannedTime,
                dueTime: task.dueTime
            ),
            checklist: aggregateChecklist(payload),
            tagIDs: task.tags.map(\.id),
            creating: false
        )
    }

    private func checklistRequests(
        taskID: UUID,
        values: [ChecklistEditorPayload]
    ) async throws -> [ChecklistItemRequestDTO] {
        var result: [ChecklistItemRequestDTO] = []
        for item in values {
            let remoteID: UUID?
            if let localID = item.id {
                remoteID = try await persistence.checklistRemoteID(
                    localID: localID,
                    taskID: taskID
                )
            } else {
                remoteID = nil
            }
            result.append(
                ChecklistItemRequestDTO(
                    id: remoteID,
                    text: item.text,
                    checked: item.checked,
                    displayOrder: item.displayOrder
                )
            )
        }
        return result
    }

    private func remoteTagIDs(_ localIDs: [UUID]) async throws -> [UUID] {
        var values: [UUID] = []
        for localID in localIDs {
            values.append(try await persistence.remoteID(for: .tag, localID: localID))
        }
        return canonicalUUIDs(values)
    }

    private func applyRecurrence(
        _ payload: TaskRecurrenceEditorPayload?,
        current: RecurrenceDTO?,
        taskLocalID: UUID,
        taskRemoteID: UUID,
        remote: any PlannerDetailsRemoteActioning
    ) async throws {
        let request = recurrenceRequest(payload, current: current)
        guard let request else { return }
        let response = try await remote.upsertTaskRecurrence(id: taskRemoteID, request: request)
        try await persistence.setTaskRecurrence(
            localID: taskLocalID,
            recurrence: response.recurrence
        )
    }

    private func recurrenceRequest(
        _ payload: TaskRecurrenceEditorPayload?,
        current: RecurrenceDTO?
    ) -> UpsertRecurrenceRequestDTO? {
        if let payload {
            return UpsertRecurrenceRequestDTO(
                mode: RecurrenceMode(rawValue: payload.mode.rawValue) ?? .daily,
                interval: payload.interval,
                daysOfWeek: canonicalWeekdays(
                    payload.weekdays.map { Weekday(rawValue: $0.rawValue) ?? .monday }
                ),
                dayOfMonth: payload.dayOfMonth,
                startAt: payload.anchor,
                endAt: payload.endAt,
                active: payload.active
            )
        }
        guard let current else { return nil }
        return UpsertRecurrenceRequestDTO(
            mode: current.mode,
            interval: current.interval,
            daysOfWeek: current.daysOfWeek,
            dayOfMonth: current.dayOfMonth,
            startAt: current.startAt,
            endAt: current.endAt,
            active: false
        )
    }

    private func recurrenceCreateOperationKey(
        goalID: UUID,
        task: CreateTaskRequestDTO,
        recurrence: UpsertRecurrenceRequestDTO
    ) throws -> String {
        let canonicalTask = CreateTaskRequestDTO(
            title: task.title,
            description: task.description,
            type: task.type,
            effort: task.effort,
            status: task.status,
            plannedTime: task.plannedTime,
            dueTime: task.dueTime,
            checklistItems: task.checklistItems,
            tagIds: task.tagIds.map { canonicalUUIDs($0) }
        )
        let canonicalRecurrence = UpsertRecurrenceRequestDTO(
            mode: recurrence.mode,
            interval: recurrence.interval,
            daysOfWeek: recurrence.daysOfWeek.map { canonicalWeekdays($0) },
            dayOfMonth: recurrence.dayOfMonth,
            startAt: recurrence.startAt,
            endAt: recurrence.endAt,
            active: recurrence.active
        )
        let identity = PlannerDetailsRecurrenceCreateIdentity(
            goalID: goalID,
            task: canonicalTask,
            recurrence: canonicalRecurrence
        )
        let encoder = WireJSON.encoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(identity).base64EncodedString()
    }

    private func canonicalUUIDs(_ values: [UUID]) -> [UUID] {
        values.sorted {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        }
    }

    private func canonicalWeekdays(_ values: [Weekday]) -> [Weekday] {
        values.sorted {
            let lhs = Weekday.allCases.firstIndex(of: $0) ?? Weekday.allCases.endIndex
            let rhs = Weekday.allCases.firstIndex(of: $1) ?? Weekday.allCases.endIndex
            return lhs < rhs
        }
    }

    private func finishRecurrenceCreate(
        operationKey: String,
        recovery: PlannerDetailsRecurrenceCreateRecovery,
        recurrence: UpsertRecurrenceRequestDTO,
        remote: any PlannerDetailsRemoteActioning
    ) async throws -> EditorSaveResult {
        let lease = try await beginRemoteOperation(kind: .task, localID: recovery.localID)
        defer { endRemoteOperation(lease) }
        do {
            let response = try await remote.upsertTaskRecurrence(
                id: recovery.response.id,
                request: recurrence
            )
            try await persistence.completeRecurrenceCreateRecovery(
                operationKey: operationKey,
                localID: recovery.localID,
                recurrence: response.recurrence
            )
            return EditorSaveResult(
                reference: DetailEntityReference(kind: .task, id: recovery.localID),
                pending: false
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let recurrenceError = error
            do {
                try await remote.deleteTask(id: recovery.response.id)
                try await persistence.discardRecurrenceCreateRecovery(
                    operationKey: operationKey,
                    localID: recovery.localID
                )
            } catch {
                throw PlannerDetailsIntegrationError.conflict(
                    code: "recurrence_create_reconciliation_required",
                    message: "Task creation reached the server, but recurrence failed; retry resumes the same operation."
                )
            }
            throw recurrenceError
        }
    }

    private func deleteReference(_ reference: DetailEntityReference) async throws {
        let snapshot = try await repository.snapshot()
        switch reference.kind {
        case .folder:
            guard let value = snapshot.folders.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .folder, id: reference.id)
            }
            try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
            try ensureNoActiveRemoteOperation(kind: .folder, localID: value.id)
            try await repository.delete(.folder, id: reference.id)
        case .goal:
            guard let value = snapshot.goals.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .goal, id: reference.id)
            }
            try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
            try ensureNoActiveRemoteOperation(kind: .goal, localID: value.id)
            try await repository.delete(.goal, id: reference.id)
        case .task:
            guard let value = snapshot.tasks.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .task, id: reference.id)
            }
            try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
            try ensureNoActiveRemoteOperation(kind: .task, localID: value.id)
            try await repository.delete(.task, id: reference.id)
        case .idea:
            let value = try await requireIdea(reference.id)
            let isCreator = value.creatorUserId.map { $0 == account.currentUserID } ?? !value.shared
            guard isCreator else {
                throw PlannerDetailsIntegrationError.notFound(kind: .idea, id: value.id)
            }
            let remote = try await requireRemote(operation: "idea.delete")
            let lease = try await beginRemoteOperation(kind: .idea, localID: value.id)
            defer { endRemoteOperation(lease) }
            let remoteID = try await persistence.remoteID(for: .idea, localID: value.id)
            try await remote.deleteIdea(id: remoteID)
            try await persistence.removeSynced(kind: .idea, localID: value.id)
        case .note:
            let value = try await requireNote(reference.id)
            try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
            let remote = try await requireRemote(operation: "note.delete")
            let lease = try await beginRemoteOperation(kind: .note, localID: value.id)
            defer { endRemoteOperation(lease) }
            let remoteID = try await persistence.remoteID(for: .note, localID: value.id)
            try await remote.deleteNote(id: remoteID)
            try await persistence.removeSynced(kind: .note, localID: value.id)
        }
    }

    private func deleteIdeaHistory(ideaID: UUID, noteID: UUID) async throws {
        let idea = try await requireIdea(ideaID)
        let isCreator = idea.creatorUserId.map { $0 == account.currentUserID } ?? !idea.shared
        guard isCreator else {
            throw PlannerDetailsIntegrationError.notFound(kind: .ideaNote, id: noteID)
        }
        let remote = try await requireRemote(operation: "idea_note.delete")
        let lease = try await beginRemoteOperation(kind: .ideaNote, localID: noteID)
        defer { endRemoteOperation(lease) }
        let remoteID = try await persistence.remoteID(for: .ideaNote, localID: noteID)
        try await remote.deleteIdeaNote(id: remoteID)
        try await persistence.removeSynced(kind: .ideaNote, localID: noteID)
    }

    func requireRemote(operation: String) async throws -> any PlannerDetailsRemoteActioning {
        guard await network.isConnected() else {
            throw PlannerDetailsIntegrationError.networkRequired
        }
        guard let remote else {
            throw PlannerDetailsIntegrationError.unsupported(operation: "\(operation).adapter_missing")
        }
        return remote
    }

    func requireNoPending(kind: PlanningEntityKind, localID: UUID) async throws {
        if try await persistence.hasPendingMutation(kind: kind, localID: localID) {
            throw PlannerDetailsIntegrationError.conflict(
                code: "pending_sync_required",
                message: "Sync pending local changes before this network action."
            )
        }
    }

    func beginRemoteOperation(
        kind: PlanningEntityKind,
        localID: UUID
    ) async throws -> PlannerDetailsRemoteOperationLease {
        let key = PlannerDetailsRemoteOperationKey(kind: kind, localID: localID)
        guard activeRemoteOperations.insert(key).inserted else {
            throw PlannerDetailsIntegrationError.conflict(
                code: "operation_in_flight",
                message: "Another network operation is already changing this resource."
            )
        }
        do {
            let generation = try await persistence.mutationGeneration(kind: kind, localID: localID)
            guard generation.pendingID == nil else {
                activeRemoteOperations.remove(key)
                throw PlannerDetailsIntegrationError.conflict(
                    code: "pending_sync_required",
                    message: "Sync pending local changes before this network action."
                )
            }
            return PlannerDetailsRemoteOperationLease(key: key, generation: generation)
        } catch {
            activeRemoteOperations.remove(key)
            throw error
        }
    }

    func endRemoteOperation(_ lease: PlannerDetailsRemoteOperationLease) {
        activeRemoteOperations.remove(lease.key)
    }

    func ensureNoActiveRemoteOperation(kind: PlanningEntityKind, localID: UUID) throws {
        guard !activeRemoteOperations.contains(
            PlannerDetailsRemoteOperationKey(kind: kind, localID: localID)
        ) else {
            throw PlannerDetailsIntegrationError.conflict(
                code: "operation_in_flight",
                message: "Wait for the current network operation to finish."
            )
        }
    }

    func requireWritableFolder(_ id: UUID, snapshot: PlanningSnapshot) throws -> FolderDTO {
        guard let value = snapshot.folders.first(where: { $0.id == id }) else {
            throw PlannerDetailsIntegrationError.notFound(kind: .folder, id: id)
        }
        try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
        return value
    }

    func requireWritableGoal(_ id: UUID, snapshot: PlanningSnapshot) throws -> GoalDTO {
        guard let value = snapshot.goals.first(where: { $0.id == id }) else {
            throw PlannerDetailsIntegrationError.notFound(kind: .goal, id: id)
        }
        try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
        return value
    }

    private func requireTaskCreationAccess(goalID: UUID, snapshot: PlanningSnapshot) async throws {
        guard let goal = snapshot.goals.first(where: { $0.id == goalID }) else {
            throw PlannerDetailsIntegrationError.notFound(kind: .goal, id: goalID)
        }
        guard goal.shared && !goal.fullAccess else { return }
        guard (try await persistence.cachedCreateTaskGoalIDs()).contains(goalID) else {
            throw PlannerDetailsIntegrationError.forbidden(
                code: "read_only_shared_resource",
                message: "Tasks cannot be created in this shared goal."
            )
        }
    }

    private func taskDraft(id: UUID, goalID: UUID, payload: TaskEditorPayload) -> TaskDraft {
        TaskDraft(
            id: id,
            goalID: goalID,
            title: payload.title,
            description: payload.description,
            type: TaskType(rawValue: payload.type.rawValue) ?? .green,
            effort: payload.effort,
            status: PlanningStatus(rawValue: payload.status.rawValue) ?? .todo,
            plannedTime: payload.plannedAt,
            dueTime: payload.dueAt
        )
    }

    private func aggregateChecklist(
        _ values: [ChecklistEditorPayload]
    ) -> [PlannerDetailsChecklistAggregateItem] {
        values.map {
            PlannerDetailsChecklistAggregateItem(
                id: $0.id ?? makeID(),
                text: $0.text,
                checked: $0.checked,
                displayOrder: $0.displayOrder
            )
        }
    }

    func requireApplied(_ result: PlannerDetailsGuardedApplyResult) throws {
        guard result == .applied else {
            throw PlannerDetailsIntegrationError.conflict(
                code: "newer_local_mutation_preserved",
                message: "A newer local edit was preserved; reload before retrying."
            )
        }
    }

    private func require(_ reference: DetailEntityReference, kind: DetailEntityKind) throws {
        guard reference.kind == kind else {
            throw PlannerDetailsIntegrationError.validation(
                message: "Editor resource type mismatch.",
                fields: ["resourceType": "expected_\(kind.rawValue)"]
            )
        }
    }

    func requireFullAccess(shared: Bool, fullAccess: Bool) throws {
        guard !shared || fullAccess else {
            throw PlannerDetailsIntegrationError.forbidden(
                code: "read_only_shared_resource",
                message: "This shared resource is read-only."
            )
        }
    }

    private func requireIdea(_ id: UUID) async throws -> IdeaDTO {
        let snapshot = try await repository.snapshot()
        guard let value = snapshot.ideas.first(where: { $0.id == id }) else {
            throw PlannerDetailsIntegrationError.notFound(kind: .idea, id: id)
        }
        return value
    }

    private func requireNote(_ id: UUID) async throws -> NoteDTO {
        let snapshot = try await repository.snapshot()
        guard let value = snapshot.notes.first(where: { $0.id == id }) else {
            throw PlannerDetailsIntegrationError.notFound(kind: .note, id: id)
        }
        return value
    }

    func persist(_ value: ActionTaskDTO, localID: UUID) async throws {
        let dto = try PlannerDetailsDTOMapper.task(value)
        try await persistence.bindAndApply(
            kind: .task,
            localID: localID,
            remoteID: dto.id,
            version: dto.version,
            payloadJSON: WireJSON.encoder().encode(dto)
        )
    }

    func persist(
        _ value: ActionTaskDTO,
        localID: UUID,
        expectedGeneration: PlannerDetailsMutationGeneration
    ) async throws -> PlannerDetailsGuardedApplyResult {
        let dto = try PlannerDetailsDTOMapper.task(value)
        return try await persistence.bindAndApplyGuarded(
            kind: .task,
            localID: localID,
            remoteID: dto.id,
            version: dto.version,
            payloadJSON: WireJSON.encoder().encode(dto),
            expectedGeneration: expectedGeneration
        )
    }

    func persist(_ value: ActionIdeaDTO, localID: UUID) async throws {
        let dto = PlannerDetailsDTOMapper.idea(value)
        try await persistence.bindAndApply(
            kind: .idea,
            localID: localID,
            remoteID: dto.id,
            version: dto.version,
            payloadJSON: WireJSON.encoder().encode(dto)
        )
    }

    func persist(
        _ value: ActionIdeaDTO,
        localID: UUID,
        expectedGeneration: PlannerDetailsMutationGeneration
    ) async throws -> PlannerDetailsGuardedApplyResult {
        let dto = PlannerDetailsDTOMapper.idea(value)
        return try await persistence.bindAndApplyGuarded(
            kind: .idea,
            localID: localID,
            remoteID: dto.id,
            version: dto.version,
            payloadJSON: WireJSON.encoder().encode(dto),
            expectedGeneration: expectedGeneration
        )
    }

    private func persist(_ value: ActionIdeaNoteDTO, localID: UUID) async throws {
        let dto = PlannerDetailsDTOMapper.ideaNote(value)
        try await persistence.bindAndApply(
            kind: .ideaNote,
            localID: localID,
            remoteID: dto.id,
            version: dto.version,
            payloadJSON: WireJSON.encoder().encode(dto)
        )
    }

    private func persist(
        _ value: ActionIdeaNoteDTO,
        localID: UUID,
        expectedGeneration: PlannerDetailsMutationGeneration
    ) async throws -> PlannerDetailsGuardedApplyResult {
        let dto = PlannerDetailsDTOMapper.ideaNote(value)
        return try await persistence.bindAndApplyGuarded(
            kind: .ideaNote,
            localID: localID,
            remoteID: dto.id,
            version: dto.version,
            payloadJSON: WireJSON.encoder().encode(dto),
            expectedGeneration: expectedGeneration
        )
    }

    func persist(_ value: ActionNoteDTO, localID: UUID) async throws {
        let dto = PlannerDetailsDTOMapper.note(value)
        try await persistence.bindAndApply(
            kind: .note,
            localID: localID,
            remoteID: dto.id,
            version: dto.version,
            payloadJSON: WireJSON.encoder().encode(dto)
        )
    }

    func persist(
        _ value: ActionNoteDTO,
        localID: UUID,
        expectedGeneration: PlannerDetailsMutationGeneration
    ) async throws -> PlannerDetailsGuardedApplyResult {
        let dto = PlannerDetailsDTOMapper.note(value)
        return try await persistence.bindAndApplyGuarded(
            kind: .note,
            localID: localID,
            remoteID: dto.id,
            version: dto.version,
            payloadJSON: WireJSON.encoder().encode(dto),
            expectedGeneration: expectedGeneration
        )
    }

    private func detailKind(_ value: PlannerItemKind) -> DetailEntityKind {
        switch value {
        case .folder: .folder
        case .goal: .goal
        case .task: .task
        case .idea: .idea
        case .note: .note
        }
    }
}

private struct PlannerDetailsRecurrenceCreateIdentity: Codable, Sendable {
    let goalID: UUID
    let task: CreateTaskRequestDTO
    let recurrence: UpsertRecurrenceRequestDTO
}
