import Foundation
import XCTest
@testable import RocketFlow

final class PlannerCapabilitiesTests: XCTestCase {
    func testOwnedFolderOffersAllValidChildAndManagementActions() {
        let item = PlannerTestFixtures.item(
            kind: .folder,
            id: PlannerTestFixtures.folderID,
            title: "Owned",
            createdAt: 100
        )

        XCTAssertEqual(
            PlannerActionCatalog.actions(for: item),
            [
                .openDetail,
                .create(.folder), .create(.goal), .create(.idea), .create(.note),
                .edit, .move, .clone, .share, .delete
            ]
        )
        XCTAssertFalse(item.capabilities.contains(.createTask))
    }

    func testReadOnlySharedFolderCannotMutateOrCreateChildren() {
        let item = PlannerTestFixtures.item(
            kind: .folder,
            id: PlannerTestFixtures.folderID,
            title: "Read only",
            createdAt: 100,
            shared: true,
            fullAccess: false
        )

        XCTAssertEqual(PlannerActionCatalog.actions(for: item), [.openDetail])
    }

    func testFullAccessSharedGoalCanCreateAndManageTasks() {
        let item = PlannerTestFixtures.item(
            kind: .goal,
            id: PlannerTestFixtures.goalID,
            title: "Shared full",
            createdAt: 100,
            shared: true,
            fullAccess: true
        )

        XCTAssertTrue(item.capabilities.contains(.createTask))
        XCTAssertTrue(item.capabilities.contains(.edit))
        XCTAssertTrue(item.capabilities.contains(.share))
        XCTAssertEqual(PlannerActionCatalog.actions(for: item).first, .openDetail)
    }

    func testReadOnlySharedTaskKeepsOnlyStatusException() {
        let item = PlannerTestFixtures.item(
            kind: .task,
            id: PlannerTestFixtures.taskID,
            title: "Status only",
            status: .todo,
            createdAt: 100,
            shared: true,
            fullAccess: false
        )

        XCTAssertTrue(item.capabilities.contains(.openDetail))
        XCTAssertTrue(item.capabilities.contains(.updateTaskStatus))
        XCTAssertFalse(item.capabilities.contains(.edit))
        XCTAssertFalse(item.capabilities.contains(.move))
        XCTAssertFalse(item.capabilities.contains(.delete))
        XCTAssertEqual(PlannerActionCatalog.actions(for: item), [.openDetail])
    }

    func testLegacyCreateTaskGoalIDAddsOnlyCreateTaskCapability() {
        let goal = PlannerTestFixtures.item(
            kind: .goal,
            id: PlannerTestFixtures.goalID,
            title: "Legacy create",
            createdAt: 100,
            shared: true,
            fullAccess: false
        )
        let snapshot = PlannerSnapshot(
            items: [goal],
            createTaskGoalIDs: [goal.reference.id]
        )
        let resolved = snapshot.resolvedItems[0]

        XCTAssertTrue(resolved.capabilities.contains(.createTask))
        XCTAssertFalse(resolved.capabilities.contains(.edit))
        XCTAssertFalse(resolved.capabilities.contains(.share))
        XCTAssertEqual(
            PlannerActionCatalog.actions(for: resolved),
            [.openDetail, .create(.task)]
        )
    }

    func testNoteUsesInheritedAccessWithoutUnsupportedDirectShare() {
        let note = PlannerTestFixtures.item(
            kind: .note,
            id: PlannerTestFixtures.noteID,
            title: "Note",
            createdAt: 100
        )

        XCTAssertTrue(note.capabilities.contains(.edit))
        XCTAssertTrue(note.capabilities.contains(.move))
        XCTAssertTrue(note.capabilities.contains(.clone))
        XCTAssertFalse(note.capabilities.contains(.share))
    }

    func testIdeaDeleteIsDeniedByDefaultAndRequiresExplicitCreatorGate() {
        let unknownCreator = PlannerTestFixtures.item(
            kind: .idea,
            id: PlannerTestFixtures.ideaID,
            title: "Unknown creator",
            createdAt: 100
        )
        let confirmedCreator = PlannerTestFixtures.item(
            kind: .idea,
            id: PlannerTestFixtures.ideaID,
            title: "Confirmed creator",
            createdAt: 100,
            canDelete: true
        )
        let unknownWithUnsafeCapabilities = PlannerTestFixtures.item(
            kind: .idea,
            id: UUID(),
            title: "Unknown creator with supplied capabilities",
            createdAt: 100,
            capabilities: PlannerCapabilitySet([.openDetail, .delete])
        )
        let readOnlyCreator = PlannerTestFixtures.item(
            kind: .idea,
            id: UUID(),
            title: "Read-only creator",
            createdAt: 100,
            shared: true,
            fullAccess: false,
            canDelete: true
        )

        XCTAssertFalse(unknownCreator.canDelete)
        XCTAssertFalse(unknownCreator.capabilities.contains(.delete))
        XCTAssertNotEqual(PlannerActionCatalog.actions(for: unknownCreator).last, .delete)
        XCTAssertTrue(confirmedCreator.canDelete)
        XCTAssertTrue(confirmedCreator.capabilities.contains(.delete))
        XCTAssertEqual(PlannerActionCatalog.actions(for: confirmedCreator).last, .delete)
        XCTAssertFalse(unknownWithUnsafeCapabilities.capabilities.contains(.delete))
        XCTAssertEqual(
            PlannerActionCatalog.actions(for: readOnlyCreator),
            [.openDetail, .delete]
        )
    }

    func testIdeaDTODeleteGateIsDerivedFromCurrentCreatorIdentity() {
        let creatorID = UUID()
        let idea = IdeaDTO(
            id: PlannerTestFixtures.ideaID,
            folderId: PlannerTestFixtures.folderID,
            title: "Creator-only delete",
            body: "",
            status: "active",
            displayOrder: 1,
            archived: false,
            allowAuthorNoteEdits: false,
            shared: false,
            fullAccess: true,
            creatorUserId: creatorID,
            creatorEmail: nil,
            creatorName: nil,
            version: 1,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let creatorItem = PlannerItemViewData(idea: idea, currentUserID: creatorID)
        let otherItem = PlannerItemViewData(idea: idea, currentUserID: UUID())
        let unknownItem = PlannerItemViewData(idea: idea)

        XCTAssertTrue(creatorItem.capabilities.contains(.delete))
        XCTAssertFalse(otherItem.capabilities.contains(.delete))
        XCTAssertFalse(unknownItem.capabilities.contains(.delete))
    }
}
