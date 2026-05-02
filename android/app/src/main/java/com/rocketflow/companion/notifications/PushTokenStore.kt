package com.rocketflow.companion.notifications

import android.content.Context
import java.time.Instant

class PushTokenStore(context: Context) {

    private val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun read(): PushTokenSnapshot? {
        val value = preferences.getString(KEY_VALUE, null)?.trim().orEmpty()
        val updatedAt = preferences.getString(KEY_UPDATED_AT, null)?.trim().orEmpty()
        if (value.isBlank() || updatedAt.isBlank()) {
            return null
        }
        return PushTokenSnapshot(value = value, updatedAt = updatedAt)
    }

    fun write(value: String) {
        preferences.edit()
            .putString(KEY_VALUE, value)
            .putString(KEY_UPDATED_AT, Instant.now().toString())
            .apply()
    }

    companion object {
        private const val PREFS_NAME = "rocketflow_companion_push_token"
        private const val KEY_VALUE = "push_token"
        private const val KEY_UPDATED_AT = "updated_at"
    }
}
