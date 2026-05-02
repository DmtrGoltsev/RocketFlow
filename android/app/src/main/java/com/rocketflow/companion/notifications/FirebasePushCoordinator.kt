package com.rocketflow.companion.notifications

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import com.rocketflow.companion.BuildConfig

class FirebasePushCoordinator(
    private val context: Context,
    private val pushTokenStore: PushTokenStore
) {

    fun initialize() {
        if (ensureFirebaseApp() != null) {
            refreshToken {}
        }
    }

    fun isConfigured(): Boolean = ensureFirebaseApp() != null

    fun readStoredToken(): PushTokenSnapshot? = pushTokenStore.read()

    fun persistToken(token: String) {
        if (token.isNotBlank()) {
            pushTokenStore.write(token)
        }
    }

    fun refreshToken(onComplete: (PushTokenRefreshResult) -> Unit) {
        val firebaseApp = ensureFirebaseApp()
        if (firebaseApp == null) {
            onComplete(
                PushTokenRefreshResult(
                    configured = false,
                    errorMessage = "Firebase configuration is missing for this build."
                )
            )
            return
        }

        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (!task.isSuccessful) {
                onComplete(
                    PushTokenRefreshResult(
                        configured = true,
                        errorMessage = task.exception?.message ?: "Could not refresh the push token."
                    )
                )
                return@addOnCompleteListener
            }

            val token = task.result?.trim().orEmpty()
            if (token.isBlank()) {
                onComplete(
                    PushTokenRefreshResult(
                        configured = true,
                        errorMessage = "Firebase returned an empty push token."
                    )
                )
                return@addOnCompleteListener
            }

            pushTokenStore.write(token)
            onComplete(PushTokenRefreshResult(token = pushTokenStore.read(), configured = true))
        }
    }

    private fun ensureFirebaseApp(): FirebaseApp? {
        val apps = FirebaseApp.getApps(context)
        val manualOptions = manualFirebaseOptions()

        if (manualOptions != null) {
            apps.firstOrNull { app ->
                app.name == FirebaseApp.DEFAULT_APP_NAME && app.options.matches(manualOptions)
            }?.let { return it }

            apps.firstOrNull { it.name == FirebaseApp.DEFAULT_APP_NAME }?.delete()
            return FirebaseApp.initializeApp(context, manualOptions)
        }

        apps.firstOrNull { it.name == FirebaseApp.DEFAULT_APP_NAME }?.let { return it }
        return FirebaseApp.initializeApp(context)
    }

    private fun manualFirebaseOptions(): FirebaseOptions? {
        val applicationId = BuildConfig.ROCKETFLOW_FIREBASE_APPLICATION_ID.trim()
        val apiKey = BuildConfig.ROCKETFLOW_FIREBASE_API_KEY.trim()
        val projectId = BuildConfig.ROCKETFLOW_FIREBASE_PROJECT_ID.trim()
        val gcmSenderId = BuildConfig.ROCKETFLOW_FIREBASE_GCM_SENDER_ID.trim()

        if (applicationId.isBlank() || apiKey.isBlank() || projectId.isBlank() || gcmSenderId.isBlank()) {
            return null
        }

        return FirebaseOptions.Builder()
            .setApplicationId(applicationId)
            .setApiKey(apiKey)
            .setProjectId(projectId)
            .setGcmSenderId(gcmSenderId)
            .build()
    }

    private fun FirebaseOptions.matches(other: FirebaseOptions): Boolean {
        return applicationId == other.applicationId &&
            apiKey == other.apiKey &&
            projectId == other.projectId &&
            gcmSenderId == other.gcmSenderId
    }
}
