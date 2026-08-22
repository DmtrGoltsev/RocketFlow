import Foundation

struct PlannerDetailsAccountContext: Equatable, Sendable {
    let accountID: UUID
    let currentUserID: UUID
    let timezone: String
}

enum PlannerDetailsIntegrationError: Error, Equatable, Sendable, LocalizedError {
    case networkRequired
    case unauthorized
    case forbidden(code: String, message: String)
    case validation(message: String, fields: [String: String])
    case dependencyBlocked(code: String, message: String)
    case conflict(code: String, message: String)
    case notFound(kind: PlanningEntityKind, id: UUID)
    case remoteNotFound(code: String, message: String)
    case missingMapping(kind: PlanningEntityKind, id: UUID)
    case unsupported(operation: String)
    case unavailable(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .networkRequired:
            "A network connection is required for this operation."
        case .unauthorized:
            "Authentication is required."
        case let .forbidden(_, message),
             let .validation(message, _),
             let .dependencyBlocked(_, message),
             let .conflict(_, message),
             let .unavailable(_, message):
            message
        case let .notFound(kind, id):
            "Missing \(kind.rawValue) \(id.uuidString.lowercased())."
        case let .remoteNotFound(_, message):
            message
        case let .missingMapping(kind, id):
            "Missing server mapping for \(kind.rawValue) \(id.uuidString.lowercased())."
        case let .unsupported(operation):
            "Unsupported operation: \(operation)."
        }
    }
}

struct PlannerDetailsRefreshResult: Equatable, Sendable {
    let isCurrent: Bool
    let warning: String?
}

protocol PlannerDetailsRefreshing: Sendable {
    func refreshPlannerDetails() async throws -> PlannerDetailsRefreshResult
}

struct SyncEnginePlannerDetailsRefresher: PlannerDetailsRefreshing, Sendable {
    let engine: SyncEngine

    func refreshPlannerDetails() async throws -> PlannerDetailsRefreshResult {
        let status = await engine.sync(trigger: .foreground)
        switch status.phase {
        case .idle:
            return PlannerDetailsRefreshResult(isCurrent: true, warning: nil)
        case .conflicted:
            return PlannerDetailsRefreshResult(
                isCurrent: true,
                warning: status.lastErrorCode ?? "sync_conflict"
            )
        case .waitingForNetwork, .waitingForRetry, .failed, .cancelled:
            return PlannerDetailsRefreshResult(
                isCurrent: false,
                warning: status.lastErrorCode ?? status.phase.rawValue
            )
        case .unauthorized:
            throw PlannerDetailsIntegrationError.unauthorized
        case .syncing:
            return PlannerDetailsRefreshResult(isCurrent: false, warning: "sync_incomplete")
        }
    }
}

protocol PlannerDetailsRemoteActioning: Sendable {
    func createTask(goalID: UUID, request: CreateTaskRequestDTO) async throws -> ActionTaskDTO
    func updateTask(id: UUID, request: ActionUpdateTaskRequestDTO) async throws -> ActionTaskDTO
    func deleteTask(id: UUID) async throws
    func moveTask(id: UUID, plannedTime: Date) async throws -> MoveTaskResponseDTO
    func upsertTaskRecurrence(
        id: UUID,
        request: UpsertRecurrenceRequestDTO
    ) async throws -> TaskRecurrenceResponseDTO
    func cloneFolder(id: UUID, request: CloneFolderRequestDTO) async throws -> ActionFolderDTO
    func cloneGoal(id: UUID, request: CloneGoalRequestDTO) async throws -> ActionGoalDTO
    func cloneTask(id: UUID, request: CloneTaskRequestDTO) async throws -> ActionTaskDTO
    func createIdea(folderID: UUID, request: CreateIdeaRequestDTO) async throws -> ActionIdeaDTO
    func updateIdea(id: UUID, request: UpdateIdeaRequestDTO) async throws -> ActionIdeaDTO
    func deleteIdea(id: UUID) async throws
    func moveIdea(id: UUID, request: MoveIdeaRequestDTO) async throws -> ActionIdeaDTO
    func cloneIdea(id: UUID, request: CloneIdeaRequestDTO) async throws -> ActionIdeaDTO
    func createIdeaNote(ideaID: UUID, request: CreateIdeaNoteRequestDTO) async throws -> ActionIdeaNoteDTO
    func updateIdeaNote(id: UUID, request: UpdateIdeaNoteRequestDTO) async throws -> ActionIdeaNoteDTO
    func deleteIdeaNote(id: UUID) async throws
    func createNote(folderID: UUID, request: CreateNoteRequestDTO) async throws -> ActionNoteDTO
    func updateNote(id: UUID, request: UpdateNoteRequestDTO) async throws -> ActionNoteDTO
    func deleteNote(id: UUID) async throws
    func moveNote(id: UUID, request: MoveNoteRequestDTO) async throws -> ActionNoteDTO
    func cloneNote(id: UUID, request: CloneNoteRequestDTO) async throws -> ActionNoteDTO
    func createTag(_ request: CreateTagRequestDTO) async throws -> TaskTagDTO
}

