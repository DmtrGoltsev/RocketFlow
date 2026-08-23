import Foundation
import XCTest
@testable import RocketFlow

final class PlannerDetailsIntegrationRemoteTests: XCTestCase {
    func testRecurrenceChecklistAndTagsRoundTripWhileShadowIsPreserved() async throws {
        let tag = TaskTagDTO(
            id: PlannerDetailsIntegrationFixtures.tagRemoteID,
            name: "Work",
            color: "#00AA44"
        )
        let checklist = ChecklistItemDTO(
            id: PlannerDetailsIntegrationFixtures.checklistRemoteID,
            taskId: PlannerDetailsIntegrationFixtures.taskRemoteID,
            text: "Updated checklist",
            checked: true,
            displayOrder: 0,
            version: 2,
            createdAt: PlannerDetailsIntegrationFixtures.now,
            updatedAt: PlannerDetailsIntegrationFixtures.now
        )
        let response = PlannerDetailsIntegrationFixtures.actionTask(
            title: "Updated task",
            shadow: 9,
            tags: [tag],
            checklist: [checklist]
        )
        let remote = PlannerDetailsRemoteStub(taskResponse: response)
        let (database, repository, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem(
            remote: remote
        )
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)
        try await persistence.bindAndApply(
            kind: .tag,
            localID: PlannerDetailsIntegrationFixtures.tagLocalID,
            remoteID: PlannerDetailsIntegrationFixtures.tagRemoteID,
            version: 0,
            payloadJSON: WireJSON.encoder().encode(tag)
        )
        try await PlannerDetailsIntegrationFixtures.seedTask(
            persistence: persistence,
            action: PlannerDetailsIntegrationFixtures.actionTask(
                tags: [tag],
                checklist: [checklist]
            )
        )
        let recurrence = PlannerDetailsIntegrationFixtures.recurrence
        let payload = TaskEditorPayload(
            mutationScope: .full,
            title: "Updated task",
            description: "Task body",
            status: .todo,
            type: .green,
            effort: 4,
            plannedAt: recurrence.startAt,
            dueAt: nil,
            recurrence: TaskRecurrenceEditorPayload(
                mode: .weekly,
                interval: recurrence.interval,
                weekdays: [.monday],
                dayOfMonth: nil,
                anchor: recurrence.startAt,
                endAt: recurrence.endAt,
                active: true
            ),
            checklist: [
                ChecklistEditorPayload(
                    id: PlannerDetailsIntegrationFixtures.checklistRemoteID,
                    text: checklist.text,
                    checked: true,
                    displayOrder: 0
                )
            ],
            tagIDs: [PlannerDetailsIntegrationFixtures.tagLocalID]
        )

        let result = try await adapter.saveEditor(
            .task(
                mode: .edit(
                    DetailEntityReference(
                        kind: .task,
                        id: PlannerDetailsIntegrationFixtures.taskLocalID
                    )
                ),
                goalID: PlannerDetailsIntegrationFixtures.goalLocalID,
                payload: payload
            )
        )

        let updatedSnapshot = try await repository.snapshot()
        let task = try XCTUnwrap(updatedSnapshot.tasks.first)
        XCTAssertFalse(result.pending)
        XCTAssertEqual(task.title, "Updated task")
        XCTAssertEqual(task.priorityShadow, 9)
        XCTAssertEqual(task.tags.map(\.id), [PlannerDetailsIntegrationFixtures.tagLocalID])
        XCTAssertEqual(task.checklistItems.map(\.text), ["Updated checklist"])
        XCTAssertEqual(task.recurrence, recurrence)
        let capturedUpdate = await remote.updateJSON()
        let updateData = try XCTUnwrap(capturedUpdate)
        let updateObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: updateData) as? [String: Any]
        )
        XCTAssertEqual((updateObject["priority"] as? NSNumber)?.intValue, 9)
    }

    func testCreatorOnlyIdeaDeleteRefusesForeignUserBeforeRemoteCall() async throws {
        let remote = PlannerDetailsRemoteStub()
        let (_, repository, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem(
            remote: remote
        )
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)
        try await PlannerDetailsIntegrationFixtures.seedIdea(
            persistence: persistence,
            action: PlannerDetailsIntegrationFixtures.actionIdea(
                creatorID: PlannerDetailsIntegrationFixtures.otherUserID,
                shared: true,
                fullAccess: true
            )
        )

        do {
            _ = try await adapter.performDetailMutation(
                .delete(
                    DetailEntityReference(
                        kind: .idea,
                        id: PlannerDetailsIntegrationFixtures.ideaLocalID
                    )
                )
            )
            XCTFail("Expected creator-only rejection")
        } catch let failure as DetailServiceFailure {
            XCTAssertEqual(failure.statusCode, 404)
        }
        let deletes = await remote.ideaDeletes()
        let retainedSnapshot = try await repository.snapshot()
        XCTAssertEqual(deletes, [])
        XCTAssertEqual(retainedSnapshot.ideas.count, 1)
    }

    func testIdeaCreatorDeleteUsesServerIDAndRemovesLocalCache() async throws {
        let remote = PlannerDetailsRemoteStub()
        let (_, repository, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem(
            remote: remote
        )
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)
        try await PlannerDetailsIntegrationFixtures.seedIdea(persistence: persistence)

        _ = try await adapter.performDetailMutation(
            .delete(
                DetailEntityReference(
                    kind: .idea,
                    id: PlannerDetailsIntegrationFixtures.ideaLocalID
                )
            )
        )

        let deletes = await remote.ideaDeletes()
        let deletedSnapshot = try await repository.snapshot()
        XCTAssertEqual(deletes, [PlannerDetailsIntegrationFixtures.ideaRemoteID])
        XCTAssertTrue(deletedSnapshot.ideas.isEmpty)
    }

    func testIdeaNoteAuthorMayEditButOnlyIdeaCreatorMayDelete() async throws {
        let remote = PlannerDetailsRemoteStub()
        let (_, repository, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem(
            remote: remote
        )
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)
        try await PlannerDetailsIntegrationFixtures.seedIdea(
            persistence: persistence,
            action: PlannerDetailsIntegrationFixtures.actionIdea(
                creatorID: PlannerDetailsIntegrationFixtures.otherUserID,
                shared: true,
                fullAccess: true,
                allowAuthorNoteEdits: false
            )
        )
        try await PlannerDetailsIntegrationFixtures.seedIdeaNote(persistence: persistence)

        _ = try await adapter.saveEditor(
            .ideaHistory(
                mode: .editIdeaHistory(
                    ideaID: PlannerDetailsIntegrationFixtures.ideaLocalID,
                    noteID: PlannerDetailsIntegrationFixtures.ideaNoteLocalID
                ),
                ideaID: PlannerDetailsIntegrationFixtures.ideaLocalID,
                payload: IdeaHistoryEditorPayload(
                    eventType: "decision",
                    body: "Updated",
                    metadata: ["source": "ios"]
                )
            )
        )
        let updates = await remote.ideaNoteUpdates()
        XCTAssertEqual(updates, [PlannerDetailsIntegrationFixtures.ideaNoteRemoteID])

        do {
            _ = try await adapter.performDetailMutation(
                .deleteIdeaHistory(
                    ideaID: PlannerDetailsIntegrationFixtures.ideaLocalID,
                    noteID: PlannerDetailsIntegrationFixtures.ideaNoteLocalID
                )
            )
            XCTFail("Expected creator-only history deletion rejection")
        } catch let failure as DetailServiceFailure {
            XCTAssertEqual(failure.statusCode, 404)
            XCTAssertEqual(failure.code, "not_found")
        }
        let deletes = await remote.ideaNoteDeletes()
        let retained = try await repository.snapshot()
        XCTAssertTrue(deletes.isEmpty)
        XCTAssertEqual(retained.ideas.count, 1)
    }

    func testRecurrenceCreateRecoveryUsesCanonicalKeyAcrossAdapterInstances() async throws {
        let remote = PlannerDetailsRemoteStub(
            recurrenceFailuresRemaining: 1,
            taskDeleteFailuresRemaining: 1
        )
        let (database, repository, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem(
            remote: remote
        )
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)
        let secondTagLocalID = UUID(uuidString: "11000000-0000-0000-0000-000000000003")!
        let secondTagRemoteID = UUID(uuidString: "11000000-0000-0000-0000-000000000004")!
        let tags = [
            (
                PlannerDetailsIntegrationFixtures.tagLocalID,
                TaskTagDTO(
                    id: PlannerDetailsIntegrationFixtures.tagRemoteID,
                    name: "First",
                    color: nil
                )
            ),
            (
                secondTagLocalID,
                TaskTagDTO(id: secondTagRemoteID, name: "Second", color: nil)
            )
        ]
        for (localID, tag) in tags {
            try await persistence.bindAndApply(
                kind: .tag,
                localID: localID,
                remoteID: tag.id,
                version: 0,
                payloadJSON: WireJSON.encoder().encode(tag)
            )
        }

        do {
            _ = try await adapter.saveEditor(
                .task(
                    mode: .create,
                    goalID: PlannerDetailsIntegrationFixtures.goalLocalID,
                    payload: recurringTaskPayload(
                        tagIDs: [PlannerDetailsIntegrationFixtures.tagLocalID, secondTagLocalID]
                    )
                )
            )
            XCTFail("Expected controlled recurrence failure")
        } catch let error as PlannerDetailsIntegrationError {
            guard case let .conflict(code, _) = error else { return XCTFail("Unexpected \(error)") }
            XCTAssertEqual(code, "recurrence_create_reconciliation_required")
        }
        let firstCreateCount = await remote.taskCreates()
        let recoverySnapshot = try await repository.snapshot()
        XCTAssertEqual(firstCreateCount, 1)
        XCTAssertEqual(recoverySnapshot.tasks.count, 1)

        let resumedRepository = LocalPlanningRepository(database: database)
        let resumedPersistence = GRDBPlannerDetailsPersistence(database: database)
        let resumedAdapter = PlannerDetailsAdapter(
            repository: resumedRepository,
            persistence: resumedPersistence,
            account: PlannerDetailsAccountContext(
                accountID: PlannerDetailsIntegrationFixtures.accountID,
                currentUserID: PlannerDetailsIntegrationFixtures.userID,
                timezone: "Europe/Moscow"
            ),
            network: FixedNetworkMonitor(connected: true),
            refresher: PlannerDetailsCurrentRefresher(),
            remote: remote,
            makeID: { PlannerDetailsIntegrationFixtures.taskLocalID }
        )
        let result = try await resumedAdapter.saveEditor(
            .task(
                mode: .create,
                goalID: PlannerDetailsIntegrationFixtures.goalLocalID,
                payload: recurringTaskPayload(
                    tagIDs: [secondTagLocalID, PlannerDetailsIntegrationFixtures.tagLocalID]
                )
            )
        )
        XCTAssertFalse(result.pending)
        let finalCreateCount = await remote.taskCreates()
        let completedSnapshot = try await repository.snapshot()
        XCTAssertEqual(finalCreateCount, 1)
        XCTAssertEqual(completedSnapshot.tasks.first?.recurrence, PlannerDetailsIntegrationFixtures.recurrence)
    }

    func testGuardedRemoteApplyPreservesMutationCreatedDuringAwaitGeneration() async throws {
        let (_, repository, persistence, _) = try PlannerDetailsIntegrationFixtures.makeSystem()
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)
        try await PlannerDetailsIntegrationFixtures.seedTask(persistence: persistence)
        let generation = try await persistence.mutationGeneration(
            kind: .task,
            localID: PlannerDetailsIntegrationFixtures.taskLocalID
        )
        let originalSnapshot = try await repository.snapshot()
        let original = try XCTUnwrap(originalSnapshot.tasks.first)

        try await repository.updateTask(
            id: original.id,
            draft: TaskDraft(
                id: original.id,
                goalID: original.goalId,
                title: "Newer local title",
                description: original.description,
                type: original.type,
                effort: original.effort,
                status: original.status,
                plannedTime: original.plannedTime,
                dueTime: original.dueTime
            )
        )
        let staleServer = try PlannerDetailsDTOMapper.task(
            PlannerDetailsIntegrationFixtures.actionTask(title: "Stale server title")
        )
        let result = try await persistence.bindAndApplyGuarded(
            kind: .task,
            localID: original.id,
            remoteID: staleServer.id,
            version: staleServer.version,
            payloadJSON: WireJSON.encoder().encode(staleServer),
            expectedGeneration: generation
        )

        XCTAssertEqual(result, .preservedNewerLocalMutation)
        let preservedSnapshot = try await repository.snapshot()
        XCTAssertEqual(preservedSnapshot.tasks.first?.title, "Newer local title")
    }

    func testIdeaMoveUsesRemoteIDsAndPersistsLocalParentMapping() async throws {
        let movedResponse = PlannerDetailsIntegrationFixtures.actionIdea(
            folderID: PlannerDetailsIntegrationFixtures.secondFolderRemoteID
        )
        let remote = PlannerDetailsRemoteStub(ideaResponse: movedResponse)
        let (_, repository, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem(
            remote: remote
        )
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(
            persistence: persistence,
            includeSecondParents: true
        )
        try await PlannerDetailsIntegrationFixtures.seedIdea(persistence: persistence)

        _ = try await adapter.move(
            DetailEntityReference(
                kind: .idea,
                id: PlannerDetailsIntegrationFixtures.ideaLocalID
            ),
            toParentID: PlannerDetailsIntegrationFixtures.secondFolderLocalID
        )

        let calls = await remote.ideaMoves()
        XCTAssertEqual(calls.first?.0, PlannerDetailsIntegrationFixtures.ideaRemoteID)
        XCTAssertEqual(
            calls.first?.1.targetFolderId,
            PlannerDetailsIntegrationFixtures.secondFolderRemoteID
        )
        let movedSnapshot = try await repository.snapshot()
        XCTAssertEqual(
            movedSnapshot.ideas.first?.folderId,
            PlannerDetailsIntegrationFixtures.secondFolderLocalID
        )
    }

    func testDependencyBlockedTranslationKeepsActionable409Code() {
        let failure = PlannerDetailsErrorTranslator.detailFailure(
            RemoteActionError.dependencyBlocked(
                code: "dependency_blocked",
                message: "Finish dependencies first"
            )
        )
        XCTAssertEqual(failure.statusCode, 409)
        XCTAssertEqual(failure.code, "dependency_blocked")
    }

    func testRemoteValidationUnauthorizedAndConflictTranslateWithoutLosingState() {
        XCTAssertEqual(
            PlannerDetailsErrorTranslator.map(RemoteActionError.unauthorized),
            .unauthorized
        )
        XCTAssertEqual(
            PlannerDetailsErrorTranslator.map(
                RemoteActionError.validation(
                    message: "Invalid title",
                    fieldErrors: ["title": "required"]
                )
            ),
            .validation(message: "Invalid title", fields: ["title": "required"])
        )
        XCTAssertEqual(
            PlannerDetailsErrorTranslator.map(
                RemoteActionError.versionConflict(
                    code: "version_conflict",
                    message: "Reload"
                )
            ),
            .conflict(code: "version_conflict", message: "Reload")
        )
        XCTAssertEqual(
            PlannerDetailsErrorTranslator.detailFailure(
                RemoteActionError.notFound(code: "resource_not_found", message: "Missing")
            ),
            DetailServiceFailure(statusCode: 404, code: "resource_not_found", message: "Missing")
        )
    }

    func testUnsupportedRemoteOperationFailsExplicitly() async throws {
        let (_, _, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem(
            remote: nil
        )
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)

        do {
            _ = try await adapter.clone(
                DetailEntityReference(
                    kind: .goal,
                    id: PlannerDetailsIntegrationFixtures.goalLocalID
                ),
                toParentID: PlannerDetailsIntegrationFixtures.folderLocalID
            )
            XCTFail("Expected explicit unsupported error")
        } catch let error as PlannerDetailsIntegrationError {
            guard case let .unsupported(operation) = error else {
                return XCTFail("Unexpected \(error)")
            }
            XCTAssertTrue(operation.contains("adapter_missing"))
        }
    }

    private func recurringTaskPayload(tagIDs: [UUID] = []) -> TaskEditorPayload {
        TaskEditorPayload(
            mutationScope: .full,
            title: "Recurring task",
            description: "Body",
            status: .todo,
            type: .green,
            effort: 2,
            plannedAt: PlannerDetailsIntegrationFixtures.recurrence.startAt,
            dueAt: nil,
            recurrence: TaskRecurrenceEditorPayload(
                mode: .weekly,
                interval: 1,
                weekdays: [.wednesday, .monday],
                dayOfMonth: nil,
                anchor: PlannerDetailsIntegrationFixtures.recurrence.startAt,
                endAt: PlannerDetailsIntegrationFixtures.recurrence.endAt,
                active: true
            ),
            checklist: [],
            tagIDs: tagIDs
        )
    }
}
