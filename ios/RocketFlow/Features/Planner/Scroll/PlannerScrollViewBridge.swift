import SwiftUI
import UIKit

enum PlannerScrollCoordinateSpace {
    static let name = "rocketflow.planner.scroll.content"
}

struct PlannerScrollRowPreference: Equatable {
    let anchor: PlannerScrollAnchor
    let parentAnchor: PlannerScrollAnchor?
    let frame: CGRect
}

private struct PlannerScrollRowsPreferenceKey: PreferenceKey {
    static let defaultValue: [PlannerScrollRowPreference] = []

    static func reduce(
        value: inout [PlannerScrollRowPreference],
        nextValue: () -> [PlannerScrollRowPreference]
    ) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func plannerScrollContentCoordinateSpace() -> some View {
        coordinateSpace(name: PlannerScrollCoordinateSpace.name)
    }

    func plannerScrollRow(
        _ anchor: PlannerScrollAnchor,
        parentAnchor: PlannerScrollAnchor? = nil
    ) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PlannerScrollRowsPreferenceKey.self,
                    value: [
                        PlannerScrollRowPreference(
                            anchor: anchor,
                            parentAnchor: parentAnchor,
                            frame: proxy.frame(in: .named(PlannerScrollCoordinateSpace.name))
                        )
                    ]
                )
            }
        }
    }

    func onPlannerScrollRowsChange(
        perform action: @escaping ([PlannerScrollRowGeometry]) -> Void
    ) -> some View {
        onPreferenceChange(PlannerScrollRowsPreferenceKey.self) { preferences in
            let rows = preferences.map {
                PlannerScrollRowGeometry(
                    anchor: $0.anchor,
                    parentAnchor: $0.parentAnchor,
                    minY: Double($0.frame.minY),
                    maxY: Double($0.frame.maxY)
                )
            }
            action(rows)
        }
    }
}

struct PlannerScrollViewBridge: UIViewRepresentable {
    let restorationRequest: PlannerScrollRestorationRequest?
    let onViewportChange: @MainActor (PlannerScrollViewport) -> Void

