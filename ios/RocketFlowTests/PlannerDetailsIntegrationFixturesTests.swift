import Foundation
import XCTest
@testable import RocketFlow

enum PlannerDetailsIntegrationFixtureError: Error, Sendable {
    case unsupported
}

struct PlannerDetailsCurrentRefresher: PlannerDetailsRefreshing {
    func refreshPlannerDetails() async throws -> PlannerDetailsRefreshResult {
        PlannerDetailsRefreshResult(isCurrent: true, warning: nil)
    }
}

actor PlannerDetailsRemoteStub: PlannerDetailsRemoteActioning {
    var taskResponse: ActionTaskDTO
    var ideaResponse: ActionIdeaDTO
    var noteResponse: ActionNoteDTO
    var ideaNoteResponse: ActionIdeaNoteDTO
    var recurrenceResponse: TaskRecurrenceResponseDTO
    var tagResponse: TaskTagDTO
    private(set) var taskUpdatePayloads: [Data] = []
    private(set) var taskCreateCount = 0
    private(set) var deletedTaskIDs: [UUID] = []
    private(set) var deletedIdeaIDs: [UUID] = []
    private(set) var updatedIdeaNoteIDs: [UUID] = []
    private(set) var deletedIdeaNoteIDs: [UUID] = []
    private(set) var movedIdeaRequests: [(UUID, MoveIdeaRequestDTO)] = []
    var recurrenceFailuresRemaining: Int
    var taskDeleteFailuresRemaining: Int

    init(
        taskResponse: ActionTaskDTO = PlannerDetailsIntegrationFixtures.actionTask(),
        ideaResponse: ActionIdeaDTO = PlannerDetailsIntegrationFixtures.actionIdea(),
        noteResponse: ActionNoteDTO = PlannerDetailsIntegrationFixtures.actionNote(),
        ideaNoteResponse: ActionIdeaNoteDTO = PlannerDetailsIntegrationFixtures.actionIdeaNote(),
        recurrenceResponse: TaskRecurrenceResponseDTO = PlannerDetailsIntegrationFixtures.recurrenceResponse,
        tagResponse: TaskTagDTO = TaskTagDTO(id: UUID(), name: "Tag", color: nil),
        recurrenceFailuresRemaining: Int = 0,
        taskDeleteFailuresRemaining: Int = 0
    ) {
        self.taskResponse = taskResponse
        self.ideaResponse = ideaResponse
        self.noteResponse = noteResponse
        self.ideaNoteResponse = ideaNoteResponse
        self.recurrenceResponse = recurrenceResponse
        self.tagResponse = tagResponse
        self.recurrenceFailuresRemaining = recurrenceFailuresRemaining
        self.taskDeleteFailuresRemaining = taskDeleteFailuresRemaining
    }

    func createTask(goalID: UUID, request: CreateTaskRequestDTO) -> ActionTaskDTO {
        taskCreateCount += 1
        return taskResponse
    }

    func updateTask(id: UUID, request: ActionUpdateTaskRequestDTO) throws -> ActionTaskDTO {
        taskUpdatePayloads.append(try WireJSON.encoder().encode(request))
        return taskResponse
    }

    func moveTask(id: UUID, plannedTime: Date) -> MoveTaskResponseDTO {
        MoveTaskResponseDTO(
            id: id,
            plannedTime: plannedTime,
            priorityShadow: taskResponse.priorityShadow,
            updatedAt: PlannerDetailsIntegrationFixtures.now
        )
    }

    func upsertTaskRecurrence(
        id: UUID,
        request: UpsertRecurrenceRequestDTO
    ) throws -> TaskRecurrenceResponseDTO {
        if recurrenceFailuresRemaining > 0 {
            recurrenceFailuresRemaining -= 1
            throw RemoteActionError.retryable(code: "controlled_recurrence_failure", message: "Retry")
        }
        return recurrenceResponse
    }

    func deleteTask(id: UUID) throws {
        if taskDeleteFailuresRemaining > 0 {
            taskDeleteFailuresRemaining -= 1
            throw RemoteActionError.retryable(code: "controlled_delete_failure", message: "Retry")
        }
        deletedTaskIDs.append(id)
    }

    func cloneFolder(id: UUID, request: CloneFolderRequestDTO) throws -> ActionFolderDTO {
        throw PlannerDetailsIntegrationFixtureError.unsupported
    }

    func cloneGoal(id: UUID, request: CloneGoalRequestDTO) throws -> ActionGoalDTO {
        throw PlannerDetailsIntegrationFixtureError.unsupported
    }

    func cloneTask(id: UUID, request: CloneTaskRequestDTO) -> ActionTaskDTO { taskResponse }

    func createIdea(folderID: UUID, request: CreateIdeaRequestDTO) -> ActionIdeaDTO { ideaResponse }
    func updateIdea(id: UUID, request: UpdateIdeaRequestDTO) -> ActionIdeaDTO { ideaResponse }
    func deleteIdea(id: UUID) { deletedIdeaIDs.append(id) }

    func moveIdea(id: UUID, request: MoveIdeaRequestDTO) -> ActionIdeaDTO {
        movedIdeaRequests.append((id, request))
        return ideaResponse
    }

    func cloneIdea(id: UUID, request: CloneIdeaRequestDTO) -> ActionIdeaDTO { ideaResponse }

    func createIdeaNote(
        ideaID: UUID,
        request: CreateIdeaNoteRequestDTO
    ) -> ActionIdeaNoteDTO {
        ideaNoteResponse
    }

    func updateIdeaNote(
        id: UUID,
        request: UpdateIdeaNoteRequestDTO
    ) -> ActionIdeaNoteDTO {
        updatedIdeaNoteIDs.append(id)
        return ideaNoteResponse
    }

    func deleteIdeaNote(id: UUID) { deletedIdeaNoteIDs.append(id) }
    func createNote(folderID: UUID, request: CreateNoteRequestDTO) -> ActionNoteDTO { noteResponse }
    func updateNote(id: UUID, request: UpdateNoteRequestDTO) -> ActionNoteDTO { noteResponse }
    func deleteNote(id: UUID) {}
    func moveNote(id: UUID, request: MoveNoteRequestDTO) -> ActionNoteDTO { noteResponse }
    func cloneNote(id: UUID, request: CloneNoteRequestDTO) -> ActionNoteDTO { noteResponse }
    func createTag(_ request: CreateTagRequestDTO) -> TaskTagDTO { tagResponse }

    func updateJSON() -> Data? { taskUpdatePayloads.last }
    func ideaDeletes() -> [UUID] { deletedIdeaIDs }
    func ideaNoteUpdates() -> [UUID] { updatedIdeaNoteIDs }
    func ideaNoteDeletes() -> [UUID] { deletedIdeaNoteIDs }
    func ideaMoves() -> [(UUID, MoveIdeaRequestDTO)] { movedIdeaRequests }
    func taskCreates() -> Int { taskCreateCount }
    func taskDeletes() -> [UUID] { deletedTaskIDs }
}

