import Foundation
import XCTest
@testable import RocketFlow

private enum DetailTestFailure: Error, Sendable {
    case expected
}

private actor DetailLoaderStub: DetailLoading {
    enum Behavior: Sendable {
        case result(DetailLoadResult)
        case failure
    }

    let behavior: Behavior

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func loadDetail(_ reference: DetailEntityReference) async throws -> DetailLoadResult {
        switch behavior {
        case let .result(result): result
        case .failure: throw DetailTestFailure.expected
        }
    }
}

private actor DetailMutationStub: DetailMutationPerforming {
    enum Behavior: Sendable {
        case result(DetailMutationResult)
        case failure(DetailServiceFailure)
        case genericFailure
    }

    let behavior: Behavior
    private var received: [DetailMutation] = []

    init(_ behavior: Behavior = .result(DetailMutationResult())) {
        self.behavior = behavior
    }

    func performDetailMutation(_ mutation: DetailMutation) async throws -> DetailMutationResult {
        received.append(mutation)
        switch behavior {
        case let .result(result): result
        case let .failure(failure): throw failure
        case .genericFailure: throw DetailTestFailure.expected
        }
    }

    func mutations() -> [DetailMutation] { received }
}

@MainActor
private final class DetailNavigationRecorder {
    private(set) var values: [DetailNavigationResult] = []
    func receive(_ value: DetailNavigationResult) { values.append(value) }
}

@MainActor
final class DetailViewModelTests: XCTestCase {
    func testOfflineLoadNormalizesAndExposesCacheState() async {
        let old = DetailTestFixtures.child(kind: .task, id: UUID(), createdAt: 1)
        let recent = DetailTestFixtures.child(kind: .task, id: UUID(), createdAt: 2)
        let content = DetailContent.goal(
            DetailTestFixtures.goal(tasks: [old, recent])
        )
        let model = makeModel(
            content: content,
            source: .offlineCache
        )

        await model.loadIfNeeded()

        XCTAssertEqual(model.phase, .offline)
        XCTAssertTrue(model.isOffline)
        XCTAssertFalse(model.hasPendingChanges)
        guard case let .goal(goal) = model.content else { return XCTFail("Expected goal") }
        XCTAssertEqual(goal.tasks.map(\.reference.id), [recent.reference.id, old.reference.id])
    }

    func testPendingLoadExposesPendingState() async {
        let model = makeModel(
            content: .folder(DetailTestFixtures.folder()),
            pending: true
        )
        await model.loadIfNeeded()
        XCTAssertEqual(model.phase, .pending)
        XCTAssertFalse(model.isOffline)
        XCTAssertTrue(model.hasPendingChanges)
    }

    func testInitialFailureDoesNotInventContent() async {
        let recorder = DetailNavigationRecorder()
        let model = DetailViewModel(
            reference: DetailEntityReference(kind: .folder, id: DetailTestFixtures.folderID),
            origin: .home,
            loader: DetailLoaderStub(behavior: .failure),
            mutationPerformer: DetailMutationStub(),
            onNavigate: recorder.receive
        )
        await model.loadIfNeeded()
        XCTAssertEqual(model.phase, .error)
        XCTAssertNil(model.content)
    }

    func testGoalTaskCreateContractReturnsToSameGoal() async {
        let recorder = DetailNavigationRecorder()
        let model = makeModel(content: .goal(DetailTestFixtures.goal()), recorder: recorder)
        await model.loadIfNeeded()

        model.handle(.create(.task))

        XCTAssertEqual(
            recorder.values,
            [
                .present(
                    .create(
                        kind: .task,
                        parent: DetailEntityReference(kind: .goal, id: DetailTestFixtures.goalID),
                        afterSave: .goalDetail(DetailTestFixtures.goalID)
                    ),
                    origin: .home
                )
            ]
        )
    }

