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
                shared INTEGER NOT NULL DEFAULT 0,
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
                can_create_tasks INTEGER NOT NULL DEFAULT 0,
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
                last_error TEXT,
                locally_deleted INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, id)
            )
            """.trimIndent()
        )
        createTaskTagsTable(db)
        createIdeasTable(db)
        createIdeaNotesTable(db)
        createFolderNotesTable(db)
        createFolderNoteItemsTable(db)
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
            if (oldVersion < 4) {
                addColumnIfMissing(db, TABLE_FOLDERS, "shared", "INTEGER NOT NULL DEFAULT 0")
            }
            if (oldVersion < 5) {
                addColumnIfMissing(db, TABLE_GOALS, "can_create_tasks", "INTEGER NOT NULL DEFAULT 0")
                addColumnIfMissing(db, TABLE_TASKS, "creator_user_id", "TEXT")
                addColumnIfMissing(db, TABLE_TASKS, "creator_email", "TEXT")
                addColumnIfMissing(db, TABLE_TASKS, "creator_name", "TEXT")
            }
            if (oldVersion < 6) {
                createIdeasTable(db)
                createIdeaNotesTable(db)
                createFolderNotesTable(db)
                createFolderNoteItemsTable(db)
            }
            if (oldVersion < 7) {
                addIdeaContractColumns(db)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    override fun onOpen(db: SQLiteDatabase) {
        super.onOpen(db)
        if (!db.isReadOnly) {
            addColumnIfMissing(db, TABLE_FOLDERS, "shared", "INTEGER NOT NULL DEFAULT 0")
            addColumnIfMissing(db, TABLE_GOALS, "can_create_tasks", "INTEGER NOT NULL DEFAULT 0")
            addColumnIfMissing(db, TABLE_TASKS, "creator_user_id", "TEXT")
            addColumnIfMissing(db, TABLE_TASKS, "creator_email", "TEXT")
            addColumnIfMissing(db, TABLE_TASKS, "creator_name", "TEXT")
            createIdeasTable(db)
            createIdeaNotesTable(db)
            addIdeaContractColumns(db)
            createFolderNotesTable(db)
            createFolderNoteItemsTable(db)
        }
    }

    fun snapshot(userId: String, offline: Boolean, lastSyncError: String?): PlanningSnapshot {
        val db = readableDatabase
        val folders = queryFolders(db, userId, includeDeleted = false)
        val allGoals = queryGoals(db, userId, includeDeleted = false)
        val allTasks = queryTasks(db, userId, includeDeleted = false)
        val allIdeas = queryIdeas(db, userId, includeDeleted = false)
        val ideaNotes = queryIdeaNotes(db, userId)
        val allFolderNotes = queryFolderNotes(db, userId, includeDeleted = false)
        return PlanningSnapshot(
            folders = folders.filter { !it.shared && !it.archived },
            goals = allGoals.filter { !it.shared && !it.archived },
            tasks = allTasks.filter { !it.shared && !it.archived },
            ideas = allIdeas.filter { !it.shared && !it.archived },
            ideaNotes = ideaNotes.filter { note -> allIdeas.any { !it.shared && it.id == note.ideaId } },
            folderNotes = allFolderNotes.filter { !it.shared && !it.archived },
            sharedFolders = folders.filter { it.shared && !it.archived },
            sharedGoals = allGoals.filter { it.shared && !it.archived },
            sharedTasks = allTasks.filter { it.shared && !it.archived },
            sharedIdeas = allIdeas.filter { it.shared && !it.archived },
            sharedIdeaNotes = ideaNotes.filter { note -> allIdeas.any { it.shared && it.id == note.ideaId } },
            sharedFolderNotes = allFolderNotes.filter { it.shared && !it.archived },
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

    fun updateFolder(userId: String, folder: PlanningFolder, draft: FolderDraft) {
        if (folder.shared) {
            return
        }
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
        if (folder.shared) {
            return
        }
        val db = writableDatabase
        db.beginTransaction()
        try {
            if (folder.syncState == SyncState.PendingCreate) {
                db.delete(TABLE_TASKS, "user_id = ? AND goal_id IN (SELECT id FROM goals WHERE user_id = ? AND folder_id = ?)", arrayOf(userId, userId, folder.id))
                db.delete(TABLE_GOALS, "user_id = ? AND folder_id = ?", arrayOf(userId, folder.id))
                db.delete(TABLE_IDEAS, "user_id = ? AND folder_id = ?", arrayOf(userId, folder.id))
                db.delete(TABLE_FOLDER_NOTES, "user_id = ? AND folder_id = ?", arrayOf(userId, folder.id))
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
                    canCreateTasks = true,
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
        val shared = isSharedGoal(userId, goalId)
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
                    shared = shared,
                    creatorUserId = userId,
                    creatorEmail = null,
                    creatorName = null,
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
            if (!sharedTaskUpdateChangesOnlyStatus(task, draft) || task.status == draft.status) {
                return
            }
            writableDatabase.update(
                TABLE_TASKS,
                ContentValues().apply {
                    put("status", draft.status)
                    put("updated_at", nowIso())
                    put("pending_action", ACTION_UPDATE)
                    putNull("last_error")
                },
                "user_id = ? AND id = ?",
                arrayOf(userId, task.id)
            )
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
        return queryFolders(readableDatabase, userId, includeDeleted = true).filter { it.syncState.isPending() && !it.shared }
    }

    fun pendingGoals(userId: String): List<PlanningGoal> {
        return queryGoals(readableDatabase, userId, includeDeleted = true).filter { it.syncState.isPending() && !it.shared }
    }

    fun pendingTasks(userId: String): List<PlanningTask> {
        return queryTasks(readableDatabase, userId, includeDeleted = true).filter {
            it.syncState.isPending() && (!it.shared || it.syncState == SyncState.PendingCreate || it.syncState == SyncState.PendingUpdate)
        }
    }

    fun pendingTaskTags(userId: String): List<TaskTag> {
        return queryTaskTags(readableDatabase, userId, includeDeleted = true).filter { it.syncState.isPending() }
    }

    fun findIdea(userId: String, ideaId: String): PlanningIdea? {
        return readableDatabase.query(
            TABLE_IDEAS,
            null,
            "user_id = ? AND id = ? AND locally_deleted = 0",
            arrayOf(userId, ideaId),
            null,
            null,
            null
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.toIdea() else null
        }
    }

    fun upsertRemoteIdeas(userId: String, ideas: List<PlanningIdea>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            ideas.forEach { idea ->
                db.insertWithOnConflict(
                    TABLE_IDEAS,
                    null,
                    ideaValues(userId, idea.copy(syncState = SyncState.Synced, lastError = null), null, false),
                    SQLiteDatabase.CONFLICT_REPLACE
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun upsertRemoteIdeaNotes(userId: String, notes: List<IdeaNote>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            notes.forEach { note ->
                db.insertWithOnConflict(
                    TABLE_IDEA_NOTES,
                    null,
                    ideaNoteValues(userId, note),
                    SQLiteDatabase.CONFLICT_REPLACE
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun upsertRemoteFolderNotes(userId: String, notes: List<FolderNote>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            notes.forEach { note ->
                db.insertWithOnConflict(
                    TABLE_FOLDER_NOTES,
                    null,
                    folderNoteValues(userId, note.copy(syncState = SyncState.Synced, lastError = null), null, false),
                    SQLiteDatabase.CONFLICT_REPLACE
                )
                note.items.forEach { item ->
                    db.insertWithOnConflict(
                        TABLE_FOLDER_NOTE_ITEMS,
                        null,
                        folderNoteItemValues(userId, item),
                        SQLiteDatabase.CONFLICT_REPLACE
                    )
                }
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
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

    fun replaceRemoteSharedResources(
        userId: String,
        folders: List<PlanningFolder>,
        goals: List<PlanningGoal>,
        tasks: List<PlanningTask>,
        ideas: List<PlanningIdea> = emptyList(),
        folderNotes: List<FolderNote> = emptyList()
    ) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            removeMissingSharedRows(db, TABLE_TASKS, userId, tasks.map { it.id })
            removeMissingSharedRows(db, TABLE_GOALS, userId, goals.map { it.id })
            removeMissingSharedRows(db, TABLE_FOLDERS, userId, folders.map { it.id })
            removeMissingSharedRows(db, TABLE_IDEAS, userId, ideas.map { it.id })
            removeMissingSharedRows(db, TABLE_FOLDER_NOTES, userId, folderNotes.map { it.id })

            folders.forEach { folder ->
                if (!hasLocalPending(db, TABLE_FOLDERS, userId, folder.id)) {
                    db.insertWithOnConflict(
                        TABLE_FOLDERS,
                        null,
                        folderValues(userId, folder.copy(shared = true, syncState = SyncState.Synced, lastError = null), null, false),
                        SQLiteDatabase.CONFLICT_REPLACE
                    )
                }
            }
            goals.forEach { goal ->
                if (!hasLocalPending(db, TABLE_GOALS, userId, goal.id)) {
                    db.insertWithOnConflict(
                        TABLE_GOALS,
                        null,
                        goalValues(userId, goal.copy(shared = true, syncState = SyncState.Synced, lastError = null), null, false),
                        SQLiteDatabase.CONFLICT_REPLACE
                    )
                }
            }
            tasks.forEach { task ->
                if (!hasLocalPending(db, TABLE_TASKS, userId, task.id)) {
                    db.insertWithOnConflict(
                        TABLE_TASKS,
                        null,
                        taskValues(userId, task.copy(shared = true, syncState = SyncState.Synced, lastError = null), null, false),
                        SQLiteDatabase.CONFLICT_REPLACE
                    )
                }
            }
            ideas.forEach { idea ->
                db.insertWithOnConflict(
                    TABLE_IDEAS,
                    null,
                    ideaValues(userId, idea.copy(shared = true, syncState = SyncState.Synced, lastError = null), null, false),
                    SQLiteDatabase.CONFLICT_REPLACE
                )
            }
            folderNotes.forEach { note ->
                db.insertWithOnConflict(
                    TABLE_FOLDER_NOTES,
                    null,
                    folderNoteValues(userId, note.copy(shared = true, syncState = SyncState.Synced, lastError = null), null, false),
                    SQLiteDatabase.CONFLICT_REPLACE
                )
                note.items.forEach { item ->
                    db.insertWithOnConflict(
                        TABLE_FOLDER_NOTE_ITEMS,
                        null,
                        folderNoteItemValues(userId, item),
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
            db.delete(TABLE_IDEAS, "user_id = ? AND folder_id = ?", arrayOf(userId, folderId))
            db.delete(TABLE_FOLDER_NOTE_ITEMS, "user_id = ? AND note_id IN (SELECT id FROM folder_notes WHERE user_id = ? AND folder_id = ?)", arrayOf(userId, userId, folderId))
            db.delete(TABLE_FOLDER_NOTES, "user_id = ? AND folder_id = ?", arrayOf(userId, folderId))
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

    private fun queryIdeas(db: SQLiteDatabase, userId: String, includeDeleted: Boolean): List<PlanningIdea> {
        return db.query(
            TABLE_IDEAS,
            null,
            if (includeDeleted) "user_id = ?" else "user_id = ? AND locally_deleted = 0",
            arrayOf(userId),
            null,
            null,
            "created_at ASC"
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(cursor.toIdea())
                }
            }
        }
    }

    private fun queryIdeaNotes(db: SQLiteDatabase, userId: String): List<IdeaNote> {
        return db.query(
            TABLE_IDEA_NOTES,
            null,
            "user_id = ?",
            arrayOf(userId),
            null,
            null,
            "created_at ASC"
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(cursor.toIdeaNote())
                }
            }
        }
    }

    private fun queryFolderNotes(db: SQLiteDatabase, userId: String, includeDeleted: Boolean): List<FolderNote> {
        val items = queryFolderNoteItems(db, userId).groupBy { it.noteId }
        return db.query(
            TABLE_FOLDER_NOTES,
            null,
            if (includeDeleted) "user_id = ?" else "user_id = ? AND locally_deleted = 0",
            arrayOf(userId),
            null,
            null,
            "created_at ASC"
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(cursor.toFolderNote(items[cursor.string("id")].orEmpty()))
                }
            }
        }
    }

    private fun queryFolderNoteItems(db: SQLiteDatabase, userId: String): List<FolderNoteItem> {
        return db.query(
            TABLE_FOLDER_NOTE_ITEMS,
            null,
            "user_id = ?",
            arrayOf(userId),
            null,
            null,
            "display_order ASC, created_at ASC"
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(cursor.toFolderNoteItem())
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
        db.update(
            TABLE_IDEAS,
            pendingDeleteValues(),
            "user_id = ? AND folder_id = ? AND shared = 0",
            arrayOf(userId, folderId)
        )
        db.update(
            TABLE_FOLDER_NOTES,
            pendingDeleteValues(),
            "user_id = ? AND folder_id = ? AND shared = 0",
            arrayOf(userId, folderId)
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

    private fun sharedTaskUpdateChangesOnlyStatus(task: PlanningTask, draft: TaskDraft): Boolean {
        return draft.title == task.title &&
            draft.description == task.description &&
            draft.type == task.type &&
            draft.priority == task.priority &&
            draft.plannedTime == task.plannedTime &&
            draft.dueTime == task.dueTime &&
            (draft.tagIds ?: task.tagIds) == task.tagIds &&
            (draft.recurrenceJson ?: task.recurrenceJson) == task.recurrenceJson &&
            (draft.remindersJson ?: task.remindersJson) == task.remindersJson
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

    private fun isSharedGoal(userId: String, goalId: String): Boolean {
        return readableDatabase.query(
            TABLE_GOALS,
            arrayOf("shared"),
            "user_id = ? AND id = ? AND locally_deleted = 0",
            arrayOf(userId, goalId),
            null,
            null,
            null
        ).use { cursor ->
            cursor.moveToFirst() && cursor.getInt(cursor.getColumnIndexOrThrow("shared")) == 1
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
            put("shared", folder.shared.toInt())
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
            put("can_create_tasks", goal.canCreateTasks.toInt())
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
            put("creator_user_id", task.creatorUserId)
            put("creator_email", task.creatorEmail)
            put("creator_name", task.creatorName)
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

    private fun ideaValues(
        userId: String,
        idea: PlanningIdea,
        pendingAction: String?,
        locallyDeleted: Boolean
    ): ContentValues {
        return ContentValues().apply {
            put("user_id", userId)
            put("id", idea.id)
            put("folder_id", idea.folderId)
            put("title", idea.title)
            put("body", idea.body)
            put("status", idea.status)
            put("display_order", idea.displayOrder)
            put("archived", idea.archived.toInt())
            put("shared", idea.shared.toInt())
            put("allow_author_note_edits", idea.allowAuthorNoteEdits.toInt())
            put("version", idea.version)
            put("created_at", idea.createdAt)
            put("updated_at", idea.updatedAt)
            put("pending_action", pendingAction)
            put("last_error", idea.lastError)
            put("locally_deleted", locallyDeleted.toInt())
        }
    }

    private fun ideaNoteValues(userId: String, note: IdeaNote): ContentValues {
        return ContentValues().apply {
            put("user_id", userId)
            put("id", note.id)
            put("idea_id", note.ideaId)
            put("event_type", note.eventType)
            put("body", note.body)
            put("metadata_json", note.metadataJson)
            put("author_user_id", note.authorUserId)
            put("author_email", note.authorEmail)
            put("author_name", note.authorName)
            put("version", note.version)
            put("created_at", note.createdAt)
            put("updated_at", note.updatedAt)
        }
    }

    private fun folderNoteValues(
        userId: String,
        note: FolderNote,
        pendingAction: String?,
        locallyDeleted: Boolean
    ): ContentValues {
        return ContentValues().apply {
            put("user_id", userId)
            put("id", note.id)
            put("folder_id", note.folderId)
            put("title", note.title)
            put("body", note.body)
            put("kind", note.kind)
            put("archived", note.archived.toInt())
            put("shared", note.shared.toInt())
            put("version", note.version)
            put("created_at", note.createdAt)
            put("updated_at", note.updatedAt)
            put("pending_action", pendingAction)
            put("last_error", note.lastError)
            put("locally_deleted", locallyDeleted.toInt())
        }
    }

    private fun folderNoteItemValues(userId: String, item: FolderNoteItem): ContentValues {
        return ContentValues().apply {
            put("user_id", userId)
            put("id", item.id)
            put("note_id", item.noteId)
            put("body", item.body)
            put("checked", item.checked.toInt())
            put("display_order", item.displayOrder)
            put("version", item.version)
            put("created_at", item.createdAt)
            put("updated_at", item.updatedAt)
        }
    }

    private fun Cursor.toFolder(): PlanningFolder {
        return PlanningFolder(
            id = string("id"),
            name = string("name"),
            description = string("description"),
            displayOrder = int("display_order"),
            archived = boolean("archived"),
            shared = optionalBoolean("shared"),
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
            canCreateTasks = optionalBoolean("can_create_tasks"),
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
            creatorUserId = optionalStringOrNull("creator_user_id"),
            creatorEmail = optionalStringOrNull("creator_email"),
            creatorName = optionalStringOrNull("creator_name"),
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

    private fun Cursor.toIdea(): PlanningIdea {
        return PlanningIdea(
            id = string("id"),
            folderId = string("folder_id"),
            title = string("title"),
            body = string("body"),
            status = optionalStringOrNull("status") ?: "active",
            displayOrder = optionalInt("display_order"),
            archived = boolean("archived"),
            shared = boolean("shared"),
            allowAuthorNoteEdits = optionalBoolean("allow_author_note_edits"),
            version = long("version"),
            createdAt = string("created_at"),
            updatedAt = string("updated_at"),
            syncState = syncState(stringOrNull("pending_action")),
            lastError = stringOrNull("last_error")
        )
    }

    private fun Cursor.toIdeaNote(): IdeaNote {
        return IdeaNote(
            id = string("id"),
            ideaId = string("idea_id"),
            eventType = optionalStringOrNull("event_type") ?: "note",
            body = string("body"),
            metadataJson = optionalStringOrNull("metadata_json") ?: "{}",
            authorUserId = optionalStringOrNull("author_user_id"),
            authorEmail = optionalStringOrNull("author_email"),
            authorName = optionalStringOrNull("author_name"),
            version = optionalLong("version"),
            createdAt = string("created_at"),
            updatedAt = optionalStringOrNull("updated_at") ?: string("created_at")
        )
    }

    private fun Cursor.toFolderNote(items: List<FolderNoteItem>): FolderNote {
        return FolderNote(
            id = string("id"),
            folderId = string("folder_id"),
            title = string("title"),
            body = string("body"),
            kind = string("kind"),
            archived = boolean("archived"),
            shared = boolean("shared"),
            version = long("version"),
            items = items,
            createdAt = string("created_at"),
            updatedAt = string("updated_at"),
            syncState = syncState(stringOrNull("pending_action")),
            lastError = stringOrNull("last_error")
        )
    }

    private fun Cursor.toFolderNoteItem(): FolderNoteItem {
        return FolderNoteItem(
            id = string("id"),
            noteId = string("note_id"),
            body = string("body"),
            checked = boolean("checked"),
            displayOrder = int("display_order"),
            version = long("version"),
            createdAt = string("created_at"),
            updatedAt = string("updated_at")
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

    private fun Cursor.optionalInt(column: String): Int {
        val index = getColumnIndex(column)
        return if (index < 0 || isNull(index)) 0 else getInt(index)
    }

    private fun Cursor.long(column: String): Long {
        return getLong(getColumnIndexOrThrow(column))
    }

    private fun Cursor.optionalLong(column: String): Long {
        val index = getColumnIndex(column)
        return if (index < 0 || isNull(index)) 0L else getLong(index)
    }

    private fun Cursor.boolean(column: String): Boolean {
        return int(column) == 1
    }

    private fun Cursor.optionalBoolean(column: String): Boolean {
        val index = getColumnIndex(column)
        return index >= 0 && getInt(index) == 1
    }

    private fun removeMissingSharedRows(db: SQLiteDatabase, table: String, userId: String, keepIds: List<String>) {
        if (keepIds.isEmpty()) {
            db.delete(table, "user_id = ? AND shared = 1", arrayOf(userId))
            return
        }
        val placeholders = keepIds.joinToString(",") { "?" }
        db.delete(
            table,
            "user_id = ? AND shared = 1 AND id NOT IN ($placeholders)",
            arrayOf(userId, *keepIds.toTypedArray())
        )
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

    private fun createIdeasTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS ideas (
                user_id TEXT NOT NULL,
                id TEXT NOT NULL,
                folder_id TEXT NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'active',
                display_order INTEGER NOT NULL DEFAULT 0,
                archived INTEGER NOT NULL,
                shared INTEGER NOT NULL,
                allow_author_note_edits INTEGER NOT NULL DEFAULT 0,
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
    }

    private fun createIdeaNotesTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS idea_notes (
                user_id TEXT NOT NULL,
                id TEXT NOT NULL,
                idea_id TEXT NOT NULL,
                event_type TEXT NOT NULL DEFAULT 'note',
                body TEXT NOT NULL,
                metadata_json TEXT NOT NULL DEFAULT '{}',
                author_user_id TEXT,
                author_email TEXT,
                author_name TEXT,
                version INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL DEFAULT '',
                PRIMARY KEY (user_id, id)
            )
            """.trimIndent()
        )
    }

    private fun addIdeaContractColumns(db: SQLiteDatabase) {
        addColumnIfMissing(db, TABLE_IDEAS, "status", "TEXT NOT NULL DEFAULT 'active'")
        addColumnIfMissing(db, TABLE_IDEAS, "display_order", "INTEGER NOT NULL DEFAULT 0")
        addColumnIfMissing(db, TABLE_IDEAS, "allow_author_note_edits", "INTEGER NOT NULL DEFAULT 0")
        addColumnIfMissing(db, TABLE_IDEA_NOTES, "event_type", "TEXT NOT NULL DEFAULT 'note'")
        addColumnIfMissing(db, TABLE_IDEA_NOTES, "metadata_json", "TEXT NOT NULL DEFAULT '{}'")
        addColumnIfMissing(db, TABLE_IDEA_NOTES, "version", "INTEGER NOT NULL DEFAULT 0")
        addColumnIfMissing(db, TABLE_IDEA_NOTES, "updated_at", "TEXT NOT NULL DEFAULT ''")
    }

    private fun createFolderNotesTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS folder_notes (
                user_id TEXT NOT NULL,
                id TEXT NOT NULL,
                folder_id TEXT NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                kind TEXT NOT NULL,
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
    }

    private fun createFolderNoteItemsTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS folder_note_items (
                user_id TEXT NOT NULL,
                id TEXT NOT NULL,
                note_id TEXT NOT NULL,
                body TEXT NOT NULL,
                checked INTEGER NOT NULL,
                display_order INTEGER NOT NULL,
                version INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
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
        private const val DATABASE_VERSION = 7

        const val TABLE_FOLDERS = "folders"
        const val TABLE_GOALS = "goals"
        const val TABLE_TASKS = "tasks"
        const val TABLE_TASK_TAGS = "task_tags"
        const val TABLE_IDEAS = "ideas"
        const val TABLE_IDEA_NOTES = "idea_notes"
        const val TABLE_FOLDER_NOTES = "folder_notes"
        const val TABLE_FOLDER_NOTE_ITEMS = "folder_note_items"

        private const val ACTION_CREATE = "create"
        private const val ACTION_UPDATE = "update"
        private const val ACTION_DELETE = "delete"
        private const val ACTION_CONFLICT = "conflict"

        fun nowIso(): String = Instant.now().toString()
        fun localId(): String = UUID.randomUUID().toString()
    }
}
