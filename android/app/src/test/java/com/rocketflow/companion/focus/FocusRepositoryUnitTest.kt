package com.rocketflow.companion.focus

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.AuthTokens
import com.rocketflow.companion.auth.CurrentUser
import com.rocketflow.companion.auth.SessionBoundResult
import com.rocketflow.companion.network.ApiException
import com.rocketflow.companion.planning.PlanningLocalStore
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.IOException

@RunWith(RobolectricTestRunner::class)
class FocusRepositoryUnitTest {
    private lateinit var context: Context
    private lateinit var store: PlanningLocalStore
    private lateinit var local: FocusLocalDataSource
    private val session = AuthSession(
        CurrentUser("user-1", "user@example.com", "User", "Europe/Moscow", "ru"),
        AuthTokens("access", "refresh", "2026-09-01T00:00:00Z")
    )

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(DATABASE_NAME)
        store = PlanningLocalStore(context)
        local = FocusLocalDataSource(store)
        local.savePeriod("user-1", period(version = 1, taskIds = emptyList()))
    }

    @After
    fun tearDown() {
        store.close()
        context.deleteDatabase(DATABASE_NAME)
    }

    @Test
    fun rejectedRefresh401IsPropagatedWithoutReturningOriginalSession() = runBlocking {
        val error = ApiException(401, "refresh_rejected", "Refresh rejected", emptyMap(), null)
        val repository = FocusRepository(FailingRemote(error), local)
        var returnedSession: AuthSession? = null

        try {
            returnedSession = repository.loadCurrent(session).first
            fail("Expected rejected refresh to propagate")
        } catch (thrown: ApiException) {
            assertSame(error, thrown)
        }

        assertNull(returnedSession)
        assertEquals(1L, local.loadCurrent(session.user.id)?.version)
    }

    @Test
    fun allCachedReadPathsPropagate401() = runBlocking {
        val repository = FocusRepository(FailingRemote(apiError(401)), local)

        assertUnauthorized { repository.loadHistory(session) }
        assertUnauthorized { repository.loadHistoryPeriod(session, PERIOD_ID) }
        assertUnauthorized { repository.loadSettings(session) }
    }

    @Test
    fun transientOfflineCurrentLoadReturnsCacheAndOriginalSession() = runBlocking {
        val repository = FocusRepository(FailingRemote(IOException("offline")), local)

        val result = repository.loadCurrent(session)

        assertSame(session, result.first)
        assertTrue(result.second.offline)
        assertEquals(1L, result.second.period?.version)
        assertEquals("offline", result.second.error)
    }

    @Test
    fun sequentialMutationsUseVersionReturnedByPreviousMutation() = runBlocking {
        val remote = StatefulRemote(session, serverVersion = 1)
        val repository = FocusRepository(remote, local)
        local.enqueue("user-1", action("01-add-a", "add", "task-a", 1))
        local.enqueue("user-1", action("02-add-b", "add", "task-b", 1))
        local.enqueue("user-1", action("03-reorder", "reorder", null, 1, JSONObject().put("taskIds", JSONArray(listOf("task-b", "task-a")))))
        local.enqueue("user-1", action("04-remove-a", "remove", "task-a", 1))

        repository.syncPending(session)

        assertEquals(listOf(1L, 2L, 3L, 4L), remote.receivedVersions)
        assertEquals(0, local.pendingCount("user-1"))
        assertEquals(5, local.loadCurrent("user-1")!!.version)
        assertEquals(listOf("task-b"), local.loadCurrent("user-1")!!.items.map { it.taskId })
    }

    @Test
    fun conflictFetchesCurrentAndReplaysAgainstFreshVersion() = runBlocking {
        val remote = StatefulRemote(session, serverVersion = 5, failFirstMutationWithConflict = true)
        val repository = FocusRepository(remote, local)
        local.enqueue("user-1", action("add-a", "add", "task-a", 1))

        repository.syncPending(session)

        assertEquals(listOf(1L, 5L), remote.receivedVersions)
        assertEquals(1, remote.currentFetches)
        assertEquals(0, local.pendingCount("user-1"))
        assertTrue(local.loadCurrent("user-1")!!.items.any { it.taskId == "task-a" })
    }

    @Test
    fun conflictDropsActionWhenServerAlreadyAppliedIt() = runBlocking {
        val remote = StatefulRemote(
            session,
            serverVersion = 5,
            initialTaskIds = mutableListOf("task-a"),
            failFirstMutationWithConflict = true
        )
        val repository = FocusRepository(remote, local)
        local.enqueue("user-1", action("add-a", "add", "task-a", 1))

        repository.syncPending(session)

        assertEquals(listOf(1L), remote.receivedVersions)
        assertEquals(0, local.pendingCount("user-1"))
    }

    @Test
    fun transientFailureIsPropagatedAndLeavesQueueForWorkManagerRetry() = runBlocking {
        val remote = StatefulRemote(session, serverVersion = 1, transientFailure = true)
        val repository = FocusRepository(remote, local)
        local.enqueue("user-1", action("add-a", "add", "task-a", 1))

        var thrown = false
        try {
            repository.syncPending(session)
        } catch (_: IOException) {
            thrown = true
        }

        assertTrue(thrown)
        assertEquals(1, local.pendingCount("user-1"))
        assertTrue(isRetryableFocusSyncFailure(IOException("offline")))
        assertTrue(isRetryableFocusSyncFailure(apiError(503)))
        assertTrue(isRetryableFocusSyncFailure(apiError(409)))
        assertFalse(isRetryableFocusSyncFailure(apiError(401)))
        assertFalse(isRetryableFocusSyncFailure(apiError(422)))
    }

    @Test
    fun settingsPatchIncludesVersionAndPersistsReturnedVersion() = runBlocking {
        val remote = SettingsRemote(session, serverVersion = 7)
        val repository = FocusRepository(remote, local)

        val result = repository.updateSettings(
            session,
            FocusNotificationSettings(60, "23:00", "07:00", version = 7)
        )

        assertEquals(7L, remote.patchBodies.single().getLong("version"))
        assertFalse(remote.patchBodies.single().has("periodVersion"))
        assertFalse(remote.patchBodies.single().has("idempotencyKey"))
        assertEquals(8L, result.second.version)
        assertEquals(8L, local.loadSettings("user-1").version)
        assertEquals(0, local.pendingCount("user-1"))
    }

    @Test
    fun settingsConflictRebasesDesiredValuesAgainstSettingsVersion() = runBlocking {
        val remote = SettingsRemote(session, serverVersion = 5, conflictsBeforeSuccess = 1)
        val repository = FocusRepository(remote, local)

        val result = repository.updateSettings(
            session,
            FocusNotificationSettings(30, "21:30", "06:15", version = 1)
        )

        assertEquals(listOf(1L, 5L), remote.patchBodies.map { it.getLong("version") })
        assertEquals(listOf("/focus/notification-settings"), remote.getPaths)
        assertTrue(remote.getPaths.none { it == "/focus/current" })
        assertEquals(30, remote.patchBodies.last().getInt("intervalMinutes"))
        assertEquals("21:30", remote.patchBodies.last().getString("quietHoursStart"))
        assertEquals("06:15", remote.patchBodies.last().getString("quietHoursEnd"))
        assertEquals(6L, result.second.version)
        assertEquals(0, local.pendingCount("user-1"))
    }

    @Test
    fun settingsConflictRetryIsBoundedAndRollsBackToServerState() = runBlocking {
        val remote = SettingsRemote(session, serverVersion = 9, conflictsBeforeSuccess = 10)
        val repository = FocusRepository(remote, local)
        local.enqueue(
            "user-1",
            FocusPendingAction(
                id = "settings-rebase",
                action = "settings",
                taskId = null,
                periodId = null,
                expectedVersion = null,
                payloadJson = JSONObject()
                    .put("intervalMinutes", 240)
                    .put("quietHoursStart", "23:30")
                    .put("quietHoursEnd", "06:30")
                    .put("version", 1)
                    .toString()
            )
        )
        repository.syncPending(session)

        assertEquals(3, remote.patchBodies.size)
        assertEquals(3, remote.getPaths.size)
        assertEquals(0, local.pendingCount("user-1"))
        assertTrue(local.latestTerminalError("user-1")!!.contains("409"))
        assertEquals(120, local.loadSettings("user-1").intervalMinutes)
        assertEquals(9L, local.loadSettings("user-1").version)
    }

    @Test
    fun deferredPermanentSettingsErrorIsTerminalVisibleAndRollsBack() = runBlocking {
        val repository = FocusRepository(SettingsRemote(session, serverVersion = 2, permanentStatus = 400), local)
        local.saveSettings("user-1", FocusNotificationSettings(30, null, null, version = 2))
        local.enqueue(
            "user-1",
            FocusPendingAction(
                id = "deferred-settings",
                action = "settings",
                taskId = null,
                periodId = null,
                expectedVersion = null,
                payloadJson = settingsPayload(30, null, null, 2)
            )
        )

        repository.syncPending(session)

        assertEquals(0, local.pendingCount("user-1"))
        assertTrue(local.latestTerminalError("user-1")!!.contains("400"))
        assertEquals(FocusNotificationSettings(120, "22:00", "08:00", 2), local.loadSettings("user-1"))
    }

    @Test
    fun conflictAttemptCapPersistsAcrossRepositoryAndWorkerInstances() = runBlocking {
        local.enqueue(
            "user-1",
            FocusPendingAction(
                id = "persistent-conflict",
                action = "settings",
                taskId = null,
                periodId = null,
                expectedVersion = null,
                payloadJson = settingsPayload(30, null, null, 1)
            )
        )

        repeat(2) { index ->
            val repository = FocusRepository(ConflictRefreshRemote(session, failRefresh = true), FocusLocalDataSource(store))
            try {
                repository.syncPending(session)
            } catch (_: IOException) {
                Unit
            }
            assertEquals(index + 1, FocusLocalDataSource(store).pending("user-1").single().conflictAttempts)
        }

        FocusRepository(ConflictRefreshRemote(session, failRefresh = false), FocusLocalDataSource(store))
            .syncPending(session)

        assertEquals(0, local.pendingCount("user-1"))
        assertTrue(local.latestTerminalError("user-1")!!.contains("409"))
        assertEquals(11L, local.loadSettings("user-1").version)
    }

    @Test
    fun quietHoursMustBePairedAndStrictlyFormattedBeforeQueueing() = runBlocking {
        assertEquals(
            QuietHoursValidationError.PAIR_REQUIRED,
            FocusNotificationSettings(60, "22:00", null, 1).quietHoursValidationError()
        )
        assertEquals(
            QuietHoursValidationError.INVALID_FORMAT,
            FocusNotificationSettings(60, "22:00", "8:00", 1).quietHoursValidationError()
        )
        assertEquals(null, FocusNotificationSettings(60, null, null, 1).quietHoursValidationError())
        assertEquals(null, FocusNotificationSettings(60, "22:00", "08:00", 1).quietHoursValidationError())

        val repository = FocusRepository(SettingsRemote(session, serverVersion = 1), local)
        var rejected = false
        try {
            repository.updateSettings(session, FocusNotificationSettings(60, "22:00", null, 1))
        } catch (_: IllegalArgumentException) {
            rejected = true
        }
        assertTrue(rejected)
        assertEquals(0, local.pendingCount("user-1"))
    }

    @Test
    fun candidatesUseOpaqueCursorAndServerCandidateData() = runBlocking {
        val remote = CandidateRemote(session)
        val repository = FocusRepository(remote, local)

        val first = repository.searchCandidates(session, "road map")
        val second = repository.searchCandidates(first.first, "road map", first.second.nextCursor)

        assertEquals("task-server-1", first.second.items.single().taskId)
        assertEquals("Server folder / Server goal", first.second.items.single().path)
        assertEquals("next cursor", first.second.nextCursor)
        assertTrue(remote.paths.first().contains("q=road+map"))
        assertTrue(remote.paths.last().contains("cursor=next+cursor"))
        assertEquals("task-server-2", second.second.items.single().taskId)
    }

    private fun action(
        id: String,
        type: String,
        taskId: String?,
        version: Long,
        body: JSONObject = JSONObject()
    ) = FocusPendingAction(id, type, taskId, PERIOD_ID, version, body.toString())

    private suspend fun assertUnauthorized(block: suspend () -> Any?) {
        try {
            block()
            fail("Expected 401")
        } catch (error: ApiException) {
            assertEquals(401, error.status)
        }
    }

    private fun period(version: Long, taskIds: List<String>): FocusPeriod = FocusPeriod(
        id = PERIOD_ID,
        weekStart = "2026-08-03",
        weekEndExclusive = "2026-08-10",
        timezone = "Europe/Moscow",
        status = "active",
        version = version,
        items = taskIds.mapIndexed { index, id -> FocusItem(id, id, "todo", 1, "Folder / Goal", index) }
    )

    private fun settingsPayload(interval: Int?, start: String?, end: String?, version: Long): String = JSONObject()
        .put("intervalMinutes", interval ?: JSONObject.NULL)
        .put("quietHoursStart", start ?: JSONObject.NULL)
        .put("quietHoursEnd", end ?: JSONObject.NULL)
        .put("version", version)
        .toString()

    private class StatefulRemote(
        private val session: AuthSession,
        var serverVersion: Long,
        private val initialTaskIds: MutableList<String> = mutableListOf(),
        private val failFirstMutationWithConflict: Boolean = false,
        private val transientFailure: Boolean = false
    ) : FocusRemoteDataSource {
        val receivedVersions = mutableListOf<Long>()
        var currentFetches = 0
        private val taskIds = initialTaskIds
        private var mutationCount = 0

        override suspend fun get(session: AuthSession, path: String): SessionBoundResult<JSONObject> {
            currentFetches += 1
            return result()
        }

        override suspend fun post(session: AuthSession, path: String, body: JSONObject) = mutate(path, body)
        override suspend fun patch(session: AuthSession, path: String, body: JSONObject) = mutate(path, body)
        override suspend fun put(session: AuthSession, path: String, body: JSONObject) = mutate(path, body)
        override suspend fun delete(session: AuthSession, path: String, body: JSONObject) = mutate(path, body)

        private fun mutate(path: String, body: JSONObject): SessionBoundResult<JSONObject> {
            val version = body.getLong("periodVersion")
            receivedVersions += version
            mutationCount += 1
            if (transientFailure) throw IOException("offline")
            if (failFirstMutationWithConflict && mutationCount == 1) throw apiError(409)
            assertEquals(serverVersion, version)
            when {
                path.contains("/items/order") -> {
                    val desired = body.getJSONArray("taskIds")
                    taskIds.clear()
                    repeat(desired.length()) { taskIds += desired.getString(it) }
                }
                path.contains("/items/") && path.contains("remove-never") -> Unit
                path.contains("/items/") -> {
                    val taskId = path.substringAfterLast('/')
                    if (taskId !in taskIds) taskIds += taskId
                }
            }
            if (path.endsWith("task-a") && mutationCount > 3) taskIds.remove("task-a")
            serverVersion += 1
            return result()
        }

        private fun result(): SessionBoundResult<JSONObject> = SessionBoundResult(
            session,
            JSONObject()
                .put("id", PERIOD_ID)
                .put("weekStart", "2026-08-03")
                .put("weekEndExclusive", "2026-08-10")
                .put("timezone", "Europe/Moscow")
                .put("status", "active")
                .put("version", serverVersion)
                .put("items", JSONArray(taskIds.mapIndexed { index, id ->
                    JSONObject().put("taskId", id).put("title", id).put("status", "todo").put("effort", 1).put("position", index)
                }))
        )
    }

    private class FailingRemote(
        private val error: Exception
    ) : FocusRemoteDataSource {
        override suspend fun get(session: AuthSession, path: String): SessionBoundResult<JSONObject> = throw error
        override suspend fun post(session: AuthSession, path: String, body: JSONObject): SessionBoundResult<JSONObject> = throw error
        override suspend fun patch(session: AuthSession, path: String, body: JSONObject): SessionBoundResult<JSONObject> = throw error
        override suspend fun put(session: AuthSession, path: String, body: JSONObject): SessionBoundResult<JSONObject> = throw error
        override suspend fun delete(session: AuthSession, path: String, body: JSONObject): SessionBoundResult<JSONObject> = throw error
    }

    private class CandidateRemote(private val session: AuthSession) : FocusRemoteDataSource {
        val paths = mutableListOf<String>()

        override suspend fun get(session: AuthSession, path: String): SessionBoundResult<JSONObject> {
            paths += path
            val second = "cursor=" in path
            val item = JSONObject()
                .put("taskId", if (second) "task-server-2" else "task-server-1")
                .put("title", if (second) "Second" else "First")
                .put("status", "todo")
                .put("effort", 2)
                .put("folderId", "folder-server")
                .put("folderTitle", "Server folder")
                .put("goalId", "goal-server")
                .put("goalTitle", "Server goal")
                .put("shared", true)
            return SessionBoundResult(
                this.session,
                JSONObject()
                    .put("items", JSONArray().put(item))
                    .put("nextCursor", if (second) JSONObject.NULL else "next cursor")
            )
        }

        override suspend fun post(session: AuthSession, path: String, body: JSONObject) = unsupported()
        override suspend fun patch(session: AuthSession, path: String, body: JSONObject) = unsupported()
        override suspend fun put(session: AuthSession, path: String, body: JSONObject) = unsupported()
        override suspend fun delete(session: AuthSession, path: String, body: JSONObject) = unsupported()

        private fun unsupported(): SessionBoundResult<JSONObject> = error("Unexpected mutation")
    }

    private class SettingsRemote(
        private val session: AuthSession,
        private var serverVersion: Long,
        private val conflictsBeforeSuccess: Int = 0,
        private val permanentStatus: Int? = null
    ) : FocusRemoteDataSource {
        val patchBodies = mutableListOf<JSONObject>()
        val getPaths = mutableListOf<String>()
        private var patchCount = 0
        private var intervalMinutes: Int? = 120
        private var quietStart: String? = "22:00"
        private var quietEnd: String? = "08:00"

        override suspend fun get(session: AuthSession, path: String): SessionBoundResult<JSONObject> {
            getPaths += path
            check(path == "/focus/notification-settings")
            return settingsResult()
        }

        override suspend fun patch(session: AuthSession, path: String, body: JSONObject): SessionBoundResult<JSONObject> {
            check(path == "/focus/notification-settings")
            patchBodies += JSONObject(body.toString())
            patchCount += 1
            permanentStatus?.let { throw apiError(it) }
            if (patchCount <= conflictsBeforeSuccess) throw apiError(409)
            assertEquals(serverVersion, body.getLong("version"))
            intervalMinutes = if (body.isNull("intervalMinutes")) null else body.getInt("intervalMinutes")
            quietStart = body.optString("quietHoursStart").takeIf { !body.isNull("quietHoursStart") }
            quietEnd = body.optString("quietHoursEnd").takeIf { !body.isNull("quietHoursEnd") }
            serverVersion += 1
            return settingsResult()
        }

        override suspend fun post(session: AuthSession, path: String, body: JSONObject) = unsupported()
        override suspend fun put(session: AuthSession, path: String, body: JSONObject) = unsupported()
        override suspend fun delete(session: AuthSession, path: String, body: JSONObject) = unsupported()

        private fun settingsResult(): SessionBoundResult<JSONObject> = SessionBoundResult(
            session,
            JSONObject()
                .put("intervalMinutes", intervalMinutes ?: JSONObject.NULL)
                .put("quietHoursStart", quietStart ?: JSONObject.NULL)
                .put("quietHoursEnd", quietEnd ?: JSONObject.NULL)
                .put("version", serverVersion)
        )

        private fun unsupported(): SessionBoundResult<JSONObject> = error("Unexpected mutation")
    }

    private class ConflictRefreshRemote(
        private val session: AuthSession,
        private val failRefresh: Boolean
    ) : FocusRemoteDataSource {
        override suspend fun get(session: AuthSession, path: String): SessionBoundResult<JSONObject> {
            if (failRefresh) throw IOException("refresh unavailable")
            return SessionBoundResult(
                this.session,
                JSONObject()
                    .put("intervalMinutes", 120)
                    .put("quietHoursStart", "22:00")
                    .put("quietHoursEnd", "08:00")
                    .put("version", 11)
            )
        }

        override suspend fun patch(session: AuthSession, path: String, body: JSONObject): SessionBoundResult<JSONObject> =
            throw apiError(409)

        override suspend fun post(session: AuthSession, path: String, body: JSONObject) = unsupported()
        override suspend fun put(session: AuthSession, path: String, body: JSONObject) = unsupported()
        override suspend fun delete(session: AuthSession, path: String, body: JSONObject) = unsupported()

        private fun unsupported(): SessionBoundResult<JSONObject> = error("Unexpected mutation")
    }

    companion object {
        private const val DATABASE_NAME = "rocketflow_planning.db"
        private const val PERIOD_ID = "period-1"

        private fun apiError(status: Int) = ApiException(status, "test", "test", emptyMap(), null)
    }
}
