import Foundation
import XCTest
@testable import RocketFlow

private enum PlannerViewModelTestFailure: Error, Sendable {
    case expected
}

private actor PlannerLoaderStub: PlannerLoading {
    enum Behavior: Sendable {
        case result(PlannerLoadResult)
        case failure
    }

    private let behavior: Behavior
    private var loadCount = 0

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func loadPlanner() async throws -> PlannerLoadResult {
        loadCount += 1
        switch behavior {
        case let .result(result): return result
        case .failure: throw PlannerViewModelTestFailure.expected
        }
    }

    func count() -> Int { loadCount }
}

private actor ControlledPlannerLoader: PlannerLoading {
    private var continuations: [Int: CheckedContinuation<PlannerLoadResult, Error>] = [:]
    private var loadCount = 0

    func loadPlanner() async throws -> PlannerLoadResult {
        let index = loadCount
        loadCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
        }
    }

    func count() -> Int { loadCount }

    func complete(_ index: Int, with result: PlannerLoadResult) {
        continuations.removeValue(forKey: index)?.resume(returning: result)
    }
}

private actor PlannerActionStub: PlannerActionPerforming {
    private let result: PlannerMutationResult
    private var received: [PlannerMutationAction] = []

    init(result: PlannerMutationResult = PlannerMutationResult()) {
        self.result = result
    }

    func perform(_ action: PlannerMutationAction) async throws -> PlannerMutationResult {
        received.append(action)
        return result
    }

    func actions() -> [PlannerMutationAction] { received }
}

private actor ControlledPlannerActionStub: PlannerActionPerforming {
    private var continuations: [Int: CheckedContinuation<PlannerMutationResult, Error>] = [:]
    private var received: [PlannerMutationAction] = []

    func perform(_ action: PlannerMutationAction) async throws -> PlannerMutationResult {
        let index = received.count
        received.append(action)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
        }
    }

    func count() -> Int { received.count }

    func complete(_ index: Int, with result: PlannerMutationResult = PlannerMutationResult()) {
        continuations.removeValue(forKey: index)?.resume(returning: result)
    }
}

private final class PlannerViewModelScrollStore: PlannerScrollStatePersisting {
    var states: [UUID: PlannerScrollRestorableState] = [:]

    func load(accountID: UUID) -> PlannerScrollRestorableState? {
        states[accountID]
    }

    func save(_ state: PlannerScrollRestorableState) {
        states[state.accountID] = state
    }

    func remove(accountID: UUID) {
        states.removeValue(forKey: accountID)
    }
}

@MainActor
private final class PlannerNavigationRecorder {
    private(set) var intents: [PlannerNavigationIntent] = []

    func receive(_ intent: PlannerNavigationIntent) {
        intents.append(intent)
    }
}

@MainActor
final class PlannerViewModelTests: XCTestCase {
    private let accountID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

