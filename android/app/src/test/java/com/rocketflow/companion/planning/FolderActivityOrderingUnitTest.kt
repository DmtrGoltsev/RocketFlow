package com.rocketflow.companion.planning

import org.junit.Assert.assertEquals
import org.junit.Test

class FolderActivityOrderingUnitTest {

    @Test
    fun descendantTaskActivityMovesFolderAboveQuieterSibling() {
        val store = MemoryBucketStore()
        val ordering = FolderActivityOrdering(store)
        val quiet = folder("quiet", updatedAt = "2026-05-10T00:00:00Z")
        val active = folder("active", updatedAt = "2026-05-01T00:00:00Z")
        val activeChild = folder("active-child", parentFolderId = active.id, updatedAt = "2026-05-02T00:00:00Z")
        val goal = goal("goal-1", folderId = activeChild.id, updatedAt = "2026-05-03T00:00:00Z")
        val task = task("task-1", goalId = goal.id, updatedAt = "2026-05-20T00:00:00Z")

        val ordered = ordering.orderSiblings(
            userId = "user-1",
            parentFolderId = null,
            scope = "own",
            siblingFolders = listOf(quiet, active),
            snapshot = snapshot(
                folders = listOf(quiet, active, activeChild),
                goals = listOf(goal),
                tasks = listOf(task)
            ),
            nowMillis = 1_000L
        )

        assertEquals(listOf("active", "quiet"), ordered.map { it.id })
    }

    @Test
    fun storedOrderFreezesCandidateChangesUntilTwentyFourHoursPass() {
        val store = MemoryBucketStore()
        val ordering = FolderActivityOrdering(store)
        val a = folder("a", updatedAt = "2026-05-20T00:00:00Z")
        val b = folder("b", updatedAt = "2026-05-10T00:00:00Z")

        assertEquals(
            listOf("a", "b"),
            ordering.orderSiblings(
                userId = "user-1",
                parentFolderId = null,
                scope = "own",
                siblingFolders = listOf(a, b),
                snapshot = snapshot(folders = listOf(a, b)),
                nowMillis = 1_000L
            ).map { it.id }
        )

        val olderA = a.copy(updatedAt = "2026-05-01T00:00:00Z")
        val newerB = b.copy(updatedAt = "2026-05-21T00:00:00Z")
        assertEquals(
            listOf("a", "b"),
            ordering.orderSiblings(
                userId = "user-1",
                parentFolderId = null,
                scope = "own",
                siblingFolders = listOf(olderA, newerB),
                snapshot = snapshot(folders = listOf(olderA, newerB)),
                nowMillis = 1_000L + 60_000L
            ).map { it.id }
        )

        assertEquals(
            listOf("b", "a"),
            ordering.orderSiblings(
                userId = "user-1",
                parentFolderId = null,
                scope = "own",
                siblingFolders = listOf(olderA, newerB),
                snapshot = snapshot(folders = listOf(olderA, newerB)),
                nowMillis = 1_000L + FolderActivityOrdering.APPLY_INTERVAL_MILLIS
            ).map { it.id }
        )
    }

    @Test
    fun newFoldersAreInsertedByActivityWithoutReorderingStoredIds() {
        val store = MemoryBucketStore().apply {
            write(
                userId = "user-1",
                bucketId = "own:root",
                order = FolderActivityOrdering.StoredOrder(
                    folderIds = listOf("a", "c"),
                    lastAppliedAtMillis = 1_000L
                )
            )
        }
        val ordering = FolderActivityOrdering(store)
        val a = folder("a", updatedAt = "2026-05-01T00:00:00Z")
        val c = folder("c", updatedAt = "2026-05-20T00:00:00Z")
        val b = folder("b", updatedAt = "2026-05-25T00:00:00Z")

        val ordered = ordering.orderSiblings(
            userId = "user-1",
            parentFolderId = null,
            scope = "own",
            siblingFolders = listOf(a, b, c),
            snapshot = snapshot(folders = listOf(a, b, c)),
            nowMillis = 2_000L
        )

        assertEquals(listOf("b", "a", "c"), ordered.map { it.id })
    }

