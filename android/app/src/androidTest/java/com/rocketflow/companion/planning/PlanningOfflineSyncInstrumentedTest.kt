package com.rocketflow.companion.planning

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rocketflow.companion.BuildConfig
import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.AuthTokens
import com.rocketflow.companion.auth.CurrentUser
import com.rocketflow.companion.auth.SessionStore
import com.rocketflow.companion.network.HttpJsonClient
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PlanningOfflineSyncInstrumentedTest {

    private lateinit var context: Context

    @Before
    fun resetLocalDatabase() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase("rocketflow_planning.db")
    }

    @Test
    fun androidOfflineChangesSyncBackToBackendAndRemoteChangesSyncToAndroid() = runBlocking {
        val unique = System.currentTimeMillis()
        val email = "android-e2e-$unique@example.test"
        val password = "ValidationPass123!"
        val onlineClient = HttpJsonClient(BuildConfig.ROCKETFLOW_API_BASE_URL)

        registerUser(onlineClient, email, password)
        val session = login(onlineClient, email, password)

        val onlineRepository = planningRepository(BuildConfig.ROCKETFLOW_API_BASE_URL)
        val offlineRepository = planningRepository("http://10.0.2.2:9/api")

        val remoteFolderId = createRemoteFolder(onlineClient, session, "Web Folder $unique")
        val remoteGoalId = createRemoteGoal(onlineClient, session, remoteFolderId, "Web Goal $unique")
        createRemoteTask(onlineClient, session, remoteGoalId, "Web Task $unique")
        val tagId = createRemoteTag(onlineClient, session, "Android Preserve $unique")
        val richRemoteTaskId = createRemoteTask(
            onlineClient,
            session,
            remoteGoalId,
            "Web Rich Task $unique",
            listOf(tagId)
        )
        upsertRemoteRecurrence(onlineClient, session, richRemoteTaskId)

        val pulled = onlineRepository.syncAndLoad(session)
        assertTrue(pulled.snapshot.folders.any { it.name == "Web Folder $unique" })
        assertTrue(pulled.snapshot.goals.any { it.name == "Web Goal $unique" })
        assertTrue(pulled.snapshot.tasks.any { it.title == "Web Task $unique" })
        val pulledRichTask = pulled.snapshot.tasks.first { it.title == "Web Rich Task $unique" }
        assertEquals(listOf(tagId), pulledRichTask.tagIds)

        val offlineRichUpdate = offlineRepository.updateTask(
            pulled.session,
            pulledRichTask,
            TaskDraft(
                title = "Web Rich Task Edited $unique",
                description = "Edited from Android without metadata authoring",
                type = "green",
                priority = 5,
                status = "in_progress",
                plannedTime = "2026-05-12T09:00:00Z",
                dueTime = "2026-05-12T18:00:00Z"
            )
        )
        assertTrue(offlineRichUpdate.snapshot.offline)
        val syncedRichUpdate = onlineRepository.syncAndLoad(pulled.session)
        val syncedRichTask = syncedRichUpdate.snapshot.tasks.first { it.title == "Web Rich Task Edited $unique" }
        assertRemoteTaskMetadataPreserved(onlineClient, syncedRichUpdate.session, syncedRichTask.id, tagId)

        val offlineFolder = offlineRepository.createFolder(
            session,
            FolderDraft("Phone Folder $unique", "Created while offline")
        )
        assertTrue(offlineFolder.snapshot.offline)
        assertEquals(1, offlineFolder.snapshot.pendingCount)
        val localFolderId = offlineFolder.snapshot.folders.first { it.name == "Phone Folder $unique" }.id

        val offlineGoal = offlineRepository.createGoal(
            session,
            localFolderId,
            GoalDraft("Phone Goal $unique", "Offline goal")
        )
        val localGoalId = offlineGoal.snapshot.goals.first { it.name == "Phone Goal $unique" }.id

        val offlineTask = offlineRepository.createTask(
            session,
            localGoalId,
            TaskDraft(
                title = "Phone Task $unique",
                description = "Offline task",
                type = "green",
                priority = 6,
                status = "todo",
                plannedTime = "2026-05-10T09:00:00Z",
                dueTime = "2026-05-10T18:00:00Z"
            )
        )
        assertTrue(offlineTask.snapshot.offline)
        assertTrue(offlineTask.snapshot.pendingCount >= 3)

        val syncedAfterCreate = onlineRepository.syncAndLoad(session)
        assertFalse(syncedAfterCreate.snapshot.offline)
        assertEquals(0, syncedAfterCreate.snapshot.pendingCount)
        val remotePhoneFolder = syncedAfterCreate.snapshot.folders.first { it.name == "Phone Folder $unique" }
        val remotePhoneGoal = syncedAfterCreate.snapshot.goals.first { it.name == "Phone Goal $unique" }
        val remotePhoneTask = syncedAfterCreate.snapshot.tasks.first { it.title == "Phone Task $unique" }
        assertTrue(remotePhoneFolder.id != localFolderId)
        assertTrue(remotePhoneGoal.id != localGoalId)
        assertBackendTaskExists(onlineClient, syncedAfterCreate.session, remotePhoneGoal.id, "Phone Task $unique")

        val offlineFolderUpdate = offlineRepository.updateFolder(
            syncedAfterCreate.session,
            remotePhoneFolder,
            FolderDraft("Phone Folder Edited $unique", "Folder edited offline")
        )
        assertTrue(offlineFolderUpdate.snapshot.offline)
        val syncedAfterFolderUpdate = onlineRepository.syncAndLoad(syncedAfterCreate.session)
        val editedFolder = syncedAfterFolderUpdate.snapshot.folders.first { it.id == remotePhoneFolder.id }
        assertEquals("Phone Folder Edited $unique", editedFolder.name)

        val goalBeforeUpdate = syncedAfterFolderUpdate.snapshot.goals.first { it.id == remotePhoneGoal.id }
        val offlineGoalUpdate = offlineRepository.updateGoal(
            syncedAfterFolderUpdate.session,
            goalBeforeUpdate,
            GoalDraft("Phone Goal Edited $unique", "Goal edited offline")
        )
        assertTrue(offlineGoalUpdate.snapshot.offline)
        val syncedAfterGoalUpdate = onlineRepository.syncAndLoad(syncedAfterFolderUpdate.session)
        val editedGoal = syncedAfterGoalUpdate.snapshot.goals.first { it.id == remotePhoneGoal.id }
        assertEquals("Phone Goal Edited $unique", editedGoal.name)
        val taskBeforeUpdate = syncedAfterGoalUpdate.snapshot.tasks.first { it.id == remotePhoneTask.id }

        val offlineUpdate = offlineRepository.updateTask(
            syncedAfterGoalUpdate.session,
            taskBeforeUpdate,
            TaskDraft(
                title = "Phone Task Edited $unique",
                description = "Edited offline",
                type = "red",
                priority = 8,
                status = "in_progress",
                plannedTime = "2026-05-11T09:00:00Z",
                dueTime = "2026-05-11T18:00:00Z"
            )
        )
        assertTrue(offlineUpdate.snapshot.offline)
        assertTrue(offlineUpdate.snapshot.pendingCount >= 1)

        val syncedAfterUpdate = onlineRepository.syncAndLoad(syncedAfterGoalUpdate.session)
        val editedTask = syncedAfterUpdate.snapshot.tasks.first { it.title == "Phone Task Edited $unique" }
        assertEquals("red", editedTask.type)
        assertEquals("in_progress", editedTask.status)
        assertBackendTaskExists(onlineClient, syncedAfterUpdate.session, editedGoal.id, "Phone Task Edited $unique")

        val offlineDelete = offlineRepository.deleteTask(syncedAfterUpdate.session, editedTask)
        assertTrue(offlineDelete.snapshot.offline)
        val syncedAfterDelete = onlineRepository.syncAndLoad(syncedAfterUpdate.session)
        assertFalse(syncedAfterDelete.snapshot.tasks.any { it.id == editedTask.id })
        assertBackendTaskArchived(onlineClient, syncedAfterDelete.session, editedTask.id)

        val goalBeforeDelete = syncedAfterDelete.snapshot.goals.first { it.id == editedGoal.id }
        val offlineGoalDelete = offlineRepository.deleteGoal(syncedAfterDelete.session, goalBeforeDelete)
        assertTrue(offlineGoalDelete.snapshot.offline)
        val syncedAfterGoalDelete = onlineRepository.syncAndLoad(syncedAfterDelete.session)
        assertFalse(syncedAfterGoalDelete.snapshot.goals.any { it.id == editedGoal.id })

        val folderBeforeDelete = syncedAfterGoalDelete.snapshot.folders.first { it.id == editedFolder.id }
        val offlineFolderDelete = offlineRepository.deleteFolder(syncedAfterGoalDelete.session, folderBeforeDelete)
        assertTrue(offlineFolderDelete.snapshot.offline)
        val syncedAfterFolderDelete = onlineRepository.syncAndLoad(syncedAfterGoalDelete.session)
        assertFalse(syncedAfterFolderDelete.snapshot.folders.any { it.id == editedFolder.id })
    }

    private fun planningRepository(baseUrl: String): PlanningRepository {
        val client = HttpJsonClient(baseUrl)
        val authRepository = AuthRepository(client, SessionStore(context))
        return PlanningRepository(authRepository, PlanningLocalStore(context))
    }

    private suspend fun registerUser(client: HttpJsonClient, email: String, password: String) {
        client.post(
            "/auth/register",
            JSONObject()
                .put("email", email)
                .put("password", password)
                .put("displayName", "Android E2E")
                .put("timezone", "Europe/Moscow")
                .put("language", "en")
        )
    }

    private suspend fun login(client: HttpJsonClient, email: String, password: String): AuthSession {
        return client.post(
            "/auth/login",
            JSONObject()
                .put("email", email)
                .put("password", password)
        ).toSession()
    }

    private suspend fun createRemoteFolder(client: HttpJsonClient, session: AuthSession, name: String): String {
        return client.post(
            "/folders",
            JSONObject()
                .put("name", name)
                .put("description", "Remote folder"),
            session.tokens.accessToken
        ).getString("id")
    }

    private suspend fun createRemoteGoal(
        client: HttpJsonClient,
        session: AuthSession,
        folderId: String,
        name: String
    ): String {
        return client.post(
            "/folders/$folderId/goals",
            JSONObject()
                .put("name", name)
                .put("description", "Remote goal"),
            session.tokens.accessToken
        ).getString("id")
    }

    private suspend fun createRemoteTask(
        client: HttpJsonClient,
        session: AuthSession,
        goalId: String,
        title: String,
        tagIds: List<String> = emptyList()
    ): String {
        return client.post(
            "/goals/$goalId/tasks",
            taskPayload(title, "Remote task", "green", 4, "todo", tagIds),
            session.tokens.accessToken
        ).getString("id")
    }

    private suspend fun createRemoteTag(client: HttpJsonClient, session: AuthSession, name: String): String {
        return client.post(
            "/tags",
            JSONObject()
                .put("name", name)
                .put("color", "#2f80ed"),
            session.tokens.accessToken
        ).getString("id")
    }

    private suspend fun upsertRemoteRecurrence(client: HttpJsonClient, session: AuthSession, taskId: String) {
        client.put(
            "/tasks/$taskId/recurrence",
            JSONObject()
                .put("mode", "daily")
                .put("interval", 1)
                .put("startAt", "2026-05-10T09:00:00Z")
                .put("active", true),
            session.tokens.accessToken
        )
    }

    private suspend fun assertBackendTaskExists(
        client: HttpJsonClient,
        session: AuthSession,
        goalId: String,
        title: String
    ) {
        val tasks = client.get("/goals/$goalId/tasks", session.tokens.accessToken).getJSONArray("items")
        assertTrue((0 until tasks.length()).any { tasks.getJSONObject(it).getString("title") == title })
    }

    private suspend fun assertBackendTaskArchived(client: HttpJsonClient, session: AuthSession, taskId: String) {
        val task = client.get("/tasks/$taskId", session.tokens.accessToken)
        assertTrue(task.optBoolean("archived", false))
    }

    private suspend fun assertRemoteTaskMetadataPreserved(
        client: HttpJsonClient,
        session: AuthSession,
        taskId: String,
        tagId: String
    ) {
        val task = client.get("/tasks/$taskId", session.tokens.accessToken)
        val tags = task.getJSONArray("tags")
        assertTrue((0 until tags.length()).any { tags.getJSONObject(it).getString("id") == tagId })
        assertNotNull(task.optJSONObject("recurrence"))
    }

    private fun taskPayload(
        title: String,
        description: String,
        type: String,
        priority: Int,
        status: String,
        tagIds: List<String> = emptyList()
    ): JSONObject {
        return JSONObject()
            .put("title", title)
            .put("description", description)
            .put("type", type)
            .put("priority", priority)
            .put("status", status)
            .put("plannedTime", "2026-05-10T09:00:00Z")
            .put("dueTime", "2026-05-10T18:00:00Z")
            .put("tagIds", JSONArray(tagIds))
    }

    private fun JSONObject.toSession(): AuthSession {
        val user = getJSONObject("user")
        val tokens = getJSONObject("tokens")
        return AuthSession(
            user = CurrentUser(
                id = user.getString("id"),
                email = user.getString("email"),
                displayName = user.getString("displayName"),
                timezone = user.getString("timezone"),
                language = user.optString("language", "en")
            ),
            tokens = AuthTokens(
                accessToken = tokens.getString("accessToken"),
                refreshToken = tokens.getString("refreshToken"),
                expiresAt = tokens.getString("expiresAt")
            )
        )
    }
}
