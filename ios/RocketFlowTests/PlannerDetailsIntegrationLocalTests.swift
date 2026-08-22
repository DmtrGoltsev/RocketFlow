import Foundation
import XCTest
@testable import RocketFlow

final class PlannerDetailsIntegrationLocalTests: XCTestCase {
    func testCreateTaskInGoalQueuesLocallyAndReloadsSameStableID() async throws {
        let (_, repository, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem(
            generatedID: PlannerDetailsIntegrationFixtures.taskLocalID
        )
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)
        let checklist = ChecklistEditorPayload(
            id: nil,
            text: "First step",
            checked: false,
            displayOrder: 0
        )
        let payload = taskPayload(checklist: [checklist])

        let result = try await adapter.saveEditor(
            .task(
                mode: .create,
                goalID: PlannerDetailsIntegrationFixtures.goalLocalID,
                payload: payload
            )
        )
        let snapshot = try await repository.snapshot()
        let task = try XCTUnwrap(snapshot.tasks.first)
        let loaded = try await adapter.loadDetail(result.reference)

        XCTAssertEqual(result.reference.id, PlannerDetailsIntegrationFixtures.taskLocalID)
        XCTAssertTrue(result.pending)
        XCTAssertEqual(task.goalId, PlannerDetailsIntegrationFixtures.goalLocalID)
        XCTAssertEqual(task.checklistItems.map(\.text), ["First step"])
        guard case let .task(detail) = loaded.content else { return XCTFail("Expected task") }
        XCTAssertEqual(detail.id, result.reference.id)
        XCTAssertEqual(detail.goalID, PlannerDetailsIntegrationFixtures.goalLocalID)
    }

    func testStatusToggleQueuesExactTaskUpdateAndPreservesCompatibilityShadow() async throws {
        let (_, repository, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem()
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)
        try await PlannerDetailsIntegrationFixtures.seedTask(persistence: persistence)
        let reference = PlannerItemReference(
            kind: .task,
            id: PlannerDetailsIntegrationFixtures.taskLocalID
        )

        _ = try await adapter.perform(.updateTaskStatus(reference, .done))

        let updatedSnapshot = try await repository.snapshot()
        let task = try XCTUnwrap(updatedSnapshot.tasks.first)
        XCTAssertEqual(task.status, .done)
        XCTAssertEqual(task.priorityShadow, 9)
        XCTAssertGreaterThan(updatedSnapshot.pendingCount, 0)
    }

