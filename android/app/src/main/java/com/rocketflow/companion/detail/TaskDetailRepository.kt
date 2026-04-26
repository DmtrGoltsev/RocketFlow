package com.rocketflow.companion.detail

import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.SessionBoundResult
import org.json.JSONArray
import org.json.JSONObject

class TaskDetailRepository(
    private val authRepository: AuthRepository
) {

    suspend fun getTaskDetail(session: AuthSession, taskId: String): SessionBoundResult<TaskDetail> {
        val result = authRepository.authorizedGet(session, "/tasks/$taskId")
        return SessionBoundResult(
            session = result.session,
            value = result.value.toTaskDetail()
        )
    }
}

private fun JSONObject.toTaskDetail(): TaskDetail {
    return TaskDetail(
        id = getString("id"),
        goalId = getString("goalId"),
        title = getString("title"),
        description = optString("description"),
        type = getString("type"),
        priority = getInt("priority"),
        status = getString("status"),
        plannedTime = optString("plannedTime").ifBlank { null },
        dueTime = optString("dueTime").ifBlank { null },
        archived = optBoolean("archived", false),
        shared = optBoolean("shared", false),
        tags = optJSONArray("tags").toTags(),
        recurrence = optJSONObject("recurrence").toRecurrence(),
        reminders = optJSONArray("reminders").toReminders()
    )
}

private fun JSONArray?.toTags(): List<TaskTag> {
    if (this == null) {
        return emptyList()
    }

    return List(length()) { index ->
        val item = getJSONObject(index)
        TaskTag(
            id = item.getString("id"),
            name = item.getString("name"),
            color = item.optString("color")
        )
    }
}

private fun JSONObject?.toRecurrence(): TaskRecurrence? {
    if (this == null) {
        return null
    }

    return TaskRecurrence(
        mode = getString("mode"),
        interval = if (has("interval")) optInt("interval") else null,
        daysOfWeek = optJSONArray("daysOfWeek").toStringList(),
        startAt = optString("startAt").ifBlank { null },
        endAt = optString("endAt").ifBlank { null },
        active = if (has("active")) optBoolean("active") else null
    )
}

private fun JSONArray?.toReminders(): List<TaskReminder> {
    if (this == null) {
        return emptyList()
    }

    return List(length()) { index ->
        val item = getJSONObject(index)
        TaskReminder(
            id = item.getString("id"),
            mode = item.getString("mode"),
            offsetMinutes = item.getInt("offsetMinutes"),
            active = item.optBoolean("active", false)
        )
    }
}

private fun JSONArray?.toStringList(): List<String> {
    if (this == null) {
        return emptyList()
    }

    return List(length()) { index -> getString(index) }
}
