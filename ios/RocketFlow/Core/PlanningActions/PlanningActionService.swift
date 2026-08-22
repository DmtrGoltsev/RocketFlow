import Foundation

enum TaskRescheduleMinutes: Int, CaseIterable, Sendable {
    case thirtyMinutes = 30
    case oneHour = 60
    case threeHours = 180
    case oneDay = 1_440
}

enum TaskRescheduleChoice: Equatable, Sendable {
    case preset(QuickReschedulePreset)
    case minutes(TaskRescheduleMinutes)

    fileprivate var request: QuickRescheduleRequestDTO {
        switch self {
        case let .preset(value):
            QuickRescheduleRequestDTO(preset: value, minutes: nil)
        case let .minutes(value):
            QuickRescheduleRequestDTO(preset: nil, minutes: value.rawValue)
        }
    }
}

protocol PlanningActionServicing: Sendable {
    func createFolder(_ request: CreateFolderRequestDTO) async throws -> ActionFolderDTO
    func createChildFolder(parentFolderID: UUID, request: CreateFolderRequestDTO) async throws -> ActionFolderDTO
    func updateFolder(id: UUID, request: UpdateFolderRequestDTO) async throws -> ActionFolderDTO
    func deleteFolder(id: UUID) async throws
    func moveFolder(id: UUID, request: MoveFolderRequestDTO) async throws -> ActionFolderDTO
    func cloneFolder(id: UUID, request: CloneFolderRequestDTO) async throws -> ActionFolderDTO

    func createGoal(folderID: UUID, request: CreateGoalRequestDTO) async throws -> ActionGoalDTO
    func updateGoal(id: UUID, request: UpdateGoalRequestDTO) async throws -> ActionGoalDTO
    func deleteGoal(id: UUID) async throws
    func moveGoal(id: UUID, request: MoveGoalRequestDTO) async throws -> ActionGoalDTO
    func cloneGoal(id: UUID, request: CloneGoalRequestDTO) async throws -> ActionGoalDTO

    func createTask(goalID: UUID, request: CreateTaskRequestDTO) async throws -> ActionTaskDTO
    func updateTask(id: UUID, request: ActionUpdateTaskRequestDTO) async throws -> ActionTaskDTO
    func deleteTask(id: UUID) async throws
    func moveTask(id: UUID, plannedTime: Date) async throws -> MoveTaskResponseDTO
    func moveTask(id: UUID, toGoalID: UUID, version: Int64) async throws -> ActionTaskDTO
    func cloneTask(id: UUID, request: CloneTaskRequestDTO) async throws -> ActionTaskDTO
    func quickRescheduleTask(id: UUID, choice: TaskRescheduleChoice) async throws -> QuickRescheduleResponseDTO
    func upsertTaskRecurrence(id: UUID, request: UpsertRecurrenceRequestDTO) async throws -> TaskRecurrenceResponseDTO
    func replaceTaskChecklist(id: UUID, items: [ChecklistItemRequestDTO]) async throws -> TaskChecklistResponseDTO
    func listTags() async throws -> [TaskTagDTO]
    func createTag(_ request: CreateTagRequestDTO) async throws -> TaskTagDTO
    func assignTag(id: UUID, to task: ActionTaskDTO) async throws -> ActionTaskDTO
    func unassignTag(id: UUID, from task: ActionTaskDTO) async throws -> ActionTaskDTO

    func createIdea(folderID: UUID, request: CreateIdeaRequestDTO) async throws -> ActionIdeaDTO
    func updateIdea(id: UUID, request: UpdateIdeaRequestDTO) async throws -> ActionIdeaDTO
    func deleteIdea(id: UUID) async throws
    func moveIdea(id: UUID, request: MoveIdeaRequestDTO) async throws -> ActionIdeaDTO
    func cloneIdea(id: UUID, request: CloneIdeaRequestDTO) async throws -> ActionIdeaDTO
    func listIdeaNotes(ideaID: UUID) async throws -> [ActionIdeaNoteDTO]
    func createIdeaNote(ideaID: UUID, request: CreateIdeaNoteRequestDTO) async throws -> ActionIdeaNoteDTO
    func updateIdeaNote(id: UUID, request: UpdateIdeaNoteRequestDTO) async throws -> ActionIdeaNoteDTO
    func deleteIdeaNote(id: UUID) async throws

