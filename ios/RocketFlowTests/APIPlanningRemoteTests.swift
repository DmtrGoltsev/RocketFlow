import Foundation
import XCTest
@testable import RocketFlow

private actor RemoteTestSender: AuthenticatedRequestSending {
    struct Stub: Sendable {
        let response: Data?
        let error: APIError?

        init<Response: Encodable>(_ response: Response) throws {
            self.response = try WireJSON.encoder().encode(response)
            error = nil
        }

        init(error: APIError) {
            response = nil
            self.error = error
        }
    }

    struct Captured: Sendable {
        let method: String
        let path: String
        let body: Data?
    }

    private var stubs: [Stub]
    private var captured: [Captured] = []

    init(stubs: [Stub]) {
        self.stubs = stubs
    }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let request = try endpoint.makeRequest(
            baseURL: URL(string: "https://example.test/rocket-api")!,
            bearerToken: "test-token"
        ).urlRequest
        captured.append(
            Captured(
                method: request.httpMethod ?? "",
                path: request.url?.path ?? "",
                body: request.httpBody
            )
        )
        let stub = stubs.removeFirst()
        if let error = stub.error { throw error }
        return try WireJSON.decoder().decode(Response.self, from: stub.response ?? Data("{}".utf8))
    }

    func requests() -> [Captured] { captured }
}

private actor RemoteTestIDResolver: RemoteIDResolving {
    private let values: [UUID: UUID]

    init(values: [UUID: UUID] = [:]) {
        self.values = values
    }

    func remoteID(for entityType: PlanningEntityKind, localID: UUID) throws -> UUID {
        values[localID] ?? localID
    }
}

