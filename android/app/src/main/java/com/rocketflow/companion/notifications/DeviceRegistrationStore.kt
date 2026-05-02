package com.rocketflow.companion.notifications

import android.content.Context
import java.util.UUID

class DeviceRegistrationStore(context: Context) {

    private val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun read(): DeviceRegistration? {
        return readState()?.registration
    }

    fun readOrCreateInstallationId(): String {
        val existing = preferences.getString(KEY_INSTALLATION_ID, null)?.trim().orEmpty()
        if (existing.isNotBlank()) {
            return existing
        }

        val generated = UUID.randomUUID().toString()
        preferences.edit()
            .putString(KEY_INSTALLATION_ID, generated)
            .apply()
        return generated
    }

    fun readState(): StoredDeviceRegistration? {
        val id = preferences.getString(KEY_ID, null) ?: return null
        val platform = preferences.getString(KEY_PLATFORM, null) ?: return null
        val createdAt = preferences.getString(KEY_CREATED_AT, null) ?: return null

        return StoredDeviceRegistration(
            registration = DeviceRegistration(
                id = id,
                platform = platform,
                deviceName = preferences.getString(KEY_DEVICE_NAME, null),
                active = preferences.getBoolean(KEY_ACTIVE, false),
                createdAt = createdAt
            ),
            userId = preferences.getString(KEY_USER_ID, null),
            pushToken = preferences.getString(KEY_PUSH_TOKEN, null),
            deviceName = preferences.getString(KEY_LAST_DEVICE_NAME, null)
        )
    }

    fun write(
        registration: DeviceRegistration,
        userId: String,
        pushToken: String,
        deviceName: String?
    ) {
        preferences.edit()
            .putString(KEY_ID, registration.id)
            .putString(KEY_PLATFORM, registration.platform)
            .putString(KEY_DEVICE_NAME, registration.deviceName)
            .putBoolean(KEY_ACTIVE, registration.active)
            .putString(KEY_CREATED_AT, registration.createdAt)
            .putString(KEY_USER_ID, userId)
            .putString(KEY_PUSH_TOKEN, pushToken)
            .putString(KEY_LAST_DEVICE_NAME, deviceName)
            .apply()
    }

    fun clear() {
        preferences.edit()
            .remove(KEY_ID)
            .remove(KEY_PLATFORM)
            .remove(KEY_DEVICE_NAME)
            .remove(KEY_ACTIVE)
            .remove(KEY_CREATED_AT)
            .remove(KEY_USER_ID)
            .remove(KEY_PUSH_TOKEN)
            .remove(KEY_LAST_DEVICE_NAME)
            .apply()
    }

    companion object {
        private const val PREFS_NAME = "rocketflow_companion_device_registration"
        private const val KEY_ID = "device_id"
        private const val KEY_PLATFORM = "platform"
        private const val KEY_DEVICE_NAME = "device_name"
        private const val KEY_ACTIVE = "active"
        private const val KEY_CREATED_AT = "created_at"
        private const val KEY_USER_ID = "user_id"
        private const val KEY_PUSH_TOKEN = "push_token"
        private const val KEY_LAST_DEVICE_NAME = "last_device_name"
        private const val KEY_INSTALLATION_ID = "installation_id"
    }
}

data class StoredDeviceRegistration(
    val registration: DeviceRegistration,
    val userId: String?,
    val pushToken: String?,
    val deviceName: String?
)