enum PlannerDetailsIntegrationFixtures {
    static let accountID = UUID(uuidString: "a0000000-0000-0000-0000-000000000001")!
    static let userID = UUID(uuidString: "a0000000-0000-0000-0000-000000000002")!
    static let otherUserID = UUID(uuidString: "a0000000-0000-0000-0000-000000000003")!
    static let folderLocalID = UUID(uuidString: "b0000000-0000-0000-0000-000000000001")!
    static let folderRemoteID = UUID(uuidString: "b0000000-0000-0000-0000-000000000002")!
    static let secondFolderLocalID = UUID(uuidString: "b0000000-0000-0000-0000-000000000003")!
    static let secondFolderRemoteID = UUID(uuidString: "b0000000-0000-0000-0000-000000000004")!
    static let goalLocalID = UUID(uuidString: "c0000000-0000-0000-0000-000000000001")!
    static let goalRemoteID = UUID(uuidString: "c0000000-0000-0000-0000-000000000002")!
    static let secondGoalLocalID = UUID(uuidString: "c0000000-0000-0000-0000-000000000003")!
    static let secondGoalRemoteID = UUID(uuidString: "c0000000-0000-0000-0000-000000000004")!
    static let taskLocalID = UUID(uuidString: "d0000000-0000-0000-0000-000000000001")!
    static let taskRemoteID = UUID(uuidString: "d0000000-0000-0000-0000-000000000002")!
    static let ideaLocalID = UUID(uuidString: "e0000000-0000-0000-0000-000000000001")!
    static let ideaRemoteID = UUID(uuidString: "e0000000-0000-0000-0000-000000000002")!
    static let ideaNoteLocalID = UUID(uuidString: "e0000000-0000-0000-0000-000000000003")!
    static let ideaNoteRemoteID = UUID(uuidString: "e0000000-0000-0000-0000-000000000004")!
    static let noteLocalID = UUID(uuidString: "f0000000-0000-0000-0000-000000000001")!
    static let noteRemoteID = UUID(uuidString: "f0000000-0000-0000-0000-000000000002")!
    static let tagLocalID = UUID(uuidString: "11000000-0000-0000-0000-000000000001")!
    static let tagRemoteID = UUID(uuidString: "11000000-0000-0000-0000-000000000002")!
    static let checklistRemoteID = UUID(uuidString: "12000000-0000-0000-0000-000000000001")!
    static let now = Date(timeIntervalSince1970: 1_787_568_000)