    func testNetworkLoadBuildsTreeAndExpandsHierarchyInitially() async {
        let loader = PlannerLoaderStub(
            .result(PlannerLoadResult(snapshot: PlannerTestFixtures.snapshot, source: .network))
        )
        let model = makeModel(loader: loader)

        await model.loadIfNeeded()

        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.snapshot, PlannerTestFixtures.snapshot)
        XCTAssertEqual(model.expandedFolderIDs, [PlannerTestFixtures.folderID])
        XCTAssertEqual(model.expandedGoalIDs, [PlannerTestFixtures.goalID])
        XCTAssertEqual(model.tree.allRows.count, 5)
        let loadCount = await loader.count()
        XCTAssertEqual(loadCount, 1)
    }

    func testOfflineLoadKeepsCachedTreeAndWarning() async {
        let loader = PlannerLoaderStub(
            .result(
                PlannerLoadResult(
                    snapshot: PlannerTestFixtures.snapshot,
                    source: .offlineCache,
                    warning: "partial cache"
                )
            )
        )
        let model = makeModel(loader: loader)

        await model.loadIfNeeded()

        XCTAssertEqual(model.phase, .offline)
        XCTAssertFalse(model.tree.isEmpty)
        XCTAssertEqual(model.warning, "partial cache")
    }

    func testInitialFailureShowsErrorWithoutInventingData() async {
        let model = makeModel(loader: PlannerLoaderStub(.failure))

        await model.loadIfNeeded()

        XCTAssertEqual(model.phase, .error)
        XCTAssertNil(model.snapshot)
        XCTAssertTrue(model.tree.isEmpty)
    }

    func testTaskCreationInsideGoalReturnsToSameGoalDetailAfterSave() {
        let recorder = PlannerNavigationRecorder()
        let model = makeModel(
            loader: PlannerLoaderStub(.failure),
            recorder: recorder
        )
        let goal = PlannerTestFixtures.hierarchy().first { $0.reference.kind == .goal }!

        model.create(.task, in: goal)

        XCTAssertEqual(
            recorder.intents,
            [
                .create(
                    PlannerCreateIntent(
                        kind: .task,
                        parent: goal.reference,
                        afterSuccessfulSave: .openDetail(goal.reference)
                    )
                )
            ]
        )
    }

    func testToolbarCreationLeavesParentSelectionToIntegrationAdapter() {
        let recorder = PlannerNavigationRecorder()
        let model = makeModel(
            loader: PlannerLoaderStub(.failure),
            recorder: recorder
        )

        model.create(.note)

        XCTAssertEqual(
            recorder.intents,
            [
                .create(
                    PlannerCreateIntent(
                        kind: .note,
                        parent: nil,
                        afterSuccessfulSave: .openCreatedItem
                    )
                )
            ]
        )
    }

    func testReadOnlySharedItemCannotEmitForbiddenNavigation() {
        let recorder = PlannerNavigationRecorder()
        let model = makeModel(
            loader: PlannerLoaderStub(.failure),
            recorder: recorder
        )
        let item = PlannerTestFixtures.item(
            kind: .goal,
            id: PlannerTestFixtures.goalID,
            title: "Read only",
            createdAt: 100,
            shared: true,
            fullAccess: false
        )

        model.handle(.edit, for: item)
        model.handle(.move, for: item)
        model.handle(.share, for: item)

        XCTAssertTrue(recorder.intents.isEmpty)
    }

    func testAllowedContextActionsEmitTypedNavigationIntents() {
        let recorder = PlannerNavigationRecorder()
        let model = makeModel(
            loader: PlannerLoaderStub(.failure),
            recorder: recorder
        )
        let idea = PlannerTestFixtures.hierarchy().first { $0.reference.kind == .idea }!

        model.handle(.edit, for: idea)
        model.handle(.move, for: idea)
        model.handle(.clone, for: idea)
        model.handle(.share, for: idea)

        XCTAssertEqual(
            recorder.intents,
            [
                .edit(idea.reference),
                .move(idea.reference),
                .clone(idea.reference),
                .share(idea.reference)
            ]
        )
    }

    func testStatusOnlySharedTaskCanUpdateStatusButCannotFullEdit() async {
        let performer = PlannerActionStub()
        let recorder = PlannerNavigationRecorder()
        let model = makeModel(
            loader: PlannerLoaderStub(.failure),
            performer: performer,
            recorder: recorder
        )
        let task = PlannerTestFixtures.item(
            kind: .task,
            id: PlannerTestFixtures.taskID,
            title: "Status only",
            status: .todo,
            createdAt: 100,
            shared: true,
            fullAccess: false
        )

        model.handle(.edit, for: task)
        await model.toggleTaskStatus(task)
        let actions = await performer.actions()

        XCTAssertTrue(recorder.intents.isEmpty)
        XCTAssertEqual(
            actions,
            [.updateTaskStatus(task.reference, .done)]
        )
    }

    func testOpeningDetailCapturesExactScrollAnchorBeforeNavigation() {
        let recorder = PlannerNavigationRecorder()
        let scrollState = PlannerScrollStateController(
            persistence: PlannerViewModelScrollStore()
        )
        let model = makeModel(
            loader: PlannerLoaderStub(.failure),
            scrollState: scrollState,
            recorder: recorder
        )
        let task = PlannerTestFixtures.hierarchy().first { $0.reference.kind == .task }!
        model.receiveViewport(viewport(absoluteY: 100))
        model.receiveVisibleRows(scrollRows())

        model.open(task)

        XCTAssertEqual(scrollState.lastCaptureReason, .openDetail)
        XCTAssertEqual(scrollState.position?.anchor?.resourceType, .task)
        XCTAssertEqual(scrollState.position?.anchor?.resourceID, PlannerTestFixtures.taskID)
        XCTAssertEqual(scrollState.position?.pixelOffset, 12)
        XCTAssertEqual(recorder.intents, [.openDetail(task.reference)])
    }

    func testCollapseCapturesThenRestoresThroughNearestVisibleAncestor() async throws {
        let scrollState = PlannerScrollStateController(
            persistence: PlannerViewModelScrollStore()
        )
        let model = makeModel(
            loader: PlannerLoaderStub(
                .result(PlannerLoadResult(snapshot: PlannerTestFixtures.snapshot, source: .network))
            ),
            scrollState: scrollState
        )
        await model.loadIfNeeded()
        model.receiveViewport(viewport(absoluteY: 100))
        model.receiveVisibleRows(scrollRows())
        let initialRequestID = model.restorationRequest?.id
        let folderRow = try XCTUnwrap(
            model.tree.allRows.first { $0.item.reference.kind == .folder }
        )

        model.toggleExpanded(folderRow)
        model.receiveVisibleRows([
            PlannerScrollRowGeometry(
                anchor: folderRow.scrollAnchor,
                minY: 0,
                maxY: 44
            )
        ])

        XCTAssertEqual(scrollState.lastCaptureReason, .expandCollapse)
        XCTAssertFalse(model.expandedFolderIDs.contains(PlannerTestFixtures.folderID))
        XCTAssertNotEqual(model.restorationRequest?.id, initialRequestID)
        XCTAssertEqual(model.restorationRequest?.absoluteY, 12)
    }

    func testInsertionAbovePreservesExactRowPixelOffset() async {
        let scrollState = PlannerScrollStateController(
            persistence: PlannerViewModelScrollStore()
        )
        let model = makeModel(
            loader: PlannerLoaderStub(
                .result(PlannerLoadResult(snapshot: PlannerTestFixtures.snapshot, source: .network))
            ),
            scrollState: scrollState
        )
        await model.loadIfNeeded()
        model.receiveViewport(viewport(absoluteY: 100))
        model.receiveVisibleRows(scrollRows())

        model.applyExternalSnapshot(PlannerTestFixtures.snapshot, reason: .insertionAbove)
        model.receiveVisibleRows(scrollRows(offset: 60))

        XCTAssertEqual(scrollState.lastCaptureReason, .insertionAbove)
        XCTAssertEqual(model.restorationRequest?.absoluteY, 160)
    }

    func testRefreshBackgroundAndRotationUseDedicatedCaptureHooks() async {
        let scrollState = PlannerScrollStateController(
            persistence: PlannerViewModelScrollStore()
        )
        let model = makeModel(
            loader: PlannerLoaderStub(
                .result(PlannerLoadResult(snapshot: PlannerTestFixtures.snapshot, source: .network))
            ),
            scrollState: scrollState
        )
        await model.loadIfNeeded()
        model.receiveViewport(viewport(absoluteY: 100))
        model.receiveVisibleRows(scrollRows())

        await model.refresh()
        XCTAssertEqual(scrollState.lastCaptureReason, .snapshotRefresh)
        model.receiveVisibleRows(scrollRows())
        model.captureForBackground()
        XCTAssertEqual(scrollState.lastCaptureReason, .background)
        model.captureForRotation()
        XCTAssertEqual(scrollState.lastCaptureReason, .rotation)
    }

    func testSuccessfulMutationAppliesReturnedSnapshotAndCapturesPosition() async {
        let updated = PlannerSnapshot(
            items: PlannerTestFixtures.hierarchy().filter {
                $0.reference.id != PlannerTestFixtures.noteID
            }
        )
        let performer = PlannerActionStub(
            result: PlannerMutationResult(snapshot: updated)
        )
        let scrollState = PlannerScrollStateController(
            persistence: PlannerViewModelScrollStore()
        )
        let model = makeModel(
            loader: PlannerLoaderStub(
                .result(PlannerLoadResult(snapshot: PlannerTestFixtures.snapshot, source: .network))
            ),
            performer: performer,
            scrollState: scrollState
        )
        await model.loadIfNeeded()
        model.receiveViewport(viewport(absoluteY: 100))
        model.receiveVisibleRows(scrollRows())
        let note = PlannerTestFixtures.hierarchy().first { $0.reference.kind == .note }!

        await model.delete(note)
        let actions = await performer.actions()

        XCTAssertEqual(actions, [.delete(note.reference)])
        XCTAssertEqual(model.snapshot, updated)
        XCTAssertEqual(scrollState.lastCaptureReason, .mutation)
    }

    func testExternalSnapshotInvalidatesOlderInFlightLoad() async {
        let loader = ControlledPlannerLoader()
        let model = makeModel(loader: loader)
        let newerSnapshot = PlannerSnapshot(
            items: PlannerTestFixtures.hierarchy().filter {
                $0.reference.id != PlannerTestFixtures.noteID
            }
        )
        let loadTask = Task { await model.loadIfNeeded() }
        await waitForLoads(1, loader: loader)

        model.applyExternalSnapshot(newerSnapshot, reason: .insertionAbove)
        await loader.complete(
            0,
            with: PlannerLoadResult(snapshot: PlannerTestFixtures.snapshot, source: .network)
        )
        await loadTask.value

        XCTAssertEqual(model.snapshot, newerSnapshot)
        XCTAssertEqual(model.phase, .loaded)
    }

    func testSuccessfulMutationInvalidatesOlderInFlightLoad() async {
        let loader = ControlledPlannerLoader()
        let updatedSnapshot = PlannerSnapshot(
            items: PlannerTestFixtures.hierarchy().filter {
                $0.reference.id != PlannerTestFixtures.noteID
            }
        )
        let performer = PlannerActionStub(
            result: PlannerMutationResult(snapshot: updatedSnapshot)
        )
        let model = makeModel(loader: loader, performer: performer)
        let note = PlannerTestFixtures.hierarchy().first { $0.reference.kind == .note }!
        let loadTask = Task { await model.loadIfNeeded() }
        await waitForLoads(1, loader: loader)

        await model.delete(note)
        await loader.complete(
            0,
            with: PlannerLoadResult(snapshot: PlannerTestFixtures.snapshot, source: .network)
        )
        await loadTask.value

        XCTAssertEqual(model.snapshot, updatedSnapshot)
        XCTAssertEqual(model.phase, .loaded)
    }

    func testBusyMutationBlocksContextAndDirectNavigationActions() async {
        let performer = ControlledPlannerActionStub()
        let recorder = PlannerNavigationRecorder()
        let model = makeModel(
            loader: PlannerLoaderStub(.failure),
            performer: performer,
            recorder: recorder
        )
        let note = PlannerTestFixtures.hierarchy().first { $0.reference.kind == .note }!
        let mutationTask = Task { await model.delete(note) }
        await waitForActions(1, performer: performer)

        XCTAssertTrue(model.isPerformingAction)
        model.open(note)
        model.handle(.edit, for: note)
        model.create(.folder)
        model.openSettings()

        XCTAssertTrue(recorder.intents.isEmpty)
        await performer.complete(0)
        await mutationTask.value
        XCTAssertFalse(model.isPerformingAction)
    }

    func testStatusAccessibilityHintsDescribeCompleteAndReopenInBothLanguages() {
        let russian = PlannerCopy(language: .ru)
        let english = PlannerCopy(language: .en)

        XCTAssertEqual(russian.taskStatusActionHint(.todo), "Отметить задачу выполненной")
        XCTAssertEqual(russian.taskStatusActionHint(.done), "Вернуть задачу к выполнению")
        XCTAssertEqual(english.taskStatusActionHint(.inProgress), "Mark task as complete")
        XCTAssertEqual(english.taskStatusActionHint(.done), "Reopen task")
    }

    private func makeModel(
        loader: any PlannerLoading,
        performer: any PlannerActionPerforming = PlannerActionStub(),
        scrollState: PlannerScrollStateController? = nil,
        recorder: PlannerNavigationRecorder? = nil
    ) -> PlannerViewModel {
        let recorder = recorder ?? PlannerNavigationRecorder()
        return PlannerViewModel(
            accountID: accountID,
            language: .ru,
            loader: loader,
            actionPerformer: performer,
            scrollState: scrollState ?? PlannerScrollStateController(
                persistence: PlannerViewModelScrollStore()
            ),
            onNavigate: recorder.receive
        )
    }

    private func waitForLoads(_ count: Int, loader: ControlledPlannerLoader) async {
        for _ in 0..<200 {
            if await loader.count() >= count { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(count) planner loads")
    }

    private func waitForActions(_ count: Int, performer: ControlledPlannerActionStub) async {
        for _ in 0..<200 {
            if await performer.count() >= count { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(count) planner actions")
    }

    private func viewport(absoluteY: Double) -> PlannerScrollViewport {
        PlannerScrollViewport(
            absoluteY: absoluteY,
            maximumOffsetY: 500,
            contentHeight: 800,
            viewportHeight: 300
        )
    }

    private func scrollRows(offset: Double = 0) -> [PlannerScrollRowGeometry] {
        let folder = PlannerScrollAnchor(
            resourceType: .folder,
            resourceID: PlannerTestFixtures.folderID
        )
        let goal = PlannerScrollAnchor(
            resourceType: .goal,
            resourceID: PlannerTestFixtures.goalID
        )
        return [
            PlannerScrollRowGeometry(
                anchor: folder,
                minY: offset,
                maxY: offset + 44
            ),
            PlannerScrollRowGeometry(
                anchor: goal,
                parentAnchor: folder,
                minY: offset + 44,
                maxY: offset + 88
            ),
            PlannerScrollRowGeometry(
                anchor: PlannerScrollAnchor(
                    resourceType: .task,
                    resourceID: PlannerTestFixtures.taskID
                ),
                parentAnchor: goal,
                minY: offset + 88,
                maxY: offset + 132
            )
        ]
    }
}
