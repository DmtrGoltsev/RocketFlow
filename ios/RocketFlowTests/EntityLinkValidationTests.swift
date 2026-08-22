import Foundation
import XCTest
@testable import RocketFlow

final class EntityLinkValidationTests: XCTestCase {
    func testRejectsSelfDependencyOnNonTasksAndReverseRelatedDuplicate() {
        let sourceID = UUID()
        let context = EntityLinkContext(type: .goal, id: sourceID, title: "Goal", canManage: true)
        let selfCandidate = EntityLinkCandidate(id: sourceID, type: .goal, title: "Goal", path: nil)

        XCTAssertThrowsError(
            try EntityLinkValidator.validateCreate(
                context: context,
                candidate: selfCandidate,
                relation: .related,
                existing: []
            )
        ) { error in
            XCTAssertEqual(error as? EntityLinkValidationError, .selfLink)
        }

        let task = EntityLinkCandidate(id: UUID(), type: .task, title: "Task", path: nil)
        XCTAssertThrowsError(
            try EntityLinkValidator.validateCreate(
                context: context,
                candidate: task,
                relation: .dependency,
                existing: []
            )
        ) { error in
            XCTAssertEqual(error as? EntityLinkValidationError, .dependencyRequiresTasks)
        }

        let reverse = entityLinkValidationFixture(
            sourceType: .task,
            sourceID: task.id,
            targetType: .goal,
            targetID: sourceID,
            relation: .related
        )
        XCTAssertThrowsError(
            try EntityLinkValidator.validateCreate(
                context: context,
                candidate: task,
                relation: .related,
                existing: [reverse]
            )
        ) { error in
            XCTAssertEqual(error as? EntityLinkValidationError, .duplicate)
        }
    }

    func testDependencyDirectionIsNotCollapsedIntoReverseDuplicate() throws {
        let sourceID = UUID(), targetID = UUID()
        let context = EntityLinkContext(type: .task, id: sourceID, title: "Source", canManage: true)
        let candidate = EntityLinkCandidate(id: targetID, type: .task, title: "Target", path: nil)
        let reverse = entityLinkValidationFixture(
            sourceType: .task,
            sourceID: targetID,
            targetType: .task,
            targetID: sourceID,
            relation: .dependency
        )

        XCTAssertNoThrow(
            try EntityLinkValidator.validateCreate(
                context: context,
                candidate: candidate,
                relation: .dependency,
                existing: [reverse]
            )
        )
    }
}

private func entityLinkValidationFixture(
    sourceType: LinkedEntityType,
    sourceID: UUID,
    targetType: LinkedEntityType,
    targetID: UUID,
    relation: EntityRelationType
) -> ActionEntityLinkDTO {
    let date = Date(timeIntervalSince1970: 1_787_001_200)
    return ActionEntityLinkDTO(
        id: UUID(),
        source: ActionEntityReferenceDTO(
            type: sourceType, id: sourceID, title: "Source", subtitle: nil,
            status: nil, path: nil, archived: false, accessible: true, redacted: false
        ),
        target: ActionEntityReferenceDTO(
            type: targetType, id: targetID, title: "Target", subtitle: nil,
            status: nil, path: nil, archived: false, accessible: true, redacted: false
        ),
        relationType: relation,
        createdByUserId: nil,
        createdByName: nil,
        createdAt: date,
        updatedAt: date,
        version: 1
    )
}