final class APIPlanningRemoteTests: XCTestCase {
    func testPushesEveryRepresentableMutationTypeWithExpectedRoutes() async throws {
        let date = Date(timeIntervalSince1970: 1_724_323_200)
        let folder = FolderDTO(
            id: UUID(), parentFolderId: nil, name: "Folder", description: "",
            displayOrder: 0, archived: false, shared: false, fullAccess: true,
            version: 0, createdAt: date, updatedAt: date
        )
        let goal = GoalDTO(
            id: UUID(), folderId: folder.id, name: "Goal", description: "",
            status: .todo, archived: false, shared: false, fullAccess: true,
            version: 0, createdAt: date, updatedAt: date
        )
        let task: TaskDTO = try fixture(
            """
            {"id":"\(UUID())","goalId":"\(goal.id)","title":"Task","description":"",\
            "type":"green","effort":2,"status":"todo","archived":false,"shared":false,\
            "fullAccess":true,"version":0,"tags":[],"checklistItems":[{"id":"\(UUID())",\
            "taskId":"\(UUID())","text":"Step","checked":false,"displayOrder":0,"version":0,\
            "createdAt":"2024-08-22T10:00:00Z","updatedAt":"2024-08-22T10:00:00Z"}],\
            "createdAt":"2024-08-22T10:00:00Z","updatedAt":"2024-08-22T10:00:00Z"}
            """
        )
        let idea = IdeaDTO(
            id: UUID(), folderId: folder.id, title: "Idea", body: "", status: "active",
            displayOrder: 0, archived: false, allowAuthorNoteEdits: false, shared: false,
            fullAccess: true, creatorUserId: nil, creatorEmail: nil, creatorName: nil,
            version: 0, createdAt: date, updatedAt: date
        )
        let ideaNote = IdeaNoteDTO(
            id: UUID(), ideaId: idea.id, eventType: "note", body: "Body", metadata: [:],
            authorUserId: nil, authorEmail: nil, authorName: nil, version: 0,
            createdAt: date, updatedAt: date
        )
        let note = NoteDTO(
            id: UUID(), folderId: folder.id, title: "Note", body: "", displayOrder: 0,
            archived: false, shared: false, fullAccess: true, authorUserId: nil,
            authorEmail: nil, authorName: nil, version: 0, createdAt: date, updatedAt: date
        )
        let tag = TaskTagDTO(id: UUID(), name: "Tag", color: "#112233")
        let link = EntityLinkDTO(
            id: UUID(),
            source: EntityReferenceDTO(
                type: .goal, id: goal.id, title: goal.name, subtitle: nil, status: nil,
                path: nil, archived: false, accessible: true, redacted: false
            ),
            target: EntityReferenceDTO(
                type: .task, id: task.id, title: task.title, subtitle: nil, status: nil,
                path: nil, archived: false, accessible: true, redacted: false
            ),
            relationType: .related, createdByUserId: nil, createdByName: nil,
            createdAt: date, updatedAt: date, version: 0
        )
        let focusSettings = FocusNotificationSettingsDTO(
            intervalMinutes: 60, quietHoursStart: nil, quietHoursEnd: nil, version: 1
        )
        let settings = UserSettingsDTO(
            language: .ru,
            greenPriorityDecayPolicy: PriorityDecayPolicyDTO(
                taskType: "green", enabled: false, thresholdPreset: "day", decayAmount: 1
            ),
            redPriorityDecayPolicy: nil,
            notificationsEnabled: true,
            version: 2
        )
        let sender = try RemoteTestSender(stubs: [
            .init(folder), .init(goal), .init(task), .init(idea), .init(ideaNote),
            .init(note), .init(tag), .init(link), .init(focusSettings), .init(settings)
        ])
        let remote = APIPlanningRemote(sender: sender, idResolver: RemoteTestIDResolver())
        let mutations: [(PlanningEntityKind, Data)] = [
            (.folder, try WireJSON.encoder().encode(folder)),
            (.goal, try WireJSON.encoder().encode(goal)),
            (.task, try WireJSON.encoder().encode(task)),
            (.idea, try WireJSON.encoder().encode(idea)),
            (.ideaNote, try WireJSON.encoder().encode(ideaNote)),
            (.note, try WireJSON.encoder().encode(note)),
            (.tag, try WireJSON.encoder().encode(tag)),
            (.entityLink, try WireJSON.encoder().encode(link)),
            (.focus, try WireJSON.encoder().encode(
                FocusPendingMutationPayload(
                    action: .updateNotificationSettings, taskID: nil, taskIDs: nil,
                    sourcePeriodID: nil, periodVersion: nil, idempotencyKey: nil,
                    notificationSettings: FocusNotificationSettingsRequestDTO(
                        intervalMinutes: 60, quietHoursStart: nil, quietHoursEnd: nil, version: 0
                    )
                )
            )),
            (.settings, try WireJSON.encoder().encode(settings))
        ]
        for (kind, payload) in mutations {
            _ = try await remote.push(mutation(kind, operation: kind == .settings ? .update : .create, payload: payload))
        }

        let requests = await sender.requests()
        XCTAssertEqual(
            requests.map(\.path),
            [
                "/rocket-api/folders", "/rocket-api/folders/\(folder.id.wire)/goals",
                "/rocket-api/goals/\(goal.id.wire)/tasks", "/rocket-api/folders/\(folder.id.wire)/ideas",
                "/rocket-api/ideas/\(idea.id.wire)/notes", "/rocket-api/folders/\(folder.id.wire)/notes",
                "/rocket-api/tags", "/rocket-api/entity-links",
                "/rocket-api/focus/notification-settings", "/rocket-api/me/settings"
            ]
        )
        let taskBody = try XCTUnwrap(requests[2].body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: taskBody) as? [String: Any])
        XCTAssertEqual(object["priority"] as? Int, TaskPriorityCompatibility.defaultShadow)
        XCTAssertEqual((object["checklistItems"] as? [[String: Any]])?.count, 1)
    }

    func testConflictFetchIncludesCurrentServerVersionAndPayload() async throws {
        let date = Date(timeIntervalSince1970: 1_724_323_200)
        let folder = FolderDTO(
            id: UUID(), parentFolderId: nil, name: "Server", description: "",
            displayOrder: 0, archived: false, shared: false, fullAccess: true,
            version: 9, createdAt: date, updatedAt: date
        )
        let conflict = APIError(
            statusCode: 409, code: "version_conflict", message: "Conflict",
            details: [], traceID: nil, requestID: UUID()
        )
        let sender = try RemoteTestSender(stubs: [.init(error: conflict), .init(folder)])
        let remote = APIPlanningRemote(sender: sender, idResolver: RemoteTestIDResolver())

        do {
            _ = try await remote.push(
                mutation(.folder, operation: .update, payload: WireJSON.encoder().encode(folder), baseVersion: 8)
            )
            XCTFail("Expected a conflict")
        } catch let failure as SyncRemoteFailure {
            guard case let .conflict(code, version, payload, serverDeleted) = failure else {
                return XCTFail("Unexpected failure: \(failure)")
            }
            XCTAssertEqual(code, "version_conflict")
            XCTAssertEqual(version, 9)
            XCTAssertFalse(serverDeleted)
            XCTAssertEqual(try WireJSON.decoder().decode(FolderDTO.self, from: XCTUnwrap(payload)), folder)
        }
    }

    func testOptionalIdeasFailureReturnsRequiredSnapshotWithWarning() async throws {
        let folder = folderDTO()
        let failure = apiError(code: "ideas_unavailable")
        let sender = try RemoteTestSender(stubs: [
            .init(FolderListResponseDTO(items: [folder])),
            .init(GoalListResponseDTO(items: [])),
            .init(error: failure),
            .init(NoteListResponseDTO(items: []))
        ])
        let remote = APIPlanningRemote(sender: sender, idResolver: RemoteTestIDResolver())

        let snapshot = try await remote.pull()
        let latestWarnings = await remote.latestPullWarnings()

        XCTAssertEqual(snapshot.folders, [folder])
        XCTAssertEqual(snapshot.ideas, [])
        XCTAssertFalse(snapshot.loadedCollections.contains(.ideas))
        XCTAssertEqual(snapshot.partialWarnings.map(\.code), ["ideas_unavailable"])
        XCTAssertEqual(latestWarnings, snapshot.partialWarnings)
    }

    func testOptionalNotesFailureDoesNotAbortRequiredPull() async throws {
        let folder = folderDTO()
        let sender = try RemoteTestSender(stubs: [
            .init(FolderListResponseDTO(items: [folder])),
            .init(GoalListResponseDTO(items: [])),
            .init(IdeaListResponseDTO(items: [])),
            .init(error: apiError(code: "notes_unavailable"))
        ])
        let remote = APIPlanningRemote(sender: sender, idResolver: RemoteTestIDResolver())

        let snapshot = try await remote.pull()

        XCTAssertEqual(snapshot.folders, [folder])
        XCTAssertEqual(snapshot.notes, [])
        XCTAssertFalse(snapshot.loadedCollections.contains(.notes))
        XCTAssertEqual(snapshot.partialWarnings.map(\.resource), ["notes:\(folder.id.wire)"])
    }

    func testRequiredGoalsFailureAbortsPull() async throws {
        let folder = folderDTO()
        let sender = try RemoteTestSender(stubs: [
            .init(FolderListResponseDTO(items: [folder])),
            .init(error: apiError(code: "goals_unavailable"))
        ])
        let remote = APIPlanningRemote(sender: sender, idResolver: RemoteTestIDResolver())

        do {
            _ = try await remote.pull()
            XCTFail("Expected required pull failure")
        } catch let failure as SyncRemoteFailure {
            XCTAssertEqual(failure, .transient(code: "goals_unavailable"))
        }
    }

    func testRequiredTasksFailureAbortsBeforeOptionalResources() async throws {
        let folder = folderDTO()
        let goal = GoalDTO(
            id: UUID(), folderId: folder.id, name: "Goal", description: "", status: .todo,
            archived: false, shared: false, fullAccess: true, version: 0,
            createdAt: folder.createdAt, updatedAt: folder.updatedAt
        )
        let sender = try RemoteTestSender(stubs: [
            .init(FolderListResponseDTO(items: [folder])),
            .init(GoalListResponseDTO(items: [goal])),
            .init(error: apiError(code: "tasks_unavailable"))
        ])
        let remote = APIPlanningRemote(sender: sender, idResolver: RemoteTestIDResolver())

        do {
            _ = try await remote.pull()
            XCTFail("Expected required pull failure")
        } catch let failure as SyncRemoteFailure {
            XCTAssertEqual(failure, .transient(code: "tasks_unavailable"))
        }
    }

    func testTagUpdateAndDeleteReturnTypedPermanentFailures() async throws {
        let tag = TaskTagDTO(id: UUID(), name: "Tag", color: nil)
        let remote = APIPlanningRemote(
            sender: RemoteTestSender(stubs: []),
            idResolver: RemoteTestIDResolver()
        )

        for (operation, expectedCode) in [
            (MutationOperation.update, "tag_update_not_supported"),
            (.delete, "tag_delete_not_supported")
        ] {
            do {
                _ = try await remote.push(
                    mutation(.tag, operation: operation, payload: WireJSON.encoder().encode(tag))
                )
                XCTFail("Expected typed permanent failure")
            } catch let failure as SyncRemoteFailure {
                XCTAssertEqual(failure, .permanent(code: expectedCode, serverPayloadJSON: nil))
            }
        }
    }

    func testTaskTagAssignmentUsesRemoteTagIDs() async throws {
        let localGoalID = UUID()
        let remoteGoalID = UUID()
        let localTagID = UUID()
        let remoteTagID = UUID()
        let task: TaskDTO = try fixture(
            """
            {"id":"\(UUID())","goalId":"\(localGoalID)","title":"Task","description":"",\
            "type":"green","effort":1,"status":"todo","archived":false,"shared":false,\
            "fullAccess":true,"version":0,"tags":[{"id":"\(localTagID)","name":"Tag"}],\
            "checklistItems":[],"createdAt":"2024-08-22T10:00:00Z",\
            "updatedAt":"2024-08-22T10:00:00Z"}
            """
        )
        let sender = try RemoteTestSender(stubs: [.init(task)])
        let remote = APIPlanningRemote(
            sender: sender,
            idResolver: RemoteTestIDResolver(values: [localGoalID: remoteGoalID, localTagID: remoteTagID])
        )

        _ = try await remote.push(
            mutation(.task, operation: .create, payload: WireJSON.encoder().encode(task))
        )

        let requests = await sender.requests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(request.path, "/rocket-api/goals/\(remoteGoalID.wire)/tasks")
        XCTAssertEqual(
            try apiRemoteDecodedUUIDSet(object["tagIds"]),
            Set([remoteTagID])
        )
    }

    func testChecklistUpdateIsNestedInSingleTaskRequest() async throws {
        let localTaskID = UUID()
        let remoteTaskID = UUID()
        let checklistID = UUID()
        let task: TaskDTO = try fixture(
            """
            {"id":"\(localTaskID)","goalId":"\(UUID())","title":"Task","description":"",\
            "type":"green","effort":1,"status":"todo","archived":false,"shared":false,\
            "fullAccess":true,"version":3,"tags":[],"checklistItems":[{"id":"\(checklistID)",\
            "taskId":"\(localTaskID)","text":"Nested","checked":true,"displayOrder":0,\
            "version":0,"createdAt":"2024-08-22T10:00:00Z","updatedAt":"2024-08-22T10:00:00Z"}],\
            "createdAt":"2024-08-22T10:00:00Z","updatedAt":"2024-08-22T10:00:00Z"}
            """
        )
        let sender = try RemoteTestSender(stubs: [.init(task)])
        let remote = APIPlanningRemote(
            sender: sender,
            idResolver: RemoteTestIDResolver(values: [localTaskID: remoteTaskID])
        )

        _ = try await remote.push(
            PendingMutation(
                id: UUID(), entityType: .task, entityID: localTaskID, operation: .update,
                payloadJSON: WireJSON.encoder().encode(task), baseVersion: 3, attemptCount: 0,
                nextRetryAt: nil, lastErrorCode: nil, state: .queued, dependencies: [],
                createdAt: Date(), updatedAt: Date()
            )
        )

        let requests = await sender.requests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(request.path, "/rocket-api/tasks/\(remoteTaskID.wire)")
        XCTAssertEqual((object["checklistItems"] as? [[String: Any]])?.first?["text"] as? String, "Nested")
    }

    func testMoveMutationsUseDedicatedBackendRoutesAndRemoteParentIDs() async throws {
        let now = Date(timeIntervalSince1970: 1_724_323_200)
        let localParent = UUID(), remoteFolder = UUID()
        let localGoalParent = UUID(), remoteGoalParent = UUID()
        let entities = (folder: UUID(), goal: UUID(), task: UUID(), idea: UUID(), note: UUID())
        let remoteEntities = (folder: UUID(), goal: UUID(), task: UUID(), idea: UUID(), note: UUID())
        let folderResponse = FolderDTO(
            id: remoteEntities.folder, parentFolderId: remoteFolder, name: "F", description: "",
            displayOrder: 0, archived: false, shared: false, fullAccess: true,
            version: 8, createdAt: now, updatedAt: now
        )
        let goalResponse = GoalDTO(
            id: remoteEntities.goal, folderId: remoteFolder, name: "G", description: "",
            status: .todo, archived: false, shared: false, fullAccess: true,
            version: 8, createdAt: now, updatedAt: now
        )
        let taskResponse: TaskDTO = try fixture(
            """
            {"id":"\(remoteEntities.task)","goalId":"\(remoteGoalParent)","title":"T",\
            "description":"","type":"green","effort":1,"status":"todo","archived":false,\
            "shared":false,"fullAccess":true,"version":8,"tags":[],"checklistItems":[],\
            "createdAt":"2024-08-22T10:00:00Z","updatedAt":"2024-08-22T10:00:00Z"}
            """
        )
        let ideaResponse = IdeaDTO(
            id: remoteEntities.idea, folderId: remoteFolder, title: "I", body: "", status: "ACTIVE",
            displayOrder: 0, archived: false, allowAuthorNoteEdits: false, shared: false,
            fullAccess: true, creatorUserId: nil, creatorEmail: nil, creatorName: nil,
            version: 8, createdAt: now, updatedAt: now
        )
        let noteResponse = NoteDTO(
            id: remoteEntities.note, folderId: remoteFolder, title: "N", body: "", displayOrder: 0,
            archived: false, shared: false, fullAccess: true, authorUserId: nil,
            authorEmail: nil, authorName: nil, version: 8, createdAt: now, updatedAt: now
        )
        let sender = try RemoteTestSender(stubs: [
            .init(folderResponse), .init(goalResponse), .init(taskResponse),
            .init(ideaResponse), .init(noteResponse)
        ])
        let remote = APIPlanningRemote(
            sender: sender,
            idResolver: RemoteTestIDResolver(values: [
                localParent: remoteFolder,
                localGoalParent: remoteGoalParent,
                entities.folder: remoteEntities.folder,
                entities.goal: remoteEntities.goal,
                entities.task: remoteEntities.task,
                entities.idea: remoteEntities.idea,
                entities.note: remoteEntities.note
            ])
        )
        let folderMove = MoveMutationPayload(targetParentID: localParent, version: 7)
        let requiredMove = MoveMutationPayload(targetParentID: localParent, version: 7)
        let taskMove = MoveMutationPayload(targetParentID: localGoalParent, version: 7)
        for (kind, entityID, payload) in [
            (PlanningEntityKind.folder, entities.folder, folderMove),
            (.goal, entities.goal, requiredMove),
            (.task, entities.task, taskMove),
            (.idea, entities.idea, requiredMove),
            (.note, entities.note, requiredMove)
        ] {
            _ = try await remote.push(
                mutation(
                    kind,
                    operation: .move,
                    payload: WireJSON.encoder().encode(payload),
                    baseVersion: 7,
                    entityID: entityID
                )
            )
        }

        let requests = await sender.requests()
        XCTAssertEqual(requests.map(\.method), Array(repeating: "POST", count: 5))
        XCTAssertEqual(requests.map(\.path), [
            "/rocket-api/folders/\(remoteEntities.folder.wire)/move",
            "/rocket-api/goals/\(remoteEntities.goal.wire)/move",
            "/rocket-api/tasks/\(remoteEntities.task.wire)/move-to-goal",
            "/rocket-api/ideas/\(remoteEntities.idea.wire)/move",
            "/rocket-api/notes/\(remoteEntities.note.wire)/move"
        ])
        let bodies = try requests.map { try XCTUnwrap($0.body) }
        let objects = try bodies.map { try XCTUnwrap(JSONSerialization.jsonObject(with: $0) as? [String: Any]) }
        XCTAssertEqual(try apiRemoteDecodedUUID(objects[0]["targetFolderId"]), remoteFolder)
        XCTAssertEqual(try apiRemoteDecodedUUID(objects[1]["targetFolderId"]), remoteFolder)
        XCTAssertEqual(try apiRemoteDecodedUUID(objects[2]["targetGoalId"]), remoteGoalParent)
        XCTAssertEqual(try apiRemoteDecodedUUID(objects[3]["targetFolderId"]), remoteFolder)
        XCTAssertEqual(try apiRemoteDecodedUUID(objects[4]["targetFolderId"]), remoteFolder)
        XCTAssertTrue(objects.allSatisfy { $0["version"] as? Int == 7 })
    }

    func testConflictFetch404MarksServerDeletedInsteadOfUnavailable() async throws {
        let folder = folderDTO()
        let conflict = APIError(
            statusCode: 409, code: "version_conflict", message: "Conflict",
            details: [], traceID: nil, requestID: UUID()
        )
        let missing = APIError(
            statusCode: 404, code: "not_found", message: "Missing",
            details: [], traceID: nil, requestID: UUID()
        )
        let sender = RemoteTestSender(stubs: [.init(error: conflict), .init(error: missing)])
        let remote = APIPlanningRemote(sender: sender, idResolver: RemoteTestIDResolver())

        do {
            _ = try await remote.push(
                mutation(.folder, operation: .update, payload: WireJSON.encoder().encode(folder), entityID: folder.id)
            )
            XCTFail("Expected conflict")
        } catch let failure as SyncRemoteFailure {
            guard case let .conflict(_, version, payload, serverDeleted) = failure else {
                return XCTFail("Unexpected failure: \(failure)")
            }
            XCTAssertNil(version)
            XCTAssertNil(payload)
            XCTAssertTrue(serverDeleted)
        }
    }

    func testConflictFetchFailureRemainsUnavailableAndNeverMarksDeleted() async throws {
        let folder = folderDTO()
        let conflict = APIError(
            statusCode: 409, code: "version_conflict", message: "Conflict",
            details: [], traceID: nil, requestID: UUID()
        )
        let sender = RemoteTestSender(stubs: [
            .init(error: conflict),
            .init(error: apiError(code: "lookup_unavailable"))
        ])
        let remote = APIPlanningRemote(sender: sender, idResolver: RemoteTestIDResolver())

        do {
            _ = try await remote.push(
                mutation(.folder, operation: .update, payload: WireJSON.encoder().encode(folder), entityID: folder.id)
            )
            XCTFail("Expected conflict")
        } catch let failure as SyncRemoteFailure {
            guard case let .conflict(code, _, payload, serverDeleted) = failure else {
                return XCTFail("Unexpected failure: \(failure)")
            }
            XCTAssertEqual(code, "version_conflict:server_payload_unavailable")
            XCTAssertNil(payload)
            XCTAssertFalse(serverDeleted)
        }
    }

    func testDirectDelete404IsAcknowledgedAsIdempotentSuccess() async throws {
        let localID = UUID()
        let remoteID = UUID()
        let missing = APIError(
            statusCode: 404, code: "not_found", message: "Missing",
            details: [], traceID: nil, requestID: UUID()
        )
        let sender = RemoteTestSender(stubs: [.init(error: missing)])
        let remote = APIPlanningRemote(
            sender: sender,
            idResolver: RemoteTestIDResolver(values: [localID: remoteID])
        )
        let payload = DeleteMutationPayload(remoteID: remoteID, version: 7)

        let ack = try await remote.push(
            mutation(
                .folder,
                operation: .delete,
                payload: WireJSON.encoder().encode(payload),
                baseVersion: 7,
                entityID: localID
            )
        )

        XCTAssertEqual(ack.remoteID, remoteID)
        XCTAssertEqual(ack.version, 7)
        XCTAssertNil(ack.serverPayloadJSON)
        let requests = await sender.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.method, "DELETE")
    }

    func testDirectUpdate404CreatesResolvableServerDeletedConflict() async throws {
        let folder = folderDTO()
        let missing = APIError(
            statusCode: 404, code: "not_found", message: "Missing",
            details: [], traceID: nil, requestID: UUID()
        )
        let sender = RemoteTestSender(stubs: [.init(error: missing)])
        let remote = APIPlanningRemote(sender: sender, idResolver: RemoteTestIDResolver())

        do {
            _ = try await remote.push(
                mutation(
                    .folder,
                    operation: .update,
                    payload: WireJSON.encoder().encode(folder),
                    baseVersion: folder.version,
                    entityID: folder.id
                )
            )
            XCTFail("Expected server-deleted conflict")
        } catch let failure as SyncRemoteFailure {
            guard case let .conflict(code, version, payload, serverDeleted) = failure else {
                return XCTFail("Unexpected failure: \(failure)")
            }
            XCTAssertEqual(code, "not_found")
            XCTAssertNil(version)
            XCTAssertNil(payload)
            XCTAssertTrue(serverDeleted)
        }

        let requests = await sender.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testRedactedEntityReferenceDecodesAndReencodesNullIdentity() throws {
        let linkID = UUID()
        let sourceID = UUID()
        let payload = Data(
            """
            {"id":"\(linkID)","source":{"type":"goal","id":"\(sourceID)","title":"Goal",\
            "accessible":true,"redacted":false},"target":{"type":null,"id":null,"title":null,\
            "subtitle":null,"status":null,"path":null,"archived":null,"accessible":false,"redacted":true},\
            "relationType":"related","createdByUserId":null,"createdByName":null,\
            "createdAt":"2024-08-22T10:00:00Z","updatedAt":"2024-08-22T10:00:00Z","version":1}
            """.utf8
        )

        let link = try WireJSON.decoder().decode(EntityLinkDTO.self, from: payload)
        XCTAssertNotNil(link.source.identity)
        XCTAssertNil(link.target.identity)
        XCTAssertTrue(link.target.redacted)
        XCTAssertFalse(link.target.accessible)

        let encoded = try WireJSON.encoder().encode(link)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let target = try XCTUnwrap(object["target"] as? [String: Any])
        XCTAssertTrue(target["type"] is NSNull)
        XCTAssertTrue(target["id"] is NSNull)
        XCTAssertTrue(target["title"] is NSNull)
    }

    private func mutation(
        _ kind: PlanningEntityKind,
        operation: MutationOperation,
        payload: Data,
        baseVersion: Int64? = nil,
        entityID: UUID = UUID()
    ) -> PendingMutation {
        PendingMutation(
            id: UUID(), entityType: kind, entityID: entityID, operation: operation,
            payloadJSON: payload, baseVersion: baseVersion, attemptCount: 0,
            nextRetryAt: nil, lastErrorCode: nil, state: .queued, dependencies: [],
            createdAt: Date(), updatedAt: Date()
        )
    }

    private func fixture<Value: Decodable>(_ json: String) throws -> Value {
        try WireJSON.decoder().decode(Value.self, from: Data(json.utf8))
    }

    private func apiRemoteDecodedUUID(
        _ value: Any?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> UUID {
        let string = try XCTUnwrap(value as? String, "Expected UUID string", file: file, line: line)
        return try XCTUnwrap(UUID(uuidString: string), "Invalid UUID string", file: file, line: line)
    }

    private func apiRemoteDecodedUUIDSet(
        _ value: Any?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Set<UUID> {
        let strings = try XCTUnwrap(value as? [String], "Expected UUID string array", file: file, line: line)
        return Set(try strings.map { string in
            try XCTUnwrap(UUID(uuidString: string), "Invalid UUID string", file: file, line: line)
        })
    }

    private func folderDTO() -> FolderDTO {
        let date = Date(timeIntervalSince1970: 1_724_323_200)
        return FolderDTO(
            id: UUID(), parentFolderId: nil, name: "Folder", description: "",
            displayOrder: 0, archived: false, shared: false, fullAccess: true,
            version: 1, createdAt: date, updatedAt: date
        )
    }

    private func apiError(code: String) -> APIError {
        APIError(
            statusCode: 503,
            code: code,
            message: "Unavailable",
            details: [],
            traceID: nil,
            requestID: UUID()
        )
    }
}

private extension UUID {
    var wire: String { uuidString.lowercased() }
}
