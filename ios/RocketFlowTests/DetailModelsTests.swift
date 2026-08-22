import Foundation
import XCTest
@testable import RocketFlow

enum DetailTestFixtures {
    static let folderID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let goalID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    static let taskID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    static let ideaID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
    static let noteID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!

    static func child(
        kind: DetailEntityKind,
        id: UUID,
        createdAt: TimeInterval
    ) -> DetailChildViewData {
        DetailChildViewData(
            reference: DetailEntityReference(kind: kind, id: id),
            title: kind.rawValue,
            subtitle: "",
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }

    static func folder(
        shared: Bool = false,
        fullAccess: Bool = true,
        parentFolderID: UUID? = nil,
        children: [DetailChildViewData] = []
    ) -> FolderDetailViewData {
        FolderDetailViewData(
            id: folderID,
            parentFolderID: parentFolderID,
            name: "Folder",
            description: "Description",
            activitySummary: "Active",
            shared: shared,
            fullAccess: fullAccess,
            capabilities: DetailCapabilityPolicy.folder(shared: shared, fullAccess: fullAccess),
            children: children
        )
    }

    static func goal(
        shared: Bool = false,
        fullAccess: Bool = true,
        canCreateTask: Bool = false,
        tasks: [DetailChildViewData] = []
    ) -> GoalDetailViewData {
        GoalDetailViewData(
            id: goalID,
            folderID: folderID,
            name: "Goal",
            description: "Description",
            status: .todo,
            shared: shared,
            fullAccess: fullAccess,
            capabilities: DetailCapabilityPolicy.goal(
                shared: shared,
                fullAccess: fullAccess,
                canCreateTask: canCreateTask
            ),
            tasks: tasks,
            links: []
        )
    }

    static func task(
        shared: Bool = false,
        fullAccess: Bool = true,
        isOwner: Bool = true,
        status: DetailTaskStatus = .todo,
        checklist: [DetailChecklistItemViewData] = [],
        focused: Bool = false
    ) -> TaskDetailViewData {
        TaskDetailViewData(
            id: taskID,
            goalID: goalID,
            title: "Task",
            description: "Description",
            status: status,
            type: .green,
            effort: 3,
            plannedAt: nil,
            dueAt: nil,
            shared: shared,
            fullAccess: fullAccess,
            isOwner: isOwner,
            capabilities: DetailCapabilityPolicy.task(
                shared: shared,
                fullAccess: fullAccess,
                isOwner: isOwner
            ),
            checklist: checklist,
            tags: [],
            recurrence: nil,
            links: [],
            isInFocus: focused,
            version: 7
        )
    }

    static func idea(
        shared: Bool = false,
        fullAccess: Bool = true,
        isCreator: Bool = true,
        allowAuthorHistoryEdits: Bool = true,
        history: [DetailIdeaHistoryViewData] = []
    ) -> IdeaDetailViewData {
        IdeaDetailViewData(
            id: ideaID,
            folderID: folderID,
            title: "Idea",
            body: "Body",
            status: "open",
            allowAuthorHistoryEdits: allowAuthorHistoryEdits,
            shared: shared,
            fullAccess: fullAccess,
            isCreator: isCreator,
            capabilities: DetailCapabilityPolicy.idea(
                shared: shared,
                fullAccess: fullAccess,
                isCreator: isCreator
            ),
            history: history,
            links: []
        )
    }

    static func note(shared: Bool = false, fullAccess: Bool = true) -> NoteDetailViewData {
        NoteDetailViewData(
            id: noteID,
            folderID: folderID,
            title: "Note",
            body: "Body",
            authorName: "Author",
            shared: shared,
            fullAccess: fullAccess,
            capabilities: DetailCapabilityPolicy.note(shared: shared, fullAccess: fullAccess),
            links: []
        )
    }

    static func history(
        id: UUID = UUID(),
        authored: Bool,
        createdAt: TimeInterval
    ) -> DetailIdeaHistoryViewData {
        DetailIdeaHistoryViewData(
            id: id,
            ideaID: ideaID,
            eventType: "comment",
            body: "Body",
            metadata: [:],
            authorName: "Author",
            authorUserID: UUID(),
            isAuthoredByCurrentUser: authored,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: createdAt),
            version: 1
        )
    }
}

