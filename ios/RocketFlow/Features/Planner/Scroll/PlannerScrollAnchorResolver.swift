import Foundation

enum PlannerScrollAnchorResolver {
    static func capture(
        rows: [PlannerScrollRowGeometry],
        absoluteY: Double,
        expandedFolderIDs: Set<UUID>,
        expandedGoalIDs: Set<UUID>
    ) -> PlannerScrollPosition {
        let clampedY = max(0, absoluteY)
        let orderedRows = rows.sorted(by: ordersBefore)
        guard let anchorRow = orderedRows.first(where: { $0.maxY > clampedY })
            ?? orderedRows.last else {
            return PlannerScrollPosition(
                absoluteY: clampedY,
                expandedFolderIDs: expandedFolderIDs,
                expandedGoalIDs: expandedGoalIDs
            )
        }

        let rowsByAnchor = Dictionary(
            orderedRows.map { ($0.anchor, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var ancestors: [PlannerScrollAnchor] = []
        var visited: Set<PlannerScrollAnchor> = []
        var parent = anchorRow.parentAnchor
        while let current = parent, visited.insert(current).inserted {
            ancestors.append(current)
            parent = rowsByAnchor[current]?.parentAnchor
        }

        return PlannerScrollPosition(
            anchor: anchorRow.anchor,
            ancestorChain: ancestors,
            pixelOffset: clampedY - anchorRow.minY,
            absoluteY: clampedY,
            expandedFolderIDs: expandedFolderIDs,
            expandedGoalIDs: expandedGoalIDs
        )
    }

    static func restore(
        _ position: PlannerScrollPosition?,
        rows: [PlannerScrollRowGeometry],
        maximumOffsetY: Double
    ) -> PlannerScrollRestoration {
        let maximum = max(0, maximumOffsetY)
        let desired = desiredRestoration(position, rows: rows)
        return PlannerScrollRestoration(
            absoluteY: clamp(desired.absoluteY, maximum: maximum),
            source: desired.source
        )
    }

    static func desiredRestoration(
        _ position: PlannerScrollPosition?,
        rows: [PlannerScrollRowGeometry]
    ) -> PlannerScrollRestoration {
        guard let position else {
            return PlannerScrollRestoration(absoluteY: 0, source: .top)
        }
        let rowsByAnchor = Dictionary(
            rows.map { ($0.anchor, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        if let anchor = position.anchor, let row = rowsByAnchor[anchor] {
            return PlannerScrollRestoration(
                absoluteY: max(0, row.minY + position.pixelOffset),
                source: .exact(anchor)
            )
        }
        for ancestor in position.ancestorChain {
            if let row = rowsByAnchor[ancestor] {
                return PlannerScrollRestoration(
                    absoluteY: max(0, row.minY + position.pixelOffset),
                    source: .ancestor(ancestor)
                )
            }
        }
        return PlannerScrollRestoration(
            absoluteY: max(0, position.absoluteY),
            source: .absoluteY
        )
    }

    private static func ordersBefore(
        _ lhs: PlannerScrollRowGeometry,
        _ rhs: PlannerScrollRowGeometry
    ) -> Bool {
        if lhs.minY != rhs.minY { return lhs.minY < rhs.minY }
        if lhs.maxY != rhs.maxY { return lhs.maxY < rhs.maxY }
        if lhs.anchor.resourceType.rawValue != rhs.anchor.resourceType.rawValue {
            return lhs.anchor.resourceType.rawValue < rhs.anchor.resourceType.rawValue
        }
        return lhs.anchor.resourceID.uuidString < rhs.anchor.resourceID.uuidString
    }

    private static func clamp(_ value: Double, maximum: Double) -> Double {
        min(max(0, value), maximum)
    }
}
