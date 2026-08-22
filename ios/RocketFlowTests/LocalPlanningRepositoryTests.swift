import Foundation
import GRDB
import XCTest
@testable import RocketFlow

private actor RepositoryTestClock: SyncClock {
    private var value: Date

    init(_ value: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.value = value
    }

    func now() -> Date { value }
    func advance(_ seconds: TimeInterval = 1) { value = value.addingTimeInterval(seconds) }
}

final class LocalPlanningRepositoryTests: XCTestCase {
    func testFolderCreateAndUpdateCoalesceIntoCreate() async throws {
        let fixture = try makeFixture()
        let folder = try await fixture.repository.createFolder(FolderDraft(name: "Before"))
        try await fixture.repository.updateFolder(id: folder.id, name: "After", description: "Details")

        let snapshot = try await fixture.repository.snapshot()
        XCTAssertEqual(snapshot.folders.first?.name, "After")
        let mutations = try await fixture.store.all()
        XCTAssertEqual(mutations.count, 1)
        XCTAssertEqual(mutations.first?.operation, .create)
    }

    func testGoalCreateAndUpdate() async throws {
        let fixture = try makeFixture()
        let folder = try await fixture.repository.createFolder(FolderDraft(name: "Folder"))
        let goal = try await fixture.repository.createGoal(GoalDraft(folderID: folder.id, name: "Before"))
        try await fixture.repository.updateGoal(
            id: goal.id,
            draft: GoalDraft(id: goal.id, folderID: folder.id, name: "After", status: .inProgress)
        )

        let snapshot = try await fixture.repository.snapshot()
        let stored = snapshot.goals.first
        XCTAssertEqual(stored?.name, "After")
        XCTAssertEqual(stored?.status, .inProgress)
    }

    func testTaskCreateAndUpdateKeepsHiddenPriorityShadow() async throws {
        let fixture = try makeFixture()
        let hierarchy = try await makeHierarchy(fixture)
        let task = try await fixture.repository.createTask(TaskDraft(goalID: hierarchy.goal.id, title: "Before"))
        try fixture.database.write { db in
            try db.execute(
                sql: "UPDATE tasks SET priorityShadow = 2 WHERE id = ?",
                arguments: [task.id]
            )
        }
        try await fixture.repository.updateTask(
            id: task.idValue,
            draft: TaskDraft(id: task.idValue, goalID: hierarchy.goal.id, title: "After", effort: 8)
        )

        let snapshot = try await fixture.repository.snapshot()
        let stored = snapshot.tasks.first
        let mutations = try await fixture.store.all()
        let queued = try XCTUnwrap(mutations.first { $0.entityID == task.idValue })
        let payload = try WireJSON.decoder().decode(TaskDTO.self, from: queued.payloadJSON)
        XCTAssertEqual(stored?.title, "After")
        XCTAssertEqual(stored?.effort, 8)
        XCTAssertEqual(stored?.priorityShadow, 2)
        XCTAssertEqual(payload.priorityShadow, 2)
    }

    func testIdeaCreateAndUpdate() async throws {
        let fixture = try makeFixture()
        let folder = try await fixture.repository.createFolder(FolderDraft(name: "Folder"))
        let idea = try await fixture.repository.createIdea(IdeaDraft(folderID: folder.id, title: "Before"))
        try await fixture.repository.updateIdea(
            id: idea.id,
            draft: IdeaDraft(id: idea.id, folderID: folder.id, title: "After", body: "Body", status: "DONE")
        )

        let snapshot = try await fixture.repository.snapshot()
        let stored = snapshot.ideas.first
        XCTAssertEqual(stored?.title, "After")
        XCTAssertEqual(stored?.status, "DONE")
    }

    func testNoteCreateAndUpdate() async throws {
        let fixture = try makeFixture()
        let folder = try await fixture.repository.createFolder(FolderDraft(name: "Folder"))
        let note = try await fixture.repository.createNote(NoteDraft(folderID: folder.id, title: "Before"))
        try await fixture.repository.updateNote(
            id: note.id,
            draft: NoteDraft(id: note.id, folderID: folder.id, title: "After", body: "Body")
        )

        let snapshot = try await fixture.repository.snapshot()
        let stored = snapshot.notes.first
        XCTAssertEqual(stored?.title, "After")
        XCTAssertEqual(stored?.body, "Body")
    }