struct PlanningActionPlannerDetailsRemote: PlannerDetailsRemoteActioning, Sendable {
    let service: any PlanningActionServicing

    func createTask(goalID: UUID, request: CreateTaskRequestDTO) async throws -> ActionTaskDTO {
        try await service.createTask(goalID: goalID, request: request)
    }

    func updateTask(id: UUID, request: ActionUpdateTaskRequestDTO) async throws -> ActionTaskDTO {
        try await service.updateTask(id: id, request: request)
    }

    func deleteTask(id: UUID) async throws {
        try await service.deleteTask(id: id)
    }

    func moveTask(id: UUID, plannedTime: Date) async throws -> MoveTaskResponseDTO {
        try await service.moveTask(id: id, plannedTime: plannedTime)
    }

    func upsertTaskRecurrence(
        id: UUID,
        request: UpsertRecurrenceRequestDTO
    ) async throws -> TaskRecurrenceResponseDTO {
        try await service.upsertTaskRecurrence(id: id, request: request)
    }

    func cloneFolder(id: UUID, request: CloneFolderRequestDTO) async throws -> ActionFolderDTO {
        try await service.cloneFolder(id: id, request: request)
    }

    func cloneGoal(id: UUID, request: CloneGoalRequestDTO) async throws -> ActionGoalDTO {
        try await service.cloneGoal(id: id, request: request)
    }

    func cloneTask(id: UUID, request: CloneTaskRequestDTO) async throws -> ActionTaskDTO {
        try await service.cloneTask(id: id, request: request)
    }

    func createIdea(folderID: UUID, request: CreateIdeaRequestDTO) async throws -> ActionIdeaDTO {
        try await service.createIdea(folderID: folderID, request: request)
    }

    func updateIdea(id: UUID, request: UpdateIdeaRequestDTO) async throws -> ActionIdeaDTO {
        try await service.updateIdea(id: id, request: request)
    }

    func deleteIdea(id: UUID) async throws { try await service.deleteIdea(id: id) }

    func moveIdea(id: UUID, request: MoveIdeaRequestDTO) async throws -> ActionIdeaDTO {
        try await service.moveIdea(id: id, request: request)
    }

    func cloneIdea(id: UUID, request: CloneIdeaRequestDTO) async throws -> ActionIdeaDTO {
        try await service.cloneIdea(id: id, request: request)
    }

    func createIdeaNote(
        ideaID: UUID,
        request: CreateIdeaNoteRequestDTO
    ) async throws -> ActionIdeaNoteDTO {
        try await service.createIdeaNote(ideaID: ideaID, request: request)
    }

    func updateIdeaNote(
        id: UUID,
        request: UpdateIdeaNoteRequestDTO
    ) async throws -> ActionIdeaNoteDTO {
        try await service.updateIdeaNote(id: id, request: request)
    }

    func deleteIdeaNote(id: UUID) async throws { try await service.deleteIdeaNote(id: id) }

    func createNote(folderID: UUID, request: CreateNoteRequestDTO) async throws -> ActionNoteDTO {
        try await service.createNote(folderID: folderID, request: request)
    }

    func updateNote(id: UUID, request: UpdateNoteRequestDTO) async throws -> ActionNoteDTO {
        try await service.updateNote(id: id, request: request)
    }

    func deleteNote(id: UUID) async throws { try await service.deleteNote(id: id) }

