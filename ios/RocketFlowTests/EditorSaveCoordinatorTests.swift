import Foundation
import XCTest
@testable import RocketFlow

private enum EditorSaveTestFailure: Error, Sendable {
    case expected
}

private actor EditorSaverStub: EditorSaving {
    enum Behavior: Sendable {
        case result(EditorSaveResult)
        case failure
        case reminderFailure(EditorReminderFailure)
    }

    let behavior: Behavior
    private var received: [EditorSaveRequest] = []

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func saveEditor(_ request: EditorSaveRequest) async throws -> EditorSaveResult {
        received.append(request)
        switch behavior {
        case let .result(result): return result
        case .failure: throw EditorSaveTestFailure.expected
        case let .reminderFailure(failure): throw failure
        }
    }

    func requests() -> [EditorSaveRequest] { received }
}

@MainActor
private final class EditorNavigationRecorder {
    private(set) var values: [DetailNavigationResult] = []
    func receive(_ value: DetailNavigationResult) { values.append(value) }
}

@MainActor
final class EditorSaveCoordinatorTests: XCTestCase {
    func testTaskCreationReturnsToSameGoalAndPreservesOrigin() async throws {
        let result = EditorSaveResult(
            reference: DetailEntityReference(kind: .task, id: EditorTestFixtures.taskID),
            pending: false
        )
        let saver = EditorSaverStub(behavior: .result(result))
        let recorder = EditorNavigationRecorder()
        let coordinator = EditorSaveCoordinator(
            context: EditorContext(
                origin: .calendar,
                parent: DetailEntityReference(kind: .goal, id: EditorTestFixtures.goalID),
                afterSave: .goalDetail(EditorTestFixtures.goalID)
            ),
            isOnline: true,
            saver: saver,
            onComplete: recorder.receive
        )
        let payload = try XCTUnwrap(
            EditorValidator.payload(
                EditorTestFixtures.taskDraft(),
                timezone: EditorTestFixtures.timezone
            )
        )

        await coordinator.save(.task(mode: .create, goalID: EditorTestFixtures.goalID, payload: payload))

        XCTAssertEqual(coordinator.state, .saved)
        XCTAssertEqual(
            recorder.values,
            [
                .taskCreated(
                    taskID: EditorTestFixtures.taskID,
                    returnToGoalID: EditorTestFixtures.goalID,
                    origin: .calendar
                )
            ]
        )
    }

