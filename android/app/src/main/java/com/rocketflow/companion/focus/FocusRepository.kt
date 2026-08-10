package com.rocketflow.companion.focus

import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.SessionBoundResult
import com.rocketflow.companion.network.ApiException
import com.rocketflow.companion.planning.PlanningTask
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.UUID

class FocusRepository internal constructor(
    private val remote: FocusRemoteDataSource,
    private val local: FocusLocalDataSource,
    private val syncEnqueuer: FocusSyncEnqueuer? = null
) {
    constructor(
        authRepository: AuthRepository,
        local: FocusLocalDataSource,
        syncEnqueuer: FocusSyncEnqueuer? = null
    ) : this(AuthFocusRemoteDataSource(authRepository), local, syncEnqueuer)

    suspend fun loadCurrent(session: AuthSession): Pair<AuthSession, FocusLoadResult> {
        var activeSession = session
        return try {
            activeSession = syncPending(activeSession)
            val result = remote.get(activeSession, "/focus/current")
            activeSession = result.session
            val period = result.value.periodObject()?.toFocusPeriod()
            if (period != null) local.savePeriod(activeSession.user.id, period)
            activeSession to FocusLoadResult(
                period,
                offline = false,
                pendingCount = local.pendingCount(activeSession.user.id),
                error = local.latestTerminalError(activeSession.user.id)
            )
        } catch (error: ApiException) {
            if (error.status == 401) throw error
            offlineCurrent(activeSession, error)
        } catch (error: Exception) {
            offlineCurrent(activeSession, error)
        }
    }

    private fun offlineCurrent(session: AuthSession, error: Exception): Pair<AuthSession, FocusLoadResult> {
        return session to FocusLoadResult(
            period = local.loadCurrent(session.user.id),
            offline = true,
            pendingCount = local.pendingCount(session.user.id),
            error = local.latestTerminalError(session.user.id) ?: error.message
        )
    }

    suspend fun loadHistory(session: AuthSession): Pair<AuthSession, List<FocusHistorySummary>> {
        return try {
            val result = remote.get(session, "/focus/history")
            val summaries = result.value.optJSONArray("items").toObjectList().mapNotNull { it.toHistorySummary() }
            summaries.forEach { local.saveHistorySummary(result.session.user.id, it) }
            result.session to summaries
        } catch (error: ApiException) {
            if (error.status == 401) throw error
            session to local.loadHistorySummaries(session.user.id)
        } catch (_: Exception) {
            session to local.loadHistorySummaries(session.user.id)
        }
    }

    suspend fun loadHistoryPeriod(session: AuthSession, periodId: String): Pair<AuthSession, FocusPeriod?> {
        return try {
            val result = remote.get(session, "/focus/history/$periodId")
            val period = result.value.periodObject()?.toFocusPeriod()
            if (period != null) local.savePeriod(result.session.user.id, period)
            result.session to period
        } catch (error: ApiException) {
            if (error.status == 401) throw error
            session to local.loadPeriod(session.user.id, periodId)
        } catch (_: Exception) {
            session to local.loadPeriod(session.user.id, periodId)
        }
    }

    suspend fun searchCandidates(
        session: AuthSession,
        query: String,
        cursor: String? = null
    ): Pair<AuthSession, FocusCandidatePage> {
        val cursorPart = cursor?.let { "&cursor=${it.urlEncoded()}" }.orEmpty()
        val path = "/focus/candidates?q=${query.urlEncoded()}&limit=100$cursorPart"
        val result = remote.get(session, path)
        val candidates = result.value.optJSONArray("items").toObjectList().mapNotNull { it.toFocusCandidate() }
        return result.session to FocusCandidatePage(candidates, result.value.nullableString("nextCursor"))
    }

    suspend fun addTask(session: AuthSession, task: PlanningTask, path: String): Pair<AuthSession, FocusLoadResult> {
        return enqueueAdd(
            session,
            FocusItem(
                taskId = task.id,
                title = task.title,
                status = task.status,
                effort = task.effort,
                path = path,
                displayOrder = local.loadCurrent(session.user.id)?.items?.size ?: 0,
                plannedTime = task.plannedTime,
                dueTime = task.dueTime
            )
        )
    }

    suspend fun addCandidate(session: AuthSession, candidate: FocusCandidate): Pair<AuthSession, FocusLoadResult> {
        return enqueueAdd(
            session,
            FocusItem(
                taskId = candidate.taskId,
                title = candidate.title,
                status = candidate.status,
                effort = candidate.effort,
                path = candidate.path,
                displayOrder = local.loadCurrent(session.user.id)?.items?.size ?: 0
            )
        )
    }

    private suspend fun enqueueAdd(session: AuthSession, item: FocusItem): Pair<AuthSession, FocusLoadResult> {
        val current = local.loadCurrent(session.user.id)
        val action = pendingAction(
            action = ACTION_ADD,
            taskId = item.taskId,
            period = current,
            body = JSONObject()
        )
        local.enqueue(session.user.id, action)
        if (current != null) {
            local.addLocalItem(
                session.user.id,
                current.id,
                item.copy(displayOrder = current.items.size)
            )
        }
        syncEnqueuer?.enqueueFocusSync()
        return loadCurrent(session)
    }

    suspend fun removeTask(session: AuthSession, taskId: String): Pair<AuthSession, FocusLoadResult> {
        val current = local.loadCurrent(session.user.id)
        local.enqueue(
            session.user.id,
            pendingAction(ACTION_REMOVE, taskId, current, JSONObject())
        )
        current?.let { local.removeLocalItem(session.user.id, it.id, taskId) }
        syncEnqueuer?.enqueueFocusSync()
        return loadCurrent(session)
    }

    suspend fun reorder(session: AuthSession, taskIds: List<String>): Pair<AuthSession, FocusLoadResult> {
        val current = local.loadCurrent(session.user.id)
        val body = JSONObject().put("taskIds", JSONArray(taskIds))
        local.enqueue(session.user.id, pendingAction(ACTION_REORDER, null, current, body))
        current?.let { local.reorderLocalItems(session.user.id, it.id, taskIds) }
        syncEnqueuer?.enqueueFocusSync()
        return loadCurrent(session)
    }

    suspend fun resolveRollover(
        session: AuthSession,
        sourcePeriodId: String,
        carryTaskIds: List<String>
    ): Pair<AuthSession, FocusLoadResult> {
        val current = local.loadCurrent(session.user.id)
        val body = JSONObject().put("taskIds", JSONArray(carryTaskIds))
        val action = pendingAction(ACTION_RESOLVE, null, current, body).copy(periodId = sourcePeriodId)
        local.enqueue(session.user.id, action)
        syncEnqueuer?.enqueueFocusSync()
        return loadCurrent(session)
    }

    suspend fun loadSettings(session: AuthSession): Pair<AuthSession, FocusNotificationSettings> {
        return try {
            val result = remote.get(session, "/focus/notification-settings")
            val settings = result.value.toSettings()
            local.saveSettings(result.session.user.id, settings)
            result.session to settings
        } catch (error: ApiException) {
            if (error.status == 401) throw error
            session to local.loadSettings(session.user.id)
        } catch (_: Exception) {
            session to local.loadSettings(session.user.id)
        }
    }

    suspend fun updateSettings(
        session: AuthSession,
        settings: FocusNotificationSettings
    ): Pair<AuthSession, FocusNotificationSettings> {
        require(settings.quietHoursValidationError() == null) { "Quiet hours must both be empty or valid HH:mm values." }
        val body = settings.toJson()
        local.saveSettings(session.user.id, settings)
        local.enqueue(
            session.user.id,
            FocusPendingAction(
                id = UUID.randomUUID().toString(),
                action = ACTION_SETTINGS,
                taskId = null,
                periodId = null,
                expectedVersion = null,
                payloadJson = body.toString()
            )
        )
        syncEnqueuer?.enqueueFocusSync()
        val updatedSession = try {
            syncPending(session)
        } catch (error: Exception) {
            if (error is ApiException && !isRetryableFocusSyncFailure(error)) throw error
            session
        }
        return updatedSession to local.loadSettings(session.user.id)
    }

    suspend fun syncPending(session: AuthSession): AuthSession {
        var activeSession = session
        var currentPeriod = local.loadCurrent(session.user.id)
        val actions = local.pending(session.user.id)
        actionLoop@ for (queuedAction in actions) {
            var action = queuedAction
            while (true) {
                try {
                val body = JSONObject(action.payloadJson).also { payload ->
                    if (action.action != ACTION_SETTINGS) {
                        payload.put("idempotencyKey", action.id)
                        (currentPeriod?.version ?: action.expectedVersion)?.let { payload.put("periodVersion", it) }
                    }
                }
                val result = when (action.action) {
                    ACTION_ADD -> remote.put(activeSession, "/focus/current/items/${action.taskId}", body)
                    ACTION_REMOVE -> remote.delete(activeSession, "/focus/current/items/${action.taskId}", body)
                    ACTION_REORDER -> remote.patch(activeSession, "/focus/current/items/order", body)
                    ACTION_RESOLVE -> remote.post(activeSession, "/focus/rollovers/${action.periodId}/resolve", body)
                    ACTION_SETTINGS -> {
                        val settingsResult = remote.patch(activeSession, "/focus/notification-settings", body)
                        local.saveSettings(settingsResult.session.user.id, settingsResult.value.toSettings())
                        activeSession = settingsResult.session
                        null
                    }
                    else -> null
                }
                if (result != null) {
                    activeSession = result.session
                    val returnedPeriod = result.value.periodObject()?.toFocusPeriod()
                        ?: error("Focus mutation did not return a period.")
                    local.savePeriod(activeSession.user.id, returnedPeriod)
                    currentPeriod = returnedPeriod
                }
                local.removePending(session.user.id, action.id)
                break
                } catch (error: ApiException) {
                    if (error.status == 401) throw error
                    local.markPendingError(session.user.id, action.id, error.message)
                    if (error.status != 409) {
                        if (error.status in 400..499 && error.status != 429) {
                            activeSession = refreshRejectedAction(activeSession, action)
                            local.terminalizePending(
                                session.user.id,
                                action.id,
                                terminalMessage(action, error)
                            )
                            continue@actionLoop
                        }
                        throw error
                    }
                    val conflictAttempts = local.incrementConflictAttempts(session.user.id, action.id)
                    action = action.copy(conflictAttempts = conflictAttempts)
                    if (action.action == ACTION_SETTINGS) {
                        val refreshed = remote.get(activeSession, "/focus/notification-settings")
                        activeSession = refreshed.session
                        val serverSettings = refreshed.value.toSettings()
                        if (conflictAttempts >= MAX_CONFLICT_ATTEMPTS) {
                            local.saveSettings(activeSession.user.id, serverSettings)
                            local.terminalizePending(
                                session.user.id,
                                action.id,
                                terminalMessage(action, error)
                            )
                            continue@actionLoop
                        }
                        val desiredSettings = JSONObject(action.payloadJson).toSettings()
                            .copy(version = serverSettings.version)
                        val rebasedPayload = desiredSettings.toJson().toString()
                        action = action.copy(payloadJson = rebasedPayload)
                        local.saveSettings(activeSession.user.id, desiredSettings)
                        local.updatePendingPayload(activeSession.user.id, action.id, rebasedPayload)
                    } else {
                        val refreshed = remote.get(activeSession, "/focus/current")
                        activeSession = refreshed.session
                        currentPeriod = refreshed.value.periodObject()?.toFocusPeriod()
                        currentPeriod?.let { local.savePeriod(activeSession.user.id, it) }
                        if (actionAlreadyApplied(action, currentPeriod)) {
                            local.removePending(session.user.id, action.id)
                            break
                        }
                        if (conflictAttempts >= MAX_CONFLICT_ATTEMPTS) {
                            local.terminalizePending(
                                session.user.id,
                                action.id,
                                terminalMessage(action, error)
                            )
                            continue@actionLoop
                        }
                    }
                } catch (error: Exception) {
                    local.markPendingError(session.user.id, action.id, error.message.orEmpty())
                    throw error
                }
            }
        }
        return activeSession
    }

    fun cachedCurrent(userId: String): FocusPeriod? = local.loadCurrent(userId)
    fun cachedSettings(userId: String): FocusNotificationSettings = local.loadSettings(userId)
    fun latestSyncError(userId: String): String? = local.latestTerminalError(userId)

    private suspend fun refreshRejectedAction(session: AuthSession, action: FocusPendingAction): AuthSession {
        return if (action.action == ACTION_SETTINGS) {
            val refreshed = remote.get(session, "/focus/notification-settings")
            local.saveSettings(refreshed.session.user.id, refreshed.value.toSettings())
            refreshed.session
        } else {
            val refreshed = remote.get(session, "/focus/current")
            refreshed.value.periodObject()?.toFocusPeriod()?.let { period ->
                local.savePeriod(refreshed.session.user.id, period)
            }
            refreshed.session
        }
    }

    private fun terminalMessage(action: FocusPendingAction, error: ApiException): String {
        val target = if (action.action == ACTION_SETTINGS) "Focus settings" else "Focus change"
        return "$target was not saved (${error.status}): ${error.message}"
    }

    private fun pendingAction(
        action: String,
        taskId: String?,
        period: FocusPeriod?,
        body: JSONObject
    ): FocusPendingAction = FocusPendingAction(
        id = UUID.randomUUID().toString(),
        action = action,
        taskId = taskId,
        periodId = period?.id,
        expectedVersion = period?.version,
        payloadJson = body.toString()
    )

    private fun JSONObject.periodObject(): JSONObject? = optJSONObject("period") ?: takeIf { has("id") }

    private fun actionAlreadyApplied(action: FocusPendingAction, period: FocusPeriod?): Boolean {
        val active = period ?: return false
        return when (action.action) {
            ACTION_ADD -> active.items.any { it.taskId == action.taskId }
            ACTION_REMOVE -> active.items.none { it.taskId == action.taskId }
            ACTION_REORDER -> {
                val expected = runCatching {
                    JSONObject(action.payloadJson).optJSONArray("taskIds").toStringList()
                }.getOrDefault(emptyList())
                expected.isNotEmpty() && active.items.sortedBy { it.displayOrder }.map { it.taskId } == expected
            }
            ACTION_RESOLVE -> active.rolloverOffer?.sourcePeriodId != action.periodId
            else -> false
        }
    }

    private fun JSONObject.toFocusPeriod(): FocusPeriod? {
        val id = optString("id").ifBlank { return null }
        val items = (optJSONArray("items") ?: JSONArray()).toObjectList().mapNotNull { it.toFocusItem() }
        val rollover = optJSONObject("rolloverOffer")?.let { offer ->
            val source = offer.optString("sourcePeriodId").ifBlank { offer.optString("sourcePeriod") }
            if (source.isBlank()) null else FocusRolloverOffer(
                sourcePeriodId = source,
                taskIds = when {
                    offer.optJSONArray("items") != null -> offer.optJSONArray("items").toObjectList().map { it.optString("taskId") }.filter { it.isNotBlank() }
                    else -> (offer.optJSONArray("taskIds") ?: offer.optJSONArray("eligibleTaskIds")).toStringList()
                }
            )
        }
        return FocusPeriod(
            id = id,
            weekStart = optString("weekStart").ifBlank { optString("startsAt") },
            weekEndExclusive = optString("weekEndExclusive").ifBlank { optString("endsAt") },
            timezone = optString("timezone").ifBlank { optString("timezoneSnapshot", "UTC") },
            status = optString("status", "active"),
            version = optLong("version", 0),
            items = items,
            rolloverOffer = rollover
        )
    }

    private fun JSONObject.toHistorySummary(): FocusHistorySummary? {
        val id = optString("id").ifBlank { return null }
        val progressJson = optJSONObject("progress") ?: JSONObject()
        return FocusHistorySummary(
            id = id,
            weekStart = optString("weekStart").ifBlank { optString("startsAt") },
            weekEndExclusive = optString("weekEndExclusive").ifBlank { optString("endsAt") },
            timezone = optString("timezone").ifBlank { optString("timezoneSnapshot", "UTC") },
            status = optString("status", "completed"),
            version = optLong("version", 0),
            progress = FocusProgress(
                completedWeight = progressJson.optInt("completedWeight", 0),
                totalWeight = progressJson.optInt("totalWeight", 0)
            )
        )
    }

    private fun JSONObject.toFocusItem(): FocusItem? {
        val task = optJSONObject("task")
        val taskId = optString("taskId").ifBlank { task?.optString("id").orEmpty() }
        if (taskId.isBlank()) return null
        return FocusItem(
            taskId = taskId,
            title = optString("titleSnapshot").ifBlank { optString("title").ifBlank { task?.optString("title").orEmpty() } },
            status = optString("statusSnapshot").ifBlank { optString("status").ifBlank { task?.optString("status", "todo").orEmpty() } },
            effort = if (has("effortSnapshot")) optInt("effortSnapshot") else optInt("effort", task?.optInt("effort", 0) ?: 0),
            path = optString("pathSnapshot").ifBlank {
                optString("path").ifBlank {
                    listOf(optString("folderTitle"), optString("goalTitle")).filter { it.isNotBlank() }.joinToString(" / ")
                }
            },
            displayOrder = optInt("displayOrder", optInt("position", 0)),
            historyOnly = optBoolean("historyOnly", false),
            plannedTime = nullableString("plannedTimeSnapshot") ?: nullableString("plannedTime"),
            dueTime = nullableString("dueTimeSnapshot") ?: nullableString("dueTime")
        )
    }

    private fun JSONObject.toFocusCandidate(): FocusCandidate? {
        val task = optJSONObject("task") ?: this
        val taskId = task.optString("id").ifBlank { optString("taskId") }
        if (taskId.isBlank()) return null
        val folder = optJSONObject("folder")
        val goal = optJSONObject("goal")
        return FocusCandidate(
            taskId = taskId,
            title = task.optString("title"),
            status = task.optString("status", "todo"),
            effort = task.optInt("effort", 0),
            folderId = folder?.nullableString("id") ?: nullableString("folderId"),
            folderName = folder?.nullableString("name") ?: nullableString("folderName") ?: nullableString("folderTitle"),
            goalId = goal?.nullableString("id") ?: nullableString("goalId"),
            goalName = goal?.nullableString("name") ?: nullableString("goalName") ?: nullableString("goalTitle"),
            path = optString("path").ifBlank {
                listOf(nullableString("folderTitle"), nullableString("goalTitle")).filterNotNull().joinToString(" / ")
            },
            shared = optBoolean("shared", task.optBoolean("shared", false))
        )
    }

    private fun JSONObject.toSettings(): FocusNotificationSettings {
        val interval = when {
            isNull("intervalMinutes") -> null
            has("intervalMinutes") -> optInt("intervalMinutes").takeIf { it > 0 }
            else -> optString("interval").removeSuffix("m").toIntOrNull()
        }
        return FocusNotificationSettings(
            intervalMinutes = interval,
            quietStart = nullableString("quietHoursStart") ?: nullableString("quietStart"),
            quietEnd = nullableString("quietHoursEnd") ?: nullableString("quietEnd"),
            version = optLong("version", 0)
        )
    }

    private fun FocusNotificationSettings.toJson(): JSONObject = JSONObject()
        .put("intervalMinutes", intervalMinutes ?: JSONObject.NULL)
        .put("quietHoursStart", quietStart ?: JSONObject.NULL)
        .put("quietHoursEnd", quietEnd ?: JSONObject.NULL)
        .put("version", version)

    private fun JSONArray?.toObjectList(): List<JSONObject> = if (this == null) emptyList() else
        List(length()) { index -> optJSONObject(index) }.filterNotNull()

    private fun JSONArray?.toStringList(): List<String> = if (this == null) emptyList() else
        List(length()) { index -> optString(index) }.filter { it.isNotBlank() }

    private fun JSONObject.nullableString(key: String): String? =
        if (has(key) && !isNull(key)) optString(key).ifBlank { null } else null

    private fun String.urlEncoded(): String = URLEncoder.encode(this, StandardCharsets.UTF_8.name())

    companion object {
        private const val ACTION_ADD = "add"
        private const val ACTION_REMOVE = "remove"
        private const val ACTION_REORDER = "reorder"
        private const val ACTION_RESOLVE = "resolve"
        private const val ACTION_SETTINGS = "settings"
        private const val MAX_CONFLICT_ATTEMPTS = 3
    }
}

