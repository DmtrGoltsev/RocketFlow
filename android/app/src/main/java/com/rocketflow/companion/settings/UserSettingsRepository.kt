package com.rocketflow.companion.settings

import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.SessionBoundResult
import org.json.JSONObject

data class SettingsCompatibilityShadows(
    val greenJson: String,
    val redJson: String
) {
    companion object
}

data class UserSettings(
    val language: String,
    val notificationsEnabled: Boolean,
    val version: Long,
    internal val compatibilityShadows: SettingsCompatibilityShadows = SettingsCompatibilityShadows.defaults()
)

class UserSettingsRepository(
    private val authRepository: AuthRepository
) {

    suspend fun getSettings(session: AuthSession): SessionBoundResult<UserSettings> {
        val result = authRepository.authorizedGet(session, "/me/settings")
        return SessionBoundResult(result.session, result.value.toSettings())
    }

    suspend fun updateSettings(
        session: AuthSession,
        settings: UserSettings
    ): SessionBoundResult<UserSettings> {
        val result = authRepository.authorizedPatch(session, "/me/settings", settings.toV20Body())
        return SessionBoundResult(result.session, result.value.toSettings())
    }

    private fun JSONObject.toSettings(): UserSettings {
        return toUserSettings()
    }
}

internal fun JSONObject.toUserSettings(): UserSettings {
    val defaults = SettingsCompatibilityShadows.defaults()
    return UserSettings(
        language = optString("language", "ru"),
        notificationsEnabled = optBoolean("notificationsEnabled", true),
        version = optLong("version", 0),
        compatibilityShadows = SettingsCompatibilityShadows(
            greenJson = optJSONObject("greenPriorityDecayPolicy")?.toString() ?: defaults.greenJson,
            redJson = optJSONObject("redPriorityDecayPolicy")?.toString() ?: defaults.redJson
        )
    )
}

internal fun UserSettings.toV20Body(): JSONObject {
    return JSONObject()
        .put("language", language)
        .put("greenPriorityDecayPolicy", JSONObject(compatibilityShadows.greenJson))
        .put("redPriorityDecayPolicy", JSONObject(compatibilityShadows.redJson))
        .put("notificationsEnabled", notificationsEnabled)
        .put("version", version)
}

private fun SettingsCompatibilityShadows.Companion.defaults(): SettingsCompatibilityShadows =
    SettingsCompatibilityShadows(
        greenJson = defaultPolicyJson(),
        redJson = defaultPolicyJson()
    )

private fun defaultPolicyJson(): String = JSONObject()
    .put("enabled", false)
    .put("thresholdPreset", "day")
    .put("decayAmount", 1)
    .toString()