    func testChecklistCreateUpdateReorderAndDelete() async throws {
        let fixture = try makeFixture()
        let hierarchy = try await makeHierarchy(fixture)
        let task = try await fixture.repository.createTask(TaskDraft(goalID: hierarchy.goal.id, title: "Task"))
        let taskID = task.idValue
        let first = try await fixture.repository.createChecklistItem(
            ChecklistItemDraft(taskID: taskID, text: "First")
        )
        let second = try await fixture.repository.createChecklistItem(
            ChecklistItemDraft(taskID: taskID, text: "Second")
        )
        try await fixture.repository.updateChecklistItem(
            id: first.id,
            draft: ChecklistItemDraft(id: first.id, taskID: taskID, text: "Updated", checked: true)
        )
        try await fixture.repository.reorderChecklist(taskID: taskID, orderedIDs: [second.id, first.id])

        var snapshot = try await fixture.repository.snapshot()
        var items = snapshot.tasks.first?.checklistItems ?? []
        XCTAssertEqual(items.map(\.id), [second.id, first.id])
        XCTAssertEqual(items.last?.text, "Updated")
        XCTAssertEqual(items.last?.checked, true)

        try await fixture.repository.deleteChecklistItem(id: second.id, taskID: taskID)
        snapshot = try await fixture.repository.snapshot()
        items = snapshot.tasks.first?.checklistItems ?? []
        XCTAssertEqual(items.map(\.id), [first.id])
    }

    func testTagUpdateRefusesBeforeMutationAndTaskAssignmentUsesExistingTag() async throws {
        let fixture = try makeFixture()
        let hierarchy = try await makeHierarchy(fixture)
        let task = try await fixture.repository.createTask(TaskDraft(goalID: hierarchy.goal.id, title: "Task"))
        let tag = try await fixture.repository.createTag(TagDraft(name: "Before", color: "#fff"))
        do {
            try await fixture.repository.updateTag(
                id: tag.id,
                draft: TagDraft(id: tag.id, name: "After", color: "#000")
            )
            XCTFail("Expected unsupported tag update")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .unsupportedMutation(.tag, .update))
        }
        try await fixture.repository.setTags([tag.id], for: task.idValue)