    func moveNote(id: UUID, request: MoveNoteRequestDTO) async throws -> ActionNoteDTO {
        try await service.moveNote(id: id, request: request)
    }

    func cloneNote(id: UUID, request: CloneNoteRequestDTO) async throws -> ActionNoteDTO {
        try await service.cloneNote(id: id, request: request)
    }

    func createTag(_ request: CreateTagRequestDTO) async throws -> TaskTagDTO {
        try await service.createTag(request)
    }
}

protocol PlannerDetailsSharingAccessing: Sendable {
    func sharedResources() async throws -> ActionSharedResourcesResponseDTO
    func createInvitation(
        resource: ShareableResourceKind,
        id: UUID,
        request: SharingInvitationRequest
    ) async throws -> ShareInvitationDTO
}

struct SharingPlannerDetailsAccess: PlannerDetailsSharingAccessing, Sendable {
    let service: any SharingServicing

    func sharedResources() async throws -> ActionSharedResourcesResponseDTO {
        try await service.listSharedResources()
    }

    func createInvitation(
        resource: ShareableResourceKind,
        id: UUID,
        request: SharingInvitationRequest
    ) async throws -> ShareInvitationDTO {
        try await service.createInvitation(resource: resource, id: id, request: request)
    }
}

enum PlannerDetailsErrorTranslator {
    static func map(_ error: Error) -> PlannerDetailsIntegrationError {
        if let integration = error as? PlannerDetailsIntegrationError { return integration }
        if error is CancellationError {
            return .unavailable(code: "cancelled", message: "The operation was cancelled.")
        }
        if let remote = error as? RemoteActionError {
            switch remote {
            case .unauthorized:
                return .unauthorized
            case let .forbidden(code, message):
                return .forbidden(code: code, message: message)
            case let .notFound(code, message):
                return .remoteNotFound(code: code, message: message)
            case let .versionConflict(code, message), let .conflict(code, message):
                return .conflict(code: code, message: message)
            case let .dependencyBlocked(code, message):
                return .dependencyBlocked(code: code, message: message)
            case let .validation(message, fields):
                return .validation(message: message, fields: fields)
            case let .retryable(code, message), let .unexpected(_, code, message):
                return .unavailable(code: code, message: message)
            case .cancelled:
                return .unavailable(code: "cancelled", message: "The operation was cancelled.")
            }
        }
        if let repository = error as? RepositoryError {
            switch repository {
            case let .missingEntity(kind, id):
                return .notFound(kind: kind, id: id)
            case let .unsupportedEntity(kind):
                return .unsupported(operation: kind.rawValue)
            case let .unsupportedMutation(kind, operation):
                return .unsupported(operation: "\(kind.rawValue).\(operation.rawValue)")
            case let .conflictExists(id):
                return .conflict(code: "local_conflict", message: id.uuidString.lowercased())
            case let .invalidParent(kind, id),
                 let .parentMoveRequiresDedicatedOperation(kind, id),
                 let .pendingMutationRequiresSync(kind, id):
                return .conflict(
                    code: "local_state_conflict",
                    message: "\(kind.rawValue):\(id.uuidString.lowercased())"
                )
            case let .missingServerPayload(id), let .missingServerVersion(id):
                return .conflict(code: "server_state_missing", message: id.uuidString.lowercased())
            }
        }
        if let api = error as? APIError, api.isUnauthorized { return .unauthorized }
        if error is URLError { return .networkRequired }
        return .unavailable(code: "integration_error", message: error.localizedDescription)
    }