internal interface FocusRemoteDataSource {
    suspend fun get(session: AuthSession, path: String): SessionBoundResult<JSONObject>
    suspend fun post(session: AuthSession, path: String, body: JSONObject): SessionBoundResult<JSONObject>
    suspend fun patch(session: AuthSession, path: String, body: JSONObject): SessionBoundResult<JSONObject>
    suspend fun put(session: AuthSession, path: String, body: JSONObject): SessionBoundResult<JSONObject>
    suspend fun delete(session: AuthSession, path: String, body: JSONObject): SessionBoundResult<JSONObject>
}

private class AuthFocusRemoteDataSource(private val authRepository: AuthRepository) : FocusRemoteDataSource {
    override suspend fun get(session: AuthSession, path: String) = authRepository.authorizedGet(session, path)
    override suspend fun post(session: AuthSession, path: String, body: JSONObject) =
        authRepository.authorizedPost(session, path, body)
    override suspend fun patch(session: AuthSession, path: String, body: JSONObject) =
        authRepository.authorizedPatch(session, path, body)
    override suspend fun put(session: AuthSession, path: String, body: JSONObject) =
        authRepository.authorizedPut(session, path, body)
    override suspend fun delete(session: AuthSession, path: String, body: JSONObject) =
        authRepository.authorizedDeleteResult(session, path, body)
}

fun interface FocusSyncEnqueuer {
    fun enqueueFocusSync()
}
