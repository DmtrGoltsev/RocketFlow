package com.rocketflow.companion.calendar

import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.SessionBoundResult
import com.rocketflow.companion.focus.FocusLocalDataSource
import com.rocketflow.companion.network.ApiException
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate

class CalendarRepository internal constructor(
    private val remote: CalendarRemoteDataSource,
    private val local: FocusLocalDataSource
) {
    constructor(
        authRepository: AuthRepository,
        local: FocusLocalDataSource
    ) : this(AuthCalendarRemoteDataSource(authRepository), local)

    suspend fun load(
        session: AuthSession,
        from: LocalDate,
        toExclusive: LocalDate
    ): Pair<AuthSession, CalendarMonth> {
        return try {
            val result = remote.get(
                session,
                "/calendar?from=$from&toExclusive=$toExclusive"
            )
            val month = result.value.toCalendarMonth(from, toExclusive)
            local.saveCalendar(result.session.user.id, month)
            result.session to month
        } catch (error: ApiException) {
            if (error.status == 401) throw error
            offlineResult(session, from, toExclusive, error)
        } catch (error: Exception) {
            offlineResult(session, from, toExclusive, error)
        }
    }

    private fun offlineResult(
        session: AuthSession,
        from: LocalDate,
        toExclusive: LocalDate,
        error: Exception
    ): Pair<AuthSession, CalendarMonth> {
        val cached = local.loadCalendar(session.user.id, from, toExclusive)
        return session to (cached ?: CalendarMonth(
            timezone = session.user.timezone,
            from = from,
            toExclusive = toExclusive,
            markers = emptyList(),
            offline = true,
            error = error.message
        ))
    }

    private fun JSONObject.toCalendarMonth(fromFallback: LocalDate, toFallback: LocalDate): CalendarMonth {
        val timezone = optString("timezone", "UTC")
        val from = optString("from").takeIf { it.isNotBlank() }?.let(LocalDate::parse) ?: fromFallback
        val to = optString("toExclusive").takeIf { it.isNotBlank() }?.let(LocalDate::parse) ?: toFallback
        val array = optJSONArray("markers") ?: optJSONArray("items") ?: JSONArray()
        val markers = List(array.length()) { index -> array.optJSONObject(index) }
            .filterNotNull()
            .mapNotNull { it.toMarker() }
        return CalendarMonth(timezone, from, to, markers)
    }

    private fun JSONObject.toMarker(): CalendarMarker? {
        val task = optJSONObject("task")
        val taskId = optString("taskId").ifBlank { task?.optString("id").orEmpty() }
        val date = optString("localDate").takeIf { it.isNotBlank() }?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
            ?: return null
        if (taskId.isBlank()) return null
        val kind = CalendarMarkerKind.fromApi(optString("kind"))
        val occurrenceId = optString("occurrenceId").ifBlank { "$taskId:$date" }
        return CalendarMarker(
            markerId = optString("markerId").ifBlank { "$occurrenceId:${kind.name.lowercase()}" },
            occurrenceId = occurrenceId,
            taskId = taskId,
            goalId = optString("goalId").ifBlank { task?.optString("goalId").orEmpty() }.ifBlank { null },
            kind = kind,
            at = optString("at"),
            localDate = date,
            title = optString("title").ifBlank { task?.optString("title").orEmpty() },
            status = optString("status").ifBlank { task?.optString("status", "todo").orEmpty() },
            effort = if (has("effort")) optInt("effort") else task?.optInt("effort", 0) ?: 0,
            recurring = optBoolean("recurring", false)
        )
    }
}

internal fun interface CalendarRemoteDataSource {
    suspend fun get(session: AuthSession, path: String): SessionBoundResult<JSONObject>
}

private class AuthCalendarRemoteDataSource(
    private val authRepository: AuthRepository
) : CalendarRemoteDataSource {
    override suspend fun get(session: AuthSession, path: String) = authRepository.authorizedGet(session, path)
}
