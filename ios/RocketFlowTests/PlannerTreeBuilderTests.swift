import Foundation
import XCTest
@testable import RocketFlow

final class PlannerTreeBuilderTests: XCTestCase {
    func testBuildsExpandedOwnedAndSharedSections() {
        let owned = PlannerTestFixtures.hierarchy()
        let sharedFolderID = UUID(uuidString: "60000000-0000-0000-0000-000000000006")!
        let sharedNoteID = UUID(uuidString: "70000000-0000-0000-0000-000000000007")!
        let sharedFolder = PlannerTestFixtures.item(
            kind: .folder,
            id: sharedFolderID,
            title: "Общая папка",
            createdAt: 600,
            shared: true,
            fullAccess: false
        )
        let sharedNote = PlannerTestFixtures.item(
            kind: .note,
            id: sharedNoteID,
            parent: sharedFolder.reference,
            title: "Общая заметка",
            createdAt: 700,
            shared: true,
            fullAccess: false
        )

        let tree = PlannerTreeBuilder.build(
            snapshot: PlannerSnapshot(items: owned + [sharedFolder, sharedNote]),
            expandedFolderIDs: [PlannerTestFixtures.folderID, sharedFolderID],
            expandedGoalIDs: [PlannerTestFixtures.goalID],
            searchQuery: ""
        )

        XCTAssertEqual(tree.sections.map(\.kind), [.owned, .shared])
        XCTAssertEqual(
            tree.sections[0].rows.map { $0.item.reference.kind },
            [.folder, .note, .idea, .goal, .task]
        )
        XCTAssertEqual(tree.sections[0].rows.map(\.depth), [0, 1, 1, 1, 2])
        XCTAssertEqual(tree.sections[1].rows.map { $0.item.reference.id }, [sharedFolderID, sharedNoteID])
    }

    func testCollapsedFolderHidesDescendants() {
        let tree = PlannerTreeBuilder.build(
            snapshot: PlannerTestFixtures.snapshot,
            expandedFolderIDs: [],
            expandedGoalIDs: [PlannerTestFixtures.goalID],
            searchQuery: ""
        )

        XCTAssertEqual(tree.allRows.map { $0.item.reference.id }, [PlannerTestFixtures.folderID])
        XCTAssertTrue(tree.allRows[0].hasChildren)
        XCTAssertFalse(tree.allRows[0].isExpanded)
    }

    func testCollapsedFolderKeepsNestedDescendantsHiddenInsteadOfRecoveringThemAsOrphans() {
        let root = PlannerTestFixtures.item(
            kind: .folder,
            id: PlannerTestFixtures.folderID,
            title: "Root",
            createdAt: 100
        )
        let childFolderID = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
        let childFolder = PlannerTestFixtures.item(
            kind: .folder,
            id: childFolderID,
            parent: root.reference,
            title: "Child",
            createdAt: 200
        )
        let goal = PlannerTestFixtures.item(
            kind: .goal,
            id: PlannerTestFixtures.goalID,
            parent: childFolder.reference,
            title: "Goal",
            createdAt: 300
        )
        let task = PlannerTestFixtures.item(
            kind: .task,
            id: PlannerTestFixtures.taskID,
            parent: goal.reference,
            title: "Task",
            status: .todo,
            createdAt: 400
        )

        let tree = PlannerTreeBuilder.build(
            snapshot: PlannerSnapshot(items: [root, childFolder, goal, task]),
            expandedFolderIDs: [childFolderID],
            expandedGoalIDs: [PlannerTestFixtures.goalID],
            searchQuery: ""
        )

        XCTAssertEqual(tree.allRows.map { $0.item.reference }, [root.reference])
    }