final class DetailModelsTests: XCTestCase {
    func testFolderAndGoalChildrenAreNewestFirstWithStableIDTieBreak() throws {
        let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let high = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let values = [
            DetailTestFixtures.child(kind: .task, id: low, createdAt: 10),
            DetailTestFixtures.child(kind: .task, id: high, createdAt: 10),
            DetailTestFixtures.child(kind: .task, id: UUID(), createdAt: 20)
        ]

        guard case let .folder(folder) = DetailContent.folder(
            DetailTestFixtures.folder(children: values)
        ).normalized() else {
            return XCTFail("Expected folder")
        }
        guard case let .goal(goal) = DetailContent.goal(
            DetailTestFixtures.goal(tasks: values)
        ).normalized() else {
            return XCTFail("Expected goal")
        }

        XCTAssertEqual(folder.children.map(\.createdAt), folder.children.map(\.createdAt).sorted(by: >))
        XCTAssertEqual(folder.children.dropFirst().map(\.reference.id), [high, low])
        XCTAssertEqual(goal.tasks.map(\.reference.id), folder.children.map(\.reference.id))
    }

    func testChecklistUsesDisplayOrderThenCreationAndID() {
        let first = DetailChecklistItemViewData(
            id: UUID(), text: "First", checked: false, displayOrder: 0,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let second = DetailChecklistItemViewData(
            id: UUID(), text: "Second", checked: false, displayOrder: 1,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        guard case let .task(task) = DetailContent.task(
            DetailTestFixtures.task(checklist: [second, first])
        ).normalized() else {
            return XCTFail("Expected task")
        }
        XCTAssertEqual(task.checklist.map(\.id), [first.id, second.id])
    }

    func testIdeaHistoryIsChronological() {
        let older = DetailTestFixtures.history(authored: true, createdAt: 1)
        let newer = DetailTestFixtures.history(authored: true, createdAt: 2)
        guard case let .idea(idea) = DetailContent.idea(
            DetailTestFixtures.idea(history: [newer, older])
        ).normalized() else {
            return XCTFail("Expected idea")
        }
        XCTAssertEqual(idea.history.map(\.id), [older.id, newer.id])
    }

    func testTaskDeleteReturnsEachSavedTopLevelOrigin() {
        for origin in DetailOriginTab.allCases {
            XCTAssertEqual(
                DetailDeleteReturnPolicy.destination(
                    for: .task(DetailTestFixtures.task()),
                    origin: origin
                ),
                .originRoot(origin)
            )
        }
    }

    func testNonTaskDeleteDestinationsUsePlannerContract() {
        XCTAssertEqual(
            DetailDeleteReturnPolicy.destination(
                for: .note(DetailTestFixtures.note()),
                origin: .focus
            ),
            .originRoot(.home)
        )
        XCTAssertEqual(
            DetailDeleteReturnPolicy.destination(
                for: .idea(DetailTestFixtures.idea()),
                origin: .calendar
            ),
            .originRoot(.home)
        )
        XCTAssertEqual(
            DetailDeleteReturnPolicy.destination(
                for: .goal(DetailTestFixtures.goal()),
                origin: .focus
            ),
            .folder(DetailTestFixtures.folderID, origin: .home)
        )
        XCTAssertEqual(
            DetailDeleteReturnPolicy.destination(
                for: .folder(DetailTestFixtures.folder()),
                origin: .calendar
            ),
            .originRoot(.home)
        )
        let parentID = UUID()
        XCTAssertEqual(
            DetailDeleteReturnPolicy.destination(
                for: .folder(DetailTestFixtures.folder(parentFolderID: parentID)),
                origin: .focus
            ),
            .folder(parentID, origin: .home)
        )
    }
}
