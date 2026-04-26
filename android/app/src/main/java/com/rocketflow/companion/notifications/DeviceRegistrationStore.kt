package com.rocketflow.companion.notifications

import android.content.Context

class DeviceRegistrationStore(context: Context) {

    private val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun read(): DeviceRegistration? {
        val id = preferences.getString(KEY_ID, null) ?: return null
        val platform = preferences.getString(KEY_PLATFORM, null) ?: return null
        val createdAt = preferences.getString(KEY_CREATED_AT, null) ?: return null

        return DeviceRegistration(
            id = id,
            platform = platform,
            deviceName = preferences.getString(KEY_DEVICE_NAME, null),
            active = preferences.getBoolean(KEY_ACTIVE, false),
            createdAt = createdAt
        )
    }

    fun write(registration: DeviceRegistration) {
        preferences.edit()
            .putString(KEY_ID, registration.id)
            .putString(KEY_PLATFORM, registration.platform)
            .putString(KEY_DEVICE_NAME, registration.deviceName)
            .putBoolean(KEY_ACTIVE, registration.active)
            .putString(KEY_CREATED_AT, registration.createdAt)
            .apply()
    }

    fun clear() {
        preferences.edit().clear().apply()
    }

    companion object {
        private const val PREFS_NAME = "rocketflow_companion_device_registration"
        private const val KEY_ID = "device_id"
        private const val KEY_PLATFORM = "platform"
        private const val KEY_DEVICE_NAME = "device_name"
        private const val KEY_ACTIVE = "active"
        private const val KEY_CREATED_AT = "created_at"
    }
}