    static var recurrence: RecurrenceDTO {
        RecurrenceDTO(
            mode: .weekly,
            interval: 1,
            daysOfWeek: [.monday],
            dayOfMonth: nil,
            startAt: now,
            endAt: now.addingTimeInterval(86_400 * 30),
            active: true
        )
    }

    static var recurrenceResponse: TaskRecurrenceResponseDTO {
        TaskRecurrenceResponseDTO(taskId: taskRemoteID, recurrence: recurrence)
    }

    static func folder(
        id: UUID = folderRemoteID,
        name: String = "Folder",
        shared: Bool = false,
        fullAccess: Bool = true
    ) -> FolderDTO {
        FolderDTO(
            id: id,
            parentFolderId: nil,
            name: name,
            description: "Folder body",
            displayOrder: 0,
            archived: false,
            shared: shared,
            fullAccess: fullAccess,
            version: 2,
            createdAt: now,
            updatedAt: now
        )
    }

    static func goal(
        id: UUID = goalRemoteID,
        folderID: UUID = folderRemoteID,
        name: String = "Goal",
        shared: Bool = false,
        fullAccess: Bool = true
    ) -> GoalDTO {
        GoalDTO(
            id: id,
            folderId: folderID,
            name: name,
            description: "Goal body",
            status: .todo,
            archived: false,
            shared: shared,
            fullAccess: fullAccess,
            version: 3,
            createdAt: now,
            updatedAt: now
        )
    }

    static func actionTask(
        id: UUID = taskRemoteID,
        goalID: UUID = goalRemoteID,
        title: String = "Task",
        status: PlanningStatus = .todo,
        shadow: Int = 9,
        shared: Bool = false,
        fullAccess: Bool = true,
        creatorID: UUID? = userID,
        plannedTime: Date? = nil,
        dueTime: Date? = nil,
        tags: [TaskTagDTO] = [],
        checklist: [ChecklistItemDTO] = [],
        recurrence: RecurrenceDTO? = nil
    ) -> ActionTaskDTO {
        ActionTaskDTO(
            id: id,
            goalId: goalID,
            title: title,
            description: "Task body",
            type: .green,
            priorityShadow: shadow,
            effort: 4,
            status: status,
            plannedTime: plannedTime,
            dueTime: dueTime,
            archived: false,
            shared: shared,
            fullAccess: fullAccess,
            creatorUserId: creatorID,
            creatorEmail: nil,
            creatorName: "Owner",
            version: 4,
            tags: tags,
            checklistItems: checklist,
            recurrence: recurrence,
            createdAt: now,
            updatedAt: now
        )
    }

    static func actionIdea(
        id: UUID = ideaRemoteID,
        folderID: UUID = folderRemoteID,
        creatorID: UUID? = userID,
        shared: Bool = false,
        fullAccess: Bool = true,
        allowAuthorNoteEdits: Bool = true
    ) -> ActionIdeaDTO {
        ActionIdeaDTO(
            id: id,
            folderId: folderID,
            title: "Idea",
            body: "Idea body",
            status: "ACTIVE",
            displayOrder: 0,
            archived: false,
            allowAuthorNoteEdits: allowAuthorNoteEdits,
            shared: shared,
            fullAccess: fullAccess,
            creatorUserId: creatorID,
            creatorEmail: nil,
            creatorName: "Owner",
            version: 5,
            createdAt: now,
            updatedAt: now
        )
    }

    static func actionNote(
        id: UUID = noteRemoteID,
        folderID: UUID = folderRemoteID
    ) -> ActionNoteDTO {
        ActionNoteDTO(
            id: id,
            folderId: folderID,
            title: "Note",
            body: "Note body",
            displayOrder: 0,
            archived: false,
            shared: false,
            fullAccess: true,
            authorUserId: userID,
            authorEmail: nil,
            authorName: "Owner",
            version: 2,
            createdAt: now,
            updatedAt: now
        )
    }

