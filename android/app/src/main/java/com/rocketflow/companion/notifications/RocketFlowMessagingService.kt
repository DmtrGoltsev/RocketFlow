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

    private fun defaultDeviceName(): String {
        return listOfNotNull(Build.MANUFACTURER, Build.MODEL)
            .joinToString(separator = " ")
            .trim()
            .ifBlank { "Android companion" }
    }
}