    func createNote(folderID: UUID, request: CreateNoteRequestDTO) async throws -> ActionNoteDTO
    func updateNote(id: UUID, request: UpdateNoteRequestDTO) async throws -> ActionNoteDTO
    func deleteNote(id: UUID) async throws
    func moveNote(id: UUID, request: MoveNoteRequestDTO) async throws -> ActionNoteDTO
    func cloneNote(id: UUID, request: CloneNoteRequestDTO) async throws -> ActionNoteDTO

    func listEntityLinks(type: LinkedEntityType, id: UUID) async throws -> [ActionEntityLinkDTO]
    func createEntityLink(_ request: CreateEntityLinkRequestDTO) async throws -> ActionEntityLinkDTO
    func updateEntityLink(id: UUID, request: UpdateEntityLinkRequestDTO) async throws -> ActionEntityLinkDTO
    func deleteEntityLink(id: UUID) async throws
}

struct PlanningActionService: PlanningActionServicing, Sendable {
    private let transport: AuthenticatedActionTransport

    init(sender: any AuthenticatedRequestSending) {
        transport = AuthenticatedActionTransport(sender: sender)
    }

    func createFolder(_ request: CreateFolderRequestDTO) async throws -> ActionFolderDTO {
        try await transport.send(Endpoint(method: .post, path: ["folders"], body: request))
    }

    func createChildFolder(parentFolderID: UUID, request: CreateFolderRequestDTO) async throws -> ActionFolderDTO {
        try await transport.send(
            Endpoint(method: .post, path: ["folders", parentFolderID.wire, "folders"], body: request)
        )
    }

    func updateFolder(id: UUID, request: UpdateFolderRequestDTO) async throws -> ActionFolderDTO {
        try await transport.send(
            Endpoint(method: .patch, path: ["folders", id.wire], body: request),
            versioned: true
        )
    }

    func deleteFolder(id: UUID) async throws {
        let _: EmptyResponse = try await transport.send(Endpoint(method: .delete, path: ["folders", id.wire]))
    }

    func moveFolder(id: UUID, request: MoveFolderRequestDTO) async throws -> ActionFolderDTO {
        try await transport.send(
            Endpoint(method: .post, path: ["folders", id.wire, "move"], body: request),
            versioned: true
        )
    }

    func cloneFolder(id: UUID, request: CloneFolderRequestDTO) async throws -> ActionFolderDTO {
        try await transport.send(
            Endpoint(method: .post, path: ["folders", id.wire, "clone"], body: request)
        )
    }

    func createGoal(folderID: UUID, request: CreateGoalRequestDTO) async throws -> ActionGoalDTO {
        try await transport.send(
            Endpoint(method: .post, path: ["folders", folderID.wire, "goals"], body: request)
        )
    }

    func updateGoal(id: UUID, request: UpdateGoalRequestDTO) async throws -> ActionGoalDTO {
        try await transport.send(
            Endpoint(method: .patch, path: ["goals", id.wire], body: request),
            versioned: true
        )
    }

    func deleteGoal(id: UUID) async throws {
        let _: EmptyResponse = try await transport.send(Endpoint(method: .delete, path: ["goals", id.wire]))
    }

    func moveGoal(id: UUID, request: MoveGoalRequestDTO) async throws -> ActionGoalDTO {
        try await transport.send(
            Endpoint(method: .post, path: ["goals", id.wire, "move"], body: request),
            versioned: true
        )
    }

    func cloneGoal(id: UUID, request: CloneGoalRequestDTO) async throws -> ActionGoalDTO {
        try await transport.send(Endpoint(method: .post, path: ["goals", id.wire, "clone"], body: request))
    }

    func createTask(goalID: UUID, request: CreateTaskRequestDTO) async throws -> ActionTaskDTO {
        try await transport.send(
            Endpoint(method: .post, path: ["goals", goalID.wire, "tasks"], body: request)
        )
    }

