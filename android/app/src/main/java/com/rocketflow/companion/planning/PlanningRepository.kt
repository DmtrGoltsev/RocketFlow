package com.rocketflow.companion.planning

import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.SessionBoundResult
import com.rocketflow.companion.network.ApiException
import org.json.JSONArray
import org.json.JSONObject

class PlanningRepository(
    private val authRepository: AuthRepository,
    private val localStore: PlanningLocalStore,
    private val syncEnqueuer: PlanningSyncEnqueuer? = null
) {

    suspend fun syncAndLoad(session: AuthSession): PlanningLoadResult {
        var activeSession = session
        var offline = false
        var lastSyncError: String? = null

        try {
            activeSession = pushPending(activeSession)
            activeSession = pullRemote(activeSession)
        } catch (error: ApiException) {
            if (error.status == 401) {
                throw error
            }
            lastSyncError = error.message
        } catch (error: Exception) {
            offline = true
            lastSyncError = error.message ?: "Network unavailable."
        }

        return PlanningLoadResult(
            session = activeSession,
            snapshot = localStore.snapshot(activeSession.user.id, offline, lastSyncError)
        )
    }

    suspend fun createFolder(session: AuthSession, draft: FolderDraft): PlanningLoadResult {
        localStore.createFolder(session.user.id, draft)
        syncEnqueuer?.enqueuePlanningSync(PlanningSyncReason.PendingChange)
        return syncAndLoad(session)
    }

    suspend fun updateFolder(session: AuthSession, folder: PlanningFolder, draft: FolderDraft): PlanningLoadResult {
        localStore.updateFolder(session.user.id, folder, draft)
        syncEnqueuer?.enqueuePlanningSync(PlanningSyncReason.PendingChange)
        return syncAndLoad(session)
    }

    suspend fun deleteFolder(session: AuthSession, folder: PlanningFolder): PlanningLoadResult {
        localStore.deleteFolder(session.user.id, folder)
        syncEnqueuer?.enqueuePlanningSync(PlanningSyncReason.PendingChange)
        return syncAndLoad(session)
    }

    suspend fun createGoal(session: AuthSession, folderId: String, draft: GoalDraft): PlanningLoadResult {
        localStore.createGoal(session.user.id, folderId, draft)
        syncEnqueuer?.enqueuePlanningSync(PlanningSyncReason.PendingChange)
        return syncAndLoad(session)
    }

    suspend fun updateGoal(session: AuthSession, goal: PlanningGoal, draft: GoalDraft): PlanningLoadResult {
        localStore.updateGoal(session.user.id, goal, draft)
        syncEnqueuer?.enqueuePlanningSync(PlanningSyncReason.PendingChange)
        return syncAndLoad(session)
    }

    suspend fun deleteGoal(session: AuthSession, goal: PlanningGoal): PlanningLoadResult {
        localStore.deleteGoal(session.user.id, goal)
        syncEnqueuer?.enqueuePlanningSync(PlanningSyncReason.PendingChange)
        return syncAndLoad(session)
    }

    suspend fun createTask(session: AuthSession, goalId: String, draft: TaskDraft): PlanningLoadResult {
        localStore.createTask(session.user.id, goalId, draft)
        syncEnqueuer?.enqueuePlanningSync(PlanningSyncReason.PendingChange)
        return syncAndLoad(session)
    }

    suspend fun createTag(session: AuthSession, draft: TaskTagDraft): PlanningLoadResult {
        localStore.createTag(session.user.id, draft)
        syncEnqueuer?.enqueuePlanningSync(PlanningSyncReason.PendingChange)
        return syncAndLoad(session)
    }

    suspend fun updateTask(session: AuthSession, task: PlanningTask, draft: TaskDraft): PlanningLoadResult {
        localStore.updateTask(session.user.id, task, draft)
        syncEnqueuer?.enqueuePlanningSync(PlanningSyncReason.PendingChange)
        return syncAndLoad(session)
    }

    suspend fun deleteTask(session: AuthSession, task: PlanningTask): PlanningLoadResult {
        localStore.deleteTask(session.user.id, task)
        syncEnqueuer?.enqueuePlanningSync(PlanningSyncReason.PendingChange)
        return syncAndLoad(session)
    }

    suspend fun quickRescheduleTask(
        session: AuthSession,
        task: PlanningTask,
        preset: String
    ): TaskRescheduleResult {
        val result = authRepository.authorizedPost(
            session,
            "/tasks/${task.id}/reschedule",
            JSONObject().put("preset", preset)
        )
        val refreshedSession = pullRemote(result.session)
        return TaskRescheduleResult(
            session = refreshedSession,
            snapshot = localStore.snapshot(refreshedSession.user.id, offline = false, lastSyncError = null),
            priorityDecayApplied = result.value.optBoolean("priorityDecayApplied", false)
        )
    }

    suspend fun getTask(session: AuthSession, taskId: String): Pair<AuthSession, PlanningTask?> {
        localStore.findTask(session.user.id, taskId)?.let { return session to it }

        return try {
            val result = authRepository.authorizedGet(session, "/tasks/$taskId")
            val task = result.value.toTask(shared = result.value.optBoolean("shared", false))
            localStore.upsertRemoteTasks(result.session.user.id, listOf(task))
            result.session to task
        } catch (error: ApiException) {
            if (error.status == 401) {
                throw error
            }
            session to localStore.findTask(session.user.id, taskId)
        } catch (_: Exception) {
            session to localStore.findTask(session.user.id, taskId)
        }
    }

    private suspend fun pushPending(session: AuthSession): AuthSession {
        var activeSession = session
        val userId = session.user.id

        localStore.pendingTaskTags(userId).forEach { tag ->
            activeSession = pushTaskTag(activeSession, tag)
        }

        localStore.pendingFolders(userId).forEach { folder ->
            activeSession = pushFolder(activeSession, folder)
        }

        localStore.pendingGoals(userId).forEach { goal ->
            activeSession = pushGoal(activeSession, goal)
        }

        localStore.pendingTasks(userId).forEach { task ->
            activeSession = pushTask(activeSession, task)
        }

        return activeSession
    }

    private suspend fun pushTaskTag(session: AuthSession, tag: TaskTag): AuthSession {
        val userId = session.user.id
        return try {
            when (tag.syncState) {
                SyncState.PendingCreate -> {
                    val result = authRepository.authorizedPost(
                        session,
                        "/tags",
                        JSONObject()
                            .put("name", tag.name)
                            .put("color", tag.color)
                    )
                    localStore.applySyncedTaskTag(userId, tag.id, result.value.toTaskTag())
                    result.session
                }

                SyncState.PendingUpdate,
                SyncState.PendingDelete,
                SyncState.Conflict,
                SyncState.Synced -> session
            }
        } catch (error: ApiException) {
            if (error.status == 401) {
                throw error
            }
            localStore.markSyncError(
                userId,
                PlanningLocalStore.TABLE_TASK_TAGS,
                tag.id,
                error.message,
                conflict = error.status == 409 || error.code == "conflict"
            )
            session
        }
    }

    private suspend fun pushFolder(session: AuthSession, folder: PlanningFolder): AuthSession {
        val userId = session.user.id
        return try {
            when (folder.syncState) {
                SyncState.PendingCreate -> {
                    val result = authRepository.authorizedPost(
                        session,
                        "/folders",
                        JSONObject()
                            .put("name", folder.name)
                            .put("description", folder.description)
                    )
                    localStore.applySyncedFolder(userId, folder.id, result.value.toFolder(shared = false))
                    result.session
                }

                SyncState.PendingUpdate -> {
                    val result = authRepository.authorizedPatch(
                        session,
                        "/folders/${folder.id}",
                        JSONObject()
                            .put("name", folder.name)
                            .put("description", folder.description)
                            .put("displayOrder", folder.displayOrder)
                            .put("archived", folder.archived)
                            .put("version", folder.version)
                    )
                    localStore.applySyncedFolder(userId, folder.id, result.value.toFolder(shared = false))
                    result.session
                }

                SyncState.PendingDelete -> {
                    val refreshed = authRepository.authorizedDelete(session, "/folders/${folder.id}")
                    localStore.removeFolder(userId, folder.id)
                    refreshed
                }

                SyncState.Conflict,
                SyncState.Synced -> session
            }
        } catch (error: ApiException) {
            if (error.status == 401) {
                throw error
            }
            localStore.markSyncError(
                userId,
                PlanningLocalStore.TABLE_FOLDERS,
                folder.id,
                error.message,
                conflict = error.status == 409 || error.code == "conflict"
            )
            session
        }
    }

    private suspend fun pushGoal(session: AuthSession, goal: PlanningGoal): AuthSession {
        val userId = session.user.id
        return try {
            when (goal.syncState) {
                SyncState.PendingCreate -> {
                    val result = authRepository.authorizedPost(
                        session,
                        "/folders/${goal.folderId}/goals",
                        JSONObject()
                            .put("name", goal.name)
                            .put("description", goal.description)
                    )
                    localStore.applySyncedGoal(userId, goal.id, result.value.toGoal(shared = false))
                    result.session
                }

                SyncState.PendingUpdate -> {
                    val result = authRepository.authorizedPatch(
                        session,
                        "/goals/${goal.id}",
                        JSONObject()
                            .put("name", goal.name)
                            .put("description", goal.description)
                            .put("archived", goal.archived)
                            .put("version", goal.version)
                    )
                    localStore.applySyncedGoal(userId, goal.id, result.value.toGoal(shared = goal.shared))
                    result.session
                }

                SyncState.PendingDelete -> {
                    val refreshed = authRepository.authorizedDelete(session, "/goals/${goal.id}")
                    localStore.removeGoal(userId, goal.id)
                    refreshed
                }

                SyncState.Conflict,
                SyncState.Synced -> session
            }
        } catch (error: ApiException) {
            if (error.status == 401) {
                throw error
            }
            localStore.markSyncError(
                userId,
                PlanningLocalStore.TABLE_GOALS,
                goal.id,
                error.message,
                conflict = error.status == 409 || error.code == "conflict"
            )
            session
        }
    }

    private suspend fun pushTask(session: AuthSession, task: PlanningTask): AuthSession {
        val userId = session.user.id
        return try {
            when (task.syncState) {
                SyncState.PendingCreate -> {
                    val recurrenceJson = task.recurrenceJson
                    val remindersJson = task.remindersJson
                    val result = authRepository.authorizedPost(
                        session,
                        "/goals/${task.goalId}/tasks",
                        task.toCreateBody()
                    )
                    val remoteTask = result.value.toTask(shared = false)
                    val metadataSession = syncTaskMetadata(
                        result.session,
                        remoteTask.id,
                        recurrenceJson,
                        remindersJson
                    )
                    val refreshed = authRepository.authorizedGet(metadataSession, "/tasks/${remoteTask.id}")
                    localStore.applySyncedTask(userId, task.id, refreshed.value.toTask(shared = false))
                    refreshed.session
                }

                SyncState.PendingUpdate -> {
                    val remoteBefore = authRepository.authorizedGet(session, "/tasks/${task.id}")
                    val recurrenceJson = if (task.recurrenceJson.differsFromObject(remoteBefore.value.optJsonObjectString("recurrence"))) {
                        task.recurrenceJson?.normalizedFor(task)
                    } else {
                        null
                    }
                    val remindersJson = if (task.remindersJson.differsFromReminders(remoteBefore.value.optJsonArrayString("reminders"))) {
                        task.remindersJson?.withoutReminderIds()
                    } else {
                        null
                    }
                    val result = authRepository.authorizedPatch(
                        remoteBefore.session,
                        "/tasks/${task.id}",
                        task.toUpdateBody()
                    )
                    val metadataSession = syncTaskMetadata(
                        result.session,
                        task.id,
                        recurrenceJson,
                        remindersJson
                    )
                    val refreshed = authRepository.authorizedGet(metadataSession, "/tasks/${task.id}")
                    localStore.applySyncedTask(userId, task.id, refreshed.value.toTask(shared = task.shared))
                    refreshed.session
                }

                SyncState.PendingDelete -> {
                    val refreshed = authRepository.authorizedDelete(session, "/tasks/${task.id}")
                    localStore.removeTask(userId, task.id)
                    refreshed
                }

                SyncState.Conflict,
                SyncState.Synced -> session
            }
        } catch (error: ApiException) {
            if (error.status == 401) {
                throw error
            }
            localStore.markSyncError(
                userId,
                PlanningLocalStore.TABLE_TASKS,
                task.id,
                error.message,
                conflict = error.status == 409 || error.code == "conflict"
            )
            session
        }
    }

    private suspend fun syncTaskMetadata(
        session: AuthSession,
        taskId: String,
        recurrenceJson: String?,
        remindersJson: String?
    ): AuthSession {
        var activeSession = session
        if (!recurrenceJson.isNullOrBlank()) {
            val result = authRepository.authorizedPut(
                activeSession,
                "/tasks/$taskId/recurrence",
                JSONObject(recurrenceJson)
            )
            activeSession = result.session
        }
        if (!remindersJson.isNullOrBlank()) {
            val reminders = JSONArray(remindersJson)
            val result = authRepository.authorizedPut(
                activeSession,
                "/tasks/$taskId/reminders",
                JSONObject().put("reminders", reminders)
            )
            activeSession = result.session
        }
        return activeSession
    }

    private suspend fun pullRemote(session: AuthSession): AuthSession {
        var activeSession = session
        val userId = session.user.id

        val foldersResult = syncGet(activeSession, "/folders")
        activeSession = foldersResult.session
        val folders = foldersResult.value.getJSONArray("items").toFolders(shared = false)
        localStore.upsertRemoteFolders(userId, folders)

        val tagsResult = syncGet(activeSession, "/tags")
        activeSession = tagsResult.session
        localStore.upsertRemoteTaskTags(userId, tagsResult.value.getJSONArray("items").toTaskTags())

        val allGoals = mutableListOf<PlanningGoal>()
        val allTasks = mutableListOf<PlanningTask>()
        folders.filterNot { it.archived }.forEach { folder ->
            val goalsResult = syncGet(activeSession, "/folders/${folder.id}/goals")
            activeSession = goalsResult.session
            val goals = goalsResult.value.getJSONArray("items").toGoals(shared = false)
            allGoals += goals

            goals.filterNot { it.archived }.forEach { goal ->
                val tasksResult = syncGet(activeSession, "/goals/${goal.id}/tasks")
                activeSession = tasksResult.session
                allTasks += tasksResult.value.getJSONArray("items").toTasks(shared = false)
            }
        }
        localStore.upsertRemoteGoals(userId, allGoals)
        localStore.upsertRemoteTasks(userId, allTasks)

        val sharedResult = syncGet(activeSession, "/shares/resources")
        activeSession = sharedResult.session
        localStore.replaceRemoteSharedResources(
            userId,
            folders = sharedResult.value.optJSONArray("folders").orEmptyArray().toFolders(shared = true),
            goals = sharedResult.value.optJSONArray("goals").orEmptyArray().toGoals(shared = true),
            tasks = sharedResult.value.optJSONArray("tasks").orEmptyArray().toTasks(shared = true)
        )

        return activeSession
    }

    private suspend fun syncGet(session: AuthSession, path: String): SessionBoundResult<JSONObject> {
        return try {
            authRepository.authorizedGet(session, path)
        } catch (error: ApiException) {
            throw error.withSyncContext("GET", path)
        }
    }

    private fun ApiException.withSyncContext(method: String, path: String): ApiException {
        val parts = mutableListOf("$method $path", "HTTP $status")
        if (code.isNotBlank()) parts += code
        if (message.isNotBlank()) parts += message
        traceId?.takeIf { it.isNotBlank() }?.let { parts += "trace $it" }
        return ApiException(
            status = status,
            code = code,
            message = parts.joinToString(" - "),
            fieldErrors = fieldErrors,
            traceId = traceId
        )
    }

    private fun PlanningTask.toCreateBody(): JSONObject {
        return JSONObject()
            .put("title", title)
            .put("description", description)
            .put("type", type)
            .put("priority", priority)
            .put("status", status)
            .putNullable("plannedTime", plannedTime)
            .putNullable("dueTime", dueTime)
            .put("tagIds", JSONArray(tagIds))
    }

    private fun PlanningTask.toUpdateBody(): JSONObject {
        return JSONObject()
            .put("title", title)
            .put("description", description)
            .put("type", type)
            .put("priority", priority)
            .put("status", status)
            .putNullable("plannedTime", plannedTime)
            .putNullable("dueTime", dueTime)
            .put("archived", archived)
            .put("tagIds", JSONArray(tagIds))
            .put("version", version)
    }

    private fun JSONArray.toFolders(shared: Boolean): List<PlanningFolder> {
        return List(length()) { index -> getJSONObject(index).toFolder(shared = shared) }
    }

    private fun JSONArray.toGoals(shared: Boolean): List<PlanningGoal> {
        return List(length()) { index -> getJSONObject(index).toGoal(shared = shared) }
    }

    private fun JSONArray.toTasks(shared: Boolean): List<PlanningTask> {
        return List(length()) { index -> getJSONObject(index).toTask(shared = shared) }
    }

    private fun JSONArray.toTaskTags(): List<TaskTag> {
        return List(length()) { index -> getJSONObject(index).toTaskTag() }
    }

    private fun JSONObject.toFolder(shared: Boolean): PlanningFolder {
        return PlanningFolder(
            id = getString("id"),
            name = text("name"),
            description = text("description"),
            displayOrder = optInt("displayOrder", 0),
            archived = optBoolean("archived", false),
            shared = shared,
            version = optLong("version", 0),
            createdAt = text("createdAt").ifBlank { PlanningLocalStore.nowIso() },
            updatedAt = text("updatedAt").ifBlank { PlanningLocalStore.nowIso() },
            syncState = SyncState.Synced,
            lastError = null
        )
    }

    private fun JSONObject.toGoal(shared: Boolean): PlanningGoal {
        return PlanningGoal(
            id = getString("id"),
            folderId = text("folderId"),
            name = text("name"),
            description = text("description"),
            archived = optBoolean("archived", false),
            shared = shared,
            version = optLong("version", 0),
            createdAt = text("createdAt").ifBlank { PlanningLocalStore.nowIso() },
            updatedAt = text("updatedAt").ifBlank { PlanningLocalStore.nowIso() },
            syncState = SyncState.Synced,
            lastError = null
        )
    }

    private fun JSONObject.toTask(shared: Boolean): PlanningTask {
        return PlanningTask(
            id = getString("id"),
            goalId = text("goalId"),
            title = text("title"),
            description = text("description"),
            type = text("type").ifBlank { "green" },
            priority = optInt("priority", 5),
            status = text("status").ifBlank { "todo" },
            plannedTime = nullableText("plannedTime"),
            dueTime = nullableText("dueTime"),
            archived = optBoolean("archived", false),
            shared = shared,
            version = optLong("version", 0),
            tagIds = tagIds(),
            recurrenceJson = optJsonObjectString("recurrence"),
            remindersJson = optJsonArrayString("reminders"),
            createdAt = text("createdAt").ifBlank { PlanningLocalStore.nowIso() },
            updatedAt = text("updatedAt").ifBlank { PlanningLocalStore.nowIso() },
            syncState = SyncState.Synced,
            lastError = null
        )
    }

    private fun JSONObject.toTaskTag(): TaskTag {
        return TaskTag(
            id = getString("id"),
            name = text("name"),
            color = text("color").ifBlank { "#2f6b57" },
            syncState = SyncState.Synced,
            lastError = null
        )
    }

    private fun JSONObject.text(key: String): String {
        return if (has(key) && !isNull(key)) getString(key) else ""
    }

    private fun JSONObject.nullableText(key: String): String? {
        return if (has(key) && !isNull(key)) getString(key).ifBlank { null } else null
    }

    private fun JSONObject.putNullable(key: String, value: String?): JSONObject {
        if (value == null) {
            put(key, JSONObject.NULL)
        } else {
            put(key, value)
        }
        return this
    }

    private fun JSONObject.tagIds(): List<String> {
        val tags = optJSONArray("tags") ?: return emptyList()
        return List(tags.length()) { index ->
            tags.optJSONObject(index)?.optString("id").orEmpty()
        }.filter { it.isNotBlank() }
    }

    private fun JSONObject.optJsonObjectString(key: String): String? {
        return if (has(key) && !isNull(key)) optJSONObject(key)?.toString() else null
    }

    private fun JSONObject.optJsonArrayString(key: String): String? {
        return if (has(key) && !isNull(key)) optJSONArray(key)?.toString() else null
    }

    private fun JSONArray?.orEmptyArray(): JSONArray {
        return this ?: JSONArray()
    }

    private fun String.normalizedFor(task: PlanningTask): String {
        return try {
            val recurrence = JSONObject(this)
            val currentStartAt = recurrence.optString("startAt")
            val alignedStartAt = when (currentStartAt) {
                task.plannedTime, task.dueTime -> currentStartAt
                else -> task.plannedTime ?: task.dueTime ?: currentStartAt
            }
            if (alignedStartAt.isNotBlank()) {
                recurrence.put("startAt", alignedStartAt)
            }
            recurrence.toString()
        } catch (_: Exception) {
            this
        }
    }

    private fun String?.differsFromObject(remote: String?): Boolean {
        if (this.isNullOrBlank() && remote.isNullOrBlank()) {
            return false
        }
        if (this.isNullOrBlank() || remote.isNullOrBlank()) {
            return true
        }
        return try {
            this.recurrenceComparable() != remote.recurrenceComparable()
        } catch (_: Exception) {
            this != remote
        }
    }

    private fun String?.differsFromReminders(remote: String?): Boolean {
        if (this.isNullOrBlank() && remote.isNullOrBlank()) {
            return false
        }
        if (this.isNullOrBlank() || remote.isNullOrBlank()) {
            return true
        }
        return try {
            this.withoutReminderIds() != remote.withoutReminderIds()
        } catch (_: Exception) {
            this != remote
        }
    }

    private fun String.recurrenceComparable(): String {
        val recurrence = JSONObject(this)
        return JSONObject()
            .put("mode", recurrence.optString("mode"))
            .put("interval", recurrence.optInt("interval"))
            .put("daysOfWeek", recurrence.optJSONArray("daysOfWeek") ?: JSONArray())
            .putNullable("dayOfMonth", recurrence.nullableText("dayOfMonth"))
            .put("startAt", recurrence.optString("startAt"))
            .putNullable("endAt", recurrence.nullableText("endAt"))
            .put("active", recurrence.optBoolean("active", true))
            .toString()
    }

    private fun String.withoutReminderIds(): String {
        return try {
            val source = JSONArray(this)
            val cleaned = JSONArray()
            for (index in 0 until source.length()) {
                val reminder = source.getJSONObject(index)
                cleaned.put(
                    JSONObject()
                        .put("mode", reminder.optString("mode"))
                        .put("offsetMinutes", reminder.optInt("offsetMinutes"))
                        .put("active", reminder.optBoolean("active", true))
                )
            }
            cleaned.toString()
        } catch (_: Exception) {
            this
        }
    }
}
