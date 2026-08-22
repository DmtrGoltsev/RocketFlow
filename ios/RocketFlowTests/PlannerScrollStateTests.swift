import Foundation
import XCTest
@testable import RocketFlow

private final class InMemoryPlannerScrollStateStore: PlannerScrollStatePersisting {
    private(set) var states: [UUID: PlannerScrollRestorableState] = [:]

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
final class PlannerScrollStateTests: XCTestCase {
    private let accountA = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private let accountB = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private let folderID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let goalID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let taskID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

    func testEveryIntegrationCaptureReasonUpdatesWithoutResettingState() {
        let store = InMemoryPlannerScrollStateStore()
        let controller = PlannerScrollStateController(persistence: store)
        controller.activate(accountID: accountA)

        for (index, reason) in PlannerScrollCaptureReason.allCases.enumerated() {
            let absoluteY = Double(90 + index)
            controller.captureBefore(
                reason,
                rows: rows(),
                viewport: viewport(absoluteY: absoluteY),
                expandedFolderIDs: [folderID],
                expandedGoalIDs: [goalID]
            )

            XCTAssertEqual(controller.lastCaptureReason, reason)
            XCTAssertEqual(controller.position?.absoluteY, absoluteY)
            XCTAssertEqual(controller.activeAccountID, accountA)
        }
    }

    func testExpandedStateSurvivesPersistenceAndRestoration() {
        let store = InMemoryPlannerScrollStateStore()
        let source = PlannerScrollStateController(persistence: store)
        source.activate(accountID: accountA)
        source.captureBefore(
            .expandCollapse,
            rows: rows(),
            viewport: viewport(absoluteY: 100),
            expandedFolderIDs: [folderID],
            expandedGoalIDs: [goalID]
        )

        let restored = PlannerScrollStateController(persistence: store)
        restored.activate(accountID: accountA)

        XCTAssertEqual(restored.position?.expandedFolderIDs, [folderID])
        XCTAssertEqual(restored.position?.expandedGoalIDs, [goalID])
        XCTAssertEqual(
            restored.restoration(rows: rows(offset: 40), viewport: viewport()).absoluteY,
            140
        )
    }

    func testExpandedStateCanBeUpdatedAfterCaptureWithoutLosingAnchor() {
        let controller = PlannerScrollStateController(
            persistence: InMemoryPlannerScrollStateStore()
        )
        controller.activate(accountID: accountA)
        controller.captureBefore(
            .expandCollapse,
            rows: rows(),
            viewport: viewport(absoluteY: 100),
            expandedFolderIDs: [],
            expandedGoalIDs: []
        )

        controller.updateExpandedState(folderIDs: [folderID], goalIDs: [goalID])

        XCTAssertEqual(controller.position?.anchor?.resourceID, taskID)
        XCTAssertEqual(controller.position?.pixelOffset, 12)
        XCTAssertEqual(controller.position?.expandedFolderIDs, [folderID])
        XCTAssertEqual(controller.position?.expandedGoalIDs, [goalID])
    }

    func testAccountScopedStoreDoesNotLeakPositionsAcrossAccounts() {
        let store = InMemoryPlannerScrollStateStore()
        let controller = PlannerScrollStateController(persistence: store)
        controller.activate(accountID: accountA)
        controller.captureBefore(
            .openDetail,
            rows: rows(),
            viewport: viewport(absoluteY: 100),
            expandedFolderIDs: [],
            expandedGoalIDs: []
        )

        XCTAssertNil(controller.activate(accountID: accountB))
        controller.captureBefore(
            .openEditor,
            rows: rows(),
            viewport: viewport(absoluteY: 50),
            expandedFolderIDs: [],
            expandedGoalIDs: []
        )

        XCTAssertEqual(controller.activate(accountID: accountA)?.absoluteY, 100)
        XCTAssertEqual(controller.activate(accountID: accountB)?.absoluteY, 50)
    }