    func testMoveTaskUsesLocalDedicatedMoveAndConvergesOnTargetGoal() async throws {
        let (_, repository, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem()
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(
            persistence: persistence,
            includeSecondParents: true
        )
        try await PlannerDetailsIntegrationFixtures.seedTask(persistence: persistence)

        _ = try await adapter.move(
            DetailEntityReference(
                kind: .task,
                id: PlannerDetailsIntegrationFixtures.taskLocalID
            ),
            toParentID: PlannerDetailsIntegrationFixtures.secondGoalLocalID
        )

        let movedSnapshot = try await repository.snapshot()
        let task = try XCTUnwrap(movedSnapshot.tasks.first)
        XCTAssertEqual(task.goalId, PlannerDetailsIntegrationFixtures.secondGoalLocalID)
        XCTAssertGreaterThan(movedSnapshot.pendingCount, 0)
    }

    func testDeleteTaskCreatesTombstoneAndRemovesItFromPlannerSnapshot() async throws {
        let (_, repository, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem()
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)
        try await PlannerDetailsIntegrationFixtures.seedTask(persistence: persistence)

        let result = try await adapter.perform(
            .delete(
                PlannerItemReference(
                    kind: .task,
                    id: PlannerDetailsIntegrationFixtures.taskLocalID
                )
            )
        )

        let deletedSnapshot = try await repository.snapshot()
        XCTAssertTrue(deletedSnapshot.tasks.isEmpty)
        XCTAssertTrue(result.snapshot?.items.contains {
            $0.reference.id == PlannerDetailsIntegrationFixtures.taskLocalID
        } == false)
        XCTAssertGreaterThan(deletedSnapshot.pendingCount, 0)
    }

    func testPlannerUsesLocalIDsAndResolvesServerDeepLinkBackToSameResource() async throws {
        let (_, _, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem()
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)
        try await PlannerDetailsIntegrationFixtures.seedTask(persistence: persistence)

        let planner = try await adapter.loadPlanner()
        let task = try XCTUnwrap(
            planner.snapshot.items.first { $0.reference.kind == .task }
        )
        let mapped = try await adapter.localID(
            kind: .task,
            serverID: PlannerDetailsIntegrationFixtures.taskRemoteID
        )
        let serverID = try await adapter.serverID(
            kind: .task,
            localID: PlannerDetailsIntegrationFixtures.taskLocalID
        )

        XCTAssertEqual(task.reference.id, PlannerDetailsIntegrationFixtures.taskLocalID)
        XCTAssertEqual(task.parent?.id, PlannerDetailsIntegrationFixtures.goalLocalID)
        XCTAssertEqual(mapped, PlannerDetailsIntegrationFixtures.taskLocalID)
        XCTAssertEqual(serverID, PlannerDetailsIntegrationFixtures.taskRemoteID)
    }

    func testReadOnlySharedTaskAcceptsStatusOnlyAndRejectsFullEditorMutation() async throws {
        let (_, repository, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem()
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)
        try await PlannerDetailsIntegrationFixtures.seedTask(
            persistence: persistence,
            action: PlannerDetailsIntegrationFixtures.actionTask(
                shared: true,
                fullAccess: false,
                creatorID: PlannerDetailsIntegrationFixtures.otherUserID
            )
        )
        var statusPayload = taskPayload()
        statusPayload = TaskEditorPayload(
            mutationScope: .statusOnly,
            title: "Ignored",
            description: "Ignored",
            status: .done,
            type: .red,
            effort: 999,
            plannedAt: Date(),
            dueAt: Date(),
            recurrence: nil,
            checklist: [],
            tagIDs: []
        )

        _ = try await adapter.saveEditor(
            .task(
                mode: .edit(
                    DetailEntityReference(
                        kind: .task,
                        id: PlannerDetailsIntegrationFixtures.taskLocalID
                    )
                ),
                goalID: PlannerDetailsIntegrationFixtures.goalLocalID,
                payload: statusPayload
            )
        )
        let statusSnapshot = try await repository.snapshot()
        let task = try XCTUnwrap(statusSnapshot.tasks.first)
        XCTAssertEqual(task.status, .done)
        XCTAssertEqual(task.title, "Task")
        XCTAssertEqual(task.type, .green)
        XCTAssertEqual(task.effort, 4)

        do {
            _ = try await adapter.saveEditor(
                .task(
                    mode: .edit(
                        DetailEntityReference(
                            kind: .task,
                            id: PlannerDetailsIntegrationFixtures.taskLocalID
                        )
                    ),
                    goalID: PlannerDetailsIntegrationFixtures.goalLocalID,
                    payload: taskPayload()
                )
            )
            XCTFail("Expected read-only rejection")
        } catch let error as PlannerDetailsIntegrationError {
            guard case .forbidden = error else { return XCTFail("Unexpected \(error)") }
        }
    }

    func testEditorSeedPreservesDueAnchoredRecurrenceWhenPlannedAndDueExist() async throws {
        let (_, _, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem()
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)
        let plannedAt = PlannerDetailsIntegrationFixtures.now
        let dueAt = plannedAt.addingTimeInterval(86_400)
        let recurrence = RecurrenceDTO(
            mode: .weekly,
            interval: 2,
            daysOfWeek: [.monday],
            dayOfMonth: nil,
            startAt: dueAt,
            endAt: dueAt.addingTimeInterval(86_400 * 60),
            active: true
        )
        try await PlannerDetailsIntegrationFixtures.seedTask(
            persistence: persistence,
            action: PlannerDetailsIntegrationFixtures.actionTask(
                plannedTime: plannedAt,
                dueTime: dueAt,
                recurrence: recurrence
            )
        )

        let seed = try await adapter.editorSeed(
            for: .edit(
                DetailEntityReference(
                    kind: .task,
                    id: PlannerDetailsIntegrationFixtures.taskLocalID
                )
            )
        )
        guard case let .task(draft, _, _, _) = seed else {
            return XCTFail("Expected task editor seed")
        }
        XCTAssertEqual(draft.recurrence.anchorSource, .due)
        XCTAssertEqual(draft.recurrence.startAt, dueAt)

        let timezone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let payload = try XCTUnwrap(EditorValidator.payload(draft, timezone: timezone))
        let recurrencePayload = try XCTUnwrap(payload.recurrence)
        XCTAssertEqual(payload.plannedAt, plannedAt)
        XCTAssertEqual(payload.dueAt, dueAt)
        XCTAssertEqual(recurrencePayload.anchor, dueAt)
        XCTAssertEqual(recurrencePayload.interval, 2)
        XCTAssertEqual(recurrencePayload.weekdays, [.monday])
    }

    func testOfflineTaskQueuesButIdeaCreateFailsExplicitlyWithoutFakeSuccess() async throws {
        let remote = PlannerDetailsRemoteStub()
        let (_, repository, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem(
            connected: false,
            remote: remote
        )
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)

        let taskResult = try await adapter.saveEditor(
            .task(
                mode: .create,
                goalID: PlannerDetailsIntegrationFixtures.goalLocalID,
                payload: taskPayload()
            )
        )
        XCTAssertTrue(taskResult.pending)
        let queuedSnapshot = try await repository.snapshot()
        XCTAssertEqual(queuedSnapshot.tasks.count, 1)

        do {
            _ = try await adapter.saveEditor(
                .idea(
                    mode: .create,
                    folderID: PlannerDetailsIntegrationFixtures.folderLocalID,
                    payload: IdeaEditorPayload(
                        title: "Offline idea",
                        body: "",
                        status: "ACTIVE",
                        allowAuthorHistoryEdits: true
                    )
                )
            )
            XCTFail("Expected explicit network error")
        } catch let error as PlannerDetailsIntegrationError {
            XCTAssertEqual(error, .networkRequired)
        }
        let finalSnapshot = try await repository.snapshot()
        XCTAssertTrue(finalSnapshot.ideas.isEmpty)
    }

    func testTaskAggregateValidationRollsBackBaseChecklistTagsAndPendingMutation() async throws {
        let (_, repository, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem()
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)
        let duplicate = ChecklistEditorPayload(
            id: nil,
            text: "Duplicate identity",
            checked: false,
            displayOrder: 0
        )

        do {
            _ = try await adapter.saveEditor(
                .task(
                    mode: .create,
                    goalID: PlannerDetailsIntegrationFixtures.goalLocalID,
                    payload: taskPayload(checklist: [duplicate, duplicate])
                )
            )
            XCTFail("Expected aggregate validation failure")
        } catch let error as PlannerDetailsIntegrationError {
            guard case .validation = error else { return XCTFail("Unexpected \(error)") }
        }

        let snapshot = try await repository.snapshot()
        XCTAssertTrue(snapshot.tasks.isEmpty)
        XCTAssertEqual(snapshot.pendingCount, 0)
    }

    func testSharedGoalTaskCreationRequiresCachedGrantAndGrantAppearsInDetail() async throws {
        let (database, repository, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem()
        try await persistence.bindAndApply(
            kind: .folder,
            localID: PlannerDetailsIntegrationFixtures.folderLocalID,
            remoteID: PlannerDetailsIntegrationFixtures.folderRemoteID,
            version: 2,
            payloadJSON: WireJSON.encoder().encode(PlannerDetailsIntegrationFixtures.folder())
        )
        try await persistence.bindAndApply(
            kind: .goal,
            localID: PlannerDetailsIntegrationFixtures.goalLocalID,
            remoteID: PlannerDetailsIntegrationFixtures.goalRemoteID,
            version: 3,
            payloadJSON: WireJSON.encoder().encode(
                PlannerDetailsIntegrationFixtures.goal(shared: true, fullAccess: false)
            )
        )

        do {
            _ = try await adapter.saveEditor(
                .task(
                    mode: .create,
                    goalID: PlannerDetailsIntegrationFixtures.goalLocalID,
                    payload: taskPayload()
                )
            )
            XCTFail("Expected missing grant rejection")
        } catch let error as PlannerDetailsIntegrationError {
            guard case .forbidden = error else { return XCTFail("Unexpected \(error)") }
        }
        let deniedSnapshot = try await repository.snapshot()
        XCTAssertTrue(deniedSnapshot.tasks.isEmpty)

        try PlannerDetailsIntegrationFixtures.grantTaskCreation(
            database: database,
            goalIDs: [PlannerDetailsIntegrationFixtures.goalLocalID]
        )
        let detail = try await adapter.loadDetail(
            DetailEntityReference(kind: .goal, id: PlannerDetailsIntegrationFixtures.goalLocalID)
        )
        guard case let .goal(goal) = detail.content else { return XCTFail("Expected goal") }
        XCTAssertTrue(goal.capabilities.contains(.createTask))

        _ = try await adapter.saveEditor(
            .task(
                mode: .create,
                goalID: PlannerDetailsIntegrationFixtures.goalLocalID,
                payload: taskPayload()
            )
        )
        let grantedSnapshot = try await repository.snapshot()
        XCTAssertEqual(grantedSnapshot.tasks.count, 1)
    }

    func testUnknownMoveDestinationIsDeniedBeforeLocalMutation() async throws {
        let (_, repository, persistence, adapter) = try PlannerDetailsIntegrationFixtures.makeSystem()
        try await PlannerDetailsIntegrationFixtures.seedHierarchy(persistence: persistence)
        try await PlannerDetailsIntegrationFixtures.seedTask(persistence: persistence)

        do {
            _ = try await adapter.move(
                DetailEntityReference(kind: .task, id: PlannerDetailsIntegrationFixtures.taskLocalID),
                toParentID: UUID()
            )
            XCTFail("Expected unknown destination rejection")
        } catch let error as PlannerDetailsIntegrationError {
            guard case .notFound = error else { return XCTFail("Unexpected \(error)") }
        }
        let unchanged = try await repository.snapshot()
        XCTAssertEqual(unchanged.tasks.first?.goalId, PlannerDetailsIntegrationFixtures.goalLocalID)
    }

    private func taskPayload(
        checklist: [ChecklistEditorPayload] = []
    ) -> TaskEditorPayload {
        TaskEditorPayload(
            mutationScope: .full,
            title: "Created task",
            description: "Body",
            status: .todo,
            type: .green,
            effort: 3,
            plannedAt: nil,
            dueAt: nil,
            recurrence: nil,
            checklist: checklist,
            tagIDs: []
        )
    }
}