    func updateTask(id: UUID, request: ActionUpdateTaskRequestDTO) async throws -> ActionTaskDTO {
        try await transport.send(
            Endpoint(method: .patch, path: ["tasks", id.wire], body: request),
            versioned: true
        )
    }

    func deleteTask(id: UUID) async throws {
        let _: EmptyResponse = try await transport.send(Endpoint(method: .delete, path: ["tasks", id.wire]))
    }

    func moveTask(id: UUID, plannedTime: Date) async throws -> MoveTaskResponseDTO {
        try await transport.send(
            Endpoint(
                method: .post,
                path: ["tasks", id.wire, "move"],
                body: MoveTaskRequestDTO(plannedTime: plannedTime)
            )
        )
    }

    func moveTask(id: UUID, toGoalID: UUID, version: Int64) async throws -> ActionTaskDTO {
        try await transport.send(
            Endpoint(
                method: .post,
                path: ["tasks", id.wire, "move-to-goal"],
                body: MoveTaskToGoalRequestDTO(targetGoalId: toGoalID, version: version)
            ),
            versioned: true
        )
    }

    func cloneTask(id: UUID, request: CloneTaskRequestDTO) async throws -> ActionTaskDTO {
        try await transport.send(Endpoint(method: .post, path: ["tasks", id.wire, "clone"], body: request))
    }

    func quickRescheduleTask(
        id: UUID,
        choice: TaskRescheduleChoice
    ) async throws -> QuickRescheduleResponseDTO {
        try await transport.send(
            Endpoint(method: .post, path: ["tasks", id.wire, "reschedule"], body: choice.request)
        )
    }

    func upsertTaskRecurrence(
        id: UUID,
        request: UpsertRecurrenceRequestDTO
    ) async throws -> TaskRecurrenceResponseDTO {
        try await transport.send(
            Endpoint(method: .put, path: ["tasks", id.wire, "recurrence"], body: request)
        )
    }

    func replaceTaskChecklist(
        id: UUID,
        items: [ChecklistItemRequestDTO]
    ) async throws -> TaskChecklistResponseDTO {
        try await transport.send(
            Endpoint(
                method: .put,
                path: ["tasks", id.wire, "checklist"],
                body: ReplaceChecklistRequestDTO(items: items)
            )
        )
    }

    func listTags() async throws -> [TaskTagDTO] {
        let response: TagListResponseDTO = try await transport.send(
            Endpoint(method: .get, path: ["tags"])
        )
        return response.items
    }

    func createTag(_ request: CreateTagRequestDTO) async throws -> TaskTagDTO {
        try await transport.send(Endpoint(method: .post, path: ["tags"], body: request))
    }

    func assignTag(id: UUID, to task: ActionTaskDTO) async throws -> ActionTaskDTO {
        var tagIDs = task.tags.map(\.id)
        if !tagIDs.contains(id) {
            tagIDs.append(id)
        }
        return try await replaceTags(on: task, tagIDs: tagIDs)
    }

    func unassignTag(id: UUID, from task: ActionTaskDTO) async throws -> ActionTaskDTO {
        try await replaceTags(on: task, tagIDs: task.tags.map(\.id).filter { $0 != id })
    }

    func createIdea(folderID: UUID, request: CreateIdeaRequestDTO) async throws -> ActionIdeaDTO {
        try await transport.send(
            Endpoint(method: .post, path: ["folders", folderID.wire, "ideas"], body: request)
        )
    }

    func updateIdea(id: UUID, request: UpdateIdeaRequestDTO) async throws -> ActionIdeaDTO {
        try await transport.send(
            Endpoint(method: .patch, path: ["ideas", id.wire], body: request),
            versioned: true
        )
    }

    func deleteIdea(id: UUID) async throws {
        let _: EmptyResponse = try await transport.send(Endpoint(method: .delete, path: ["ideas", id.wire]))
    }

    func moveIdea(id: UUID, request: MoveIdeaRequestDTO) async throws -> ActionIdeaDTO {
        try await transport.send(
            Endpoint(method: .post, path: ["ideas", id.wire, "move"], body: request),
            versioned: true
        )
    }