    func testProcessStateRoundTripsCodableAndRejectsAnotherAccount() throws {
        let original = PlannerScrollRestorableState(
            accountID: accountA,
            position: PlannerScrollPosition(
                anchor: PlannerScrollAnchor(resourceType: .task, resourceID: taskID),
                ancestorChain: [PlannerScrollAnchor(resourceType: .goal, resourceID: goalID)],
                pixelOffset: 12,
                absoluteY: 100,
                expandedFolderIDs: [folderID],
                expandedGoalIDs: [goalID]
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlannerScrollRestorableState.self, from: data)
        let controller = PlannerScrollStateController(
            persistence: InMemoryPlannerScrollStateStore()
        )

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(controller.activate(accountID: accountA, processState: decoded), original.position)
        XCTAssertNil(controller.activate(accountID: accountB, processState: decoded))
    }

    func testUserDefaultsPersistenceIsAccountScoped() {
        let suiteName = "PlannerScrollStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PlannerScrollUserDefaultsStore(defaults: defaults, keyPrefix: "test.scroll")
        let position = PlannerScrollPosition(absoluteY: 123)

        store.save(PlannerScrollRestorableState(accountID: accountA, position: position))

        XCTAssertEqual(store.load(accountID: accountA)?.position, position)
        XCTAssertNil(store.load(accountID: accountB))
    }

    func testOnlyTypedResetReasonsClearPersistedState() {
        let store = InMemoryPlannerScrollStateStore()
        let controller = PlannerScrollStateController(persistence: store)
        controller.activate(accountID: accountA)
        controller.captureBefore(
            .background,
            rows: rows(),
            viewport: viewport(absoluteY: 100),
            expandedFolderIDs: [],
            expandedGoalIDs: []
        )

        controller.reset(.explicitTopLevelTabSwitch)

        XCTAssertEqual(controller.activeAccountID, accountA)
        XCTAssertNil(controller.position)
        XCTAssertNil(store.load(accountID: accountA))

        controller.captureBefore(
            .mutation,
            rows: rows(),
            viewport: viewport(absoluteY: 80),
            expandedFolderIDs: [],
            expandedGoalIDs: []
        )
        controller.reset(.logout)

        XCTAssertNil(controller.activeAccountID)
        XCTAssertNil(store.load(accountID: accountA))
    }

    func testRestorationRequestPreservesDesiredOffsetUntilContentCanReachIt() {
        let controller = PlannerScrollStateController(
            persistence: InMemoryPlannerScrollStateStore()
        )
        controller.activate(accountID: accountA)
        controller.captureBefore(
            .insertionAbove,
            rows: rows(),
            viewport: viewport(absoluteY: 100),
            expandedFolderIDs: [],
            expandedGoalIDs: []
        )
        let shiftedRows = rows(offset: 500)
        let partialViewport = PlannerScrollViewport(
            absoluteY: 0,
            maximumOffsetY: 200,
            contentHeight: 400,
            viewportHeight: 200
        )

        let request = controller.makeRestorationRequest(
            rows: shiftedRows,
            viewport: partialViewport
        )

        XCTAssertEqual(request.absoluteY, 600)
        XCTAssertEqual(
            controller.restoration(rows: shiftedRows, viewport: partialViewport).absoluteY,
            200
        )
    }

    private func rows(offset: Double = 0) -> [PlannerScrollRowGeometry] {
        let folder = PlannerScrollAnchor(resourceType: .folder, resourceID: folderID)
        let goal = PlannerScrollAnchor(resourceType: .goal, resourceID: goalID)
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
                anchor: PlannerScrollAnchor(resourceType: .task, resourceID: taskID),
                parentAnchor: goal,
                minY: offset + 88,
                maxY: offset + 132
            )
        ]
    }

    private func viewport(absoluteY: Double = 0) -> PlannerScrollViewport {
        PlannerScrollViewport(
            absoluteY: absoluteY,
            maximumOffsetY: 500,
            contentHeight: 800,
            viewportHeight: 300
        )
    }
}
