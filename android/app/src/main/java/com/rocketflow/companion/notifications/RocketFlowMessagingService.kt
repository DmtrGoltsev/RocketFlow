package com.rocketflow.companion.notifications

import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.rocketflow.companion.RocketFlowCompanionApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class RocketFlowMessagingService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        if (token.isBlank()) {
            return
        }
        val container = (application as? RocketFlowCompanionApp)?.container ?: return
        container.firebasePushCoordinator.persistToken(token)
        CoroutineScope(Dispatchers.IO).launch {
            runCatching {
                container.notificationsRepository.syncDeviceRegistrationWithStoredSession(defaultDeviceName())
            }
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val messageType = message.data["type"]?.trim().orEmpty()
        if (messageType.equals("focus_reminder", ignoreCase = true)) {
            showFocusReminder(message)
            return
        }
        if (messageType.isNotBlank() && messageType != "task_reminder") {
            return
        }

        val taskId = message.data["taskId"]?.trim().orEmpty()
        if (taskId.isBlank()) {
            return
        }

        val title = message.notification?.title
            ?: message.data["title"]
            ?: "RocketFlow reminder"
        val body = message.notification?.body
            ?: message.data["body"]
            ?: "Open the task in RocketFlow Companion."

        (application as? RocketFlowCompanionApp)
            ?.container
            ?.notificationRuntime
            ?.showTaskReminderNotification(taskId, title, body)
    }

    private fun showFocusReminder(message: RemoteMessage) {
        val payload = focusPushPayload(message.data, message.notification != null) ?: return
        if (!FocusNotificationEventStore(this).markIfNew(payload.eventId)) return
        (application as? RocketFlowCompanionApp)
            ?.container
            ?.notificationRuntime
            ?.showFocusReminderNotification(payload.periodId, payload.title, payload.body)
    }

    private fun defaultDeviceName(): String {
        return listOfNotNull(Build.MANUFACTURER, Build.MODEL)
            .joinToString(separator = " ")
            .trim()
            .ifBlank { "Android companion" }
    }
}

internal data class FocusPushPayload(
    val periodId: String,
    val eventId: String,
    val title: String,
    val body: String
)

internal fun focusPushPayload(data: Map<String, String>, hasNotificationPayload: Boolean): FocusPushPayload? {
    if (hasNotificationPayload || !data["type"].orEmpty().equals("focus_reminder", ignoreCase = true)) return null
    val periodId = data["periodId"]?.trim().orEmpty()
    val eventId = data["eventId"]?.trim().orEmpty()
    if (periodId.isBlank() || eventId.isBlank()) return null
    return FocusPushPayload(
        periodId = periodId,
        eventId = eventId,
        title = data["title"]?.trim().orEmpty().ifBlank { "RocketFlow" },
        body = data["body"]?.trim().orEmpty().ifBlank { "Open your weekly focus." }
    )
}
