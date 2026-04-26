package com.rocketflow.companion.auth

import android.content.Context

class SessionStore(context: Context) {

    private val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun readSession(): AuthSession? {
        val accessToken = preferences.getString(KEY_ACCESS_TOKEN, null) ?: return null
        val refreshToken = preferences.getString(KEY_REFRESH_TOKEN, null) ?: return null
        val expiresAt = preferences.getString(KEY_EXPIRES_AT, null) ?: return null
        val userId = preferences.getString(KEY_USER_ID, null) ?: return null
        val email = preferences.getString(KEY_EMAIL, null) ?: return null
        val displayName = preferences.getString(KEY_DISPLAY_NAME, null) ?: return null
        val timezone = preferences.getString(KEY_TIMEZONE, null) ?: return null
        val language = preferences.getString(KEY_LANGUAGE, null) ?: return null

        return AuthSession(
            user = CurrentUser(
                id = userId,
                email = email,
                displayName = displayName,
                timezone = timezone,
                language = language
            ),
            tokens = AuthTokens(
                accessToken = accessToken,
                refreshToken = refreshToken,
                expiresAt = expiresAt
            )
        )
    }

    fun writeSession(session: AuthSession) {
        preferences.edit()
            .putString(KEY_ACCESS_TOKEN, session.tokens.accessToken)
            .putString(KEY_REFRESH_TOKEN, session.tokens.refreshToken)
            .putString(KEY_EXPIRES_AT, session.tokens.expiresAt)
            .putString(KEY_USER_ID, session.user.id)
            .putString(KEY_EMAIL, session.user.email)
            .putString(KEY_DISPLAY_NAME, session.user.displayName)
            .putString(KEY_TIMEZONE, session.user.timezone)
            .putString(KEY_LANGUAGE, session.user.language)
            .apply()
    }

    fun clear() {
        preferences.edit().clear().apply()
    }

    companion object {
        private const val PREFS_NAME = "rocketflow_companion_session"
        private const val KEY_ACCESS_TOKEN = "access_token"
        private const val KEY_REFRESH_TOKEN = "refresh_token"
        private const val KEY_EXPIRES_AT = "expires_at"
        private const val KEY_USER_ID = "user_id"
        private const val KEY_EMAIL = "email"
        private const val KEY_DISPLAY_NAME = "display_name"
        private const val KEY_TIMEZONE = "timezone"
        private const val KEY_LANGUAGE = "language"
    }
}

