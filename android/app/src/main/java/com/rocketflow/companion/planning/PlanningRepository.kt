package com.rocketflow.companion.planning

import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.SessionBoundResult
import com.rocketflow.companion.network.ApiException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject

class PlanningRepository(
    private val authRepository: AuthRepository,
    private val localStore: PlanningLocalStore,
    private val syncEnqueuer: PlanningSyncEnqueuer? = null
) {

    suspend fun syncAndLoad(session: AuthSession): PlanningLoadResult {
        return syncMutex.withLock {
            syncAndLoadLocked(session)
        }
    }

    private suspend fun syncAndLoadLocked(session: AuthSession): PlanningLoadResult {
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
        return syncAfterLocalChange(session)
    }

    suspend fun updateFolder(session: AuthSession, folder: PlanningFolder, draft: FolderDraft): PlanningLoadResult {
        localStore.updateFolder(session.user.id, folder, draft)
        return syncAfterLocalChange(session)
    }

    suspend fun deleteFolder(session: AuthSession, folder: PlanningFolder): PlanningLoadResult {
        localStore.deleteFolder(session.user.id, folder)
        return syncAfterLocalChange(session)
    }

    suspend fun createGoal(session: AuthSession, folderId: String, draft: GoalDraft): PlanningLoadResult {
        localStore.createGoal(session.user.id, folderId, draft)
        return syncAfterLocalChange(session)
    }

    suspend fun updateGoal(session: AuthSession, goal: PlanningGoal, draft: GoalDraft): PlanningLoadResult {
        localStore.updateGoal(session.user.id, goal, draft)
        return syncAfterLocalChange(session)
    }

    suspend fun deleteGoal(session: AuthSession, goal: PlanningGoal): PlanningLoadResult {
        localStore.deleteGoal(session.user.id, goal)
        return syncAfterLocalChange(session)
    }

    suspend fun createTask(session: AuthSession, goalId: String, draft: TaskDraft): PlanningLoadResult {
        localStore.createTask(session.user.id, goalId, draft)
        return syncAfterLocalChange(session)
    }

    suspend fun createIdea(session: AuthSession, folderId: String, draft: IdeaDraft): PlanningLoadResult {
        val result = authRepository.authorizedPost(
            session,
            "/folders/$folderId/ideas",
            JSONObject()
                .put("title", draft.title)
                .put("body", draft.body)
                .put("status", draft.status)
                .put("allowAuthorNoteEdits", draft.allowAuthorNoteEdits)
        )
        val idea = result.value.toIdea(shared = isSharedFolder(result.session.user.id, folderId))
        localStore.upsertRemoteIdeas(result.session.user.id, listOf(idea))
        val refreshed = pullRemote(result.session)
        return PlanningLoadResult(
            session = refreshed,
            snapshot = localStore.snapshot(refreshed.user.id, offline = false, lastSyncError = null)
        )
    }

    suspend fun updateIdea(session: AuthSession, idea: PlanningIdea, draft: IdeaDraft): PlanningLoadResult {
        val result = authRepository.authorizedPatch(
            session,
            "/ideas/${idea.id}",
            JSONObject()
                .put("title", draft.title)
                .put("body", draft.body)
                .put("status", draft.status)
                .put("displayOrder", idea.displayOrder)
                .put("archived", idea.archived)
                .put("allowAuthorNoteEdits", draft.allowAuthorNoteEdits)
                .put("version", idea.version)
        )
        val updated = result.value.toIdea(shared = idea.shared)
        localStore.upsertRemoteIdeas(result.session.user.id, listOf(updated))
        val refreshed = pullRemote(result.session)
        return PlanningLoadResult(
            session = refreshed,
            snapshot = localStore.snapshot(refreshed.user.id, offline = false, lastSyncError = null)
        )
    }

    suspend fun createIdeaNote(session: AuthSession, ideaId: String, draft: IdeaNoteDraft): PlanningLoadResult {
        val result = authRepository.authorizedPost(
            session,
            "/ideas/$ideaId/notes",
            JSONObject()
                .put("eventType", draft.eventType)
                .put("body", draft.body)
                .put("metadata", draft.metadataObject())
        )
        localStore.upsertRemoteIdeaNotes(result.session.user.id, listOf(result.value.toIdeaNote(ideaId)))
        val refreshed = pullRemote(result.session)
        return PlanningLoadResult(
            session = refreshed,
            snapshot = localStore.snapshot(refreshed.user.id, offline = false, lastSyncError = null)
        )
    }

    suspend fun updateIdeaNote(session: AuthSession, note: IdeaNote, draft: IdeaNoteDraft): PlanningLoadResult {
        val result = authRepository.authorizedPatch(
            session,
            "/idea-notes/${note.id}",
            JSONObject()
                .put("eventType", draft.eventType)
                .put("body", draft.body)
                .put("metadata", draft.metadataObject())
                .put("version", note.version)
        )
        localStore.upsertRemoteIdeaNotes(result.session.user.id, listOf(result.value.toIdeaNote(note.ideaId)))
        val refreshed = pullRemote(result.session)
        return PlanningLoadResult(
            session = refreshed,
            snapshot = localStore.snapshot(refreshed.user.id, offline = false, lastSyncError = null)
        )
    }

    suspend fun createNote(session: AuthSession, folderId: String, draft: NoteDraft): PlanningLoadResult {
        localStore.createNote(session.user.id, folderId, draft)
        return syncAfterLocalChange(session)
    }

    suspend fun updateNote(session: AuthSession, note: PlanningNote, draft: NoteDraft): PlanningLoadResult {
        localStore.updateNote(session.user.id, note, draft)
        return syncAfterLocalChange(session)
    }

    suspend fun deleteNote(session: AuthSession, note: PlanningNote): PlanningLoadResult {
        localStore.deleteNote(session.user.id, note)
        return syncAfterLocalChange(session)
    }

    suspend fun createEntityLink(session: AuthSession, draft: EntityLinkDraft): PlanningLoadResult {
        localStore.createEntityLink(session.user.id, draft)
        return syncAfterLocalChange(session)
    }

    suspend fun deleteEntityLink(session: AuthSession, link: EntityLink): PlanningLoadResult {
        localStore.deleteEntityLink(session.user.id, link)
        return syncAfterLocalChange(session)
    }

    suspend fun moveFolder(session: AuthSession, folder: PlanningFolder, targetFolderId: String): PlanningLoadResult =
        moveEntity(session, "/folders/${folder.id}/move", JSONObject().put("targetFolderId", targetFolderId).put("version", folder.version))

    suspend fun moveGoal(session: AuthSession, goal: PlanningGoal, targetFolderId: String): PlanningLoadResult =
        moveEntity(session, "/goals/${goal.id}/move", JSONObject().put("targetFolderId", targetFolderId).put("version", goal.version))

    suspend fun moveTask(session: AuthSession, task: PlanningTask, targetGoalId: String): PlanningLoadResult =
        moveEntity(session, "/tasks/${task.id}/move-to-goal", JSONObject().put("targetGoalId", targetGoalId).put("version", task.version))

    suspend fun moveIdea(session: AuthSession, idea: PlanningIdea, targetFolderId: String): PlanningLoadResult =
        moveEntity(session, "/ideas/${idea.id}/move", JSONObject().put("targetFolderId", targetFolderId).put("version", idea.version))

    suspend fun moveNote(session: AuthSession, note: PlanningNote, targetFolderId: String): PlanningLoadResult =
        moveEntity(session, "/notes/${note.id}/move", JSONObject().put("targetFolderId", targetFolderId).put("version", note.version))

    suspend fun cloneFolder(session: AuthSession, folder: PlanningFolder, targetFolderId: String): PlanningLoadResult =
        moveEntity(session, "/folders/${folder.id}/clone", JSONObject().put("targetFolderId", targetFolderId).put("includeChildren", false))

    suspend fun cloneGoal(session: AuthSession, goal: PlanningGoal, targetFolderId: String): PlanningLoadResult =
        moveEntity(session, "/goals/${goal.id}/clone", JSONObject().put("targetFolderId", targetFolderId))

    suspend fun cloneTask(session: AuthSession, task: PlanningTask, targetGoalId: String): PlanningLoadResult =
        moveEntity(session, "/tasks/${task.id}/clone", JSONObject().put("targetGoalId", targetGoalId).put("includeTags", false))

    suspend fun cloneIdea(session: AuthSession, idea: PlanningIdea, targetFolderId: String): PlanningLoadResult =
        moveEntity(session, "/ideas/${idea.id}/clone", JSONObject().put("targetFolderId", targetFolderId))

    suspend fun cloneNote(session: AuthSession, note: PlanningNote, targetFolderId: String): PlanningLoadResult =
        moveEntity(session, "/notes/${note.id}/clone", JSONObject().put("targetFolderId", targetFolderId))

    private suspend fun moveEntity(session: AuthSession, path: String, body: JSONObject): PlanningLoadResult {
        val result = authRepository.authorizedPost(session, path, body)
        val refreshed = pullRemote(result.session)
        return PlanningLoadResult(
            session = refreshed,
            snapshot = localStore.snapshot(refreshed.user.id, offline = false, lastSyncError = null)
        )
    }

    suspend fun createTag(session: AuthSession, draft: TaskTagDraft): PlanningLoadResult {
        localStore.createTag(session.user.id, draft)
        return syncAfterLocalChange(session)
    }

    suspend fun updateTask(session: AuthSession, task: PlanningTask, draft: TaskDraft): PlanningLoadResult {
        localStore.updateTask(session.user.id, task, draft)
        return syncAfterLocalChange(session)
    }

    suspend fun deleteTask(session: AuthSession, task: PlanningTask): PlanningLoadResult {
        localStore.deleteTask(session.user.id, task)
        return syncAfterLocalChange(session)
    }

    private suspend fun syncAfterLocalChange(session: AuthSession): PlanningLoadResult {
        val result = syncAndLoad(session)
        if (result.snapshot.offline || result.snapshot.pendingCount > 0) {
            syncEnqueuer?.enqueuePlanningSync(PlanningSyncReason.PendingChange)
        }
        return result
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

    suspend fun getIdea(session: AuthSession, ideaId: String): Pair<AuthSession, PlanningIdea?> {
        localStore.findIdea(session.user.id, ideaId)?.let { return session to it }

        return try {
            val result = authRepository.authorizedGet(session, "/ideas/$ideaId")
            val idea = result.value.toIdea(shared = result.value.optBoolean("shared", false))
            localStore.upsertRemoteIdeas(result.session.user.id, listOf(idea))
            result.session to idea
        } catch (error: ApiException) {
            if (error.status == 401) {
                throw error
            }
            session to localStore.findIdea(session.user.id, ideaId)
        } catch (_: Exception) {
            session to localStore.findIdea(session.user.id, ideaId)
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

        localStore.pendingNotes(userId).forEach { note ->
            activeSession = pushNote(activeSession, note)
        }

        localStore.pendingEntityLinks(userId).forEach { link ->
            activeSession = pushEntityLink(activeSession, link)
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
                            .putNullable("parentFolderId", folder.parentFolderId)
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
                            .putNullable("parentFolderId", folder.parentFolderId)
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
                            .put("status", goal.status)
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
                            .put("status", goal.status)
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
                    val result = authRepository.authorizedPost(
                        session,
                        "/goals/${task.goalId}/tasks",
                        task.toCreateBody()
                    )
                    val remoteTask = result.value.toTask(shared = task.shared)
                    val metadataSession = syncTaskMetadata(
                        result.session,
                        remoteTask.id,
                        recurrenceJson
                    )
                    val refreshed = authRepository.authorizedGet(metadataSession, "/tasks/${remoteTask.id}")
                    localStore.applySyncedTask(userId, task.id, refreshed.value.toTask(shared = task.shared))
                    refreshed.session
                }

                SyncState.PendingUpdate -> {
                    val remoteBefore = authRepository.authorizedGet(session, "/tasks/${task.id}")
                    val recurrenceJson = if (task.recurrenceJson.differsFromObject(remoteBefore.value.optJsonObjectString("recurrence"))) {
                        task.recurrenceJson?.normalizedFor(task)
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
                        recurrenceJson
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

    private suspend fun pushNote(session: AuthSession, note: PlanningNote): AuthSession {
        val userId = session.user.id
        return try {
            when (note.syncState) {
                SyncState.PendingCreate -> {
                    val result = authRepository.authorizedPost(
                        session,
                        "/folders/${note.folderId}/notes",
                        JSONObject()
                            .put("title", note.title)
                            .put("body", note.body)
                    )
                    localStore.applySyncedNote(userId, note.id, result.value.toNote(shared = note.shared))
                    result.session
                }

                SyncState.PendingUpdate -> {
                    val result = authRepository.authorizedPatch(
                        session,
                        "/notes/${note.id}",
                        JSONObject()
                            .put("title", note.title)
                            .put("body", note.body)
                            .put("displayOrder", note.displayOrder)
                            .put("archived", note.archived)
                            .put("version", note.version)
                    )
                    localStore.applySyncedNote(userId, note.id, result.value.toNote(shared = note.shared))
                    result.session
                }

                SyncState.PendingDelete -> {
                    val refreshed = authRepository.authorizedDelete(session, "/notes/${note.id}")
                    localStore.removeNote(userId, note.id)
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
                PlanningLocalStore.TABLE_NOTES,
                note.id,
                error.message,
                conflict = error.status == 409 || error.code == "conflict"
            )
            session
        }
    }

    private suspend fun pushEntityLink(session: AuthSession, link: EntityLink): AuthSession {
        val userId = session.user.id
        return try {
            when (link.syncState) {
                SyncState.PendingCreate -> {
                    val result = authRepository.authorizedPost(
                        session,
                        "/entity-links",
                        link.toCreateBody()
                    )
                    localStore.applySyncedEntityLink(userId, link.id, result.value.toEntityLink())
                    result.session
                }

                SyncState.PendingDelete -> {
                    val refreshed = authRepository.authorizedDelete(session, "/entity-links/${link.id}")
                    localStore.removeEntityLink(userId, link.id)
                    refreshed
                }

                SyncState.PendingUpdate,
                SyncState.Conflict,
                SyncState.Synced -> session
            }
        } catch (error: ApiException) {
            if (error.status == 401) {
                throw error
            }
            localStore.markSyncError(
                userId,
                PlanningLocalStore.TABLE_ENTITY_LINKS,
                link.id,
                error.message,
                conflict = error.status == 409 || error.code == "conflict"
            )
            session
        }
    }

    private suspend fun syncTaskMetadata(
        session: AuthSession,
        taskId: String,
        recurrenceJson: String?
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
        val allIdeas = mutableListOf<PlanningIdea>()
        val allIdeaNotes = mutableListOf<IdeaNote>()
        val allNotes = mutableListOf<PlanningNote>()
        folders.filterNot { it.archived }.forEach { folder ->
            val goalsResult = syncGet(activeSession, "/folders/${folder.id}/goals")
            activeSession = goalsResult.session
            val goals = goalsResult.value.getJSONArray("items").toGoals(shared = false)
            allGoals += goals

            val ideasResult = syncOptionalItems(activeSession, "/folders/${folder.id}/ideas")
            activeSession = ideasResult.first
            val ideas = ideasResult.second.toIdeas(shared = false)
            allIdeas += ideas
            ideas.filterNot { it.archived }.forEach { idea ->
                val notesResult = syncOptionalItems(activeSession, "/ideas/${idea.id}/notes")
                activeSession = notesResult.first
                allIdeaNotes += notesResult.second.toIdeaNotes(idea.id)
            }

            val notesResult = syncOptionalItems(activeSession, "/folders/${folder.id}/notes")
            activeSession = notesResult.first
            allNotes += notesResult.second.toNotes(shared = false)

            goals.filterNot { it.archived }.forEach { goal ->
                val tasksResult = syncGet(activeSession, "/goals/${goal.id}/tasks")
                activeSession = tasksResult.session
                allTasks += tasksResult.value.getJSONArray("items").toTasks(shared = false)
            }
        }
        localStore.upsertRemoteGoals(userId, allGoals)
        localStore.upsertRemoteTasks(userId, allTasks)
        localStore.upsertRemoteIdeas(userId, allIdeas)
        localStore.upsertRemoteIdeaNotes(userId, allIdeaNotes)
        localStore.upsertRemoteNotes(userId, allNotes)

        val sharedResult = syncGet(activeSession, "/shares/resources")
        activeSession = sharedResult.session
        val sharedFolderObjects = sharedResult.value.optJSONArray("folders").orEmptyArray()
        val sharedGoalObjects = sharedResult.value.optJSONArray("goals").orEmptyArray()
        val sharedTaskObjects = sharedResult.value.optJSONArray("tasks").orEmptyArray()
        val createTaskGoalIds = sharedResult.value.optJSONArray("createTaskGoalIds").toStringSet()
        val sharedFolders = sharedFolderObjects.toFolders(shared = true).toMutableList()
        val sharedGoals = sharedGoalObjects.toGoals(shared = true)
            .map { goal -> goal.copy(canCreateTasks = goal.fullAccess || goal.id in createTaskGoalIds) }
            .toMutableList()
        val sharedTasks = sharedTaskObjects.toTasks(shared = true)
        sharedGoalObjects.forEachObject { goalJson ->
            goalJson.optJSONObject("folder")?.toFolder(shared = true)?.let { sharedFolders += it }
        }
        sharedTaskObjects.forEachObject { taskJson ->
            taskJson.optJSONObject("folder")?.toFolder(shared = true)?.let { sharedFolders += it }
            taskJson.optJSONObject("goal")?.let { goalJson ->
                sharedGoals += goalJson.toGoal(shared = true)
                    .copy(canCreateTasks = goalJson.optBoolean("fullAccess", false) || goalJson.text("id") in createTaskGoalIds)
                goalJson.optJSONObject("folder")?.toFolder(shared = true)?.let { sharedFolders += it }
            }
        }
        localStore.replaceRemoteSharedResources(
            userId,
            folders = sharedFolders.distinctBy { it.id },
            goals = sharedGoals.distinctBy { it.id },
            tasks = sharedTasks
        )

        val sharedIdeas = mutableListOf<PlanningIdea>()
        val sharedIdeaNotes = mutableListOf<IdeaNote>()
        val sharedNotes = mutableListOf<PlanningNote>()
        sharedFolders.distinctBy { it.id }.filterNot { it.archived }.forEach { folder ->
            val ideasResult = syncOptionalItems(activeSession, "/folders/${folder.id}/ideas")
            activeSession = ideasResult.first
            val ideas = ideasResult.second.toIdeas(shared = true)
            sharedIdeas += ideas
            ideas.filterNot { it.archived }.forEach { idea ->
                val notesResult = syncOptionalItems(activeSession, "/ideas/${idea.id}/notes")
                activeSession = notesResult.first
                sharedIdeaNotes += notesResult.second.toIdeaNotes(idea.id)
            }
            val notesResult = syncOptionalItems(activeSession, "/folders/${folder.id}/notes")
            activeSession = notesResult.first
            sharedNotes += notesResult.second.toNotes(shared = true)
        }
        localStore.upsertRemoteIdeas(userId, sharedIdeas.distinctBy { it.id })
        localStore.upsertRemoteIdeaNotes(userId, sharedIdeaNotes.distinctBy { it.id })
        localStore.upsertRemoteNotes(userId, sharedNotes.distinctBy { it.id })

        val linkEntities = (allGoals + sharedGoals).map { "goal" to it.id } +
            (allTasks + sharedTasks).map { "task" to it.id } +
            (allIdeas + sharedIdeas).map { "idea" to it.id } +
            (allNotes + sharedNotes).map { "note" to it.id }
        val allLinks = mutableListOf<EntityLink>()
        var allLinkPullsSucceeded = true
        linkEntities.distinct().forEach { (type, id) ->
            val linksResult = syncOptionalItemsWithStatus(activeSession, "/entity-links?entityType=$type&entityId=$id")
            activeSession = linksResult.session
            allLinkPullsSucceeded = allLinkPullsSucceeded && linksResult.succeeded
            allLinks += linksResult.items.toEntityLinks()
        }
        if (allLinkPullsSucceeded) {
            localStore.replaceRemoteEntityLinks(userId, allLinks.distinctBy { it.id })
        } else {
            localStore.upsertRemoteEntityLinks(userId, allLinks.distinctBy { it.id })
        }

        return activeSession
    }

    private suspend fun syncGet(session: AuthSession, path: String): SessionBoundResult<JSONObject> {
        return try {
            authRepository.authorizedGet(session, path)
        } catch (error: ApiException) {
            throw error.withSyncContext("GET", path)
        }
    }

    private suspend fun syncOptionalItems(session: AuthSession, path: String): Pair<AuthSession, JSONArray> {
        return try {
            val result = authRepository.authorizedGet(session, path)
            result.session to result.value.optJSONArray("items").orEmptyArray()
        } catch (error: ApiException) {
            if (error.status == 401) {
                throw error
            }
            session to JSONArray()
        } catch (_: Exception) {
            session to JSONArray()
        }
    }

    private suspend fun syncOptionalItemsWithStatus(session: AuthSession, path: String): OptionalItemsResult {
        return try {
            val result = authRepository.authorizedGet(session, path)
            OptionalItemsResult(result.session, result.value.optJSONArray("items").orEmptyArray(), succeeded = true)
        } catch (error: ApiException) {
            if (error.status == 401) {
                throw error
            }
            OptionalItemsResult(session, JSONArray(), succeeded = false)
        } catch (_: Exception) {
            OptionalItemsResult(session, JSONArray(), succeeded = false)
        }
    }

    private data class OptionalItemsResult(
        val session: AuthSession,
        val items: JSONArray,
        val succeeded: Boolean
    )

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

    private fun EntityLink.toCreateBody(): JSONObject {
        return JSONObject()
            .put("sourceType", sourceType)
            .put("sourceId", sourceId)
            .put("targetType", targetType)
            .put("targetId", targetId)
            .put("relationType", relationType)
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

    private fun JSONArray.toIdeas(shared: Boolean): List<PlanningIdea> {
        return List(length()) { index -> getJSONObject(index).toIdea(shared = shared) }
    }

    private fun JSONArray.toIdeaNotes(ideaId: String): List<IdeaNote> {
        return List(length()) { index -> getJSONObject(index).toIdeaNote(ideaId) }
    }

    private fun JSONArray.toNotes(shared: Boolean): List<PlanningNote> {
        return List(length()) { index -> getJSONObject(index).toNote(shared = shared) }
    }

    private fun JSONArray.toEntityLinks(): List<EntityLink> {
        return List(length()) { index -> getJSONObject(index).toEntityLink() }
    }

    private fun JSONArray.toTaskTags(): List<TaskTag> {
        return List(length()) { index -> getJSONObject(index).toTaskTag() }
    }

    private fun JSONArray.forEachObject(block: (JSONObject) -> Unit) {
        for (index in 0 until length()) {
            optJSONObject(index)?.let(block)
        }
    }

    private fun JSONObject.toFolder(shared: Boolean): PlanningFolder {
        return PlanningFolder(
            id = getString("id"),
            parentFolderId = nullableText("parentFolderId") ?: optJSONObject("parentFolder")?.nullableText("id"),
            name = text("name"),
            description = text("description"),
            displayOrder = optInt("displayOrder", 0),
            archived = optBoolean("archived", false),
            shared = shared,
            fullAccess = optBoolean("fullAccess", !shared),
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
            folderId = text("folderId").ifBlank { optJSONObject("folder")?.text("id").orEmpty() },
            name = text("name"),
            description = text("description"),
            status = text("status").ifBlank { "todo" },
            archived = optBoolean("archived", false),
            shared = shared,
            canCreateTasks = !shared || optBoolean("fullAccess", false) || optBoolean("canCreateTasks", false),
            fullAccess = optBoolean("fullAccess", !shared),
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
            goalId = text("goalId").ifBlank { optJSONObject("goal")?.text("id").orEmpty() },
            title = text("title"),
            description = text("description"),
            type = text("type").ifBlank { "green" },
            priority = optInt("priority", 5),
            status = text("status").ifBlank { "todo" },
            plannedTime = nullableText("plannedTime"),
            dueTime = nullableText("dueTime"),
            archived = optBoolean("archived", false),
            shared = shared,
            fullAccess = optBoolean("fullAccess", !shared),
            creatorUserId = nullableText("creatorUserId"),
            creatorEmail = nullableText("creatorEmail"),
            creatorName = nullableText("creatorName"),
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

    private fun JSONObject.toIdea(shared: Boolean): PlanningIdea {
        return PlanningIdea(
            id = getString("id"),
            folderId = text("folderId").ifBlank { optJSONObject("folder")?.text("id").orEmpty() },
            title = text("title").ifBlank { text("name") },
            body = text("body").ifBlank { text("description") },
            status = text("status").ifBlank { "active" },
            displayOrder = optInt("displayOrder", 0),
            archived = optBoolean("archived", false),
            shared = shared,
            fullAccess = optBoolean("fullAccess", !shared),
            allowAuthorNoteEdits = optBoolean("allowAuthorNoteEdits", false),
            version = optLong("version", 0),
            createdAt = text("createdAt").ifBlank { PlanningLocalStore.nowIso() },
            updatedAt = text("updatedAt").ifBlank { PlanningLocalStore.nowIso() },
            syncState = SyncState.Synced,
            lastError = null
        )
    }

    private fun JSONObject.toIdeaNote(ideaIdFallback: String): IdeaNote {
        val author = optJSONObject("author")
        return IdeaNote(
            id = getString("id"),
            ideaId = text("ideaId").ifBlank { ideaIdFallback },
            eventType = text("eventType").ifBlank { "note" },
            body = text("body"),
            metadataJson = (optJSONObject("metadata") ?: JSONObject()).toString(),
            authorUserId = nullableText("authorUserId") ?: author?.nullableText("id"),
            authorEmail = nullableText("authorEmail") ?: author?.nullableText("email"),
            authorName = nullableText("authorName") ?: author?.nullableText("displayName") ?: author?.nullableText("name"),
            version = optLong("version", 0),
            createdAt = text("createdAt").ifBlank { PlanningLocalStore.nowIso() },
            updatedAt = text("updatedAt").ifBlank { text("createdAt").ifBlank { PlanningLocalStore.nowIso() } }
        )
    }

    private fun JSONObject.toNote(shared: Boolean): PlanningNote {
        val author = optJSONObject("author")
        return PlanningNote(
            id = getString("id"),
            folderId = text("folderId").ifBlank { optJSONObject("folder")?.text("id").orEmpty() },
            authorUserId = nullableText("authorUserId") ?: author?.nullableText("id"),
            authorEmail = nullableText("authorEmail") ?: author?.nullableText("email"),
            authorName = nullableText("authorName") ?: author?.nullableText("displayName") ?: author?.nullableText("name"),
            title = text("title"),
            body = text("body"),
            displayOrder = optInt("displayOrder", 0),
            archived = optBoolean("archived", false),
            shared = shared,
            fullAccess = optBoolean("fullAccess", !shared),
            version = optLong("version", 0),
            createdAt = text("createdAt").ifBlank { PlanningLocalStore.nowIso() },
            updatedAt = text("updatedAt").ifBlank { PlanningLocalStore.nowIso() },
            syncState = SyncState.Synced,
            lastError = null
        )
    }

    private fun JSONObject.toEntityLink(): EntityLink {
        val sourceObject = optJSONObject("source")
        val targetObject = optJSONObject("target")
        val sourceType = text("sourceType").ifBlank { sourceObject?.text("type").orEmpty() }
        val sourceId = text("sourceId").ifBlank { sourceObject?.text("id").orEmpty() }
        val targetType = text("targetType").ifBlank { targetObject?.text("type").orEmpty() }
        val targetId = text("targetId").ifBlank { targetObject?.text("id").orEmpty() }
        return EntityLink(
            id = getString("id"),
            sourceType = sourceType,
            sourceId = sourceId,
            targetType = targetType,
            targetId = targetId,
            relationType = text("relationType").ifBlank { "related" },
            source = sourceObject?.toEntityRef() ?: EntityRef(sourceType, sourceId, "", null),
            target = targetObject?.toEntityRef() ?: EntityRef(targetType, targetId, "", null),
            createdByUserId = nullableText("createdByUserId"),
            archived = optBoolean("archived", false),
            version = optLong("version", 0),
            createdAt = text("createdAt").ifBlank { PlanningLocalStore.nowIso() },
            updatedAt = text("updatedAt").ifBlank { PlanningLocalStore.nowIso() }
        )
    }

    private fun JSONObject.toEntityRef(): EntityRef {
        return EntityRef(
            type = text("type"),
            id = text("id"),
            title = text("title").ifBlank { text("name").ifBlank { text("label") } },
            subtitle = nullableText("subtitle") ?: nullableText("path")
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

    private fun IdeaNoteDraft.metadataObject(): JSONObject {
        return try {
            JSONObject(metadataJson)
        } catch (_: Exception) {
            JSONObject()
        }
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

    private fun JSONArray?.toStringSet(): Set<String> {
        if (this == null) {
            return emptySet()
        }
        return List(length()) { index -> optString(index) }
            .filter { it.isNotBlank() }
            .toSet()
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

    private fun isSharedFolder(userId: String, folderId: String): Boolean {
        return localStore.snapshot(userId, offline = false, lastSyncError = null)
            .sharedFolders
            .any { it.id == folderId }
    }

    companion object {
        private val syncMutex = Mutex()
    }

}
