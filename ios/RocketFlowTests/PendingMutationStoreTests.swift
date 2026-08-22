import Foundation
import GRDB
import XCTest
@testable import RocketFlow

final class PendingMutationStoreTests: XCTestCase {
    func testParentMutationBecomesReadyBeforeDependentChild() async throws {
        let fixture = try makeFixture()
        let folder = try await fixture.repository.createFolder(FolderDraft(name: "Folder"))
        _ = try await fixture.repository.createGoal(GoalDraft(folderID: folder.id, name: "Goal"))

        let first = try await fixture.store.nextReady(at: fixture.now)
        XCTAssertEqual(first?.entityType, .folder)
    }

    func testUpdatesCoalesceAndPreserveCreateOperation() async throws {
        let fixture = try makeFixture()
        let folder = try await fixture.repository.createFolder(FolderDraft(name: "One"))
        try await fixture.repository.updateFolder(id: folder.id, name: "Two", description: "")
        try await fixture.repository.updateFolder(id: folder.id, name: "Three", description: "")

        let mutations = try await fixture.store.all()
        XCTAssertEqual(mutations.count, 1)
        XCTAssertEqual(mutations[0].operation, .create)
        let payload = try WireJSON.decoder().decode(FolderDTO.self, from: mutations[0].payloadJSON)
        XCTAssertEqual(payload.name, "Three")
    }

    func testDeletingUnsyncedFolderRecursivelyRemovesOwnedChildren() async throws {
        let fixture = try makeFixture()
        let folder = try await fixture.repository.createFolder(FolderDraft(name: "Folder"))
        let goal = try await fixture.repository.createGoal(GoalDraft(folderID: folder.id, name: "Goal"))
        _ = try await fixture.repository.createTask(TaskDraft(goalID: goal.id, title: "Task"))

        try await fixture.repository.delete(.folder, id: folder.id)

        let snapshot = try await fixture.repository.snapshot()
        XCTAssertTrue(snapshot.folders.isEmpty)
        XCTAssertTrue(snapshot.goals.isEmpty)
        XCTAssertTrue(snapshot.tasks.isEmpty)
        let pendingCount = try await fixture.store.pendingCount()
        XCTAssertEqual(pendingCount, 0)
    }

    func testUnsupportedTagDeleteLeavesTaskAndDependencyUntouched() async throws {
        let fixture = try makeFixture()
        let hierarchy = try await makeHierarchy(fixture)
        let task = try await fixture.repository.createTask(TaskDraft(goalID: hierarchy.goal.id, title: "Task"))
        let tag = try await fixture.repository.createTag(TagDraft(name: "Tag"))
        try await fixture.repository.setTags([tag.id], for: task.idValue)

        do {
            try await fixture.repository.delete(.tag, id: tag.id)
            XCTFail("Expected unsupported tag delete")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .unsupportedMutation(.tag, .delete))
        }

