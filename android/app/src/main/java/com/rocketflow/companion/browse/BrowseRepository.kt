package com.rocketflow.companion.browse

import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.SessionBoundResult
import org.json.JSONArray
import org.json.JSONObject

class BrowseRepository(
    private val authRepository: AuthRepository
) {

    suspend fun listFolders(session: AuthSession): SessionBoundResult<List<FolderSummary>> {
        val result = authRepository.authorizedGet(session, "/folders")
        return SessionBoundResult(
            session = result.session,
            value = result.value.getJSONArray("items").toFolders()
        )
    }

    suspend fun listGoals(session: AuthSession, folderId: String): SessionBoundResult<List<GoalSummary>> {
        val result = authRepository.authorizedGet(session, "/folders/$folderId/goals")
        return SessionBoundResult(
            session = result.session,
            value = result.value.getJSONArray("items").toGoals()
        )
    }

    suspend fun listTasks(session: AuthSession, goalId: String): SessionBoundResult<List<TaskSummary>> {
        val result = authRepository.authorizedGet(session, "/goals/$goalId/tasks")
        return SessionBoundResult(
            session = result.session,
            value = result.value.getJSONArray("items").toTasks()
        )
    }

    suspend fun getSharedResources(session: AuthSession): SessionBoundResult<SharedResources> {
        val result = authRepository.authorizedGet(session, "/shares/resources")
        return SessionBoundResult(
            session = result.session,
            value = SharedResources(
                goals = result.value.getJSONArray("goals").toGoals(),
                tasks = result.value.getJSONArray("tasks").toTasks()
            )
        )
    }
}

private fun JSONArray.toFolders(): List<FolderSummary> {
    return List(length()) { index ->
        val item = getJSONObject(index)
        FolderSummary(
            id = item.getString("id"),
            name = item.getString("name"),
            description = item.optString("description"),
            archived = item.optBoolean("archived", false)
        )
    }
}

private fun JSONArray.toGoals(): List<GoalSummary> {
    return List(length()) { index ->
        val item = getJSONObject(index)
        GoalSummary(
            id = item.getString("id"),
            folderId = item.getString("folderId"),
            name = item.getString("name"),
            description = item.optString("description"),
            archived = item.optBoolean("archived", false),
            shared = item.optBoolean("shared", false)
        )
    }
}

private fun JSONArray.toTasks(): List<TaskSummary> {
    return List(length()) { index ->
        getJSONObject(index).toTaskSummary()
    }
}

internal fun JSONObject.toTaskSummary(): TaskSummary {
    return TaskSummary(
        id = getString("id"),
        goalId = getString("goalId"),
        title = getString("title"),
        description = optString("description"),
        type = getString("type"),
        priority = getInt("priority"),
        status = getString("status"),
        plannedTime = optString("plannedTime").ifBlank { null },
        dueTime = optString("dueTime").ifBlank { null },
        shared = optBoolean("shared", false)
    )
}