    func testDisallowedMenuActionDoesNotNavigate() async {
        let recorder = DetailNavigationRecorder()
        let model = makeModel(
            content: .folder(DetailTestFixtures.folder(shared: true, fullAccess: false)),
            recorder: recorder
        )
        await model.loadIfNeeded()
        model.handle(.edit)
        model.handle(.delete)
        XCTAssertTrue(recorder.values.isEmpty)
    }

    func testStatusUpdateUsesVersionAndKeepsOptimisticValue() async {
        let performer = DetailMutationStub()
        let model = makeModel(
            content: .task(DetailTestFixtures.task()),
            performer: performer
        )
        await model.loadIfNeeded()

        await model.updateTaskStatus(.done)

        guard case let .task(task) = model.content else { return XCTFail("Expected task") }
        XCTAssertEqual(task.status, .done)
        let mutations = await performer.mutations()
        XCTAssertEqual(
            mutations,
            [.updateTaskStatus(taskID: DetailTestFixtures.taskID, status: .done, version: 7)]
        )
    }

    func testDependencyBlockedRollsBackStatusAndShowsActionableIssue() async {
        let performer = DetailMutationStub(
            .failure(
                DetailServiceFailure(
                    statusCode: 409,
                    code: "dependency_blocked",
                    message: "Blocked"
                )
            )
        )
        let model = makeModel(
            content: .task(DetailTestFixtures.task(status: .todo)),
            performer: performer
        )
        await model.loadIfNeeded()

        await model.updateTaskStatus(.done)

        guard case let .task(task) = model.content else { return XCTFail("Expected task") }
        XCTAssertEqual(task.status, .todo)
        XCTAssertEqual(model.issue, .dependencyBlocked)
        XCTAssertEqual(model.phase, .error)
    }

    func testSharedTaskCanUpdateStatusButCannotToggleChecklist() async {
        let item = DetailChecklistItemViewData(
            id: UUID(), text: "Check", checked: false, displayOrder: 0, createdAt: Date()
        )
        let performer = DetailMutationStub()
        let model = makeModel(
            content: .task(
                DetailTestFixtures.task(
                    shared: true,
                    fullAccess: false,
                    isOwner: false,
                    checklist: [item]
                )
            ),
            performer: performer
        )
        await model.loadIfNeeded()

        await model.toggleChecklistItem(item.id)
        await model.updateTaskStatus(.inProgress)

        let mutations = await performer.mutations()
        XCTAssertEqual(mutations.count, 1)
        XCTAssertEqual(
            mutations.first,
            .updateTaskStatus(taskID: DetailTestFixtures.taskID, status: .inProgress, version: 7)
        )
    }

    func testChecklistToggleIsOptimisticAndTyped() async {
        let item = DetailChecklistItemViewData(
            id: UUID(), text: "Check", checked: false, displayOrder: 0, createdAt: Date()
        )
        let performer = DetailMutationStub()
        let model = makeModel(
            content: .task(DetailTestFixtures.task(checklist: [item])),
            performer: performer
        )
        await model.loadIfNeeded()
        await model.toggleChecklistItem(item.id)

        guard case let .task(task) = model.content else { return XCTFail("Expected task") }
        XCTAssertTrue(task.checklist[0].checked)
        let mutations = await performer.mutations()
        guard case let .replaceChecklist(taskID, values) = mutations.first else {
            return XCTFail("Expected checklist mutation")
        }
        XCTAssertEqual(taskID, DetailTestFixtures.taskID)
        XCTAssertTrue(values[0].checked)
    }

    func testFocusUpdateRollsBackOnFailure() async {
        let model = makeModel(
            content: .task(DetailTestFixtures.task(focused: false)),
            performer: DetailMutationStub(.genericFailure)
        )
        await model.loadIfNeeded()
        await model.setFocus(true)

        guard case let .task(task) = model.content else { return XCTFail("Expected task") }
        XCTAssertFalse(task.isInFocus)
        XCTAssertEqual(model.issue, .unavailable)
    }

