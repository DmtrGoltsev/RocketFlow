package com.rocketflow.companion.notifications

data class DeviceRegistration(
    val id: String,
    val platform: String,
    val deviceName: String?,
    val active: Boolean,
    val createdAt: String
)