    static func detailFailure(_ error: Error) -> DetailServiceFailure {
        switch map(error) {
        case let .dependencyBlocked(code, message):
            return DetailServiceFailure(statusCode: 409, code: code, message: message)
        case .unauthorized:
            return DetailServiceFailure(statusCode: 401, code: "unauthorized", message: "Unauthorized")
        case let .validation(message, _):
            return DetailServiceFailure(statusCode: 422, code: "validation", message: message)
        case let .conflict(code, message):
            return DetailServiceFailure(statusCode: 409, code: code, message: message)
        case let .forbidden(code, message):
            return DetailServiceFailure(statusCode: 403, code: code, message: message)
        case .networkRequired:
            return DetailServiceFailure(statusCode: nil, code: "network_required", message: "Network required")
        case .notFound:
            return DetailServiceFailure(statusCode: 404, code: "not_found", message: "Not found")
        case let .remoteNotFound(code, message):
            return DetailServiceFailure(statusCode: 404, code: code, message: message)
        case let .missingMapping(kind, id):
            return DetailServiceFailure(
                statusCode: 409,
                code: "missing_id_mapping",
                message: "\(kind.rawValue):\(id.uuidString.lowercased())"
            )
        case let .unsupported(operation):
            return DetailServiceFailure(statusCode: 422, code: "unsupported", message: operation)
        case let .unavailable(code, message):
            return DetailServiceFailure(statusCode: nil, code: code, message: message)
        }
    }
}

enum PlannerDetailsDTOMapper {
    static func task(_ value: ActionTaskDTO) throws -> TaskDTO {
        try WireJSON.decoder().decode(TaskDTO.self, from: WireJSON.encoder().encode(value))
    }

    static func actionTask(_ value: TaskDTO) throws -> ActionTaskDTO {
        try WireJSON.decoder().decode(ActionTaskDTO.self, from: WireJSON.encoder().encode(value))
    }

    static func folder(_ value: ActionFolderDTO) -> FolderDTO {
        FolderDTO(
            id: value.id,
            parentFolderId: value.parentFolderId,
            name: value.name,
            description: value.description ?? "",
            displayOrder: value.displayOrder,
            archived: value.archived,
            shared: value.shared,
            fullAccess: value.fullAccess,
            version: value.version,
            createdAt: value.createdAt,
            updatedAt: value.updatedAt
        )
    }

    static func goal(_ value: ActionGoalDTO) -> GoalDTO {
        GoalDTO(
            id: value.id,
            folderId: value.folderId,
            name: value.name,
            description: value.description ?? "",
            status: value.status,
            archived: value.archived,
            shared: value.shared,
            fullAccess: value.fullAccess,
            version: value.version,
            createdAt: value.createdAt,
            updatedAt: value.updatedAt
        )
    }

    static func idea(_ value: ActionIdeaDTO) -> IdeaDTO {
        IdeaDTO(
            id: value.id,
            folderId: value.folderId,
            title: value.title,
            body: value.body ?? "",
            status: value.status,
            displayOrder: value.displayOrder,
            archived: value.archived,
            allowAuthorNoteEdits: value.allowAuthorNoteEdits,
            shared: value.shared,
            fullAccess: value.fullAccess,
            creatorUserId: value.creatorUserId,
            creatorEmail: value.creatorEmail,
            creatorName: value.creatorName,
            version: value.version,
            createdAt: value.createdAt,
            updatedAt: value.updatedAt
        )
    }

    static func ideaNote(_ value: ActionIdeaNoteDTO) -> IdeaNoteDTO {
        IdeaNoteDTO(
            id: value.id,
            ideaId: value.ideaId,
            eventType: value.eventType,
            body: value.body ?? "",
            metadata: value.metadata,
            authorUserId: value.authorUserId,
            authorEmail: value.authorEmail,
            authorName: value.authorName,
            version: value.version,
            createdAt: value.createdAt,
            updatedAt: value.updatedAt
        )
    }

    static func note(_ value: ActionNoteDTO) -> NoteDTO {
        NoteDTO(
            id: value.id,
            folderId: value.folderId,
            title: value.title,
            body: value.body ?? "",
            displayOrder: value.displayOrder,
            archived: value.archived,
            shared: value.shared,
            fullAccess: value.fullAccess,
            authorUserId: value.authorUserId,
            authorEmail: value.authorEmail,
            authorName: value.authorName,
            version: value.version,
            createdAt: value.createdAt,
            updatedAt: value.updatedAt
        )
    }
}

extension PlanningEntityKind {
    init(_ value: PlannerItemKind) {
        switch value {
        case .folder: self = .folder
        case .goal: self = .goal
        case .task: self = .task
        case .idea: self = .idea
        case .note: self = .note
        }
    }

    init(_ value: DetailEntityKind) {
        switch value {
        case .folder: self = .folder
        case .goal: self = .goal
        case .task: self = .task
        case .idea: self = .idea
        case .note: self = .note
        }
    }
}
