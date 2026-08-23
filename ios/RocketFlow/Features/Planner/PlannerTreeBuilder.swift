import Foundation

enum PlannerSectionKind: String, CaseIterable, Hashable, Sendable {
    case owned
    case shared
}

struct PlannerTreeRow: Equatable, Identifiable, Sendable {
    let item: PlannerItemViewData
    let depth: Int
    let hasChildren: Bool
    let isExpanded: Bool
    let visibleChildCount: Int

    var id: PlannerItemReference { item.reference }
    var scrollAnchor: PlannerScrollAnchor { item.reference.scrollAnchor }
    var parentScrollAnchor: PlannerScrollAnchor? { item.parent?.scrollAnchor }
}

struct PlannerTreeSection: Equatable, Identifiable, Sendable {
    let kind: PlannerSectionKind
    let rows: [PlannerTreeRow]

    var id: PlannerSectionKind { kind }
}

struct PlannerTree: Equatable, Sendable {
    let sections: [PlannerTreeSection]

    static let empty = PlannerTree(sections: [])

    var allRows: [PlannerTreeRow] { sections.flatMap(\.rows) }
    var isEmpty: Bool { allRows.isEmpty }
}

enum PlannerTreeBuilder {
    static func build(
        snapshot: PlannerSnapshot,
        expandedFolderIDs: Set<UUID>,
        expandedGoalIDs: Set<UUID>,
        searchQuery: String
    ) -> PlannerTree {
        let activeItems = snapshot.resolvedItems.filter { !$0.isArchived }
        let itemsByReference = Dictionary(
            activeItems.map { ($0.reference, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let normalizedQuery = normalize(searchQuery)
        let allowedReferences = visibleReferences(
            in: activeItems,
            itemsByReference: itemsByReference,
            normalizedQuery: normalizedQuery
        )

        let sections: [PlannerTreeSection] = PlannerSectionKind.allCases.compactMap {
            (sectionKind: PlannerSectionKind) -> PlannerTreeSection? in
            let shared = sectionKind == .shared
            let sectionItems = activeItems.filter {
                $0.isShared == shared && allowedReferences.contains($0.reference)
            }
            guard !sectionItems.isEmpty else { return nil }

            let sectionReferences = Set(sectionItems.map(\.reference))
            let childrenByParent = Dictionary(
                grouping: sectionItems.filter { item in
                    guard let parent = item.parent else { return false }
                    return sectionReferences.contains(parent)
                },
                by: { $0.parent! }
            )
            let roots = sorted(
                sectionItems.filter { item in
                    guard let parent = item.parent else { return true }
                    return !sectionReferences.contains(parent)
                }
            )
            let structurallyReachable = structurallyReachableReferences(
                from: roots,
                childrenByParent: childrenByParent
            )

            var rows: [PlannerTreeRow] = []
            var emitted: Set<PlannerItemReference> = []
            for root in roots {
                append(
                    root,
                    depth: 0,
                    normalizedQuery: normalizedQuery,
                    childrenByParent: childrenByParent,
                    expandedFolderIDs: expandedFolderIDs,
                    expandedGoalIDs: expandedGoalIDs,
                    emitted: &emitted,
                    rows: &rows
                )
            }

            // Corrupt or cyclic parent references must not make accessible items disappear.
            for orphan in sorted(sectionItems.filter { !structurallyReachable.contains($0.reference) }) {
                append(
                    orphan,
                    depth: 0,
                    normalizedQuery: normalizedQuery,
                    childrenByParent: childrenByParent,
                    expandedFolderIDs: expandedFolderIDs,
                    expandedGoalIDs: expandedGoalIDs,
                    emitted: &emitted,
                    rows: &rows
                )
            }
            return PlannerTreeSection(kind: sectionKind, rows: rows)
        }
        return PlannerTree(sections: sections)
    }

    private static func append(
        _ item: PlannerItemViewData,
        depth: Int,
        normalizedQuery: String,
        childrenByParent: [PlannerItemReference: [PlannerItemViewData]],
        expandedFolderIDs: Set<UUID>,
        expandedGoalIDs: Set<UUID>,
        emitted: inout Set<PlannerItemReference>,
        rows: inout [PlannerTreeRow]
    ) {
        guard emitted.insert(item.reference).inserted else { return }
        let children = sorted(childrenByParent[item.reference] ?? [])
        let supportsExpansion = item.reference.kind == .folder || item.reference.kind == .goal
        let explicitlyExpanded: Bool
        switch item.reference.kind {
        case .folder:
            explicitlyExpanded = expandedFolderIDs.contains(item.reference.id)
        case .goal:
            explicitlyExpanded = expandedGoalIDs.contains(item.reference.id)
        case .task, .idea, .note:
            explicitlyExpanded = false
        }
        let expanded = supportsExpansion
            && !children.isEmpty
            && (!normalizedQuery.isEmpty || explicitlyExpanded)
        rows.append(
            PlannerTreeRow(
                item: item,
                depth: depth,
                hasChildren: supportsExpansion && !children.isEmpty,
                isExpanded: expanded,
                visibleChildCount: children.count
            )
        )
        guard expanded else { return }
        for child in children {
            append(
                child,
                depth: depth + 1,
                normalizedQuery: normalizedQuery,
                childrenByParent: childrenByParent,
                expandedFolderIDs: expandedFolderIDs,
                expandedGoalIDs: expandedGoalIDs,
                emitted: &emitted,
                rows: &rows
            )
        }
    }

    private static func structurallyReachableReferences(
        from roots: [PlannerItemViewData],
        childrenByParent: [PlannerItemReference: [PlannerItemViewData]]
    ) -> Set<PlannerItemReference> {
        var reachable: Set<PlannerItemReference> = []
        var pending = roots
        while let item = pending.popLast() {
            guard reachable.insert(item.reference).inserted else { continue }
            guard item.reference.kind == .folder || item.reference.kind == .goal else { continue }
            pending.append(contentsOf: childrenByParent[item.reference] ?? [])
        }
        return reachable
    }

    private static func visibleReferences(
        in items: [PlannerItemViewData],
        itemsByReference: [PlannerItemReference: PlannerItemViewData],
        normalizedQuery: String
    ) -> Set<PlannerItemReference> {
        guard !normalizedQuery.isEmpty else { return Set(items.map(\.reference)) }
        var visible: Set<PlannerItemReference> = []
        for item in items where matches(item, normalizedQuery: normalizedQuery) {
            var candidate: PlannerItemViewData? = item
            var visited: Set<PlannerItemReference> = []
            while let current = candidate, visited.insert(current.reference).inserted {
                visible.insert(current.reference)
                candidate = current.parent.flatMap { itemsByReference[$0] }
            }
        }
        return visible
    }

    private static func matches(
        _ item: PlannerItemViewData,
        normalizedQuery: String
    ) -> Bool {
        normalize("\(item.title) \(item.subtitle) \(item.searchText)")
            .contains(normalizedQuery)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sorted(_ items: [PlannerItemViewData]) -> [PlannerItemViewData] {
        items.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.reference.id.uuidString.lowercased()
                > rhs.reference.id.uuidString.lowercased()
        }
    }
}
