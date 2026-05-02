package com.rocketflow.companion.planning

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import java.time.Instant
import java.util.UUID

class PlanningLocalStore(context: Context) : SQLiteOpenHelper(
    context,
    DATABASE_NAME,
    null,
    DATABASE_VERSION
) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS folders (
                user_id TEXT NOT NULL,
                id TEXT NOT NULL,
                name TEXT NOT NULL,
                description TEXT NOT NULL,
                display_order INTEGER NOT NULL,
                archived INTEGER NOT NULL,
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
            CREATE TABLE IF NOT EXISTS goals (
                user_id TEXT NOT NULL,
                id TEXT NOT NULL,
                folder_id TEXT NOT NULL,
                name TEXT NOT NULL,
                description TEXT NOT NULL,
                archived INTEGER NOT NULL,
                shared INTEGER NOT NULL,
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
            CREATE TABLE IF NOT EXISTS tasks (
                user_id TEXT NOT NULL,
                id TEXT NOT NULL,
                goal_id TEXT NOT NULL,
                title TEXT NOT NULL,
                description TEXT NOT NULL,
                type TEXT NOT NULL,
                priority INTEGER NOT NULL,
                status TEXT NOT NULL,
                planned_time TEXT,
                due_time TEXT,
                archived INTEGER NOT NULL,
                shared INTEGER NOT NULL,
                version INTEGER NOT NULL,
                tag_ids_json TEXT NOT NULL DEFAULT '[]',
                recurrence_json TEXT,
                reminders_json TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                pending_action TEXT,
                last_error TEXT,
                locally_deleted INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, id)
            )
            """.trimIndent()
        )
        createTaskTagsTable(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.beginTransaction()
        try {
            onCreate(db)
            if (oldVersion < 2) {
                addColumnIfMissing(db, TABLE_TASKS, "tag_ids_json", "TEXT NOT NULL DEFAULT '[]'")
                addColumnIfMissing(db, TABLE_TASKS, "recurrence_json", "TEXT")
                addColumnIfMissing(db, TABLE_TASKS, "reminders_json", "TEXT")
            }
            if (oldVersion < 3) {
                createTaskTagsTable(db)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun snapshot(userId: String, offline: Boolean, lastSyncError: String?): PlanningSnapshot {
        val db = readableDatabase
        val folders = queryFolders(db, userId, includeDeleted = false)
        val allGoals = queryGoals(db, userId, includeDeleted = false)
        val allTasks = queryTasks(db, userId, includeDeleted = false)
        return PlanningSnapshot(
            folders = folders.filterNot { it.archived },
            goals = allGoals.filter { !it.shared && !it.archived },
            tasks = allTasks.filter { !it.shared && !it.archived },
            sharedGoals = allGoals.filter { it.shared && !it.archived },
            sharedTasks = allTasks.filter { it.shared && !it.archived },
            taskTags = queryTaskTags(db, userId, includeDeleted = false),
            pendingCount = countPending(userId),
            offline = offline,
            lastSyncError = lastSyncError
        )
    }

    fun createTag(userId: String, draft: TaskTagDraft): String {
        val id = localId()
        val now = nowIso()
        writableDatabase.insertOrThrow(
            TABLE_TASK_TAGS,
            null,
            taskTagValues(
                userId = userId,
                tag = TaskTag(
                    id = id,
                    name = draft.name,
                    color = draft.color,
                    syncState = SyncState.PendingCreate,
                    lastError = null
                ),
                pendingAction = ACTION_CREATE,
                locallyDeleted = false,
                createdAt = now,
                updatedAt = now
            )
        )
        return id
    }

    fun createFolder(userId: String, draft: FolderDraft): String {
        val now = nowIso()
        val id = localId()
        writableDatabase.insertOrThrow(
            TABLE_FOLDERS,
            null,
            folderValues(
                userId = userId,
                folder = PlanningFolder(
                    id = id,
                    name = draft.name,
                    description = draft.description,
                    displayOrder = nextFolderOrder(userId),
                    archived = false,
                    version = 0,
                    createdAt = now,
                    updatedAt = now,
                    syncState = SyncState.PendingCreate,
                    lastError = null
                ),
                pendingAction = ACTION_CREATE,
                locallyDeleted = false
            )
        )
        return id
    }

    fun updateFolder(userId: String, folder: PlanningFolder, draft: FolderDraft) {
        val action = if (folder.syncState == SyncState.PendingCreate) ACTION_CREATE else ACTION_UPDATE
        writableDatabase.update(
            TABLE_FOLDERS,
            ContentValues().apply {
                put("name", draft.name)
                put("description", draft.description)
                put("updated_at", nowIso())
                put("pending_action", action)
                putNull("last_error")
            },
            "user_id = ? AND id = ?",
            arrayOf(userId, folder.id)
        )
    }

    fun deleteFolder(userId: String, folder: PlanningFolder) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            if (folder.syncState == SyncState.PendingCreate) {
                db.delete(TABLE_TASKS, "user_id = ? AND goal_id IN (SELECT id FROM goals WHERE user_id = ? AND folder_id = ?)", arrayOf(userId, userId, folder.id))
                db.delete(TABLE_GOALS, "user_id = ? AND folder_id = ?", arrayOf(userId, folder.id))
                db.delete(TABLE_FOLDERS, "user_id = ? AND id = ?", arrayOf(userId, folder.id))
            } else {
                markFolderTreeDeleted(db, userId, folder.id)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun createGoal(userId: String, folderId: String, draft: GoalDraft): String {
        val now = nowIso()
        val id = localId()
        writableDatabase.insertOrThrow(
            TABLE_GOALS,
            null,
            goalValues(
                userId = userId,
                goal = PlanningGoal(
                    id = id,
                    folderId = folderId,
                    name = draft.name,
                    description = draft.description,
                    archived = false,
                    shared = false,
                    version = 0,
                    createdAt = now,
                    updatedAt = now,
                    syncState = SyncState.PendingCreate,
                    lastError = null
                ),
                pendingAction = ACTION_CREATE,
                locallyDeleted = false
            )
        )
        return id
    }

    fun updateGoal(userId: String, goal: PlanningGoal, draft: GoalDraft) {
        if (goal.shared) {
            return
        }
        val action = if (goal.syncState == SyncState.PendingCreate) ACTION_CREATE else ACTION_UPDATE
        writableDatabase.update(
            TABLE_GOALS,
            ContentValues().apply {
                put("name", draft.name)
                put("description", draft.description)
                put("updated_at", nowIso())
                put("pending_action", action)
                putNull("last_error")
            },
            "user_id = ? AND id = ?",
            arrayOf(userId, goal.id)
        )
    }

    fun deleteGoal(userId: String, goal: PlanningGoal) {
        if (goal.shared) {
            return
        }
        val db = writableDatabase
        db.beginTransaction()
        try {
            if (goal.syncState == SyncState.PendingCreate) {
                db.delete(TABLE_TASKS, "user_id = ? AND goal_id = ?", arrayOf(userId, goal.id))
                db.delete(TABLE_GOALS, "user_id = ? AND id = ?", arrayOf(userId, goal.id))
            } else {
                markGoalTreeDeleted(db, userId, goal.id)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun createTask(userId: String, goalId: String, draft: TaskDraft): String {
        val now = nowIso()
        val id = localId()
        writableDatabase.insertOrThrow(
            TABLE_TASKS,
            null,
            taskValues(
                userId = userId,
                task = PlanningTask(
                    id = id,
                    goalId = goalId,
                    title = draft.title,
                    description = draft.description,
                    type = draft.type,
                    priority = draft.priority,
                    status = draft.status,
                    plannedTime = draft.plannedTime,
                    dueTime = draft.dueTime,
                    archived = false,
                    shared = false,
                    version = 0,
                    tagIds = draft.tagIds ?: emptyList(),
                    recurrenceJson = draft.recurrenceJson,
                    remindersJson = draft.remindersJson,
                    createdAt = now,
                    updatedAt = now,
                    syncState = SyncState.PendingCreate,
                    lastError = null
                ),
                pendingAction = ACTION_CREATE,
                locallyDeleted = false
            )
        )
        return id
    }

    fun updateTask(userId: String, task: PlanningTask, draft: TaskDraft) {
        if (task.shared) {
            return
        }
        val action = if (task.syncState == SyncState.PendingCreate) ACTION_CREATE else ACTION_UPDATE
        writableDatabase.update(
            TABLE_TASKS,
            ContentValues().apply {
                put("title", draft.title)
                put("description", draft.description)
                put("type", draft.type)
                put("priority", draft.priority)
                put("status", draft.status)
                put("planned_time", draft.plannedTime)
                put("due_time", draft.dueTime)
                put("tag_ids_json", JSONArray(draft.tagIds ?: task.tagIds).toString())
                put("recurrence_json", draft.recurrenceJson ?: task.recurrenceJson)
                put("reminders_json", draft.remindersJson ?: task.remindersJson)
                put("updated_at", nowIso())
                put("pending_action", action)
                putNull("last_error")
            },
            "user_id = ? AND id = ?",
            arrayOf(userId, task.id)
        )
    }

    fun deleteTask(userId: String, task: PlanningTask) {
        if (task.shared) {
            return
        }
        if (task.syncState == SyncState.PendingCreate) {
            writableDatabase.delete(TABLE_TASKS, "user_id = ? AND id = ?", arrayOf(userId, task.id))
            return
        }
        writableDatabase.update(
            TABLE_TASKS,
            ContentValues().apply {
                put("pending_action", ACTION_DELETE)
                put("locally_deleted", 1)
                put("updated_at", nowIso())
                putNull("last_error")
            },
            "user_id = ? AND id = ?",
            arrayOf(userId, task.id)
        )
    }

    fun findTask(userId: String, taskId: String): PlanningTask? {
        return readableDatabase.query(
            TABLE_TASKS,
            null,
            "user_id = ? AND id = ? AND locally_deleted = 0",
            arrayOf(userId, taskId),
            null,
            null,
            null
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.toTask() else null
        }
    }

    fun pendingFolders(userId: String): List<PlanningFolder> {
        return queryFolders(readableDatabase, userId, includeDeleted = true).filter { it.syncState.isPending() }
    }

    fun pendingGoals(userId: String): List<PlanningGoal> {
        return queryGoals(readableDatabase, userId, includeDeleted = true).filter { it.syncState.isPending() && !it.shared }
    }

    fun pendingTasks(userId: String): List<PlanningTask> {
        return queryTasks(readableDatabase, userId, includeDeleted = true).filter { it.syncState.isPending() && !it.shared }
    }

    fun pendingTaskTags(userId: String): List<TaskTag> {
        return queryTaskTags(readableDatabase, userId, includeDeleted = true).filter { it.syncState.isPending() }
    }

    fun upsertRemoteTaskTags(userId: String, tags: List<TaskTag>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            tags.forEach { tag ->
                if (!hasLocalPending(db, TABLE_TASK_TAGS, userId, tag.id)) {
                    db.insertWithOnConflict(
                        TABLE_TASK_TAGS,
                        null,
                        taskTagValues(
                            userId = userId,
                            tag = tag.copy(syncState = SyncState.Synced, lastError = null),
                            pendingAction = null,
                            locallyDeleted = false,
                            createdAt = nowIso(),
                            updatedAt = nowIso()
                        ),
                        SQLiteDatabase.CONFLICT_REPLACE
                    )
                }
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun upsertRemoteFolders(userId: String, folders: List<PlanningFolder>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            folders.forEach { folder ->
                if (!hasLocalPending(db, TABLE_FOLDERS, userId, folder.id)) {
                    db.insertWithOnConflict(
                        TABLE_FOLDERS,
                        null,
                        folderValues(userId, folder.copy(syncState = SyncState.Synced, lastError = null), null, false),
                        SQLiteDatabase.CONFLICT_REPLACE
                    )
                }
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun upsertRemoteGoals(userId: String, goals: List<PlanningGoal>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            goals.forEach { goal ->
                if (!hasLocalPending(db, TABLE_GOALS, userId, goal.id)) {
                    db.insertWithOnConflict(
                        TABLE_GOALS,
                        null,
                        goalValues(userId, goal.copy(syncState = SyncState.Synced, lastError = null), null, false),
                        SQLiteDatabase.CONFLICT_REPLACE
                    )
                }
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun upsertRemoteTasks(userId: String, tasks: List<PlanningTask>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            tasks.forEach { task ->
                if (!hasLocalPending(db, TABLE_TASKS, userId, task.id)) {
                    db.insertWithOnConflict(
                        TABLE_TASKS,
                        null,
                        taskValues(userId, task.copy(syncState = SyncState.Synced, lastError = null), null, false),
                        SQLiteDatabase.CONFLICT_REPLACE
                    )
                }
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun applySyncedFolder(userId: String, localId: String, remote: PlanningFolder) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.update(
                TABLE_FOLDERS,
                folderValues(userId, remote.copy(syncState = SyncState.Synced, lastError = null), null, false),
                "user_id = ? AND id = ?",
                arrayOf(userId, localId)
            )
            if (localId != remote.id) {
                db.update(TABLE_GOALS, ContentValues().apply { put("folder_id", remote.id) }, "user_id = ? AND folder_id = ?", arrayOf(userId, localId))
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun applySyncedGoal(userId: String, localId: String, remote: PlanningGoal) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.update(
                TABLE_GOALS,
                goalValues(userId, remote.copy(syncState = SyncState.Synced, lastError = null), null, false),
                "user_id = ? AND id = ?",
                arrayOf(userId, localId)
            )
            if (localId != remote.id) {
                db.update(TABLE_TASKS, ContentValues().apply { put("goal_id", remote.id) }, "user_id = ? AND goal_id = ?", arrayOf(userId, localId))
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun applySyncedTask(userId: String, localId: String, remote: PlanningTask) {
        writableDatabase.update(
            TABLE_TASKS,
            taskValues(userId, remote.copy(syncState = SyncState.Synced, lastError = null), null, false),
            "user_id = ? AND id = ?",
            arrayOf(userId, localId)
        )
    }

    fun applySyncedTaskTag(userId: String, localId: String, remote: TaskTag) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.update(
                TABLE_TASK_TAGS,
                taskTagValues(
                    userId = userId,
                    tag = remote.copy(syncState = SyncState.Synced, lastError = null),
                    pendingAction = null,
                    locallyDeleted = false,
                    createdAt = nowIso(),
                    updatedAt = nowIso()
                ),
                "user_id = ? AND id = ?",
                arrayOf(userId, localId)
            )
            if (localId != remote.id) {
                queryTasks(db, userId, includeDeleted = true).forEach { task ->
                    if (localId in task.tagIds) {
                        db.update(
                            TABLE_TASKS,
                            ContentValues().apply {
                                put("tag_ids_json", JSONArray(task.tagIds.map { if (it == localId) remote.id else it }).toString())
                            },
                            "user_id = ? AND id = ?",
                            arrayOf(userId, task.id)
                        )
                    }
                }
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun removeFolder(userId: String, folderId: String) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete(TABLE_TASKS, "user_id = ? AND goal_id IN (SELECT id FROM goals WHERE user_id = ? AND folder_id = ?)", arrayOf(userId, userId, folderId))
            db.delete(TABLE_GOALS, "user_id = ? AND folder_id = ?", arrayOf(userId, folderId))
            db.delete(TABLE_FOLDERS, "user_id = ? AND id = ?", arrayOf(userId, folderId))
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun removeGoal(userId: String, goalId: String) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete(TABLE_TASKS, "user_id = ? AND goal_id = ?", arrayOf(userId, goalId))
            db.delete(TABLE_GOALS, "user_id = ? AND id = ?", arrayOf(userId, goalId))
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun removeTask(userId: String, taskId: String) {
        writableDatabase.delete(TABLE_TASKS, "user_id = ? AND id = ?", arrayOf(userId, taskId))
    }

    fun markSyncError(userId: String, table: String, id: String, error: String, conflict: Boolean) {
        writableDatabase.update(
            table,
            ContentValues().apply {
                put("pending_action", if (conflict) ACTION_CONFLICT else existingPendingAction(table, userId, id))
                put("last_error", error)
            },
            "user_id = ? AND id = ?",
            arrayOf(userId, id)
        )
    }

    private fun queryFolders(db: SQLiteDatabase, userId: String, includeDeleted: Boolean): List<PlanningFolder> {
        return db.query(
            TABLE_FOLDERS,
            null,
            if (includeDeleted) "user_id = ?" else "user_id = ? AND locally_deleted = 0",
            arrayOf(userId),
            null,
            null,
            "display_order ASC, created_at ASC"
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(cursor.toFolder())
                }
            }
        }
    }

    private fun queryGoals(db: SQLiteDatabase, userId: String, includeDeleted: Boolean): List<PlanningGoal> {
        return db.query(
            TABLE_GOALS,
            null,
            if (includeDeleted) "user_id = ?" else "user_id = ? AND locally_deleted = 0",
            arrayOf(userId),
            null,
            null,
            "created_at ASC"
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(cursor.toGoal())
                }
            }
        }
    }

    private fun queryTasks(db: SQLiteDatabase, userId: String, includeDeleted: Boolean): List<PlanningTask> {
        return db.query(
            TABLE_TASKS,
            null,
            if (includeDeleted) "user_id = ?" else "user_id = ? AND locally_deleted = 0",
            arrayOf(userId),
            null,
            null,
            "planned_time IS NULL, planned_time ASC, created_at ASC"
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(cursor.toTask())
                }
            }
        }
    }

    private fun queryTaskTags(db: SQLiteDatabase, userId: String, includeDeleted: Boolean): List<TaskTag> {
        return db.query(
            TABLE_TASK_TAGS,
            null,
            if (includeDeleted) "user_id = ?" else "user_id = ? AND locally_deleted = 0",
            arrayOf(userId),
            null,
            null,
            "name COLLATE NOCASE ASC, created_at ASC"
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(cursor.toTaskTag())
                }
            }
        }
    }

    private fun countPending(userId: String): Int {
        return listOf(TABLE_FOLDERS, TABLE_GOALS, TABLE_TASKS, TABLE_TASK_TAGS).sumOf { table ->
            readableDatabase.rawQuery(
                "SELECT COUNT(*) FROM $table WHERE user_id = ? AND pending_action IS NOT NULL",
                arrayOf(userId)
            ).use { cursor ->
                if (cursor.moveToFirst()) cursor.getInt(0) else 0
            }
        }
    }

    private fun markFolderTreeDeleted(db: SQLiteDatabase, userId: String, folderId: String) {
        db.update(
            TABLE_FOLDERS,
            pendingDeleteValues(),
            "user_id = ? AND id = ?",
            arrayOf(userId, folderId)
        )
        db.update(
            TABLE_GOALS,
            pendingDeleteValues(),
            "user_id = ? AND folder_id = ? AND shared = 0",
            arrayOf(userId, folderId)
        )
        db.update(
            TABLE_TASKS,
            pendingDeleteValues(),
            "user_id = ? AND goal_id IN (SELECT id FROM goals WHERE user_id = ? AND folder_id = ? AND shared = 0) AND shared = 0",
            arrayOf(userId, userId, folderId)
        )
    }

    private fun markGoalTreeDeleted(db: SQLiteDatabase, userId: String, goalId: String) {
        db.update(
            TABLE_GOALS,
            pendingDeleteValues(),
            "user_id = ? AND id = ?",
            arrayOf(userId, goalId)
        )
        db.update(
            TABLE_TASKS,
            pendingDeleteValues(),
            "user_id = ? AND goal_id = ? AND shared = 0",
            arrayOf(userId, goalId)
        )
    }

    private fun pendingDeleteValues(): ContentValues {
        return ContentValues().apply {
            put("pending_action", ACTION_DELETE)
            put("locally_deleted", 1)
            put("updated_at", nowIso())
            putNull("last_error")
        }
    }

    private fun nextFolderOrder(userId: String): Int {
        return readableDatabase.rawQuery(
            "SELECT COALESCE(MAX(display_order), -1) + 1 FROM $TABLE_FOLDERS WHERE user_id = ?",
            arrayOf(userId)
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.getInt(0) else 0
        }
    }

    private fun hasLocalPending(db: SQLiteDatabase, table: String, userId: String, id: String): Boolean {
        return db.query(
            table,
            arrayOf("pending_action"),
            "user_id = ? AND id = ? AND pending_action IS NOT NULL",
            arrayOf(userId, id),
            null,
            null,
            null
        ).use { cursor -> cursor.moveToFirst() }
    }

    private fun existingPendingAction(table: String, userId: String, id: String): String? {
        return readableDatabase.query(
            table,
            arrayOf("pending_action"),
            "user_id = ? AND id = ?",
            arrayOf(userId, id),
            null,
            null,
            null
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.stringOrNull("pending_action") else null
        }
    }

    private fun folderValues(
        userId: String,
        folder: PlanningFolder,
        pendingAction: String?,
        locallyDeleted: Boolean
    ): ContentValues {
        return ContentValues().apply {
            put("user_id", userId)
            put("id", folder.id)
            put("name", folder.name)
            put("description", folder.description)
            put("display_order", folder.displayOrder)
            put("archived", folder.archived.toInt())
            put("version", folder.version)
            put("created_at", folder.createdAt)
            put("updated_at", folder.updatedAt)
            put("pending_action", pendingAction)
            put("last_error", folder.lastError)
            put("locally_deleted", locallyDeleted.toInt())
        }
    }

    private fun goalValues(
        userId: String,
        goal: PlanningGoal,
        pendingAction: String?,
        locallyDeleted: Boolean
    ): ContentValues {
        return ContentValues().apply {
            put("user_id", userId)
            put("id", goal.id)
            put("folder_id", goal.folderId)
            put("name", goal.name)
            put("description", goal.description)
            put("archived", goal.archived.toInt())
            put("shared", goal.shared.toInt())
            put("version", goal.version)
            put("created_at", goal.createdAt)
            put("updated_at", goal.updatedAt)
            put("pending_action", pendingAction)
            put("last_error", goal.lastError)
            put("locally_deleted", locallyDeleted.toInt())
        }
    }

    private fun taskTagValues(
        userId: String,
        tag: TaskTag,
        pendingAction: String?,
        locallyDeleted: Boolean,
        createdAt: String,
        updatedAt: String
    ): ContentValues {
        return ContentValues().apply {
            put("user_id", userId)
            put("id", tag.id)
            put("name", tag.name)
            put("color", tag.color)
            put("created_at", createdAt)
            put("updated_at", updatedAt)
            put("pending_action", pendingAction)
            put("last_error", tag.lastError)
            put("locally_deleted", locallyDeleted.toInt())
        }
    }

    private fun taskValues(
        userId: String,
        task: PlanningTask,
        pendingAction: String?,
        locallyDeleted: Boolean
    ): ContentValues {
        return ContentValues().apply {
            put("user_id", userId)
            put("id", task.id)
            put("goal_id", task.goalId)
            put("title", task.title)
            put("description", task.description)
            put("type", task.type)
            put("priority", task.priority)
            put("status", task.status)
            put("planned_time", task.plannedTime)
            put("due_time", task.dueTime)
            put("archived", task.archived.toInt())
            put("shared", task.shared.toInt())
            put("version", task.version)
            put("tag_ids_json", JSONArray(task.tagIds).toString())
            put("recurrence_json", task.recurrenceJson)
            put("reminders_json", task.remindersJson)
            put("created_at", task.createdAt)
            put("updated_at", task.updatedAt)
            put("pending_action", pendingAction)
            put("last_error", task.lastError)
            put("locally_deleted", locallyDeleted.toInt())
        }
    }

    private fun Cursor.toFolder(): PlanningFolder {
        return PlanningFolder(
            id = string("id"),
            name = string("name"),
            description = string("description"),
            displayOrder = int("display_order"),
            archived = boolean("archived"),
            version = long("version"),
            createdAt = string("created_at"),
            updatedAt = string("updated_at"),
            syncState = syncState(stringOrNull("pending_action")),
            lastError = stringOrNull("last_error")
        )
    }

    private fun Cursor.toGoal(): PlanningGoal {
        return PlanningGoal(
            id = string("id"),
            folderId = string("folder_id"),
            name = string("name"),
            description = string("description"),
            archived = boolean("archived"),
            shared = boolean("shared"),
            version = long("version"),
            createdAt = string("created_at"),
            updatedAt = string("updated_at"),
            syncState = syncState(stringOrNull("pending_action")),
            lastError = stringOrNull("last_error")
        )
    }

    private fun Cursor.toTaskTag(): TaskTag {
        return TaskTag(
            id = string("id"),
            name = string("name"),
            color = string("color"),
            syncState = syncState(stringOrNull("pending_action")),
            lastError = stringOrNull("last_error")
        )
    }

    private fun Cursor.toTask(): PlanningTask {
        return PlanningTask(
            id = string("id"),
            goalId = string("goal_id"),
            title = string("title"),
            description = string("description"),
            type = string("type"),
            priority = int("priority"),
            status = string("status"),
            plannedTime = stringOrNull("planned_time"),
            dueTime = stringOrNull("due_time"),
            archived = boolean("archived"),
            shared = boolean("shared"),
            version = long("version"),
            tagIds = parseStringArray(optionalStringOrNull("tag_ids_json") ?: "[]"),
            recurrenceJson = optionalStringOrNull("recurrence_json"),
            remindersJson = optionalStringOrNull("reminders_json"),
            createdAt = string("created_at"),
            updatedAt = string("updated_at"),
            syncState = syncState(stringOrNull("pending_action")),
            lastError = stringOrNull("last_error")
        )
    }

    private fun Cursor.string(column: String): String {
        return getString(getColumnIndexOrThrow(column))
    }

    private fun Cursor.stringOrNull(column: String): String? {
        val index = getColumnIndexOrThrow(column)
        return if (isNull(index)) null else getString(index)
    }

    private fun Cursor.optionalStringOrNull(column: String): String? {
        val index = getColumnIndex(column)
        return if (index < 0 || isNull(index)) null else getString(index)
    }

    private fun Cursor.int(column: String): Int {
        return getInt(getColumnIndexOrThrow(column))
    }

    private fun Cursor.long(column: String): Long {
        return getLong(getColumnIndexOrThrow(column))
    }

    private fun Cursor.boolean(column: String): Boolean {
        return int(column) == 1
    }

    private fun syncState(action: String?): SyncState {
        return when (action) {
            ACTION_CREATE -> SyncState.PendingCreate
            ACTION_UPDATE -> SyncState.PendingUpdate
            ACTION_DELETE -> SyncState.PendingDelete
            ACTION_CONFLICT -> SyncState.Conflict
            else -> SyncState.Synced
        }
    }

    private fun Boolean.toInt(): Int {
        return if (this) 1 else 0
    }

    private fun addColumnIfMissing(db: SQLiteDatabase, table: String, column: String, definition: String) {
        val hasColumn = db.rawQuery("PRAGMA table_info($table)", emptyArray()).use { cursor ->
            var found = false
            while (cursor.moveToNext()) {
                if (cursor.getString(cursor.getColumnIndexOrThrow("name")) == column) {
                    found = true
                    break
                }
            }
            found
        }
        if (!hasColumn) {
            db.execSQL("ALTER TABLE $table ADD COLUMN $column $definition")
        }
    }

    private fun createTaskTagsTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS task_tags (
                user_id TEXT NOT NULL,
                id TEXT NOT NULL,
                name TEXT NOT NULL,
                color TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                pending_action TEXT,
                last_error TEXT,
                locally_deleted INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, id)
            )
            """.trimIndent()
        )
    }

    private fun parseStringArray(raw: String): List<String> {
        return try {
            val json = JSONArray(raw)
            List(json.length()) { index -> json.optString(index) }.filter { it.isNotBlank() }
        } catch (_: Exception) {
            emptyList()
        }
    }

    companion object {
        private const val DATABASE_NAME = "rocketflow_planning.db"
        private const val DATABASE_VERSION = 3

        const val TABLE_FOLDERS = "folders"
        const val TABLE_GOALS = "goals"
        const val TABLE_TASKS = "tasks"
        const val TABLE_TASK_TAGS = "task_tags"

        private const val ACTION_CREATE = "create"
        private const val ACTION_UPDATE = "update"
        private const val ACTION_DELETE = "delete"
        private const val ACTION_CONFLICT = "conflict"

        fun nowIso(): String = Instant.now().toString()
        fun localId(): String = UUID.randomUUID().toString()
    }
}
