package com.rocketflow.companion.notifications

import android.content.Intent
import android.net.Uri

object NotificationIntents {

    private const val SCHEME = "rocketflow"
    private const val HOST = "task"
    private const val EXTRA_TASK_ID = "taskId"
    private const val EXTRA_TYPE = "type"
    private const val TASK_REMINDER_TYPE = "task_reminder"

    fun extractTaskId(intent: Intent?): String? {
        if (intent == null) {
            return null
        }

        intent.getStringExtra(EXTRA_TASK_ID)
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?.let { return it }

        val data = intent.data ?: return null
        if (data.scheme != SCHEME) {
            return null
        }

        if (data.host == HOST) {
            data.lastPathSegment?.trim()?.takeIf { it.isNotBlank() }?.let { return it }
        }

        val taskIdFromQuery = data.getQueryParameter(EXTRA_TASK_ID)?.trim()
        if (!taskIdFromQuery.isNullOrBlank()) {
            return taskIdFromQuery
        }

        if (intent.getStringExtra(EXTRA_TYPE) == TASK_REMINDER_TYPE) {
            return data.lastPathSegment?.trim()?.takeIf { it.isNotBlank() }
        }

        return null
    }

    fun taskDeepLink(taskId: String): Uri {
        return Uri.parse("$SCHEME://$HOST/$taskId")
    }
}