    func cloneIdea(id: UUID, request: CloneIdeaRequestDTO) async throws -> ActionIdeaDTO {
        try await transport.send(Endpoint(method: .post, path: ["ideas", id.wire, "clone"], body: request))
    }

    func listIdeaNotes(ideaID: UUID) async throws -> [ActionIdeaNoteDTO] {
        let response: ActionIdeaNoteListResponseDTO = try await transport.send(
            Endpoint(method: .get, path: ["ideas", ideaID.wire, "notes"])
        )
        return response.items
    }

    func createIdeaNote(ideaID: UUID, request: CreateIdeaNoteRequestDTO) async throws -> ActionIdeaNoteDTO {
        try await transport.send(
            Endpoint(method: .post, path: ["ideas", ideaID.wire, "notes"], body: request)
        )
    }

    func updateIdeaNote(id: UUID, request: UpdateIdeaNoteRequestDTO) async throws -> ActionIdeaNoteDTO {
        try await transport.send(
            Endpoint(method: .patch, path: ["idea-notes", id.wire], body: request),
            versioned: true
        )
    }

    func deleteIdeaNote(id: UUID) async throws {
        let _: EmptyResponse = try await transport.send(
            Endpoint(method: .delete, path: ["idea-notes", id.wire])
        )
    }

    func createNote(folderID: UUID, request: CreateNoteRequestDTO) async throws -> ActionNoteDTO {
        try await transport.send(
            Endpoint(method: .post, path: ["folders", folderID.wire, "notes"], body: request)
        )
    }

    func updateNote(id: UUID, request: UpdateNoteRequestDTO) async throws -> ActionNoteDTO {
        try await transport.send(
            Endpoint(method: .patch, path: ["notes", id.wire], body: request),
            versioned: true
        )
    }

    func deleteNote(id: UUID) async throws {
        let _: EmptyResponse = try await transport.send(Endpoint(method: .delete, path: ["notes", id.wire]))
    }

    func moveNote(id: UUID, request: MoveNoteRequestDTO) async throws -> ActionNoteDTO {
        try await transport.send(
            Endpoint(method: .post, path: ["notes", id.wire, "move"], body: request),
            versioned: true
        )
    }

    func cloneNote(id: UUID, request: CloneNoteRequestDTO) async throws -> ActionNoteDTO {
        try await transport.send(Endpoint(method: .post, path: ["notes", id.wire, "clone"], body: request))
    }

    func listEntityLinks(type: LinkedEntityType, id: UUID) async throws -> [ActionEntityLinkDTO] {
        let response: ActionEntityLinkListResponseDTO = try await transport.send(
            Endpoint(
                method: .get,
                path: ["entity-links"],
                queryItems: [
                    URLQueryItem(name: "entityType", value: type.rawValue),
                    URLQueryItem(name: "entityId", value: id.wire)
                ]
            )
        )
        return response.items
    }

    func createEntityLink(_ request: CreateEntityLinkRequestDTO) async throws -> ActionEntityLinkDTO {
        try await transport.send(Endpoint(method: .post, path: ["entity-links"], body: request))
    }

    func updateEntityLink(id: UUID, request: UpdateEntityLinkRequestDTO) async throws -> ActionEntityLinkDTO {
        try await transport.send(
            Endpoint(method: .patch, path: ["entity-links", id.wire], body: request),
            versioned: true
        )
    }

    func deleteEntityLink(id: UUID) async throws {
        let _: EmptyResponse = try await transport.send(
            Endpoint(method: .delete, path: ["entity-links", id.wire])
        )
    }

    private func replaceTags(on task: ActionTaskDTO, tagIDs: [UUID]) async throws -> ActionTaskDTO {
        try await updateTask(
            id: task.id,
            request: ActionUpdateTaskRequestDTO(
                preservingPriorityFrom: task,
                title: task.title,
                description: task.description,
                type: task.type,
                effort: task.effort,
                status: task.status,
                plannedTime: task.plannedTime,
                dueTime: task.dueTime,
                archived: task.archived,
                tagIds: tagIDs,
                checklistItems: nil
            )
        )
    }
}

private extension UUID {
    var wire: String { uuidString.lowercased() }
}