    init(
        restorationRequest: PlannerScrollRestorationRequest? = nil,
        onViewportChange: @escaping @MainActor (PlannerScrollViewport) -> Void
    ) {
        self.restorationRequest = restorationRequest
        self.onViewportChange = onViewportChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onViewportChange: onViewportChange)
    }

    func makeUIView(context: Context) -> PlannerScrollProbeView {
        let view = PlannerScrollProbeView()
        view.isUserInteractionEnabled = false
        view.onHierarchyChange = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.attach(to: view.enclosingScrollView)
        }
        return view
    }

    func updateUIView(_ uiView: PlannerScrollProbeView, context: Context) {
        context.coordinator.onViewportChange = onViewportChange
        context.coordinator.attach(to: uiView.enclosingScrollView)
        context.coordinator.apply(restorationRequest)
    }

    static func dismantleUIView(_ uiView: PlannerScrollProbeView, coordinator: Coordinator) {
        uiView.onHierarchyChange = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onViewportChange: @MainActor (PlannerScrollViewport) -> Void

        private weak var scrollView: UIScrollView?
        private var observations: [NSKeyValueObservation] = []
        private var lastAppliedRequestID: UUID?
        private var pendingRestorationRequest: PlannerScrollRestorationRequest?
        private var readinessTracker: PlannerScrollRestorationReadinessTracker?
        private var reevaluationTask: Task<Void, Never>?
        private var reevaluationID: UUID?

        private static let reevaluationDelayNanoseconds: UInt64 = 50_000_000

        init(onViewportChange: @escaping @MainActor (PlannerScrollViewport) -> Void) {
            self.onViewportChange = onViewportChange
        }

        func attach(to candidate: UIScrollView?) {
            guard scrollView !== candidate else {
                publishViewport()
                return
            }

            detach()
            guard let candidate else { return }
            scrollView = candidate
            observations = [
                candidate.observe(\.contentOffset, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor in self?.publishViewport() }
                },
                candidate.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor in self?.publishViewport() }
                },
                candidate.observe(\.bounds, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor in self?.publishViewport() }
                },
                candidate.observe(\.adjustedContentInset, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor in self?.publishViewport() }
                }
            ]
        }

        func apply(_ request: PlannerScrollRestorationRequest?) {
            guard let request else {
                cancelScheduledReevaluation()
                pendingRestorationRequest = nil
                readinessTracker = nil
                return
            }
            guard request.id != lastAppliedRequestID else { return }
            if pendingRestorationRequest != request {
                cancelScheduledReevaluation()
                readinessTracker = PlannerScrollRestorationReadinessTracker(request: request)
            }
            pendingRestorationRequest = request
            applyPendingRestorationIfPossible()
        }

        func detach() {
            cancelScheduledReevaluation()
            observations.removeAll()
            scrollView = nil
            if let pendingRestorationRequest {
                readinessTracker = PlannerScrollRestorationReadinessTracker(
                    request: pendingRestorationRequest
                )
            } else {
                readinessTracker = nil
            }
        }

        private func publishViewport() {
            guard let scrollView else { return }
            applyPendingRestorationIfPossible()
            onViewportChange(PlannerScrollViewGeometry.viewport(for: scrollView))
        }

        private func applyPendingRestorationIfPossible() {
            guard
                reevaluationTask == nil,
                let request = pendingRestorationRequest,
                request.id != lastAppliedRequestID,
                let scrollView,
                scrollView.bounds.height > 0
            else {
                return
            }

            scrollView.layoutIfNeeded()
            let viewport = PlannerScrollViewGeometry.viewport(for: scrollView)
            var tracker = readinessTracker
                ?? PlannerScrollRestorationReadinessTracker(request: request)
            let decision = tracker.evaluate(viewport: viewport)
            readinessTracker = tracker

            switch decision {
            case .wait:
                scheduleReevaluation()
            case let .applyTarget(absoluteY), let .applyBoundedFallback(absoluteY):
                let nativeY = absoluteY - Double(scrollView.adjustedContentInset.top)
                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: nativeY),
                    animated: false
                )
                self.lastAppliedRequestID = request.id
                self.pendingRestorationRequest = nil
                self.readinessTracker = nil
                self.onViewportChange(PlannerScrollViewGeometry.viewport(for: scrollView))
            }
        }

        private func scheduleReevaluation() {
            guard reevaluationTask == nil else { return }
            let id = UUID()
            reevaluationID = id
            reevaluationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: Self.reevaluationDelayNanoseconds)
                guard let self, !Task.isCancelled, self.reevaluationID == id else { return }
                self.reevaluationTask = nil
                self.reevaluationID = nil
                self.applyPendingRestorationIfPossible()
            }
        }

        private func cancelScheduledReevaluation() {
            reevaluationID = nil
            reevaluationTask?.cancel()
            reevaluationTask = nil
        }
    }
}

final class PlannerScrollProbeView: UIView {
    var onHierarchyChange: (() -> Void)?

    var enclosingScrollView: UIScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        onHierarchyChange?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onHierarchyChange?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onHierarchyChange?()
    }

    override var intrinsicContentSize: CGSize {
        .zero
    }
}

enum PlannerScrollViewGeometry {
    @MainActor
    static func viewport(for scrollView: UIScrollView) -> PlannerScrollViewport {
        viewport(
            nativeContentOffsetY: Double(scrollView.contentOffset.y),
            adjustedTopInset: Double(scrollView.adjustedContentInset.top),
            adjustedBottomInset: Double(scrollView.adjustedContentInset.bottom),
            contentHeight: Double(scrollView.contentSize.height),
            viewportHeight: Double(scrollView.bounds.height)
        )
    }

    static func viewport(
        nativeContentOffsetY: Double,
        adjustedTopInset: Double,
        adjustedBottomInset: Double,
        contentHeight: Double,
        viewportHeight: Double
    ) -> PlannerScrollViewport {
        let topInset = max(0, adjustedTopInset)
        let bottomInset = max(0, adjustedBottomInset)
        let height = max(0, contentHeight)
        let visibleHeight = max(0, viewportHeight)
        let maximum = max(0, height + topInset + bottomInset - visibleHeight)
        let absoluteY = min(max(0, nativeContentOffsetY + topInset), maximum)
        return PlannerScrollViewport(
            absoluteY: absoluteY,
            maximumOffsetY: maximum,
            contentHeight: height,
            viewportHeight: visibleHeight
        )
    }
}
