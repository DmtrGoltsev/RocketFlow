import Foundation
import XCTest
@testable import RocketFlow

private actor PlanningActionRecorder: AuthenticatedRequestSending {
    struct Captured: Sendable {
        let method: String
        let path: String
        let query: String?
        let headers: [String: String]
        let body: Data?
    }

    private var responses: [Data]
    private var captured: [Captured] = []

    init(responses: [Data]) {
        self.responses = responses
    }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let request = try endpoint.makeRequest(
            baseURL: URL(string: "https://example.test/rocket-api")!,
            bearerToken: "secret-test-token"
        ).urlRequest
        captured.append(
            Captured(
                method: request.httpMethod ?? "",
                path: request.url?.path ?? "",
                query: request.url?.query,
                headers: request.allHTTPHeaderFields ?? [:],
                body: request.httpBody
            )
        )
        return try WireJSON.decoder().decode(Response.self, from: responses.removeFirst())
    }

    func requests() -> [Captured] { captured }
}

private struct PlanningActionFailureSender: AuthenticatedRequestSending {
    let error: APIError

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        throw error
    }
}

final class PlanningActionServiceTests: XCTestCase {
    func testFolderGoalIdeaAndNoteRoutesMatchControllers() async throws {
        let folderID = UUID(), childID = UUID(), goalID = UUID(), ideaID = UUID(), noteID = UUID()
        let targetFolderID = UUID()
        let folder = folderDTO(id: folderID)
        let goal = goalDTO(id: goalID, folderID: folderID)
        let idea = ideaDTO(id: ideaID, folderID: folderID)
        let note = noteDTO(id: noteID, folderID: folderID)
        let empty = try encoded(EmptyResponse())
        let sender = PlanningActionRecorder(responses: [
            try encoded(folder), try encoded(folder), try encoded(folder), empty,
            try encoded(folder), try encoded(folder),
            try encoded(goal), try encoded(goal), empty, try encoded(goal), try encoded(goal),
            try encoded(idea), try encoded(idea), empty, try encoded(idea), try encoded(idea),
            try encoded(note), try encoded(note), empty, try encoded(note), try encoded(note)
        ])
        let service = PlanningActionService(sender: sender)

        let createdFolder = try await service.createFolder(
            CreateFolderRequestDTO(name: "Folder", description: "Body", parentFolderId: nil)
        )
        _ = try await service.createChildFolder(
            parentFolderID: childID,
            request: CreateFolderRequestDTO(name: "Child", description: nil, parentFolderId: childID)
        )
        _ = try await service.updateFolder(
            id: folderID,
            request: UpdateFolderRequestDTO(
                name: "Folder", description: "Body", displayOrder: 2, archived: false, version: 4
            )
        )
        try await service.deleteFolder(id: folderID)
        _ = try await service.moveFolder(
            id: folderID,
            request: MoveFolderRequestDTO(targetFolderId: targetFolderID, version: 4)
        )
        _ = try await service.cloneFolder(
            id: folderID,
            request: CloneFolderRequestDTO(
                targetFolderId: targetFolderID, name: "Copy", includeChildren: true
            )
        )

        let createdGoal = try await service.createGoal(
            folderID: folderID,
            request: CreateGoalRequestDTO(name: "Goal", description: nil, status: .todo)
        )
        _ = try await service.updateGoal(
            id: goalID,
            request: UpdateGoalRequestDTO(
                name: "Goal", description: nil, status: .inProgress, archived: false, version: 4
            )
        )
        try await service.deleteGoal(id: goalID)
        _ = try await service.moveGoal(
            id: goalID,
            request: MoveGoalRequestDTO(targetFolderId: targetFolderID, version: 4)
        )
        _ = try await service.cloneGoal(
            id: goalID,
            request: CloneGoalRequestDTO(targetFolderId: targetFolderID, name: "Copy")
        )

        let createdIdea = try await service.createIdea(
            folderID: folderID,
            request: CreateIdeaRequestDTO(
                title: "Idea", body: "Body", status: "active", allowAuthorNoteEdits: true
            )
        )
        _ = try await service.updateIdea(
            id: ideaID,
            request: UpdateIdeaRequestDTO(
                title: "Idea", body: "Body", status: "active", displayOrder: 1,
                archived: false, allowAuthorNoteEdits: true, version: 4
            )
        )
        try await service.deleteIdea(id: ideaID)
        _ = try await service.moveIdea(
            id: ideaID,
            request: MoveIdeaRequestDTO(targetFolderId: targetFolderID, version: 4)
        )
        _ = try await service.cloneIdea(
            id: ideaID,
            request: CloneIdeaRequestDTO(targetFolderId: targetFolderID, title: "Copy")
        )

        let createdNote = try await service.createNote(
            folderID: folderID,
            request: CreateNoteRequestDTO(title: "Note", body: "Body")
        )
        _ = try await service.updateNote(
            id: noteID,
            request: UpdateNoteRequestDTO(
                title: "Note", body: "Body", displayOrder: 1, archived: false, version: 4
            )
        )
        try await service.deleteNote(id: noteID)
        _ = try await service.moveNote(
            id: noteID,
            request: MoveNoteRequestDTO(targetFolderId: targetFolderID, version: 4)
        )
        _ = try await service.cloneNote(
            id: noteID,
            request: CloneNoteRequestDTO(targetFolderId: targetFolderID, title: "Copy")
        )

        let requests = await sender.requests()
        XCTAssertNil(createdFolder.description)
        XCTAssertNil(createdGoal.description)
        XCTAssertNil(createdIdea.body)
        XCTAssertNil(createdNote.body)
        XCTAssertEqual(requests.map(\.method), [
            "POST", "POST", "PATCH", "DELETE", "POST", "POST",
            "POST", "PATCH", "DELETE", "POST", "POST",
            "POST", "PATCH", "DELETE", "POST", "POST",
            "POST", "PATCH", "DELETE", "POST", "POST"
        ])
        XCTAssertEqual(requests.map(\.path), [
            "/rocket-api/folders",
            "/rocket-api/folders/\(childID.wire)/folders",
            "/rocket-api/folders/\(folderID.wire)",
            "/rocket-api/folders/\(folderID.wire)",
            "/rocket-api/folders/\(folderID.wire)/move",
            "/rocket-api/folders/\(folderID.wire)/clone",
            "/rocket-api/folders/\(folderID.wire)/goals",
            "/rocket-api/goals/\(goalID.wire)",
            "/rocket-api/goals/\(goalID.wire)",
            "/rocket-api/goals/\(goalID.wire)/move",
            "/rocket-api/goals/\(goalID.wire)/clone",
            "/rocket-api/folders/\(folderID.wire)/ideas",
            "/rocket-api/ideas/\(ideaID.wire)",
            "/rocket-api/ideas/\(ideaID.wire)",
            "/rocket-api/ideas/\(ideaID.wire)/move",
            "/rocket-api/ideas/\(ideaID.wire)/clone",
            "/rocket-api/folders/\(folderID.wire)/notes",
            "/rocket-api/notes/\(noteID.wire)",
            "/rocket-api/notes/\(noteID.wire)",
            "/rocket-api/notes/\(noteID.wire)/move",
            "/rocket-api/notes/\(noteID.wire)/clone"
        ])
        let first = try XCTUnwrap(requests.first)
        XCTAssertEqual(header("Authorization", in: first), "Bearer secret-test-token")
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(header("X-Request-ID", in: first))))
        XCTAssertEqual(header("Content-Type", in: first), "application/json; charset=utf-8")
        XCTAssertNil(header("Idempotency-Key", in: first))
        XCTAssertEqual(try body(requests[4])["targetFolderId"] as? String, targetFolderID.wire)
        XCTAssertEqual(try body(requests[4])["version"] as? Int, 4)
        XCTAssertEqual(try body(requests[5])["includeChildren"] as? Bool, true)
        XCTAssertEqual(try body(requests[9])["targetFolderId"] as? String, targetFolderID.wire)
        XCTAssertEqual(try body(requests[10])["name"] as? String, "Copy")
        XCTAssertEqual(try body(requests[14])["targetFolderId"] as? String, targetFolderID.wire)
        XCTAssertEqual(try body(requests[15])["title"] as? String, "Copy")
        XCTAssertEqual(try body(requests[19])["targetFolderId"] as? String, targetFolderID.wire)
        XCTAssertEqual(try body(requests[20])["title"] as? String, "Copy")
    }

    func testTaskRoutesPreservePriorityShadowAndUseControllerTagSurface() async throws {
        let taskID = UUID(), goalID = UUID(), targetGoalID = UUID()
        let existingTagID = UUID(), addedTagID = UUID(), checklistID = UUID()
        let taskData = taskFixture(
            id: taskID,
            goalID: goalID,
            priority: 9,
            tags: [(existingTagID, "Existing")]
        )
        let task = try WireJSON.decoder().decode(ActionTaskDTO.self, from: taskData)
        let now = Date(timeIntervalSince1970: 1_724_323_200)
        let sender = PlanningActionRecorder(responses: [
            taskData,
            taskData,
            try encoded(EmptyResponse()),
            Data("{\"id\":\"\(taskID)\",\"plannedTime\":\"2024-08-22T10:00:00Z\",\"priority\":9,\"updatedAt\":\"2024-08-22T10:00:00Z\"}".utf8),
            taskData,
            taskData,
            Data("{\"task\":{\"id\":\"\(taskID)\",\"plannedTime\":\"2024-08-22T11:00:00Z\",\"priority\":9,\"updatedAt\":\"2024-08-22T11:00:00Z\"},\"rescheduleEvent\":{\"id\":\"\(UUID())\",\"previousPlannedTime\":\"2024-08-22T10:00:00Z\",\"newPlannedTime\":\"2024-08-22T11:00:00Z\",\"createdAt\":\"2024-08-22T10:00:00Z\"},\"priorityDecayApplied\":false}".utf8),
            Data("{\"taskId\":\"\(taskID)\",\"recurrence\":{\"mode\":\"weekly\",\"interval\":1,\"daysOfWeek\":[\"MONDAY\"],\"startAt\":\"2024-08-22T10:00:00Z\",\"active\":true}}".utf8),
            Data("{\"taskId\":\"\(taskID)\",\"items\":[]}".utf8),
            Data("{\"items\":[{\"id\":\"\(existingTagID)\",\"name\":\"Existing\",\"color\":\"#123456\"}]}".utf8),
            Data("{\"id\":\"\(addedTagID)\",\"name\":\"Added\",\"color\":null}".utf8),
            taskData,
            taskData
        ])
        let service = PlanningActionService(sender: sender)

        let createdTask = try await service.createTask(
            goalID: goalID,
            request: CreateTaskRequestDTO(
                title: "Task", description: "Body", type: .green, effort: 3, status: .todo,
                plannedTime: now, dueTime: nil, checklistItems: nil, tagIds: [existingTagID]
            )
        )
        _ = try await service.updateTask(
            id: taskID,
            request: ActionUpdateTaskRequestDTO(
                preservingPriorityFrom: task,
                title: "Changed", description: task.description, type: task.type,
                effort: task.effort, status: task.status, plannedTime: task.plannedTime,
                dueTime: task.dueTime, archived: task.archived,
                tagIds: task.tags.map(\.id), checklistItems: nil
            )
        )
        try await service.deleteTask(id: taskID)
        let moved = try await service.moveTask(id: taskID, plannedTime: now)
        _ = try await service.moveTask(id: taskID, toGoalID: targetGoalID, version: 7)
        _ = try await service.cloneTask(
            id: taskID,
            request: CloneTaskRequestDTO(targetGoalId: targetGoalID, title: "Copy", includeTags: true)
        )
        let rescheduled = try await service.quickRescheduleTask(id: taskID, choice: .preset(.oneHour))
        _ = try await service.upsertTaskRecurrence(
            id: taskID,
            request: UpsertRecurrenceRequestDTO(
                mode: .weekly, interval: 1, daysOfWeek: [.monday], dayOfMonth: nil,
                startAt: now, endAt: nil, active: true
            )
        )
        _ = try await service.replaceTaskChecklist(
            id: taskID,
            items: [ChecklistItemRequestDTO(
                id: checklistID, text: "Step", checked: true, displayOrder: 0
            )]
        )
        _ = try await service.listTags()
        _ = try await service.createTag(CreateTagRequestDTO(name: "Added", color: nil))
        _ = try await service.assignTag(id: addedTagID, to: task)
        _ = try await service.unassignTag(id: existingTagID, from: task)

        XCTAssertEqual(moved.priorityShadow, 9)
        XCTAssertEqual(rescheduled.task.priorityShadow, 9)
        XCTAssertFalse(rescheduled.priorityDecayAppliedShadow)
        XCTAssertNil(createdTask.description)

        let requests = await sender.requests()
        XCTAssertEqual(requests.map(\.method), [
            "POST", "PATCH", "DELETE", "POST", "POST", "POST", "POST",
            "PUT", "PUT", "GET", "POST", "PATCH", "PATCH"
        ])
        XCTAssertEqual(requests.map(\.path), [
            "/rocket-api/goals/\(goalID.wire)/tasks",
            "/rocket-api/tasks/\(taskID.wire)",
            "/rocket-api/tasks/\(taskID.wire)",
            "/rocket-api/tasks/\(taskID.wire)/move",
            "/rocket-api/tasks/\(taskID.wire)/move-to-goal",
            "/rocket-api/tasks/\(taskID.wire)/clone",
            "/rocket-api/tasks/\(taskID.wire)/reschedule",
            "/rocket-api/tasks/\(taskID.wire)/recurrence",
            "/rocket-api/tasks/\(taskID.wire)/checklist",
            "/rocket-api/tags",
            "/rocket-api/tags",
            "/rocket-api/tasks/\(taskID.wire)",
            "/rocket-api/tasks/\(taskID.wire)"
        ])
        XCTAssertEqual(try body(requests[0])["priority"] as? Int, TaskPriorityCompatibility.defaultShadow)
        XCTAssertNil(try body(requests[0])["idempotencyKey"])
        XCTAssertEqual(try body(requests[1])["priority"] as? Int, 9)
        XCTAssertEqual(try body(requests[4])["targetGoalId"] as? String, targetGoalID.wire)
        XCTAssertEqual(try body(requests[6])["preset"] as? String, "1h")
        XCTAssertNil(try body(requests[6])["minutes"])
        XCTAssertEqual(try body(requests[7])["daysOfWeek"] as? [String], ["MONDAY"])
        XCTAssertEqual((try body(requests[8])["items"] as? [[String: Any]])?.first?["id"] as? String, checklistID.wire)
        XCTAssertEqual(Set(try XCTUnwrap(body(requests[11])["tagIds"] as? [String])), Set([existingTagID.wire, addedTagID.wire]))
        XCTAssertEqual(try body(requests[11])["priority"] as? Int, 9)
        XCTAssertEqual(try body(requests[12])["tagIds"] as? [String], [])
        XCTAssertTrue(requests.allSatisfy { header("Idempotency-Key", in: $0) == nil })
    }

    func testIdeaNoteAndEntityLinkRoutesDecodeRedactedReferences() async throws {
        let ideaID = UUID(), ideaNoteID = UUID(), sourceID = UUID(), targetID = UUID(), linkID = UUID()
        let ideaNoteData = Data(
            "{\"id\":\"\(ideaNoteID)\",\"ideaId\":\"\(ideaID)\",\"eventType\":\"note\",\"body\":null,\"metadata\":{\"kind\":\"text\"},\"authorUserId\":null,\"authorEmail\":null,\"authorName\":null,\"version\":2,\"createdAt\":\"2024-08-22T10:00:00Z\",\"updatedAt\":\"2024-08-22T10:00:00Z\"}".utf8
        )
        let linkData = entityLinkFixture(linkID: linkID, sourceID: sourceID, targetID: targetID)
        let redactedList = Data(
            "{\"items\":[{\"id\":\"\(linkID)\",\"source\":{\"type\":\"task\",\"id\":\"\(sourceID)\",\"title\":\"Visible\",\"accessible\":true,\"redacted\":false},\"target\":{\"type\":null,\"id\":null,\"title\":null,\"subtitle\":null,\"status\":null,\"path\":null,\"archived\":null,\"accessible\":false,\"redacted\":true},\"relationType\":\"related\",\"createdByUserId\":null,\"createdByName\":null,\"createdAt\":\"2024-08-22T10:00:00Z\",\"updatedAt\":\"2024-08-22T10:00:00Z\",\"version\":2}]}".utf8
        )
        let sender = PlanningActionRecorder(responses: [
            Data("{\"items\":[\(String(decoding: ideaNoteData, as: UTF8.self))]}".utf8),
            ideaNoteData,
            ideaNoteData,
            try encoded(EmptyResponse()),
            redactedList,
            linkData,
            linkData,
            try encoded(EmptyResponse())
        ])
        let service = PlanningActionService(sender: sender)

        let ideaNotes = try await service.listIdeaNotes(ideaID: ideaID)
        _ = try await service.createIdeaNote(
            ideaID: ideaID,
            request: CreateIdeaNoteRequestDTO(
                eventType: "note", body: "Body", metadata: ["kind": .string("text")]
            )
        )
        _ = try await service.updateIdeaNote(
            id: ideaNoteID,
            request: UpdateIdeaNoteRequestDTO(
                eventType: "note", body: "Body", metadata: nil, version: 2
            )
        )
        try await service.deleteIdeaNote(id: ideaNoteID)
        let redacted = try await service.listEntityLinks(type: .task, id: sourceID)
        _ = try await service.createEntityLink(
            CreateEntityLinkRequestDTO(
                sourceType: .task, sourceId: sourceID, targetType: .task,
                targetId: targetID, relationType: .dependency
            )
        )
        _ = try await service.updateEntityLink(
            id: linkID,
            request: UpdateEntityLinkRequestDTO(relationType: .related, version: 2)
        )
        try await service.deleteEntityLink(id: linkID)

        XCTAssertEqual(redacted.count, 1)
        XCTAssertNil(ideaNotes.first?.body)
        XCTAssertNotNil(redacted[0].source.identity)
        XCTAssertNil(redacted[0].target.identity)
        XCTAssertNil(redacted[0].target.type)
        XCTAssertNil(redacted[0].target.id)
        XCTAssertNil(redacted[0].target.title)
        XCTAssertTrue(redacted[0].target.redacted)

        let requests = await sender.requests()
        XCTAssertEqual(requests.map(\.method), ["GET", "POST", "PATCH", "DELETE", "GET", "POST", "PATCH", "DELETE"])
        XCTAssertEqual(requests.map(\.path), [
            "/rocket-api/ideas/\(ideaID.wire)/notes",
            "/rocket-api/ideas/\(ideaID.wire)/notes",
            "/rocket-api/idea-notes/\(ideaNoteID.wire)",
            "/rocket-api/idea-notes/\(ideaNoteID.wire)",
            "/rocket-api/entity-links",
            "/rocket-api/entity-links",
            "/rocket-api/entity-links/\(linkID.wire)",
            "/rocket-api/entity-links/\(linkID.wire)"
        ])
        let query = try XCTUnwrap(requests[4].query)
        XCTAssertTrue(query.contains("entityType=task"))
        XCTAssertTrue(query.contains("entityId=\(sourceID.wire)"))
        XCTAssertEqual(try body(requests[5])["relationType"] as? String, "dependency")
    }

    func testQuickRescheduleMinutesUsesOnlySupportedMinutesBody() async throws {
        let taskID = UUID()
        let response = Data(
            "{\"task\":{\"id\":\"\(taskID)\",\"plannedTime\":\"2024-08-22T10:30:00Z\",\"priority\":5,\"updatedAt\":\"2024-08-22T10:30:00Z\"},\"rescheduleEvent\":{\"id\":\"\(UUID())\",\"previousPlannedTime\":\"2024-08-22T10:00:00Z\",\"newPlannedTime\":\"2024-08-22T10:30:00Z\",\"createdAt\":\"2024-08-22T10:00:00Z\"},\"priorityDecayApplied\":false}".utf8
        )
        let sender = PlanningActionRecorder(responses: [response])
        let service = PlanningActionService(sender: sender)

        _ = try await service.quickRescheduleTask(
            id: taskID,
            choice: .minutes(.thirtyMinutes)
        )

        let requests = await sender.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rocket-api/tasks/\(taskID.wire)/reschedule")
        XCTAssertEqual(try body(request)["minutes"] as? Int, 30)
        XCTAssertNil(try body(request)["preset"])
    }

    func testTypedErrorMappingDistinguishesPermissionVersionDependencyAndRetry() async throws {
        let id = UUID()
        let ideaNoteRequest = UpdateIdeaNoteRequestDTO(
            eventType: "note", body: nil, metadata: nil, version: 1
        )

        let permissionService = service(error: apiError(status: 404, code: "not_found", message: "Idea note was not found."))
        do {
            _ = try await permissionService.updateIdeaNote(id: id, request: ideaNoteRequest)
            XCTFail("Expected not found")
        } catch {
            XCTAssertEqual(
                error as? RemoteActionError,
                .notFound(code: "not_found", message: "Idea note was not found.")
            )
        }

        let versionService = service(error: apiError(status: 409, code: "conflict", message: "Task was updated by another request."))
        let task = try WireJSON.decoder().decode(
            ActionTaskDTO.self,
            from: taskFixture(id: id, goalID: UUID(), priority: 8, tags: [])
        )
        do {
            _ = try await versionService.updateTask(
                id: id,
                request: ActionUpdateTaskRequestDTO(task: task, tagIds: nil, checklistItems: nil)
            )
            XCTFail("Expected version conflict")
        } catch {
            XCTAssertEqual(
                error as? RemoteActionError,
                .versionConflict(code: "conflict", message: "Task was updated by another request.")
            )
        }

        let blockedService = service(error: apiError(status: 409, code: "dependency_blocked", message: "Blocked."))
        do {
            _ = try await blockedService.updateTask(
                id: id,
                request: ActionUpdateTaskRequestDTO(task: task, tagIds: nil, checklistItems: nil)
            )
            XCTFail("Expected dependency error")
        } catch {
            XCTAssertEqual(
                error as? RemoteActionError,
                .dependencyBlocked(code: "dependency_blocked", message: "Blocked.")
            )
        }

        let validation = APIError(
            statusCode: 400,
            code: "validation_error",
            message: "Invalid request.",
            details: [APIErrorDetail(field: "title", message: "must not be blank")],
            traceID: nil,
            requestID: UUID()
        )
        do {
            _ = try await service(error: validation).listTags()
            XCTFail("Expected validation error")
        } catch {
            XCTAssertEqual(
                error as? RemoteActionError,
                .validation(message: "Invalid request.", fieldErrors: ["title": "must not be blank"])
            )
        }

        do {
            _ = try await service(
                error: apiError(status: 409, code: "dependency_cycle", message: "Cycle.")
            ).createEntityLink(
                CreateEntityLinkRequestDTO(
                    sourceType: .task,
                    sourceId: UUID(),
                    targetType: .task,
                    targetId: UUID(),
                    relationType: .dependency
                )
            )
            XCTFail("Expected conflict")
        } catch {
            XCTAssertEqual(
                error as? RemoteActionError,
                .conflict(code: "dependency_cycle", message: "Cycle.")
            )
        }

        for (status, expected) in [
            (401, RemoteActionError.unauthorized),
            (403, .forbidden(code: "forbidden", message: "No access.")),
            (503, .retryable(code: "unavailable", message: "Try later."))
        ] {
            let code = status == 403 ? "forbidden" : status == 503 ? "unavailable" : "unauthorized"
            let message = status == 403 ? "No access." : status == 503 ? "Try later." : "Sign in."
            do {
                _ = try await service(error: apiError(status: status, code: code, message: message)).listTags()
                XCTFail("Expected typed error")
            } catch {
                XCTAssertEqual(error as? RemoteActionError, expected)
            }
        }
    }

    private func service(error: APIError) -> PlanningActionService {
        PlanningActionService(sender: PlanningActionFailureSender(error: error))
    }

    private func apiError(status: Int, code: String, message: String) -> APIError {
        APIError(
            statusCode: status,
            code: code,
            message: message,
            details: [],
            traceID: nil,
            requestID: UUID()
        )
    }

    private func body(_ request: PlanningActionRecorder.Captured) throws -> [String: Any] {
        let data = try XCTUnwrap(request.body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func header(_ name: String, in request: PlanningActionRecorder.Captured) -> String? {
        request.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private func encoded<Value: Encodable>(_ value: Value) throws -> Data {
        try WireJSON.encoder().encode(value)
    }

    private func folderDTO(id: UUID) -> ActionFolderDTO {
        let date = Date(timeIntervalSince1970: 1_724_323_200)
        return ActionFolderDTO(
            id: id, parentFolderId: nil, name: "Folder", description: nil, displayOrder: 0,
            archived: false, shared: false, fullAccess: true, version: 4,
            createdAt: date, updatedAt: date
        )
    }

    private func goalDTO(id: UUID, folderID: UUID) -> ActionGoalDTO {
        let date = Date(timeIntervalSince1970: 1_724_323_200)
        return ActionGoalDTO(
            id: id, folderId: folderID, name: "Goal", description: nil, status: .todo,
            archived: false, shared: false, fullAccess: true, version: 4,
            createdAt: date, updatedAt: date
        )
    }

    private func ideaDTO(id: UUID, folderID: UUID) -> ActionIdeaDTO {
        let date = Date(timeIntervalSince1970: 1_724_323_200)
        return ActionIdeaDTO(
            id: id, folderId: folderID, title: "Idea", body: nil, status: "active",
            displayOrder: 0, archived: false, allowAuthorNoteEdits: true, shared: false,
            fullAccess: true, creatorUserId: nil, creatorEmail: nil, creatorName: nil,
            version: 4, createdAt: date, updatedAt: date
        )
    }

    private func noteDTO(id: UUID, folderID: UUID) -> ActionNoteDTO {
        let date = Date(timeIntervalSince1970: 1_724_323_200)
        return ActionNoteDTO(
            id: id, folderId: folderID, title: "Note", body: nil, displayOrder: 0,
            archived: false, shared: false, fullAccess: true, authorUserId: nil,
            authorEmail: nil, authorName: nil, version: 4, createdAt: date, updatedAt: date
        )
    }

    private func taskFixture(
        id: UUID,
        goalID: UUID,
        priority: Int,
        tags: [(UUID, String)]
    ) -> Data {
        let tagJSON = tags.map {
            "{\"id\":\"\($0.0)\",\"name\":\"\($0.1)\",\"color\":null}"
        }.joined(separator: ",")
        return Data(
            "{\"id\":\"\(id)\",\"goalId\":\"\(goalID)\",\"title\":\"Task\",\"description\":null,\"type\":\"green\",\"priority\":\(priority),\"effort\":3,\"status\":\"todo\",\"plannedTime\":\"2024-08-22T10:00:00Z\",\"dueTime\":null,\"archived\":false,\"shared\":false,\"fullAccess\":true,\"creatorUserId\":null,\"creatorEmail\":null,\"creatorName\":null,\"version\":7,\"tags\":[\(tagJSON)],\"checklistItems\":[],\"recurrence\":null,\"createdAt\":\"2024-08-22T10:00:00Z\",\"updatedAt\":\"2024-08-22T10:00:00Z\"}".utf8
        )
    }

    private func entityLinkFixture(linkID: UUID, sourceID: UUID, targetID: UUID) -> Data {
        Data(
            "{\"id\":\"\(linkID)\",\"source\":{\"type\":\"task\",\"id\":\"\(sourceID)\",\"title\":\"Source\",\"accessible\":true,\"redacted\":false},\"target\":{\"type\":\"task\",\"id\":\"\(targetID)\",\"title\":\"Target\",\"accessible\":true,\"redacted\":false},\"relationType\":\"dependency\",\"createdByUserId\":null,\"createdByName\":null,\"createdAt\":\"2024-08-22T10:00:00Z\",\"updatedAt\":\"2024-08-22T10:00:00Z\",\"version\":2}".utf8
        )
    }
}

private extension UUID {
    var wire: String { uuidString.lowercased() }
}
