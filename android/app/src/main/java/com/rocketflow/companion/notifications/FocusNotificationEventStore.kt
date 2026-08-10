package com.rocketflow.companion.notifications

import android.content.Context
import java.security.MessageDigest

class FocusNotificationEventStore(
    context: Context,
    private val nowMillis: () -> Long = System::currentTimeMillis
) {
    private val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun markIfNew(eventId: String): Boolean {
        if (eventId.isBlank()) return false
        synchronized(PROCESS_LOCK) {
            val now = nowMillis()
            val cutoff = now - RETENTION_MILLIS
            val key = EVENT_PREFIX + eventId.sha256()
            val existing = preferences.getLong(key, Long.MIN_VALUE)
            if (existing >= cutoff) return false

            val editor = preferences.edit()
            preferences.all.forEach { (storedKey, value) ->
                if (storedKey.startsWith(EVENT_PREFIX) && (value as? Long ?: Long.MIN_VALUE) < cutoff) {
                    editor.remove(storedKey)
                }
            }
            return editor.putLong(key, now).commit()
        }
    }

    private fun String.sha256(): String = MessageDigest.getInstance("SHA-256")
        .digest(toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }

    companion object {
        private const val PREFS = "rocketflow_focus_notification_events"
        private const val EVENT_PREFIX = "event."
        internal const val RETENTION_MILLIS = 14L * 24 * 60 * 60 * 1000
        private val PROCESS_LOCK = Any()
    }
}
