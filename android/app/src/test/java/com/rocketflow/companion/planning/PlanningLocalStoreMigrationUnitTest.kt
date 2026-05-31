package com.rocketflow.companion.planning

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class PlanningLocalStoreMigrationUnitTest {
    private lateinit var context: Context
    private var store: PlanningLocalStore? = null

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(DATABASE_NAME)
    }

    @After
    fun tearDown() {
        store?.close()
        context.deleteDatabase(DATABASE_NAME)
    }

    @Test
    fun upgradeFromV13IdeaSchemaAddsPendingBlockedWithDefaultAndMatchesFreshSchema() {
        createV13DatabaseWithIdeaMissingPendingBlocked()

        store = PlanningLocalStore(context)
        val upgradedColumns = ideaColumns(store!!.writableDatabase)
        val upgradedPendingBlocked = upgradedColumns["pending_blocked"]

        assertNotNull(upgradedPendingBlocked)
        assertEquals("INTEGER", upgradedPendingBlocked!!.type)
        assertEquals(1, upgradedPendingBlocked.notNull)
        assertEquals("0", upgradedPendingBlocked.defaultValue)
        assertEquals(0, ideaPendingBlockedValue(store!!.readableDatabase, "user-1", "idea-legacy"))

        store!!.close()
        store = null
        context.deleteDatabase(DATABASE_NAME)

        store = PlanningLocalStore(context)
        val freshColumns = ideaColumns(store!!.writableDatabase)

        assertEquals(freshColumns, upgradedColumns)
    }

    @Test
    fun insertReplaceRemoteIdeaDoesNotThrowAfterUpgradeFromMissingPendingBlockedColumn() {
        createV13DatabaseWithIdeaMissingPendingBlocked()
        store = PlanningLocalStore(context)

        store!!.upsertRemoteIdeas("user-1", listOf(remoteIdea("idea-remote")))

        assertEquals("Remote idea", store!!.findIdea("user-1", "idea-remote")!!.title)
        assertEquals(0, ideaPendingBlockedValue(store!!.readableDatabase, "user-1", "idea-remote"))
    }

    @Test
    fun upgradeFromV14AddsTaskChecklistItemsTableAndMatchesFreshSchema() {
        createV14DatabaseWithoutTaskChecklistItems()

        store = PlanningLocalStore(context)
        val upgradedColumns = tableColumns(store!!.writableDatabase, PlanningLocalStore.TABLE_TASK_CHECKLIST_ITEMS)

        assertTrue(upgradedColumns.containsKey("task_id"))
        assertTrue(upgradedColumns.containsKey("text"))
        assertTrue(upgradedColumns.containsKey("checked"))
        assertTrue(upgradedColumns.containsKey("display_order"))

        store!!.close()
        store = null
        context.deleteDatabase(DATABASE_NAME)

        store = PlanningLocalStore(context)
        val freshColumns = tableColumns(store!!.writableDatabase, PlanningLocalStore.TABLE_TASK_CHECKLIST_ITEMS)

        assertEquals(freshColumns, upgradedColumns)
    }

    @Test
    fun taskChecklistPersistsUpdatesAndDeletesWithPendingTask() {
        store = PlanningLocalStore(context)
        val folderId = store!!.createFolder("user-1", FolderDraft("Folder", ""))
        val goalId = store!!.createGoal("user-1", folderId, GoalDraft("Goal", ""))
        val now = PlanningLocalStore.nowIso()
        val first = TaskChecklistItem(
            id = PlanningLocalStore.localId(),
            taskId = "",
            text = "Draft scope",
            checked = false,
            displayOrder = 0,
            version = 0,
            createdAt = now,
            updatedAt = now
        )

        val taskId = store!!.createTask(
            "user-1",
            goalId,
            TaskDraft(
                title = "Task",
                description = "",
                type = "green",
                priority = 4,
                status = "todo",
                plannedTime = null,
                dueTime = null,
                checklistItems = listOf(first)
            )
        )

        val createdTask = store!!.findTask("user-1", taskId)!!
        assertEquals(listOf("Draft scope"), createdTask.checklistItems.map { it.text })
        assertEquals(false, createdTask.checklistItems.single().checked)

        store!!.updateTask(
            "user-1",
            createdTask,
            createdTask.toDraftForTest(
                checklistItems = createdTask.checklistItems.map {
                    it.copy(checked = true, updatedAt = PlanningLocalStore.nowIso())
                }
            )
        )

        val updatedTask = store!!.findTask("user-1", taskId)!!
        assertEquals(true, updatedTask.checklistItems.single().checked)

        store!!.deleteTask("user-1", updatedTask)
        assertEquals(0, checklistCount(store!!.readableDatabase, "user-1", taskId))
    }

    @Test
    fun snapshotTasksAreSortedByPriorityDescending() {
        store = PlanningLocalStore(context)
        val folderId = store!!.createFolder("user-1", FolderDraft("Folder", ""))
        val goalId = store!!.createGoal("user-1", folderId, GoalDraft("Goal", ""))

        store!!.createTask("user-1", goalId, taskDraft("Low", 1))
        store!!.createTask("user-1", goalId, taskDraft("High", 9))
        store!!.createTask("user-1", goalId, taskDraft("Middle", 5))

        val titles = store!!.snapshot("user-1", offline = false, lastSyncError = null).tasks.map { it.title }

        assertEquals(listOf("High", "Middle", "Low"), titles)
    }

    @Test
    fun resetPendingCreateIdeaClearsBlockedIssue() {
        store = PlanningLocalStore(context)
        insertPendingCreateIdea(store!!.writableDatabase, "user-1", "idea-pending")

        val blockedSnapshot = store!!.snapshot("user-1", offline = false, lastSyncError = null)
        val issue = blockedSnapshot.pendingIssues.single()
        assertEquals(1, blockedSnapshot.pendingCount)
        assertEquals(PlanningLocalStore.TABLE_IDEAS, issue.entityType)
        assertTrue(issue.blocked)

        store!!.resetPendingIssue("user-1", issue)

        val resetSnapshot = store!!.snapshot("user-1", offline = false, lastSyncError = null)
        assertEquals(0, resetSnapshot.pendingCount)
        assertTrue(resetSnapshot.pendingIssues.isEmpty())
        assertEquals(null, store!!.findIdea("user-1", "idea-pending"))
    }

    private fun createV13DatabaseWithIdeaMissingPendingBlocked() {
        context.openOrCreateDatabase(DATABASE_NAME, Context.MODE_PRIVATE, null).use { db ->
            db.execSQL(
                """
                CREATE TABLE ideas (
                    user_id TEXT NOT NULL,
                    id TEXT NOT NULL,
                    folder_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'active',
                    display_order INTEGER NOT NULL DEFAULT 0,
                    archived INTEGER NOT NULL,
                    shared INTEGER NOT NULL,
                    full_access INTEGER NOT NULL DEFAULT 0,
                    allow_author_note_edits INTEGER NOT NULL DEFAULT 0,
                    creator_user_id TEXT,
                    creator_email TEXT,
                    creator_name TEXT,
                    version INTEGER NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    pending_action TEXT,
                    last_error TEXT,
                    locally_deleted INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (user_id, id)
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                INSERT INTO ideas (
                    user_id, id, folder_id, title, body, status, display_order, archived, shared,
                    full_access, allow_author_note_edits, version, created_at, updated_at,
                    pending_action, last_error, locally_deleted
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf(
                    "user-1",
                    "idea-legacy",
                    "folder-1",
                    "Legacy idea",
                    "",
                    "active",
                    0,
                    0,
                    0,
                    0,
                    0,
                    1,
                    "2026-05-29T00:00:00Z",
                    "2026-05-29T00:00:00Z",
                    null,
                    null,
                    0
                )
            )
            db.version = 13
        }
    }

    private fun createV14DatabaseWithoutTaskChecklistItems() {
        context.openOrCreateDatabase(DATABASE_NAME, Context.MODE_PRIVATE, null).use { db ->
            db.execSQL(
                """
                CREATE TABLE tasks (
                    user_id TEXT NOT NULL,
                    id TEXT NOT NULL,
                    goal_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    description TEXT NOT NULL,
                    type TEXT NOT NULL,
                    priority INTEGER NOT NULL,
                    effort INTEGER NOT NULL DEFAULT 0,
                    status TEXT NOT NULL,
                    planned_time TEXT,
                    due_time TEXT,
                    archived INTEGER NOT NULL,
                    shared INTEGER NOT NULL,
                    full_access INTEGER NOT NULL DEFAULT 0,
                    creator_user_id TEXT,
                    creator_email TEXT,
                    creator_name TEXT,
                    version INTEGER NOT NULL,
                    tag_ids_json TEXT NOT NULL DEFAULT '[]',
                    recurrence_json TEXT,
                    reminders_json TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    pending_action TEXT,
                    pending_blocked INTEGER NOT NULL DEFAULT 0,
                    last_error TEXT,
                    locally_deleted INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (user_id, id)
                )
                """.trimIndent()
            )
            db.version = 14
        }
    }

    private fun insertPendingCreateIdea(db: SQLiteDatabase, userId: String, ideaId: String) {
        db.execSQL(
            """
            INSERT INTO ideas (
                user_id, id, folder_id, title, body, status, display_order, archived, shared,
                full_access, allow_author_note_edits, version, created_at, updated_at,
                pending_action, pending_blocked, last_error, locally_deleted
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
            arrayOf(
                userId,
                ideaId,
                "missing-folder",
                "Blocked idea",
                "",
                "active",
                0,
                0,
                0,
                0,
                0,
                0,
                "2026-05-29T00:00:00Z",
                "2026-05-29T00:00:00Z",
                "create",
                1,
                "POST /folders/missing-folder/ideas - HTTP 404 - not_found - Folder was not found.",
                0
            )
        )
    }

    private fun remoteIdea(id: String): PlanningIdea {
        return PlanningIdea(
            id = id,
            folderId = "folder-1",
            title = "Remote idea",
            body = "",
            status = "active",
            displayOrder = 0,
            archived = false,
            shared = false,
            fullAccess = true,
            allowAuthorNoteEdits = false,
            creatorUserId = "user-1",
            creatorEmail = null,
            creatorName = null,
            version = 1,
            createdAt = "2026-05-29T00:00:00Z",
            updatedAt = "2026-05-29T00:00:00Z",
            syncState = SyncState.Synced,
            lastError = null
        )
    }

    private fun ideaPendingBlockedValue(db: SQLiteDatabase, userId: String, ideaId: String): Int {
        return db.rawQuery(
            "SELECT pending_blocked FROM ideas WHERE user_id = ? AND id = ?",
            arrayOf(userId, ideaId)
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            cursor.getInt(0)
        }
    }

    private fun ideaColumns(db: SQLiteDatabase): Map<String, ColumnInfo> {
        return tableColumns(db, PlanningLocalStore.TABLE_IDEAS)
    }

    private fun tableColumns(db: SQLiteDatabase, table: String): Map<String, ColumnInfo> {
        return db.rawQuery("PRAGMA table_info($table)", emptyArray()).use { cursor ->
            buildMap {
                while (cursor.moveToNext()) {
                    val name = cursor.getString(cursor.getColumnIndexOrThrow("name"))
                    put(
                        name,
                        ColumnInfo(
                            type = cursor.getString(cursor.getColumnIndexOrThrow("type")),
                            notNull = cursor.getInt(cursor.getColumnIndexOrThrow("notnull")),
                            defaultValue = cursor.getString(cursor.getColumnIndexOrThrow("dflt_value")),
                            pk = cursor.getInt(cursor.getColumnIndexOrThrow("pk"))
                        )
                    )
                }
            }
        }
    }

    private fun checklistCount(db: SQLiteDatabase, userId: String, taskId: String): Int {
        return db.rawQuery(
            "SELECT COUNT(*) FROM ${PlanningLocalStore.TABLE_TASK_CHECKLIST_ITEMS} WHERE user_id = ? AND task_id = ?",
            arrayOf(userId, taskId)
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            cursor.getInt(0)
        }
    }

    private fun taskDraft(title: String, priority: Int): TaskDraft {
        return TaskDraft(
            title = title,
            description = "",
            type = "green",
            priority = priority,
            status = "todo",
            plannedTime = null,
            dueTime = null
        )
    }

    private fun PlanningTask.toDraftForTest(
        checklistItems: List<TaskChecklistItem> = this.checklistItems
    ): TaskDraft {
        return TaskDraft(
            title = title,
            description = description,
            type = type,
            priority = priority,
            effort = effort,
            status = status,
            plannedTime = plannedTime,
            dueTime = dueTime,
            tagIds = tagIds,
            checklistItems = checklistItems,
            recurrenceJson = recurrenceJson,
            remindersJson = remindersJson
        )
    }

    private data class ColumnInfo(
        val type: String,
        val notNull: Int,
        val defaultValue: String?,
        val pk: Int
    )

    private companion object {
        const val DATABASE_NAME = "rocketflow_planning.db"
    }
}