    func testNetworkRequiredEntityDoesNotCallSaverWhenOffline() async {
        let saver = EditorSaverStub(
            behavior: .result(
                EditorSaveResult(
                    reference: DetailEntityReference(kind: .idea, id: UUID()),
                    pending: false
                )
            )
        )
        let coordinator = makeCoordinator(saver: saver, isOnline: false)
        let request = EditorSaveRequest.idea(
            mode: .create,
            folderID: UUID(),
            payload: IdeaEditorPayload(
                title: "Idea",
                body: "",
                status: "open",
                allowAuthorHistoryEdits: true
            )
        )

        await coordinator.save(request)

        XCTAssertEqual(coordinator.state, .networkRequired)
        let requests = await saver.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testOfflineCapableEntityCanBecomePending() async {
        let reference = DetailEntityReference(kind: .folder, id: UUID())
        let saver = EditorSaverStub(
            behavior: .result(EditorSaveResult(reference: reference, pending: true))
        )
        let recorder = EditorNavigationRecorder()
        let coordinator = EditorSaveCoordinator(
            context: EditorContext(origin: .home, parent: nil, afterSave: .openCreated),
            isOnline: false,
            saver: saver,
            onComplete: recorder.receive
        )
        await coordinator.save(
            .folder(
                mode: .create,
                parentFolderID: nil,
                payload: FolderEditorPayload(name: "Folder", description: "")
            )
        )
        XCTAssertEqual(coordinator.state, .pending)
        XCTAssertEqual(recorder.values, [.open(reference, origin: .home)])
    }

    func testStayOnCurrentDetailReopensParent() async {
        let parent = DetailEntityReference(kind: .folder, id: UUID())
        let created = DetailEntityReference(kind: .note, id: UUID())
        let saver = EditorSaverStub(
            behavior: .result(EditorSaveResult(reference: created, pending: false))
        )
        let recorder = EditorNavigationRecorder()
        let coordinator = EditorSaveCoordinator(
            context: EditorContext(
                origin: .focus,
                parent: parent,
                afterSave: .stayOnCurrentDetail
            ),
            isOnline: true,
            saver: saver,
            onComplete: recorder.receive
        )
        await coordinator.save(
            .note(
                mode: .create,
                folderID: parent.id,
                payload: NoteEditorPayload(title: "Note", body: "")
            )
        )
        XCTAssertEqual(recorder.values, [.open(parent, origin: .focus)])
    }

    func testSaveFailureIsVisibleAndResettable() async {
        let coordinator = makeCoordinator(saver: EditorSaverStub(behavior: .failure))
        await coordinator.save(
            .folder(
                mode: .create,
                parentFolderID: nil,
                payload: FolderEditorPayload(name: "Folder", description: "")
            )
        )
        XCTAssertEqual(coordinator.state, .error)
        coordinator.resetError()
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testReminderFailureHasDistinctVisibleAndResettableState() async {
        let coordinator = makeCoordinator(
            saver: EditorSaverStub(behavior: .reminderFailure(.authorizationDenied))
        )

        await coordinator.save(
            .folder(
                mode: .create,
                parentFolderID: nil,
                payload: FolderEditorPayload(name: "Folder", description: "")
            )
        )

        XCTAssertEqual(coordinator.state, .reminderError(.authorizationDenied))
        coordinator.resetError()
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testSaveRequestClassifiesOfflineCapabilityExactly() {
        let folder = EditorSaveRequest.folder(
            mode: .create,
            parentFolderID: nil,
            payload: FolderEditorPayload(name: "Folder", description: "")
        )
        let goal = EditorSaveRequest.goal(
            mode: .create,
            folderID: UUID(),
            payload: GoalEditorPayload(name: "Goal", description: "", status: .todo)
        )
        let idea = EditorSaveRequest.idea(
            mode: .create,
            folderID: UUID(),
            payload: IdeaEditorPayload(
                title: "Idea", body: "", status: "open", allowAuthorHistoryEdits: true
            )
        )
        let note = EditorSaveRequest.note(
            mode: .create,
            folderID: UUID(),
            payload: NoteEditorPayload(title: "Note", body: "")
        )
        XCTAssertFalse(folder.requiresNetwork)
        XCTAssertFalse(goal.requiresNetwork)
        XCTAssertTrue(idea.requiresNetwork)
        XCTAssertTrue(note.requiresNetwork)
    }

    func testHistoryEditRequestCarriesIdeaAndEntryIdentity() {
        let ideaID = UUID()
        let entryID = UUID()
        let request = EditorSaveRequest.ideaHistory(
            mode: .editIdeaHistory(ideaID: ideaID, noteID: entryID),
            ideaID: ideaID,
            payload: IdeaHistoryEditorPayload(
                eventType: "comment",
                body: "Updated",
                metadata: ["source": "ios"]
            )
        )
        guard case let .ideaHistory(mode, capturedIdeaID, _) = request else {
            return XCTFail("Expected history request")
        }
        XCTAssertEqual(capturedIdeaID, ideaID)
        XCTAssertEqual(mode, .editIdeaHistory(ideaID: ideaID, noteID: entryID))
    }

    private func makeCoordinator(
        saver: any EditorSaving,
        isOnline: Bool = true
    ) -> EditorSaveCoordinator {
        EditorSaveCoordinator(
            context: EditorContext(origin: .home, parent: nil, afterSave: .openCreated),
            isOnline: isOnline,
            saver: saver,
            onComplete: { _ in }
        )
    }
}