    static func actionIdeaNote(
        id: UUID = ideaNoteRemoteID,
        ideaID: UUID = ideaRemoteID,
        authorID: UUID? = userID
    ) -> ActionIdeaNoteDTO {
        ActionIdeaNoteDTO(
            id: id,
            ideaId: ideaID,
            eventType: "comment",
            body: "History",
            metadata: ["source": .string("ios")],
            authorUserId: authorID,
            authorEmail: nil,
            authorName: "Owner",
            version: 1,
            createdAt: now,
            updatedAt: now
        )
    }

    static func makeSystem(
        connected: Bool = true,
        remote: (any PlannerDetailsRemoteActioning)? = nil,
        generatedID: UUID = taskLocalID
    ) throws -> (
        AppDatabase,
        LocalPlanningRepository,
        GRDBPlannerDetailsPersistence,
        PlannerDetailsAdapter
    ) {
        let database = try AppDatabase.inMemory()
        let repository = LocalPlanningRepository(database: database)
        let persistence = GRDBPlannerDetailsPersistence(database: database)
        let adapter = PlannerDetailsAdapter(
            repository: repository,
            persistence: persistence,
            account: PlannerDetailsAccountContext(
                accountID: accountID,
                currentUserID: userID,
                timezone: "Europe/Moscow"
            ),
            network: FixedNetworkMonitor(connected: connected),
            refresher: PlannerDetailsCurrentRefresher(),
            remote: remote,
            makeID: { generatedID }
        )
        return (database, repository, persistence, adapter)
    }

    static func seedHierarchy(
        persistence: GRDBPlannerDetailsPersistence,
        includeSecondParents: Bool = false
    ) async throws {
        try await persistence.bindAndApply(
            kind: .folder,
            localID: folderLocalID,
            remoteID: folderRemoteID,
            version: 2,
            payloadJSON: WireJSON.encoder().encode(folder())
        )
        try await persistence.bindAndApply(
            kind: .goal,
            localID: goalLocalID,
            remoteID: goalRemoteID,
            version: 3,
            payloadJSON: WireJSON.encoder().encode(goal())
        )
        if includeSecondParents {
            try await persistence.bindAndApply(
                kind: .folder,
                localID: secondFolderLocalID,
                remoteID: secondFolderRemoteID,
                version: 2,
                payloadJSON: WireJSON.encoder().encode(
                    folder(id: secondFolderRemoteID, name: "Second folder")
                )
            )
            try await persistence.bindAndApply(
                kind: .goal,
                localID: secondGoalLocalID,
                remoteID: secondGoalRemoteID,
                version: 3,
                payloadJSON: WireJSON.encoder().encode(
                    goal(
                        id: secondGoalRemoteID,
                        folderID: secondFolderRemoteID,
                        name: "Second goal"
                    )
                )
            )
        }
    }

    static func seedTask(
        persistence: GRDBPlannerDetailsPersistence,
        action: ActionTaskDTO = actionTask()
    ) async throws {
        let dto = try PlannerDetailsDTOMapper.task(action)
        try await persistence.bindAndApply(
            kind: .task,
            localID: taskLocalID,
            remoteID: action.id,
            version: action.version,
            payloadJSON: WireJSON.encoder().encode(dto)
        )
    }

    static func seedIdea(
        persistence: GRDBPlannerDetailsPersistence,
        action: ActionIdeaDTO = actionIdea()
    ) async throws {
        let dto = PlannerDetailsDTOMapper.idea(action)
        try await persistence.bindAndApply(
            kind: .idea,
            localID: ideaLocalID,
            remoteID: action.id,
            version: action.version,
            payloadJSON: WireJSON.encoder().encode(dto)
        )
    }

    static func seedIdeaNote(
        persistence: GRDBPlannerDetailsPersistence,
        action: ActionIdeaNoteDTO = actionIdeaNote()
    ) async throws {
        let dto = PlannerDetailsDTOMapper.ideaNote(action)
        try await persistence.bindAndApply(
            kind: .ideaNote,
            localID: ideaNoteLocalID,
            remoteID: action.id,
            version: action.version,
            payloadJSON: WireJSON.encoder().encode(dto)
        )
    }

    static func grantTaskCreation(database: AppDatabase, goalIDs: [UUID]) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO collaboration_cache (cacheKey, payloadJSON, updatedAt)
                    VALUES (?, ?, ?)
                    ON CONFLICT(cacheKey) DO UPDATE SET
                        payloadJSON = excluded.payloadJSON,
                        updatedAt = excluded.updatedAt
                    """,
                arguments: [
                    "planner.createTaskGoalIDs",
                    try WireJSON.encoder().encode(goalIDs),
                    WireDateCodec.encode(now)
                ]
            )
        }
    }
}