        let snapshot = try await fixture.repository.snapshot()
        let tags = snapshot.tasks.first?.tags ?? []
        XCTAssertEqual(tags.map(\.name), ["Before"])
    }

    func testEntityLinkCreateAndUpdate() async throws {
        let fixture = try makeFixture()
        let hierarchy = try await makeHierarchy(fixture)
        let task = try await fixture.repository.createTask(TaskDraft(goalID: hierarchy.goal.id, title: "Task"))
        let source = reference(type: .goal, id: hierarchy.goal.id, title: "Goal")
        let target = reference(type: .task, id: task.idValue, title: "Task")
        let link = try await fixture.repository.createEntityLink(
            EntityLinkDraft(source: source, target: target, relationType: .related)
        )
        try await fixture.repository.updateEntityLink(id: link.id, relationType: .dependency)

        let relation = try fixture.database.read { db in
            try EntityLinkRecord.fetchOne(db, key: link.id.uuidString.lowercased())?.relationType
        }
        XCTAssertEqual(relation, .dependency)
    }

    func testFocusAndSettingsCacheRoundTrip() async throws {
        let fixture = try makeFixture()
        let focus = Data("focus".utf8)
        let settings = Data("settings".utf8)
        try await fixture.repository.storeFocusCache(key: "current", payloadJSON: focus, version: 4)
        try await fixture.repository.storeSettingsCache(key: "user", payloadJSON: settings, version: 8)

        let storedFocus = try await fixture.repository.focusCache(key: "current")
        let storedSettings = try await fixture.repository.settingsCache(key: "user")
        XCTAssertEqual(storedFocus?.payloadJSON, focus)
        XCTAssertEqual(storedFocus?.version, 4)
        XCTAssertEqual(storedSettings?.payloadJSON, settings)
        XCTAssertEqual(storedSettings?.version, 8)

        try await fixture.repository.removeFocusCache(key: "current")
        try await fixture.repository.removeSettingsCache(key: "user")
        let removedFocus = try await fixture.repository.focusCache(key: "current")
        let removedSettings = try await fixture.repository.settingsCache(key: "user")
        XCTAssertNil(removedFocus)
        XCTAssertNil(removedSettings)
    }

    func testNewestFirstSortAndExplicitReorder() async throws {
        let fixture = try makeFixture()
        let first = try await fixture.repository.createFolder(FolderDraft(name: "First"))
        await fixture.clock.advance()
        let second = try await fixture.repository.createFolder(FolderDraft(name: "Second"))

        var snapshot = try await fixture.repository.snapshot()
        var folders = snapshot.folders
        XCTAssertEqual(folders.map(\.id), [second.id, first.id])

        try await fixture.repository.reorder(.folder, orderedIDs: [first.id, second.id])
        snapshot = try await fixture.repository.snapshot()
        folders = snapshot.folders
        XCTAssertEqual(folders.map(\.id), [first.id, second.id])
    }

    func testDeletingTagRefusesBeforeLocalMutation() async throws {
        let fixture = try makeFixture()
        let tag = try await fixture.repository.createTag(TagDraft(name: "Disposable"))

        do {
            try await fixture.repository.delete(.tag, id: tag.id)
            XCTFail("Expected unsupported tag delete")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .unsupportedMutation(.tag, .delete))
        }

        let count = try fixture.database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags WHERE id = ?", arguments: [tag.id.uuidString.lowercased()])
        }
        XCTAssertEqual(count, 1)
    }

    func testUnsupportedReorderRefusesBeforeWritingOrder() async throws {
        let fixture = try makeFixture()
        let hierarchy = try await makeHierarchy(fixture)

        do {
            try await fixture.repository.reorder(.goal, orderedIDs: [hierarchy.goal.id])
            XCTFail("Expected unsupported reorder")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .unsupportedMutation(.goal, .reorder))
        }
        do {
            try await fixture.repository.delete(.focus, id: UUID())
            XCTFail("Expected feature-owned focus delete to be unavailable")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .unsupportedMutation(.focus, .delete))
        }

        let count = try fixture.database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entity_order")
        }
        XCTAssertEqual(count, 0)
    }

    func testIdeaNoteCreateAndUpdateQueuesSupportedOperations() async throws {
        let fixture = try makeFixture()
        let folder = try await fixture.repository.createFolder(FolderDraft(name: "Folder"))
        let idea = try await fixture.repository.createIdea(IdeaDraft(folderID: folder.id, title: "Idea"))
        let note = try await fixture.repository.createIdeaNote(
            IdeaNoteDraft(ideaID: idea.id, eventType: "NOTE", body: "Before")
        )

        try await fixture.repository.updateIdeaNote(
            id: note.id,
            draft: IdeaNoteDraft(id: note.id, ideaID: idea.id, eventType: "NOTE", body: "After")
        )

        let record = try fixture.database.read { db in
            try IdeaNoteRecord.fetchOne(db, key: note.id.uuidString.lowercased())
        }
        let mutations = try await fixture.store.all()
        XCTAssertEqual(try record?.dto().body, "After")
        XCTAssertEqual(mutations.first { $0.entityID == note.id }?.operation, .create)
    }

    func testDeletingUnsyncedIdeaNoteCancelsItsCreate() async throws {
        let fixture = try makeFixture()
        let folder = try await fixture.repository.createFolder(FolderDraft(name: "Folder"))
        let idea = try await fixture.repository.createIdea(IdeaDraft(folderID: folder.id, title: "Idea"))
        let note = try await fixture.repository.createIdeaNote(
            IdeaNoteDraft(ideaID: idea.id, eventType: "NOTE", body: "Body")
        )

        try await fixture.repository.delete(.ideaNote, id: note.id)

        let count = try fixture.database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM idea_notes WHERE id = ?", arguments: [note.id.uuidString.lowercased()])
        }
        let mutations = try await fixture.store.all()
        XCTAssertEqual(count, 0)
        XCTAssertNil(mutations.first { $0.entityID == note.id })
    }

    func testMovesUpdateLocalHierarchyAndKeepUnsyncedCreates() async throws {
        let fixture = try makeFixture()
        let first = try await fixture.repository.createFolder(FolderDraft(name: "First"))
        let second = try await fixture.repository.createFolder(FolderDraft(name: "Second"))
        let goal = try await fixture.repository.createGoal(GoalDraft(folderID: first.id, name: "Goal"))
        let task = try await fixture.repository.createTask(TaskDraft(goalID: goal.id, title: "Task"))

        try await fixture.repository.moveGoal(id: goal.id, to: second.id)
        let secondGoal = try await fixture.repository.createGoal(GoalDraft(folderID: second.id, name: "Other"))
        try await fixture.repository.moveTask(id: task.idValue, to: secondGoal.id)

        let snapshot = try await fixture.repository.snapshot()
        let mutations = try await fixture.store.all()
        XCTAssertEqual(snapshot.goals.first { $0.id == goal.id }?.folderId, second.id)
        XCTAssertEqual(snapshot.tasks.first { $0.id == task.idValue }?.goalId, secondGoal.id)
        XCTAssertEqual(mutations.first { $0.entityID == goal.id }?.operation, .create)
        XCTAssertEqual(mutations.first { $0.entityID == task.idValue }?.operation, .create)
    }

    func testSyncedGoalMoveQueuesDedicatedMoveMutation() async throws {
        let fixture = try makeFixture()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = FolderDTO(
            id: UUID(), parentFolderId: nil, name: "First", description: "",
            displayOrder: 0, archived: false, shared: false, fullAccess: true,
            version: 1, createdAt: now, updatedAt: now
        )
        let second = FolderDTO(
            id: UUID(), parentFolderId: nil, name: "Second", description: "",
            displayOrder: 0, archived: false, shared: false, fullAccess: true,
            version: 1, createdAt: now, updatedAt: now
        )
        let goal = GoalDTO(
            id: UUID(), folderId: first.id, name: "Goal", description: "",
            status: .todo, archived: false, shared: false, fullAccess: true,
            version: 4, createdAt: now, updatedAt: now
        )
        try await fixture.repository.applyRemote(
            RemotePlanningSnapshot(folders: [first, second], goals: [goal])
        )

        try await fixture.repository.moveGoal(id: goal.id, to: second.id)

        let snapshot = try await fixture.repository.snapshot()
        let mutations = try await fixture.store.all()
        let move = try XCTUnwrap(mutations.first)
        let payload = try WireJSON.decoder().decode(MoveMutationPayload.self, from: move.payloadJSON)
        XCTAssertEqual(snapshot.goals.first?.folderId, second.id)
        XCTAssertEqual(move.operation, .move)
        XCTAssertEqual(move.baseVersion, 4)
        XCTAssertEqual(payload.targetParentID, second.id)
        do {
            try await fixture.repository.updateGoal(
                id: goal.id,
                draft: GoalDraft(id: goal.id, folderID: second.id, name: "Changed")
            )
            XCTFail("Expected move to sync before a field update")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .pendingMutationRequiresSync(.goal, goal.id))
        }

        let next = try await fixture.store.nextReady(at: now)
        let ready = try XCTUnwrap(next)
        let server = GoalDTO(
            id: goal.id, folderId: second.id, name: goal.name, description: goal.description,
            status: goal.status, archived: goal.archived, shared: goal.shared,
            fullAccess: goal.fullAccess, version: 5,
            createdAt: goal.createdAt, updatedAt: now
        )
        try await fixture.store.acknowledge(
            ready,
            ack: RemoteMutationAck(
                remoteID: goal.id,
                version: 5,
                serverPayloadJSON: try WireJSON.encoder().encode(server)
            ),
            at: now
        )
        let converged = try await fixture.repository.snapshot()
        XCTAssertEqual(converged.goals.first?.folderId, second.id)
        XCTAssertEqual(converged.pendingCount, 0)
    }

    private func makeFixture() throws -> Fixture {
        let database = try AppDatabase.inMemory()
        let clock = RepositoryTestClock()
        return Fixture(
            database: database,
            clock: clock,
            repository: LocalPlanningRepository(database: database, clock: clock),
            store: PendingMutationStore(database: database)
        )
    }

    private func makeHierarchy(_ fixture: Fixture) async throws -> (folder: FolderDTO, goal: GoalDTO) {
        let folder = try await fixture.repository.createFolder(FolderDraft(name: "Folder"))
        let goal = try await fixture.repository.createGoal(GoalDraft(folderID: folder.id, name: "Goal"))
        return (folder, goal)
    }

    private func reference(type: LinkedEntityType, id: UUID, title: String) -> EntityReferenceDTO {
        EntityReferenceDTO(
            type: type,
            id: id,
            title: title,
            subtitle: nil,
            status: nil,
            path: nil,
            archived: false,
            accessible: true,
            redacted: false
        )
    }

    private struct Fixture {
        let database: AppDatabase
        let clock: RepositoryTestClock
        let repository: LocalPlanningRepository
        let store: PendingMutationStore
    }
}

private extension TaskRecord {
    var idValue: UUID { UUID(uuidString: id)! }
}
