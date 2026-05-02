package com.rocketflow.companion.auth

import android.content.Context

class LanguageStore(context: Context) {

    private val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun readLanguage(): String {
        return preferences.getString(KEY_LANGUAGE, null)
            ?.takeIf { it in SUPPORTED_LANGUAGES }
            ?: DEFAULT_LANGUAGE
    }

    fun writeLanguage(language: String) {
        val normalized = language.takeIf { it in SUPPORTED_LANGUAGES } ?: DEFAULT_LANGUAGE
        preferences.edit().putString(KEY_LANGUAGE, normalized).apply()
    }

    companion object {
        const val DEFAULT_LANGUAGE = "ru"
        private const val PREFS_NAME = "rocketflow_companion_language"
        private const val KEY_LANGUAGE = "language"
        private val SUPPORTED_LANGUAGES = setOf("ru", "en")
    }
}