    @Test
    fun equalActivityKeepsStableSiblingOrder() {
        val store = MemoryBucketStore()
        val ordering = FolderActivityOrdering(store)
        val zulu = folder("zulu", name = "Zulu", updatedAt = "2026-05-20T00:00:00Z")
        val alpha = folder("alpha", name = "Alpha", updatedAt = "2026-05-20T00:00:00Z")
        val beta = folder("beta", name = "Beta", updatedAt = "2026-05-20T00:00:00Z")

        val ordered = ordering.orderSiblings(
            userId = "user-1",
            parentFolderId = null,
            scope = "own",
            siblingFolders = listOf(zulu, alpha, beta),
            snapshot = snapshot(folders = listOf(zulu, alpha, beta)),
            nowMillis = 1_000L
        )

        assertEquals(listOf("zulu", "alpha", "beta"), ordered.map { it.id })
    }

    @Test
    fun storedBucketsAreScopedByUserScopeAndParent() {
        val store = MemoryBucketStore()
        val ordering = FolderActivityOrdering(store)
        val rootA = folder("root-a", updatedAt = "2026-05-20T00:00:00Z")
        val rootB = folder("root-b", updatedAt = "2026-05-10T00:00:00Z")
        val parent = folder("parent", updatedAt = "2026-05-01T00:00:00Z")
        val childA = folder("child-a", parentFolderId = parent.id, updatedAt = "2026-05-03T00:00:00Z")
        val childB = folder("child-b", parentFolderId = parent.id, updatedAt = "2026-05-21T00:00:00Z")
        val snapshot = snapshot(folders = listOf(rootA, rootB, parent, childA, childB))

        ordering.orderSiblings(
            userId = "user-1",
            parentFolderId = null,
            scope = "own",
            siblingFolders = listOf(rootA, rootB),
            snapshot = snapshot,
            nowMillis = 1_000L
        )
        ordering.orderSiblings(
            userId = "user-1",
            parentFolderId = parent.id,
            scope = "own",
            siblingFolders = listOf(childA, childB),
            snapshot = snapshot,
            nowMillis = 1_000L
        )
        ordering.orderSiblings(
            userId = "user-2",
            parentFolderId = null,
            scope = "own",
            siblingFolders = listOf(rootB, rootA),
            snapshot = snapshot,
            nowMillis = 1_000L
        )
        ordering.orderSiblings(
            userId = "user-1",
            parentFolderId = null,
            scope = "shared",
            siblingFolders = listOf(rootB, rootA),
            snapshot = snapshot,
            nowMillis = 1_000L
        )

        assertEquals(listOf("root-a", "root-b"), store.read("user-1", "own:root")?.folderIds)
        assertEquals(listOf("child-b", "child-a"), store.read("user-1", "own:parent")?.folderIds)
        assertEquals(listOf("root-a", "root-b"), store.read("user-2", "own:root")?.folderIds)
        assertEquals(listOf("root-a", "root-b"), store.read("user-1", "shared:root")?.folderIds)
    }

    @Test
    fun badUpdatedAtFallsBackToCreatedAt() {
        val store = MemoryBucketStore()
        val ordering = FolderActivityOrdering(store)
        val fallbackRecent = folder(
            id = "fallback-recent",
            createdAt = "2026-05-20T00:00:00Z",
            updatedAt = "not-a-date"
        )
        val validOlder = folder("valid-older", updatedAt = "2026-05-10T00:00:00Z")

        val ordered = ordering.orderSiblings(
            userId = "user-1",
            parentFolderId = null,
            scope = "own",
            siblingFolders = listOf(validOlder, fallbackRecent),
            snapshot = snapshot(folders = listOf(validOlder, fallbackRecent)),
            nowMillis = 1_000L
        )

        assertEquals(listOf("fallback-recent", "valid-older"), ordered.map { it.id })
    }

