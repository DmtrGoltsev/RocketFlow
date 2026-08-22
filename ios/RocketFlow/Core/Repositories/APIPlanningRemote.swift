import Foundation

enum FocusMutationAction: String, Codable, Sendable {
    case addItem
    case removeItem
    case reorder
    case resolveRollover
    case updateNotificationSettings
}

struct FocusPendingMutationPayload: Codable, Equatable, Sendable {
    let action: FocusMutationAction
    let taskID: UUID?
    let taskIDs: [UUID]?
    let sourcePeriodID: UUID?
    let periodVersion: Int64?
    let idempotencyKey: String?
    let notificationSettings: FocusNotificationSettingsRequestDTO?
}

protocol AuthenticatedRequestSending: Sendable {
    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response
}

extension AuthSession: AuthenticatedRequestSending {}

actor APIPlanningRemote: SyncRemote {
    private enum ConflictFetch {
        case current(version: Int64, payload: Data)
        case serverDeleted
        case unavailable
    }

    private let sender: any AuthenticatedRequestSending
    private let idResolver: any RemoteIDResolving
    private(set) var pullWarnings: [RemotePullWarning] = []

    init(sender: any AuthenticatedRequestSending, idResolver: any RemoteIDResolving) {
        self.sender = sender
        self.idResolver = idResolver
    }

    func push(_ mutation: PendingMutation) async throws -> RemoteMutationAck {
        do {
            switch mutation.entityType {
            case .folder: return try await pushFolder(mutation)
            case .goal: return try await pushGoal(mutation)
            case .task: return try await pushTask(mutation)
            case .idea: return try await pushIdea(mutation)
            case .ideaNote: return try await pushIdeaNote(mutation)
            case .note: return try await pushNote(mutation)
            case .tag: return try await pushTag(mutation)
            case .entityLink: return try await pushEntityLink(mutation)
            case .focus: return try await pushFocus(mutation)
            case .settings: return try await pushSettings(mutation)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as SyncRemoteFailure {
            throw failure
        } catch let api as APIError where api.statusCode == 404 {
            if mutation.operation == .delete {
                let remoteID = try await currentRemoteID(mutation)
                let payload = try? WireJSON.decoder().decode(DeleteMutationPayload.self, from: mutation.payloadJSON)
                return RemoteMutationAck(
                    remoteID: remoteID,
                    version: mutation.baseVersion ?? payload?.version ?? 0,
                    serverPayloadJSON: nil
                )
            }
            throw SyncRemoteFailure.conflict(
                code: api.code,
                serverVersion: nil,
                serverPayloadJSON: nil,
                serverDeleted: true
            )
        } catch let api as APIError where api.statusCode == 409 || api.statusCode == 412 {
            let current = await conflictPayload(for: mutation)
            switch current {
            case let .current(version, payload):
                throw SyncRemoteFailure.conflict(
                    code: api.code,
                    serverVersion: version,
                    serverPayloadJSON: payload,
                    serverDeleted: false
                )
            case .serverDeleted:
                throw SyncRemoteFailure.conflict(
                    code: api.code,
                    serverVersion: nil,
                    serverPayloadJSON: nil,
                    serverDeleted: true
                )
            case .unavailable:
                throw SyncRemoteFailure.conflict(
                    code: "\(api.code):server_payload_unavailable",
                    serverVersion: nil,
                    serverPayloadJSON: nil,
                    serverDeleted: false
                )
            }
        } catch {
            throw Self.classify(error)
        }
    }

    func pull() async throws -> RemotePlanningSnapshot {
        pullWarnings = []
        do {
            var warnings: [RemotePullWarning] = []
            let folders = try await sender.send(PlanningEndpoints.folders).items
            var goals: [GoalDTO] = []
            var tasks: [TaskDTO] = []
            var ideas: [IdeaDTO] = []
            var ideaNotes: [IdeaNoteDTO] = []
            var notes: [NoteDTO] = []
            var linksByID: [UUID: EntityLinkDTO] = [:]
            var loadedCollections: Set<RemotePlanningCollection> = [.folders, .goals, .tasks]
            var loadedIdeas = true
            var loadedIdeaNotes = true
            var loadedNotes = true
            var loadedLinks = true
            for folder in folders {
                let folderGoals = try await sender.send(PlanningEndpoints.goals(folderID: folder.id)).items
                goals.append(contentsOf: folderGoals)
                for goal in folderGoals {
                    tasks.append(contentsOf: try await sender.send(PlanningEndpoints.tasks(goalID: goal.id)).items)
                }
                do {
                    ideas.append(contentsOf: try await sender.send(PlanningEndpoints.ideas(folderID: folder.id)).items)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let api as APIError where api.statusCode == 401 {
                    throw api
                } catch {
                    loadedIdeas = false
                    loadedIdeaNotes = false
                    loadedLinks = false
                    warnings.append(Self.warning(resource: "ideas:\(folder.id.wire)", error: error))
                }
                do {
                    notes.append(contentsOf: try await sender.send(PlanningEndpoints.notes(folderID: folder.id)).items)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let api as APIError where api.statusCode == 401 {
                    throw api
                } catch {
                    loadedNotes = false
                    loadedLinks = false
                    warnings.append(Self.warning(resource: "notes:\(folder.id.wire)", error: error))
                }
            }
            for idea in ideas {
                do {
                    ideaNotes.append(contentsOf: try await sender.send(Self.ideaNotes(idea.id)).items)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let api as APIError where api.statusCode == 401 {
                    throw api
                } catch {
                    loadedIdeaNotes = false
                    warnings.append(Self.warning(resource: "idea-notes:\(idea.id.wire)", error: error))
                }
            }
            let linkSources: [(LinkedEntityType, UUID)] =
                goals.map { (.goal, $0.id) }
                + tasks.map { (.task, $0.id) }
                + ideas.map { (.idea, $0.id) }
                + notes.map { (.note, $0.id) }
            for (type, id) in linkSources {
                do {
                    for link in try await sender.send(PlanningEndpoints.links(type: type, id: id)).items {
                        linksByID[link.id] = link
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch let api as APIError where api.statusCode == 401 {
                    throw api
                } catch {
                    loadedLinks = false
                    warnings.append(Self.warning(resource: "entity-links:\(type.rawValue):\(id.wire)", error: error))
                }
            }
            if loadedIdeas { loadedCollections.insert(.ideas) }
            if loadedIdeaNotes { loadedCollections.insert(.ideaNotes) }
            if loadedNotes { loadedCollections.insert(.notes) }
            if loadedLinks { loadedCollections.insert(.entityLinks) }
            pullWarnings = warnings
            return RemotePlanningSnapshot(
                folders: folders,
                goals: goals,
                tasks: tasks,
                ideas: ideas,
                ideaNotes: ideaNotes,
                notes: notes,
                links: linksByID.values.sorted { $0.id.uuidString < $1.id.uuidString },
                loadedCollections: loadedCollections,
                partialWarnings: warnings
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as SyncRemoteFailure {
            throw failure
        } catch {
            throw Self.classify(error)
        }
    }

    func latestPullWarnings() -> [RemotePullWarning] { pullWarnings }

    private func pushFolder(_ mutation: PendingMutation) async throws -> RemoteMutationAck {
        if mutation.operation == .delete {
            return try await delete(mutation, path: ["folders"])
        }
        if mutation.operation == .move {
            let move = try WireJSON.decoder().decode(MoveMutationPayload.self, from: mutation.payloadJSON)
            let target = try await move.targetParentID.asyncMap {
                try await idResolver.remoteID(for: .folder, localID: $0)
            }
            let remoteID = try await currentRemoteID(mutation)
            let response: FolderDTO = try await sender.send(
                Endpoint(
                    method: .post,
                    path: ["folders", remoteID.wire, "move"],
                    body: MoveFolderRequestDTO(
                        targetFolderId: target,
                        version: mutation.baseVersion ?? move.version
                    )
                )
            )
            return try ack(response.id, version: response.version, payload: response)
        }
        let dto = try WireJSON.decoder().decode(FolderDTO.self, from: mutation.payloadJSON)
        let response: FolderDTO
        if mutation.operation == .create {
            let parentID = try await dto.parentFolderId.asyncMap {
                try await idResolver.remoteID(for: .folder, localID: $0)
            }
            response = try await sender.send(
                Endpoint(
                    method: .post,
                    path: ["folders"],
                    body: CreateFolderRequestDTO(
                        name: dto.name,
                        description: dto.description,
                        parentFolderId: parentID
                    )
                )
            )
        } else {
            let remoteID = try await idResolver.remoteID(for: .folder, localID: mutation.entityID)
            response = try await sender.send(
                Endpoint(
                    method: .patch,
                    path: ["folders", remoteID.wire],
                    body: UpdateFolderRequestDTO(
                        name: dto.name,
                        description: dto.description,
                        displayOrder: dto.displayOrder,
                        archived: dto.archived,
                        version: mutation.baseVersion ?? dto.version
                    )
                )
            )
        }
        return try ack(response.id, version: response.version, payload: response)
    }

    private func pushGoal(_ mutation: PendingMutation) async throws -> RemoteMutationAck {
        if mutation.operation == .delete {
            return try await delete(mutation, path: ["goals"])
        }
        if mutation.operation == .move {
            let move = try requiredMovePayload(mutation)
            let target = try await idResolver.remoteID(for: .folder, localID: move.targetParentID)
            let remoteID = try await currentRemoteID(mutation)
            let response: GoalDTO = try await sender.send(
                Endpoint(
                    method: .post,
                    path: ["goals", remoteID.wire, "move"],
                    body: MoveGoalRequestDTO(
                        targetFolderId: target,
                        version: mutation.baseVersion ?? move.version
                    )
                )
            )
            return try ack(response.id, version: response.version, payload: response)
        }
        let dto = try WireJSON.decoder().decode(GoalDTO.self, from: mutation.payloadJSON)
        let response: GoalDTO
        if mutation.operation == .create {
            let folderID = try await idResolver.remoteID(for: .folder, localID: dto.folderId)
            response = try await sender.send(
                Endpoint(
                    method: .post,
                    path: ["folders", folderID.wire, "goals"],
                    body: CreateGoalRequestDTO(
                        name: dto.name,
                        description: dto.description,
                        status: dto.status
                    )
                )
            )
        } else {
            let remoteID = try await idResolver.remoteID(for: .goal, localID: mutation.entityID)
            response = try await sender.send(
                Endpoint(
                    method: .patch,
                    path: ["goals", remoteID.wire],
                    body: UpdateGoalRequestDTO(
                        name: dto.name,
                        description: dto.description,
                        status: dto.status,
                        archived: dto.archived,
                        version: mutation.baseVersion ?? dto.version
                    )
                )
            )
        }
        return try ack(response.id, version: response.version, payload: response)
    }

    private func pushTask(_ mutation: PendingMutation) async throws -> RemoteMutationAck {
        if mutation.operation == .delete {
            return try await delete(mutation, path: ["tasks"])
        }
        if mutation.operation == .move {
            let move = try requiredMovePayload(mutation)
            let target = try await idResolver.remoteID(for: .goal, localID: move.targetParentID)
            let remoteID = try await currentRemoteID(mutation)
            let response: TaskDTO = try await sender.send(
                Endpoint(
                    method: .post,
                    path: ["tasks", remoteID.wire, "move-to-goal"],
                    body: MoveTaskToGoalRequestDTO(
                        targetGoalId: target,
                        version: mutation.baseVersion ?? move.version
                    )
                )
            )
            return try ack(response.id, version: response.version, payload: response)
        }
        let dto = try WireJSON.decoder().decode(TaskDTO.self, from: mutation.payloadJSON)
        let remoteTagIDs = try await dto.tags.asyncMap {
            try await idResolver.remoteID(for: .tag, localID: $0.id)
        }
        // Checklist items are nested task state in the backend contract, never standalone mutations.
        let checklist = dto.checklistItems.map {
            ChecklistItemRequestDTO(
                id: mutation.operation == .create ? nil : $0.id,
                text: $0.text,
                checked: $0.checked,
                displayOrder: $0.displayOrder
            )
        }
        let response: TaskDTO
        if mutation.operation == .create {
            let goalID = try await idResolver.remoteID(for: .goal, localID: dto.goalId)
            response = try await sender.send(
                Endpoint(
                    method: .post,
                    path: ["goals", goalID.wire, "tasks"],
                    body: CreateTaskRequestDTO(
                        title: dto.title,
                        description: dto.description,
                        type: dto.type,
                        effort: dto.effort,
                        status: dto.status,
                        plannedTime: dto.plannedTime,
                        dueTime: dto.dueTime,
                        checklistItems: checklist,
                        tagIds: remoteTagIDs
                    )
                )
            )
        } else {
            let remoteID = try await idResolver.remoteID(for: .task, localID: mutation.entityID)
            response = try await sender.send(
                Endpoint(
                    method: .patch,
                    path: ["tasks", remoteID.wire],
                    body: UpdateTaskRequestDTO(
                        task: dto,
                        tagIds: remoteTagIDs,
                        checklistItems: checklist
                    )
                )
            )
        }
        return try ack(response.id, version: response.version, payload: response)
    }

    private func pushIdea(_ mutation: PendingMutation) async throws -> RemoteMutationAck {
        if mutation.operation == .delete {
            return try await delete(mutation, path: ["ideas"])
        }
        if mutation.operation == .move {
            let move = try requiredMovePayload(mutation)
            let target = try await idResolver.remoteID(for: .folder, localID: move.targetParentID)
            let remoteID = try await currentRemoteID(mutation)
            let response: IdeaDTO = try await sender.send(
                Endpoint(
                    method: .post,
                    path: ["ideas", remoteID.wire, "move"],
                    body: MoveIdeaRequestDTO(
                        targetFolderId: target,
                        version: mutation.baseVersion ?? move.version
                    )
                )
            )
            return try ack(response.id, version: response.version, payload: response)
        }
        let dto = try WireJSON.decoder().decode(IdeaDTO.self, from: mutation.payloadJSON)
        let response: IdeaDTO
        if mutation.operation == .create {
            let folderID = try await idResolver.remoteID(for: .folder, localID: dto.folderId)
            response = try await sender.send(
                Endpoint(
                    method: .post,
                    path: ["folders", folderID.wire, "ideas"],
                    body: CreateIdeaRequestDTO(
                        title: dto.title,
                        body: dto.body,
                        status: dto.status,
                        allowAuthorNoteEdits: dto.allowAuthorNoteEdits
                    )
                )
            )
        } else {
            let remoteID = try await idResolver.remoteID(for: .idea, localID: mutation.entityID)
            response = try await sender.send(
                Endpoint(
                    method: .patch,
                    path: ["ideas", remoteID.wire],
                    body: UpdateIdeaRequestDTO(
                        title: dto.title,
                        body: dto.body,
                        status: dto.status,
                        displayOrder: dto.displayOrder,
                        archived: dto.archived,
                        allowAuthorNoteEdits: dto.allowAuthorNoteEdits,
                        version: mutation.baseVersion ?? dto.version
                    )
                )
            )
        }
        return try ack(response.id, version: response.version, payload: response)
    }

    private func pushIdeaNote(_ mutation: PendingMutation) async throws -> RemoteMutationAck {
        if mutation.operation == .delete {
            return try await delete(mutation, path: ["idea-notes"])
        }
        let dto = try WireJSON.decoder().decode(IdeaNoteDTO.self, from: mutation.payloadJSON)
        let response: IdeaNoteDTO
        if mutation.operation == .create {
            let ideaID = try await idResolver.remoteID(for: .idea, localID: dto.ideaId)
            response = try await sender.send(
                Endpoint(
                    method: .post,
                    path: ["ideas", ideaID.wire, "notes"],
                    body: CreateIdeaNoteRequestDTO(
                        eventType: dto.eventType,
                        body: dto.body,
                        metadata: dto.metadata
                    )
                )
            )
        } else {
            let remoteID = try await idResolver.remoteID(for: .ideaNote, localID: mutation.entityID)
            response = try await sender.send(
                Endpoint(
                    method: .patch,
                    path: ["idea-notes", remoteID.wire],
                    body: UpdateIdeaNoteRequestDTO(
                        eventType: dto.eventType,
                        body: dto.body,
                        metadata: dto.metadata,
                        version: mutation.baseVersion ?? dto.version
                    )
                )
            )
        }
        return try ack(response.id, version: response.version, payload: response)
    }

    private func pushNote(_ mutation: PendingMutation) async throws -> RemoteMutationAck {
        if mutation.operation == .delete {
            return try await delete(mutation, path: ["notes"])
        }
        if mutation.operation == .move {
            let move = try requiredMovePayload(mutation)
            let target = try await idResolver.remoteID(for: .folder, localID: move.targetParentID)
            let remoteID = try await currentRemoteID(mutation)
            let response: NoteDTO = try await sender.send(
                Endpoint(
                    method: .post,
                    path: ["notes", remoteID.wire, "move"],
                    body: MoveNoteRequestDTO(
                        targetFolderId: target,
                        version: mutation.baseVersion ?? move.version
                    )
                )
            )
            return try ack(response.id, version: response.version, payload: response)
        }
        let dto = try WireJSON.decoder().decode(NoteDTO.self, from: mutation.payloadJSON)
        let response: NoteDTO
        if mutation.operation == .create {
            let folderID = try await idResolver.remoteID(for: .folder, localID: dto.folderId)
            response = try await sender.send(
                Endpoint(
                    method: .post,
                    path: ["folders", folderID.wire, "notes"],
                    body: CreateNoteRequestDTO(title: dto.title, body: dto.body)
                )
            )
        } else {
            let remoteID = try await idResolver.remoteID(for: .note, localID: mutation.entityID)
            response = try await sender.send(
                Endpoint(
                    method: .patch,
                    path: ["notes", remoteID.wire],
                    body: UpdateNoteRequestDTO(
                        title: dto.title,
                        body: dto.body,
                        displayOrder: dto.displayOrder,
                        archived: dto.archived,
                        version: mutation.baseVersion ?? dto.version
                    )
                )
            )
        }
        return try ack(response.id, version: response.version, payload: response)
    }

    private func pushTag(_ mutation: PendingMutation) async throws -> RemoteMutationAck {
        guard mutation.operation == .create else {
            let code: String
            switch mutation.operation {
            case .update, .reorder, .move: code = "tag_update_not_supported"
            case .delete: code = "tag_delete_not_supported"
            case .create: code = "tag_mutation_not_supported"
            }
            throw SyncRemoteFailure.permanent(
                code: code,
                serverPayloadJSON: nil
            )
        }
        let dto = try WireJSON.decoder().decode(TaskTagDTO.self, from: mutation.payloadJSON)
        let response: TaskTagDTO = try await sender.send(
            Endpoint(
                method: .post,
                path: ["tags"],
                body: CreateTagRequestDTO(name: dto.name, color: dto.color)
            )
        )
        return try ack(response.id, version: 0, payload: response)
    }

    private func pushEntityLink(_ mutation: PendingMutation) async throws -> RemoteMutationAck {
        if mutation.operation == .delete {
            return try await delete(mutation, path: ["entity-links"])
        }
        let dto = try WireJSON.decoder().decode(EntityLinkDTO.self, from: mutation.payloadJSON)
        guard dto.source.identity != nil, dto.target.identity != nil else {
            throw SyncRemoteFailure.permanent(
                code: "redacted_entity_link_not_mutable",
                serverPayloadJSON: nil
            )
        }
        let response: EntityLinkDTO
        if mutation.operation == .create {
            let sourceID = try await idResolver.remoteID(
                for: dto.source.type.entityKind,
                localID: dto.source.id
            )
            let targetID = try await idResolver.remoteID(
                for: dto.target.type.entityKind,
                localID: dto.target.id
            )
            response = try await sender.send(
                Endpoint(
                    method: .post,
                    path: ["entity-links"],
                    body: CreateEntityLinkRequestDTO(
                        sourceType: dto.source.type,
                        sourceId: sourceID,
                        targetType: dto.target.type,
                        targetId: targetID,
                        relationType: dto.relationType
                    )
                )
            )
        } else {
            let remoteID = try await idResolver.remoteID(for: .entityLink, localID: mutation.entityID)
            response = try await sender.send(
                Endpoint(
                    method: .patch,
                    path: ["entity-links", remoteID.wire],
                    body: UpdateEntityLinkRequestDTO(
                        relationType: dto.relationType,
                        version: mutation.baseVersion ?? dto.version
                    )
                )
            )
        }
        return try ack(response.id, version: response.version, payload: response)
    }

    private func pushFocus(_ mutation: PendingMutation) async throws -> RemoteMutationAck {
        let payload = try WireJSON.decoder().decode(FocusPendingMutationPayload.self, from: mutation.payloadJSON)
        switch payload.action {
        case .addItem, .removeItem:
            guard let taskID = payload.taskID else {
                throw SyncRemoteFailure.permanent(code: "focus_task_missing", serverPayloadJSON: nil)
            }
            let remoteTaskID = try await idResolver.remoteID(for: .task, localID: taskID)
            let endpoint = try Endpoint<FocusPeriodDTO>(
                method: payload.action == .addItem ? .put : .delete,
                path: ["focus", "current", "items", remoteTaskID.wire],
                body: FocusMutationRequestDTO(
                    periodVersion: payload.periodVersion,
                    idempotencyKey: payload.idempotencyKey
                )
            )
            let response = try await sender.send(endpoint)
            return RemoteMutationAck(remoteID: response.id, version: response.version, serverPayloadJSON: nil)
        case .reorder:
            let remoteTaskIDs = try await (payload.taskIDs ?? []).asyncMap {
                try await idResolver.remoteID(for: .task, localID: $0)
            }
            let response: FocusPeriodDTO = try await sender.send(
                Endpoint(
                    method: .patch,
                    path: ["focus", "current", "items", "order"],
                    body: FocusReorderRequestDTO(
                        taskIds: remoteTaskIDs,
                        periodVersion: payload.periodVersion,
                        idempotencyKey: payload.idempotencyKey
                    )
                )
            )
            return RemoteMutationAck(remoteID: response.id, version: response.version, serverPayloadJSON: nil)
        case .resolveRollover:
            guard let sourcePeriodID = payload.sourcePeriodID else {
                throw SyncRemoteFailure.permanent(code: "focus_period_missing", serverPayloadJSON: nil)
            }
            let remoteTaskIDs = try await (payload.taskIDs ?? []).asyncMap {
                try await idResolver.remoteID(for: .task, localID: $0)
            }
            let response: FocusPeriodDTO = try await sender.send(
                Endpoint(
                    method: .post,
                    path: ["focus", "rollovers", sourcePeriodID.wire, "resolve"],
                    body: FocusResolveRolloverRequestDTO(
                        taskIds: remoteTaskIDs,
                        periodVersion: payload.periodVersion,
                        idempotencyKey: payload.idempotencyKey
                    )
                )
            )
            return RemoteMutationAck(remoteID: response.id, version: response.version, serverPayloadJSON: nil)
        case .updateNotificationSettings:
            guard let settings = payload.notificationSettings else {
                throw SyncRemoteFailure.permanent(code: "focus_settings_missing", serverPayloadJSON: nil)
            }
            let response: FocusNotificationSettingsDTO = try await sender.send(
                Endpoint(
                    method: .patch,
                    path: ["focus", "notification-settings"],
                    body: settings
                )
            )
            return RemoteMutationAck(
                remoteID: mutation.entityID,
                version: response.version,
                serverPayloadJSON: nil
            )
        }
    }

    private func pushSettings(_ mutation: PendingMutation) async throws -> RemoteMutationAck {
        guard mutation.operation == .update else {
            throw SyncRemoteFailure.permanent(
                code: "settings_operation_not_supported",
                serverPayloadJSON: nil
            )
        }
        let dto = try WireJSON.decoder().decode(UserSettingsDTO.self, from: mutation.payloadJSON)
        let response: UserSettingsDTO = try await sender.send(
            Endpoint(
                method: .patch,
                path: ["me", "settings"],
                body: UpdateUserSettingsRequestDTO(
                    language: dto.language,
                    greenPriorityDecayPolicy: dto.greenPriorityDecayPolicy?.updateRequest,
                    redPriorityDecayPolicy: dto.redPriorityDecayPolicy?.updateRequest,
                    notificationsEnabled: dto.notificationsEnabled,
                    version: mutation.baseVersion ?? dto.version
                )
            )
        )
        return RemoteMutationAck(
            remoteID: mutation.entityID,
            version: response.version,
            serverPayloadJSON: nil
        )
    }

    private func delete(_ mutation: PendingMutation, path: [String]) async throws -> RemoteMutationAck {
        let payload = try WireJSON.decoder().decode(DeleteMutationPayload.self, from: mutation.payloadJSON)
        let remoteID = payload.remoteID
            ?? (try await idResolver.remoteID(for: mutation.entityType, localID: mutation.entityID))
        let _: EmptyResponse = try await sender.send(
            Endpoint(method: .delete, path: path + [remoteID.wire])
        )
        return RemoteMutationAck(
            remoteID: remoteID,
            version: mutation.baseVersion ?? payload.version,
            serverPayloadJSON: nil
        )
    }

    private func conflictPayload(for mutation: PendingMutation) async -> ConflictFetch {
        do {
            switch mutation.entityType {
            case .folder:
                let value: FolderDTO = try await sender.send(
                    Endpoint(method: .get, path: ["folders", (try await currentRemoteID(mutation)).wire])
                )
                return try currentConflict(value.version, value)
            case .goal:
                let value: GoalDTO = try await sender.send(
                    Endpoint(method: .get, path: ["goals", (try await currentRemoteID(mutation)).wire])
                )
                return try currentConflict(value.version, value)
            case .task:
                let value: TaskDTO = try await sender.send(
                    Endpoint(method: .get, path: ["tasks", (try await currentRemoteID(mutation)).wire])
                )
                return try currentConflict(value.version, value)
            case .idea:
                let value: IdeaDTO = try await sender.send(
                    Endpoint(method: .get, path: ["ideas", (try await currentRemoteID(mutation)).wire])
                )
                return try currentConflict(value.version, value)
            case .note:
                let value: NoteDTO = try await sender.send(
                    Endpoint(method: .get, path: ["notes", (try await currentRemoteID(mutation)).wire])
                )
                return try currentConflict(value.version, value)
            case .ideaNote:
                guard mutation.operation != .delete,
                      let local = try? WireJSON.decoder().decode(IdeaNoteDTO.self, from: mutation.payloadJSON) else {
                    return .unavailable
                }
                let ideaID = try await idResolver.remoteID(for: .idea, localID: local.ideaId)
                let remoteID = try await currentRemoteID(mutation)
                guard let value = try await sender.send(Self.ideaNotes(ideaID)).items.first(where: { $0.id == remoteID }) else {
                    return .serverDeleted
                }
                return try currentConflict(value.version, value)
            case .tag:
                let remoteID = try await currentRemoteID(mutation)
                guard let value = try await sender.send(Self.tags()).items.first(where: { $0.id == remoteID }) else {
                    return .serverDeleted
                }
                return try currentConflict(0, value)
            case .entityLink:
                guard mutation.operation != .delete,
                      let local = try? WireJSON.decoder().decode(EntityLinkDTO.self, from: mutation.payloadJSON),
                      local.source.identity != nil else {
                    return .unavailable
                }
                let sourceID = try await idResolver.remoteID(
                    for: local.source.type.entityKind,
                    localID: local.source.id
                )
                let remoteID = try await currentRemoteID(mutation)
                guard let value = try await sender.send(
                    PlanningEndpoints.links(type: local.source.type, id: sourceID)
                ).items.first(where: { $0.id == remoteID }) else {
                    return .serverDeleted
                }
                return try currentConflict(value.version, value)
            case .focus:
                let payload = try WireJSON.decoder().decode(
                    FocusPendingMutationPayload.self,
                    from: mutation.payloadJSON
                )
                if payload.action == .updateNotificationSettings {
                    let value: FocusNotificationSettingsDTO = try await sender.send(FocusEndpoints.settings)
                    return try currentConflict(value.version, value)
                }
                let value: FocusPeriodDTO = try await sender.send(FocusEndpoints.current)
                return try currentConflict(value.version, value)
            case .settings:
                let value: UserSettingsDTO = try await sender.send(SettingsEndpoints.current)
                return try currentConflict(value.version, value)
            }
        } catch let api as APIError where api.statusCode == 404 {
            return .serverDeleted
        } catch {
            return .unavailable
        }
    }

    private func currentRemoteID(_ mutation: PendingMutation) async throws -> UUID {
        if mutation.operation == .delete,
           let payload = try? WireJSON.decoder().decode(DeleteMutationPayload.self, from: mutation.payloadJSON),
           let remoteID = payload.remoteID {
            return remoteID
        }
        return try await idResolver.remoteID(
            for: mutation.entityType,
            localID: mutation.entityID
        )
    }

    private func currentConflict<Value: Encodable>(
        _ version: Int64,
        _ value: Value
    ) throws -> ConflictFetch {
        .current(version: version, payload: try WireJSON.encoder().encode(value))
    }

    private func requiredMovePayload(_ mutation: PendingMutation) throws -> (targetParentID: UUID, version: Int64) {
        let payload = try WireJSON.decoder().decode(MoveMutationPayload.self, from: mutation.payloadJSON)
        guard let targetParentID = payload.targetParentID else {
            throw SyncRemoteFailure.permanent(code: "move_target_missing", serverPayloadJSON: nil)
        }
        return (targetParentID, payload.version)
    }

    private func ack<Response: Encodable>(
        _ remoteID: UUID,
        version: Int64,
        payload: Response
    ) throws -> RemoteMutationAck {
        RemoteMutationAck(
            remoteID: remoteID,
            version: version,
            serverPayloadJSON: try WireJSON.encoder().encode(payload)
        )
    }

    private static func classify(_ error: Error) -> SyncRemoteFailure {
        if let failure = error as? SyncRemoteFailure { return failure }
        if let api = error as? APIError {
            if api.statusCode == 401 { return .unauthorized }
            if api.statusCode == 409 || api.statusCode == 412 {
                return .conflict(
                    code: api.code,
                    serverVersion: nil,
                    serverPayloadJSON: nil,
                    serverDeleted: false
                )
            }
            if api.statusCode == 408 || api.statusCode == 429 || api.statusCode >= 500 {
                return .transient(code: api.code)
            }
            return .permanent(code: api.code, serverPayloadJSON: nil)
        }
        if error is URLError { return .transient(code: "network_error") }
        if error is AuthSessionError { return .unauthorized }
        return .transient(code: "transport_error")
    }

    private static func ideaNotes(_ ideaID: UUID) -> Endpoint<IdeaNoteListResponseDTO> {
        Endpoint(method: .get, path: ["ideas", ideaID.wire, "notes"])
    }

    private static func tags() -> Endpoint<TagListResponseDTO> {
        Endpoint(method: .get, path: ["tags"])
    }

    private static func warning(resource: String, error: Error) -> RemotePullWarning {
        let code: String
        if let api = error as? APIError {
            code = api.code
        } else if let failure = error as? SyncRemoteFailure {
            code = failure.warningCode
        } else if error is URLError {
            code = "network_error"
        } else {
            code = "unavailable"
        }
        return RemotePullWarning(id: "\(resource):\(code)", resource: resource, code: code)
    }
}

private extension UUID {
    var wire: String { uuidString.lowercased() }
}

private extension Optional {
    func asyncMap<Value>(_ transform: (Wrapped) async throws -> Value) async rethrows -> Value? {
        guard let self else { return nil }
        return try await transform(self)
    }
}

private extension Array {
    func asyncMap<Value>(_ transform: (Element) async throws -> Value) async rethrows -> [Value] {
        var values: [Value] = []
        values.reserveCapacity(count)
        for element in self {
            values.append(try await transform(element))
        }
        return values
    }
}

private extension LinkedEntityType {
    var entityKind: PlanningEntityKind {
        switch self {
        case .goal: .goal
        case .task: .task
        case .idea: .idea
        case .note: .note
        }
    }
}

private extension PriorityDecayPolicyDTO {
    var updateRequest: UpdatePriorityDecayPolicyRequestDTO {
        UpdatePriorityDecayPolicyRequestDTO(
            enabled: enabled,
            thresholdPreset: thresholdPreset,
            decayAmount: decayAmount
        )
    }
}

private extension SyncRemoteFailure {
    var warningCode: String {
        switch self {
        case .unauthorized: "unauthorized"
        case let .conflict(code, _, _, _), let .permanent(code, _), let .transient(code): code
        }
    }
}
