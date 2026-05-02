package com.rocketflow.companion.settings

import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.SessionBoundResult
import org.json.JSONObject

data class PriorityDecayPolicy(
    val taskType: String,
    val enabled: Boolean,
    val thresholdPreset: String,
    val decayAmount: Int
)

data class UserSettings(
    val language: String,
    val greenPriorityDecayPolicy: PriorityDecayPolicy,
    val redPriorityDecayPolicy: PriorityDecayPolicy,
    val notificationsEnabled: Boolean,
    val version: Long
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
        val result = authRepository.authorizedPatch(session, "/me/settings", settings.toBody())
        return SessionBoundResult(result.session, result.value.toSettings())
    }

    private fun UserSettings.toBody(): JSONObject {
        return JSONObject()
            .put("language", language)
            .put("greenPriorityDecayPolicy", greenPriorityDecayPolicy.toRequestBody())
            .put("redPriorityDecayPolicy", redPriorityDecayPolicy.toRequestBody())
            .put("notificationsEnabled", notificationsEnabled)
            .put("version", version)
    }

    private fun PriorityDecayPolicy.toRequestBody(): JSONObject {
        return JSONObject()
            .put("enabled", enabled)
            .put("thresholdPreset", thresholdPreset)
            .put("decayAmount", decayAmount)
    }

    private fun JSONObject.toSettings(): UserSettings {
        return UserSettings(
            language = optString("language", "ru"),
            greenPriorityDecayPolicy = getJSONObject("greenPriorityDecayPolicy").toPolicy("green"),
            redPriorityDecayPolicy = getJSONObject("redPriorityDecayPolicy").toPolicy("red"),
            notificationsEnabled = optBoolean("notificationsEnabled", true),
            version = optLong("version", 0)
        )
    }

    private fun JSONObject.toPolicy(defaultTaskType: String): PriorityDecayPolicy {
        return PriorityDecayPolicy(
            taskType = optString("taskType", defaultTaskType),
            enabled = optBoolean("enabled", true),
            thresholdPreset = optString("thresholdPreset", "day"),
            decayAmount = optInt("decayAmount", 1).coerceAtLeast(1)
        )
    }
}