    func testOfflineIdeaHistoryMutationRequiresNetworkAndDoesNotCallService() async {
        let performer = DetailMutationStub()
        let model = makeModel(
            content: .idea(DetailTestFixtures.idea()),
            source: .offlineCache,
            performer: performer
        )
        await model.loadIfNeeded()
        await model.createIdeaHistory(eventType: "comment", body: "Text", metadata: [:])

        XCTAssertEqual(model.issue, .networkRequired)
        let mutations = await performer.mutations()
        XCTAssertTrue(mutations.isEmpty)
    }

    func testOfflinePendingIdeaBlocksEveryNetworkRequiredHistoryMutation() async {
        let entry = DetailTestFixtures.history(authored: true, createdAt: 1)
        let performer = DetailMutationStub()
        let model = makeModel(
            content: .idea(DetailTestFixtures.idea(history: [entry])),
            source: .offlineCache,
            pending: true,
            performer: performer
        )
        await model.loadIfNeeded()

        XCTAssertEqual(model.phase, .pending)
        XCTAssertTrue(model.isOffline)
        XCTAssertTrue(model.hasPendingChanges)

        await model.createIdeaHistory(eventType: "comment", body: "Text", metadata: [:])
        await model.updateIdeaHistory(entry)
        await model.deleteIdeaHistory(entry)

        XCTAssertEqual(model.issue, .networkRequired)
        let mutations = await performer.mutations()
        XCTAssertTrue(mutations.isEmpty)
    }

    func testHistoryEditRequiresAuthorshipAndPreservesOrigin() async {
        let recorder = DetailNavigationRecorder()
        let authored = DetailTestFixtures.history(authored: true, createdAt: 1)
        let foreign = DetailTestFixtures.history(authored: false, createdAt: 2)
        let model = makeModel(
            content: .idea(DetailTestFixtures.idea(history: [authored, foreign])),
            origin: .focus,
            recorder: recorder
        )
        await model.loadIfNeeded()

        model.editIdeaHistory(foreign)
        model.editIdeaHistory(authored)

        XCTAssertEqual(
            recorder.values,
            [
                .present(
                    .editIdeaHistory(ideaID: DetailTestFixtures.ideaID, noteID: authored.id),
                    origin: .focus
                )
            ]
        )
    }

    func testOnlyIdeaCreatorCanDeleteHistoryEntry() async {
        let entry = DetailTestFixtures.history(authored: true, createdAt: 1)
        let performer = DetailMutationStub()
        let model = makeModel(
            content: .idea(
                DetailTestFixtures.idea(isCreator: false, history: [entry])
            ),
            performer: performer
        )
        await model.loadIfNeeded()
        await model.deleteIdeaHistory(entry)
        let mutations = await performer.mutations()
        XCTAssertTrue(mutations.isEmpty)
    }

    func testTaskDeleteReturnsToSavedOriginTab() async {
        let recorder = DetailNavigationRecorder()
        let model = makeModel(
            content: .task(DetailTestFixtures.task()),
            origin: .calendar,
            recorder: recorder
        )
        await model.loadIfNeeded()
        await model.delete()
        XCTAssertEqual(
            recorder.values,
            [.deleted(.originRoot(.calendar))]
        )
    }

    private func makeModel(
        content: DetailContent,
        source: DetailLoadSource = .network,
        pending: Bool = false,
        origin: DetailOriginTab = .home,
        performer: any DetailMutationPerforming = DetailMutationStub(),
        recorder: DetailNavigationRecorder? = nil
    ) -> DetailViewModel {
        let recorder = recorder ?? DetailNavigationRecorder()
        return DetailViewModel(
            reference: content.reference,
            origin: origin,
            loader: DetailLoaderStub(
                behavior: .result(
                    DetailLoadResult(
                        content: content,
                        source: source,
                        hasPendingChanges: pending
                    )
                )
            ),
            mutationPerformer: performer,
            onNavigate: recorder.receive
        )
    }
}