    func testCycleRecoveryKeepsAccessibleItemsVisible() {
        let firstID = UUID(uuidString: "61000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "61000000-0000-0000-0000-000000000002")!
        let firstReference = PlannerItemReference(kind: .folder, id: firstID)
        let secondReference = PlannerItemReference(kind: .folder, id: secondID)
        let first = PlannerTestFixtures.item(
            kind: .folder,
            id: firstID,
            parent: secondReference,
            title: "First",
            createdAt: 100
        )
        let second = PlannerTestFixtures.item(
            kind: .folder,
            id: secondID,
            parent: firstReference,
            title: "Second",
            createdAt: 200
        )

        let tree = PlannerTreeBuilder.build(
            snapshot: PlannerSnapshot(items: [first, second]),
            expandedFolderIDs: [firstID, secondID],
            expandedGoalIDs: [],
            searchQuery: ""
        )

        XCTAssertEqual(
            Set(tree.allRows.map { $0.item.reference }),
            Set([firstReference, secondReference])
        )
        XCTAssertEqual(tree.allRows.count, 2)
    }

    func testSortsEverySiblingNewestFirstWithDescendingStableIDTieBreak() {
        let folder = PlannerTestFixtures.hierarchy()[0]
        let lowerID = UUID(uuidString: "80000000-0000-0000-0000-000000000001")!
        let higherID = UUID(uuidString: "80000000-0000-0000-0000-000000000002")!
        let newestID = UUID(uuidString: "80000000-0000-0000-0000-000000000003")!
        let tiedLower = PlannerTestFixtures.item(
            kind: .note,
            id: lowerID,
            parent: folder.reference,
            title: "Lower",
            createdAt: 200
        )
        let tiedHigher = PlannerTestFixtures.item(
            kind: .idea,
            id: higherID,
            parent: folder.reference,
            title: "Higher",
            createdAt: 200
        )
        let newest = PlannerTestFixtures.item(
            kind: .goal,
            id: newestID,
            parent: folder.reference,
            title: "Newest",
            createdAt: 300
        )

        let tree = PlannerTreeBuilder.build(
            snapshot: PlannerSnapshot(items: [folder, tiedLower, tiedHigher, newest]),
            expandedFolderIDs: [folder.reference.id],
            expandedGoalIDs: [],
            searchQuery: ""
        )

        XCTAssertEqual(
            tree.allRows.dropFirst().map { $0.item.reference.id },
            [newestID, higherID, lowerID]
        )
    }

    func testSearchFindsEachSupportedKindAndRetainsAncestorPath() {
        let cases: [(String, [PlannerItemKind])] = [
            ("работа", [.folder]),
            ("выпустить", [.folder, .goal]),
            ("сборку", [.folder, .goal, .task]),
            ("интерфейса", [.folder, .idea]),
            ("локализацию", [.folder, .note])
        ]

        for (query, expectedKinds) in cases {
            let tree = PlannerTreeBuilder.build(
                snapshot: PlannerTestFixtures.snapshot,
                expandedFolderIDs: [],
                expandedGoalIDs: [],
                searchQuery: query
            )
            XCTAssertEqual(
                tree.allRows.map { $0.item.reference.kind },
                expectedKinds,
                "Unexpected path for query \(query)"
            )
        }
    }

    func testSearchIsCaseAndDiacriticInsensitive() {
        let item = PlannerTestFixtures.item(
            kind: .folder,
            id: UUID(),
            title: "Café Launch",
            createdAt: 100
        )

        let tree = PlannerTreeBuilder.build(
            snapshot: PlannerSnapshot(items: [item]),
            expandedFolderIDs: [],
            expandedGoalIDs: [],
            searchQuery: "CAFE"
        )

        XCTAssertEqual(tree.allRows.map { $0.item.reference }, [item.reference])
    }

    func testArchivedItemsAreExcludedAndMissingParentsBecomeRoots() {
        let archivedFolder = PlannerTestFixtures.item(
            kind: .folder,
            id: PlannerTestFixtures.folderID,
            title: "Archive",
            createdAt: 100,
            archived: true
        )
        let orphan = PlannerTestFixtures.item(
            kind: .task,
            id: PlannerTestFixtures.taskID,
            parent: PlannerItemReference(kind: .goal, id: PlannerTestFixtures.goalID),
            title: "Accessible direct share",
            status: .todo,
            createdAt: 200,
            shared: true,
            fullAccess: false
        )

        let tree = PlannerTreeBuilder.build(
            snapshot: PlannerSnapshot(items: [archivedFolder, orphan]),
            expandedFolderIDs: [],
            expandedGoalIDs: [],
            searchQuery: ""
        )

        XCTAssertEqual(tree.sections.map(\.kind), [.shared])
        XCTAssertEqual(tree.allRows.map { $0.item.reference }, [orphan.reference])
        XCTAssertEqual(tree.allRows[0].depth, 0)
    }

    func testRowsExposeStableScrollKeysAndParentAnchors() {
        let tree = PlannerTreeBuilder.build(
            snapshot: PlannerTestFixtures.snapshot,
            expandedFolderIDs: [PlannerTestFixtures.folderID],
            expandedGoalIDs: [PlannerTestFixtures.goalID],
            searchQuery: ""
        )
        let task = try! XCTUnwrap(
            tree.allRows.first { $0.item.reference.kind == .task }
        )

        XCTAssertEqual(task.scrollAnchor.resourceType, .task)
        XCTAssertEqual(task.scrollAnchor.resourceID, PlannerTestFixtures.taskID)
        XCTAssertEqual(task.parentScrollAnchor?.resourceType, .goal)
        XCTAssertEqual(task.parentScrollAnchor?.resourceID, PlannerTestFixtures.goalID)
    }
}