    @Test
    fun nonPersistedOrderingDoesNotOverwriteStoredBucketForFilteredSubsets() {
        val store = MemoryBucketStore().apply {
            write(
                userId = "user-1",
                bucketId = "own:root",
                order = FolderActivityOrdering.StoredOrder(
                    folderIds = listOf("a", "c"),
                    lastAppliedAtMillis = 1_000L
                )
            )
        }
        val ordering = FolderActivityOrdering(store)
        val a = folder("a", updatedAt = "2026-05-01T00:00:00Z")
        val b = folder("b", updatedAt = "2026-05-25T00:00:00Z")
        val c = folder("c", updatedAt = "2026-05-20T00:00:00Z")

        assertEquals(
            listOf("b", "a"),
            ordering.orderSiblings(
                userId = "user-1",
                parentFolderId = null,
                scope = "own",
                siblingFolders = listOf(a, b),
                snapshot = snapshot(folders = listOf(a, b, c)),
                persist = false,
                nowMillis = 2_000L
            ).map { it.id }
        )
        assertEquals(listOf("a", "c"), store.read("user-1", "own:root")?.folderIds)
    }

    private class MemoryBucketStore : FolderActivityOrdering.BucketStore {
        private val values = mutableMapOf<Pair<String, String>, FolderActivityOrdering.StoredOrder>()

        override fun read(userId: String, bucketId: String): FolderActivityOrdering.StoredOrder? {
            return values[userId to bucketId]
        }

        override fun write(
            userId: String,
            bucketId: String,
            order: FolderActivityOrdering.StoredOrder
        ) {
            values[userId to bucketId] = order
        }
    }

    private fun snapshot(
        folders: List<PlanningFolder>,
        goals: List<PlanningGoal> = emptyList(),
        tasks: List<PlanningTask> = emptyList(),
        ideas: List<PlanningIdea> = emptyList(),
        ideaNotes: List<IdeaNote> = emptyList(),
        notes: List<PlanningNote> = emptyList()
    ): FolderActivityOrdering.SnapshotData {
        return FolderActivityOrdering.SnapshotData(
            folders = folders,
            goals = goals,
            tasks = tasks,
            ideas = ideas,
            ideaNotes = ideaNotes,
            notes = notes
        )
    }

    private fun folder(
        id: String,
        parentFolderId: String? = null,
        name: String = id,
        createdAt: String = "2026-05-01T00:00:00Z",
        updatedAt: String = createdAt
    ): PlanningFolder {
        return PlanningFolder(
            id = id,
            parentFolderId = parentFolderId,
            name = name,
            description = "",
            displayOrder = 0,
            archived = false,
            shared = false,
            fullAccess = true,
            version = 1L,
            createdAt = createdAt,
            updatedAt = updatedAt,
            syncState = SyncState.Synced,
            lastError = null
        )
    }

    private fun goal(
        id: String,
        folderId: String,
        createdAt: String = "2026-05-01T00:00:00Z",
        updatedAt: String = createdAt
    ): PlanningGoal {
        return PlanningGoal(
            id = id,
            folderId = folderId,
            name = id,
            description = "",
            status = "todo",
            archived = false,
            shared = false,
            canCreateTasks = true,
            fullAccess = true,
            version = 1L,
            createdAt = createdAt,
            updatedAt = updatedAt,
            syncState = SyncState.Synced,
            lastError = null
        )
    }

    private fun task(
        id: String,
        goalId: String,
        createdAt: String = "2026-05-01T00:00:00Z",
        updatedAt: String = createdAt
    ): PlanningTask {
        return PlanningTask(
            id = id,
            goalId = goalId,
            title = id,
            description = "",
            type = "task",
            priority = 0,
            effort = 0,
            status = "todo",
            plannedTime = null,
            dueTime = null,
            archived = false,
            shared = false,
            fullAccess = true,
            creatorUserId = null,
            creatorEmail = null,
            creatorName = null,
            version = 1L,
            tagIds = emptyList(),
            recurrenceJson = null,
            remindersJson = null,
            createdAt = createdAt,
            updatedAt = updatedAt,
            syncState = SyncState.Synced,
            lastError = null
        )
    }
}