        let snapshot = try await fixture.repository.snapshot()
        XCTAssertEqual(snapshot.tasks.map(\.id), [task.idValue])
        XCTAssertEqual(snapshot.tasks[0].tags.map(\.id), [tag.id])
        let mutations = try await fixture.store.all()
        let taskMutation = mutations.first { $0.entityID == task.idValue }
        XCTAssertTrue(taskMutation?.dependencies.contains(tag.id) ?? false)
    }

    func testReturnToQueueOnlyRecoversInFlightMutation() async throws {
        let fixture = try makeFixture()
        _ = try await fixture.repository.createFolder(FolderDraft(name: "Folder"))
        let ready = try await fixture.store.nextReady(at: fixture.now)
        let mutation = try XCTUnwrap(ready)

        try await fixture.store.returnToQueue(mutation, errorCode: "cancelled", at: fixture.now)

        let all = try await fixture.store.all()
        let stored = try XCTUnwrap(all.first)
        XCTAssertEqual(stored.state, .queued)
        XCTAssertEqual(stored.lastErrorCode, "cancelled")
    }

    func testScheduleRetryIncrementsAttemptsAndHonorsDate() async throws {
        let fixture = try makeFixture()
        _ = try await fixture.repository.createFolder(FolderDraft(name: "Folder"))
        let ready = try await fixture.store.nextReady(at: fixture.now)
        let mutation = try XCTUnwrap(ready)
        let retryAt = fixture.now.addingTimeInterval(60)

        try await fixture.store.scheduleRetry(mutation, at: retryAt, errorCode: "offline", updatedAt: fixture.now)

        let all = try await fixture.store.all()
        let stored = try XCTUnwrap(all.first)
        XCTAssertEqual(stored.state, .retry)
        XCTAssertEqual(stored.attemptCount, 1)
        XCTAssertEqual(stored.nextRetryAt, retryAt)
        let notReady = try await fixture.store.nextReady(at: fixture.now)
        XCTAssertNil(notReady)
    }

    func testAcknowledgeRemovesOriginalFlightAndStoresMapping() async throws {
        let fixture = try makeFixture()
        let folder = try await fixture.repository.createFolder(FolderDraft(name: "Folder"))
        let ready = try await fixture.store.nextReady(at: fixture.now)
        let mutation = try XCTUnwrap(ready)
        let remoteID = UUID()

        try await fixture.store.acknowledge(
            mutation,
            ack: RemoteMutationAck(remoteID: remoteID, version: 3, serverPayloadJSON: nil),
            at: fixture.now
        )

        let pendingCount = try await fixture.store.pendingCount()
        let storedRemoteID = try await fixture.store.remoteID(for: .folder, localID: folder.id)
        XCTAssertEqual(pendingCount, 0)
        XCTAssertEqual(storedRemoteID, remoteID)
    }

    func testDeleteQueueOrdersChildBeforeParent() async throws {
        let fixture = try makeFixture()
        let hierarchy = try await makeHierarchy(fixture)
        let task = try await fixture.repository.createTask(TaskDraft(goalID: hierarchy.goal.id, title: "Task"))
        for _ in 0..<3 {
            let ready = try await fixture.store.nextReady(at: fixture.now)
            let mutation = try XCTUnwrap(ready)
            try await fixture.store.acknowledge(
                mutation,
                ack: RemoteMutationAck(remoteID: UUID(), version: 1, serverPayloadJSON: nil),
                at: fixture.now
            )
        }
        try await fixture.repository.delete(.goal, id: hierarchy.goal.id)
        try await fixture.repository.delete(.task, id: task.idValue)

        let firstDelete = try await fixture.store.nextReady(at: fixture.now)
        XCTAssertEqual(firstDelete?.entityType, .task)
        XCTAssertEqual(firstDelete?.operation, .delete)
    }

    func testKeepServerWithoutPayloadRefusesWithoutDeletingEntity() async throws {
        let fixture = try await makeConflictFixture(serverVersion: 2, payload: nil)

        do {
            try await fixture.store.resolve(fixture.conflict.id, with: .keepServer, at: fixture.now)
            XCTFail("Expected missing payload")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .missingServerPayload(fixture.conflict.id))
        }

        let snapshot = try await fixture.repository.snapshot()
        let conflictCount = try await fixture.store.conflictCount()
        let pendingCount = try await fixture.store.pendingCount()
        XCTAssertEqual(snapshot.folders.map(\.id), [fixture.folder.id])
        XCTAssertEqual(conflictCount, 1)
        XCTAssertEqual(pendingCount, 1)
    }

    func testServerDeletedKeepAndDiscardRemoveEntityMutationAndConflict() async throws {
        for resolution in [ConflictResolution.keepServer, .discard] {
            let fixture = try await makeConflictFixture(
                serverVersion: nil,
                payload: nil,
                serverDeleted: true
            )

            try await fixture.store.resolve(fixture.conflict.id, with: resolution, at: fixture.now)

            let snapshot = try await fixture.repository.snapshot()
            let pendingCount = try await fixture.store.pendingCount()
            let conflictCount = try await fixture.store.conflictCount()
            XCTAssertTrue(snapshot.folders.isEmpty)
            XCTAssertEqual(pendingCount, 0)
            XCTAssertEqual(conflictCount, 0)
        }
    }

    func testKeepServerPayloadReplacesLocalEntityAndClearsConflict() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let server = FolderDTO(
            id: UUID(),
            parentFolderId: nil,
            name: "Server",
            description: "Authoritative",
            displayOrder: 0,
            archived: false,
            shared: false,
            fullAccess: true,
            version: 12,
            createdAt: now,
            updatedAt: now
        )
        let payload = try WireJSON.encoder().encode(server)
        let fixture = try await makeConflictFixture(serverVersion: 12, payload: payload)

        try await fixture.store.resolve(fixture.conflict.id, with: .keepServer, at: fixture.now)

        let snapshot = try await fixture.repository.snapshot()
        let conflictCount = try await fixture.store.conflictCount()
        let pendingCount = try await fixture.store.pendingCount()
        XCTAssertEqual(snapshot.folders.first?.name, "Server")
        XCTAssertEqual(snapshot.folders.first?.id, fixture.folder.id)
        XCTAssertEqual(conflictCount, 0)
        XCTAssertEqual(pendingCount, 0)
    }

    func testRetryLocalRequiresServerVersion() async throws {
        let fixture = try await makeConflictFixture(serverVersion: nil, payload: nil)

        do {
            try await fixture.store.resolve(fixture.conflict.id, with: .retryLocal, at: fixture.now)
            XCTFail("Expected missing version")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .missingServerVersion(fixture.conflict.id))
        }

        let conflictCount = try await fixture.store.conflictCount()
        XCTAssertEqual(conflictCount, 1)
    }

    func testRetryLocalRebasesToServerVersion() async throws {
        let fixture = try await makeConflictFixture(serverVersion: 17, payload: nil)

        try await fixture.store.resolve(fixture.conflict.id, with: .retryLocal, at: fixture.now)

        let all = try await fixture.store.all()
        let mutation = try XCTUnwrap(all.first)
        XCTAssertEqual(mutation.baseVersion, 17)
        XCTAssertEqual(mutation.state, .queued)
        let conflictCount = try await fixture.store.conflictCount()
        XCTAssertEqual(conflictCount, 0)
    }

    func testResetCachePreservesMutationAndSetsPullBeforePush() async throws {
        let fixture = try await makeConflictFixture(serverVersion: 5, payload: nil)
        try await fixture.repository.storeFocusCache(key: "focus", payloadJSON: Data("x".utf8), version: 1)

        try await fixture.store.resolve(fixture.conflict.id, with: .resetCache, at: fixture.now)

        let pendingCount = try await fixture.store.pendingCount()
        let conflictCount = try await fixture.store.conflictCount()
        let pullRequired = try await fixture.store.pullBeforePushRequired()
        let focus = try await fixture.repository.focusCache(key: "focus")
        XCTAssertEqual(pendingCount, 1)
        XCTAssertEqual(conflictCount, 1)
        XCTAssertTrue(pullRequired)
        XCTAssertNil(focus)
    }

    func testIncompleteRequiredPullClearsFlagButKeepsConflictBlocked() async throws {
        let fixture = try await makeConflictFixture(serverVersion: 5, payload: nil)
        try await fixture.store.resolve(fixture.conflict.id, with: .resetCache, at: fixture.now)

        try await fixture.store.didCompleteRequiredPull(RemotePlanningSnapshot(), at: fixture.now)

        let pullRequired = try await fixture.store.pullBeforePushRequired()
        let all = try await fixture.store.all()
        XCTAssertFalse(pullRequired)
        XCTAssertEqual(all.first?.state, .conflict)
        XCTAssertEqual(all.first?.lastErrorCode, "reset_pull_incomplete")
    }

    func testResetPullRebasesSyncedEntityAndDoesNotLoop() async throws {
        let fixture = try makeFixture()
        let remoteID = UUID()
        let serverDate = fixture.now.addingTimeInterval(-60)
        let initial = FolderDTO(
            id: remoteID, parentFolderId: nil, name: "Initial", description: "",
            displayOrder: 0, archived: false, shared: false, fullAccess: true,
            version: 3, createdAt: serverDate, updatedAt: serverDate
        )
        try await fixture.repository.applyRemote(RemotePlanningSnapshot(folders: [initial]))
        try await fixture.repository.updateFolder(id: remoteID, name: "Local", description: "")
        let ready = try await fixture.store.nextReady(at: fixture.now)
        let mutation = try XCTUnwrap(ready)
        try await fixture.store.recordConflict(
            mutation,
            code: "version",
            serverVersion: nil,
            serverPayloadJSON: nil,
            serverDeleted: false,
            at: fixture.now
        )
        let conflicts = try await fixture.store.conflicts()
        let conflict = try XCTUnwrap(conflicts.first)
        try await fixture.store.resolve(conflict.id, with: .resetCache, at: fixture.now)
        let current = FolderDTO(
            id: remoteID, parentFolderId: nil, name: "Server", description: "",
            displayOrder: 0, archived: false, shared: false, fullAccess: true,
            version: 9, createdAt: serverDate, updatedAt: fixture.now
        )
        let pulled = RemotePlanningSnapshot(folders: [current])
        try await fixture.repository.applyRemote(pulled)
        try await fixture.store.didCompleteRequiredPull(pulled, at: fixture.now)

        let pendingMutations = try await fixture.store.all()
        let pending = try XCTUnwrap(pendingMutations.first)
        let pullRequired = try await fixture.store.pullBeforePushRequired()
        let conflictCount = try await fixture.store.conflictCount()
        XCTAssertEqual(pending.baseVersion, 9)
        XCTAssertEqual(pending.state, .queued)
        XCTAssertFalse(pullRequired)
        XCTAssertEqual(conflictCount, 0)
    }

    func testRecoverInterruptedReturnsInFlightRowsToQueue() async throws {
        let fixture = try makeFixture()
        _ = try await fixture.repository.createFolder(FolderDraft(name: "Folder"))
        _ = try await fixture.store.nextReady(at: fixture.now)

        try await fixture.store.recoverInterrupted(at: fixture.now)

        let all = try await fixture.store.all()
        let mutation = try XCTUnwrap(all.first)
        XCTAssertEqual(mutation.state, .queued)
        XCTAssertEqual(mutation.lastErrorCode, "interrupted")
    }

    private func makeFixture() throws -> Fixture {
        let database = try AppDatabase.inMemory()
        return Fixture(
            database: database,
            repository: LocalPlanningRepository(database: database),
            store: PendingMutationStore(database: database),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeHierarchy(_ fixture: Fixture) async throws -> (folder: FolderDTO, goal: GoalDTO) {
        let folder = try await fixture.repository.createFolder(FolderDraft(name: "Folder"))
        let goal = try await fixture.repository.createGoal(GoalDraft(folderID: folder.id, name: "Goal"))
        return (folder, goal)
    }

    private func makeConflictFixture(
        serverVersion: Int64?,
        payload: Data?,
        serverDeleted: Bool = false
    ) async throws -> ConflictFixture {
        let fixture = try makeFixture()
        let folder = try await fixture.repository.createFolder(FolderDraft(name: "Folder"))
        let ready = try await fixture.store.nextReady(at: fixture.now)
        let mutation = try XCTUnwrap(ready)
        try await fixture.store.recordConflict(
            mutation,
            code: "version_conflict",
            serverVersion: serverVersion,
            serverPayloadJSON: payload,
            serverDeleted: serverDeleted,
            at: fixture.now
        )
        let conflicts = try await fixture.store.conflicts()
        let conflict = try XCTUnwrap(conflicts.first)
        return ConflictFixture(
            database: fixture.database,
            repository: fixture.repository,
            store: fixture.store,
            folder: folder,
            conflict: conflict,
            now: fixture.now
        )
    }

    private struct Fixture {
        let database: AppDatabase
        let repository: LocalPlanningRepository
        let store: PendingMutationStore
        let now: Date
    }

    private struct ConflictFixture {
        let database: AppDatabase
        let repository: LocalPlanningRepository
        let store: PendingMutationStore
        let folder: FolderDTO
        let conflict: SyncConflict
        let now: Date
    }
}

private extension TaskRecord {
    var idValue: UUID { UUID(uuidString: id)! }
}
