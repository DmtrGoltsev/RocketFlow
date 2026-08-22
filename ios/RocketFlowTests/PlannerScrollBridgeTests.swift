import XCTest
@testable import RocketFlow

final class PlannerScrollBridgeTests: XCTestCase {
    func testViewportUsesAdjustedInsetsAndExactPixelOffset() {
        let viewport = PlannerScrollViewGeometry.viewport(
            nativeContentOffsetY: 300,
            adjustedTopInset: 20,
            adjustedBottomInset: 10,
            contentHeight: 1_000,
            viewportHeight: 200
        )

        XCTAssertEqual(viewport.absoluteY, 320)
        XCTAssertEqual(viewport.maximumOffsetY, 830)
        XCTAssertEqual(viewport.contentHeight, 1_000)
        XCTAssertEqual(viewport.viewportHeight, 200)
    }

    func testViewportClampsBounceOffsetsToScrollableRange() {
        let aboveTop = PlannerScrollViewGeometry.viewport(
            nativeContentOffsetY: -100,
            adjustedTopInset: 20,
            adjustedBottomInset: 10,
            contentHeight: 1_000,
            viewportHeight: 200
        )
        let belowBottom = PlannerScrollViewGeometry.viewport(
            nativeContentOffsetY: 1_000,
            adjustedTopInset: 20,
            adjustedBottomInset: 10,
            contentHeight: 1_000,
            viewportHeight: 200
        )

        XCTAssertEqual(aboveTop.absoluteY, 0)
        XCTAssertEqual(belowBottom.absoluteY, 830)
    }

    func testViewportHasZeroMaximumWhenContentIsShorterThanBounds() {
        let viewport = PlannerScrollViewGeometry.viewport(
            nativeContentOffsetY: 40,
            adjustedTopInset: 0,
            adjustedBottomInset: 0,
            contentHeight: 100,
            viewportHeight: 200
        )

        XCTAssertEqual(viewport.absoluteY, 0)
        XCTAssertEqual(viewport.maximumOffsetY, 0)
    }

    func testReadinessKeepsRequestPendingWhileContentGrowsThenAppliesExactTarget() {
        let request = PlannerScrollRestorationRequest(
            absoluteY: 500,
            readinessPolicy: PlannerScrollRestorationReadinessPolicy(
                requiredStablePasses: 2,
                minimumFallbackPasses: 5,
                maximumWaitPasses: 7
            )
        )
        var tracker = PlannerScrollRestorationReadinessTracker(request: request)
        let earlyPartialLayout = viewport(maximum: 100, contentHeight: 300)

        XCTAssertEqual(
            tracker.evaluate(viewport: earlyPartialLayout),
            .wait
        )
        XCTAssertEqual(
            tracker.evaluate(viewport: earlyPartialLayout),
            .wait
        )
        XCTAssertEqual(
            tracker.evaluate(viewport: viewport(maximum: 300, contentHeight: 500)),
            .wait
        )
        XCTAssertEqual(
            tracker.evaluate(viewport: viewport(maximum: 520, contentHeight: 720)),
            .applyTarget(500)
        )
    }

    func testReadinessUsesExplicitBoundedFallbackOnlyAfterStablePassBudget() {
        let request = PlannerScrollRestorationRequest(
            absoluteY: 500,
            readinessPolicy: PlannerScrollRestorationReadinessPolicy(
                requiredStablePasses: 2,
                minimumFallbackPasses: 3,
                maximumWaitPasses: 5
            )
        )
        var tracker = PlannerScrollRestorationReadinessTracker(request: request)
        let shortContent = viewport(maximum: 120, contentHeight: 320)

        XCTAssertEqual(tracker.evaluate(viewport: shortContent), .wait)
        XCTAssertEqual(tracker.evaluate(viewport: shortContent), .wait)
        XCTAssertEqual(
            tracker.evaluate(viewport: shortContent),
            .applyBoundedFallback(120)
        )
    }

    func testReadinessWaitsUntilExactTargetIsReachable() {
        let request = PlannerScrollRestorationRequest(
            absoluteY: 500,
            readinessPolicy: PlannerScrollRestorationReadinessPolicy(
                requiredStablePasses: 2,
                minimumFallbackPasses: 4,
                maximumWaitPasses: 6,
                geometryTolerance: 1
            )
        )
        var tracker = PlannerScrollRestorationReadinessTracker(request: request)

        XCTAssertEqual(
            tracker.evaluate(viewport: viewport(maximum: 499.5, contentHeight: 699.5)),
            .wait
        )
        XCTAssertEqual(
            tracker.evaluate(viewport: viewport(maximum: 500, contentHeight: 700)),
            .applyTarget(500)
        )
    }

    private func viewport(maximum: Double, contentHeight: Double) -> PlannerScrollViewport {
        PlannerScrollViewport(
            absoluteY: 0,
            maximumOffsetY: maximum,
            contentHeight: contentHeight,
            viewportHeight: 200
        )
    }
}
