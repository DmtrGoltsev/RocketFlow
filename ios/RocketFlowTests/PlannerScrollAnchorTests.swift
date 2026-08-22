import Foundation
import XCTest
@testable import RocketFlow

final class PlannerScrollAnchorTests: XCTestCase {
    private let folder = PlannerScrollAnchor(
        resourceType: .folder,
        resourceID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    )
    private let goal = PlannerScrollAnchor(
        resourceType: .goal,
        resourceID: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    )
    private let task = PlannerScrollAnchor(
        resourceType: .task,
        resourceID: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    )

    func testCaptureStoresExactRowAncestorsAndPixelOffset() {
        let position = PlannerScrollAnchorResolver.capture(
            rows: hierarchyRows(),
            absoluteY: 100,
            expandedFolderIDs: [folder.resourceID],
            expandedGoalIDs: [goal.resourceID]
        )

        XCTAssertEqual(position.anchor, task)
        XCTAssertEqual(position.ancestorChain, [goal, folder])
        XCTAssertEqual(position.pixelOffset, 12)
        XCTAssertEqual(position.absoluteY, 100)
        XCTAssertEqual(position.expandedFolderIDs, [folder.resourceID])
        XCTAssertEqual(position.expandedGoalIDs, [goal.resourceID])
    }

    func testExactAnchorPreservesPixelPositionAfterInsertionAbove() {
        let position = PlannerScrollAnchorResolver.capture(
            rows: hierarchyRows(),
            absoluteY: 100,
            expandedFolderIDs: [],
            expandedGoalIDs: []
        )
        let shiftedRows = hierarchyRows(offset: 60)

        let restored = PlannerScrollAnchorResolver.restore(
            position,
            rows: shiftedRows,
            maximumOffsetY: 500
        )

        XCTAssertEqual(restored.absoluteY, 160)
        XCTAssertEqual(restored.source, .exact(task))
    }

    func testDeletedAnchorFallsBackToNearestVisibleAncestor() {
        let position = PlannerScrollAnchorResolver.capture(
            rows: hierarchyRows(),
            absoluteY: 100,
            expandedFolderIDs: [],
            expandedGoalIDs: []
        )
        let visibleRows = Array(hierarchyRows().prefix(2))

        let restored = PlannerScrollAnchorResolver.restore(
            position,
            rows: visibleRows,
            maximumOffsetY: 500
        )

        XCTAssertEqual(restored.absoluteY, 56)
        XCTAssertEqual(restored.source, .ancestor(goal))
    }

    func testMissingAnchorAndAncestorsFallBackToClampedAbsoluteOffset() {
        let position = PlannerScrollPosition(
            anchor: task,
            ancestorChain: [goal, folder],
            pixelOffset: 12,
            absoluteY: 100
        )

        let restored = PlannerScrollAnchorResolver.restore(
            position,
            rows: [],
            maximumOffsetY: 70
        )

        XCTAssertEqual(restored.absoluteY, 70)
        XCTAssertEqual(restored.source, .absoluteY)
    }

    func testRestorationClampsExactAnchorToBothBounds() {
        let belowTop = PlannerScrollPosition(anchor: task, pixelOffset: -80, absoluteY: 0)
        let aboveBottom = PlannerScrollPosition(anchor: task, pixelOffset: 500, absoluteY: 500)
        let rows = [PlannerScrollRowGeometry(anchor: task, minY: 40, maxY: 84)]

        XCTAssertEqual(
            PlannerScrollAnchorResolver.restore(
                belowTop,
                rows: rows,
                maximumOffsetY: 120
            ).absoluteY,
            0
        )
        XCTAssertEqual(
            PlannerScrollAnchorResolver.restore(
                aboveBottom,
                rows: rows,
                maximumOffsetY: 120
            ).absoluteY,
            120
        )
    }

    func testEmptyPositionRestoresTop() {
        let restored = PlannerScrollAnchorResolver.restore(
            nil,
            rows: hierarchyRows(),
            maximumOffsetY: 500
        )

        XCTAssertEqual(restored, PlannerScrollRestoration(absoluteY: 0, source: .top))
    }

    func testDesiredRestorationKeepsExactTargetBeyondCurrentViewportMaximum() {
        let position = PlannerScrollPosition(
            anchor: task,
            pixelOffset: 12,
            absoluteY: 100
        )
        let shiftedRows = hierarchyRows(offset: 500)

        let desired = PlannerScrollAnchorResolver.desiredRestoration(
            position,
            rows: shiftedRows
        )
        let currentlyClamped = PlannerScrollAnchorResolver.restore(
            position,
            rows: shiftedRows,
            maximumOffsetY: 200
        )

        XCTAssertEqual(desired.absoluteY, 600)
        XCTAssertEqual(desired.source, .exact(task))
        XCTAssertEqual(currentlyClamped.absoluteY, 200)
    }

    private func hierarchyRows(offset: Double = 0) -> [PlannerScrollRowGeometry] {
        [
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
                anchor: task,
                parentAnchor: goal,
                minY: offset + 88,
                maxY: offset + 132
            )
        ]
    }
}
