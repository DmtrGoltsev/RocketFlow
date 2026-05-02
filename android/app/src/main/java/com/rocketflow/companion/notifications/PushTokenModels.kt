package com.rocketflow.companion.notifications

data class PushTokenSnapshot(
    val value: String,
    val updatedAt: String
)

data class PushTokenRefreshResult(
    val token: PushTokenSnapshot? = null,
    val errorMessage: String? = null,
    val configured: Boolean = true
)
