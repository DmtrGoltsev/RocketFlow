import XCTest
@testable import RocketFlow

final class DetailCapabilitiesTests: XCTestCase {
    func testReadOnlyFolderHasNoMutationActions() {
        let content = DetailContent.folder(
            DetailTestFixtures.folder(shared: true, fullAccess: false)
        )
        XCTAssertTrue(DetailActionCatalog.actions(for: content).isEmpty)
    }

    func testFullFolderSupportsAllExpectedChildrenAndManagement() {
        let actions = Set(
            DetailActionCatalog.actions(for: .folder(DetailTestFixtures.folder()))
        )
        XCTAssertEqual(
            actions,
            [
                .create(.folder), .create(.goal), .create(.idea), .create(.note),
                .edit, .move, .clone, .share, .delete
            ]
        )
    }

    func testReadOnlyGoalCanExposeServerGrantedTaskCreationOnly() {
        let blocked = DetailTestFixtures.goal(shared: true, fullAccess: false)
        let allowed = DetailTestFixtures.goal(
            shared: true,
            fullAccess: false,
            canCreateTask: true
        )
        XCTAssertTrue(DetailActionCatalog.actions(for: .goal(blocked)).isEmpty)
        XCTAssertEqual(DetailActionCatalog.actions(for: .goal(allowed)), [.create(.task)])
    }

    func testReadOnlySharedTaskSupportsStatusAndFocusButNoMenuMutation() {
        let task = DetailTestFixtures.task(shared: true, fullAccess: false, isOwner: false)
        XCTAssertTrue(task.capabilities.contains(.updateTaskStatus))
        XCTAssertTrue(task.capabilities.contains(.manageFocus))
        XCTAssertFalse(task.capabilities.contains(.edit))
        XCTAssertTrue(DetailActionCatalog.actions(for: .task(task)).isEmpty)
    }

    func testTaskRecurrenceRequiresOwnership() {
        let member = DetailTestFixtures.task(isOwner: false)
        let owner = DetailTestFixtures.task(isOwner: true)
        XCTAssertFalse(member.capabilities.contains(.manageRecurrence))
        XCTAssertTrue(owner.capabilities.contains(.manageRecurrence))
    }

    func testIdeaHistoryCreateIsAvailableToReadOnlyMember() {
        let idea = DetailTestFixtures.idea(shared: true, fullAccess: false, isCreator: false)
        XCTAssertTrue(idea.capabilities.contains(.createIdeaHistory))
        XCTAssertFalse(idea.capabilities.contains(.edit))
        XCTAssertFalse(idea.capabilities.contains(.delete))
    }

    func testOnlyIdeaCreatorCanDeleteIdea() {
        let member = DetailTestFixtures.idea(isCreator: false)
        let creator = DetailTestFixtures.idea(isCreator: true)
        XCTAssertFalse(member.capabilities.contains(.delete))
        XCTAssertTrue(creator.capabilities.contains(.delete))
    }

    func testIdeaHistoryAuthorCanEditRegardlessOfStoredSetting() {
        let authored = DetailTestFixtures.history(authored: true, createdAt: 1)
        let foreign = DetailTestFixtures.history(authored: false, createdAt: 2)
        let idea = DetailTestFixtures.idea(
            isCreator: false,
            allowAuthorHistoryEdits: false,
            history: [authored, foreign]
        )

        XCTAssertFalse(idea.allowAuthorHistoryEdits)
        XCTAssertTrue(DetailIdeaHistoryPolicy.canEdit(authored))
        XCTAssertFalse(DetailIdeaHistoryPolicy.canEdit(foreign))
        XCTAssertFalse(DetailIdeaHistoryPolicy.canDelete(from: idea))
    }

    func testNoteDoesNotExposeDirectShareAction() {
        let actions = DetailActionCatalog.actions(for: .note(DetailTestFixtures.note()))
        XCTAssertFalse(actions.contains(.share))
        XCTAssertEqual(Set(actions), [.edit, .move, .clone, .delete, .links])
    }

    func testTaskActionCatalogContainsOnlySupportedActions() {
        let actions = Set(
            DetailActionCatalog.actions(for: .task(DetailTestFixtures.task()))
        )
        XCTAssertEqual(actions, [.edit, .move, .clone, .delete, .share, .links, .reschedule])
    }
}
