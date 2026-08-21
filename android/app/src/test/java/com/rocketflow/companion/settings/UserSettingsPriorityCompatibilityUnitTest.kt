package com.rocketflow.companion.settings

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class UserSettingsPriorityCompatibilityUnitTest {
    @Test
    fun v20UpdateRoundTripsHiddenPoliciesWithoutExposingDecayControls() {
        val source = JSONObject()
            .put("language", "ru")
            .put("notificationsEnabled", false)
            .put("version", 12)
            .put("greenPriorityDecayPolicy", JSONObject().put("enabled", true).put("thresholdPreset", "week").put("decayAmount", 3).put("futureField", "keep"))
            .put("redPriorityDecayPolicy", JSONObject().put("enabled", false).put("thresholdPreset", "day").put("decayAmount", 7))

        val updated = source.toUserSettings().copy(language = "en", notificationsEnabled = true).toV20Body()

        assertEquals("en", updated.getString("language"))
        assertTrue(updated.getBoolean("notificationsEnabled"))
        assertEquals(12, updated.getLong("version"))
        assertEquals("keep", updated.getJSONObject("greenPriorityDecayPolicy").getString("futureField"))
        assertEquals(3, updated.getJSONObject("greenPriorityDecayPolicy").getInt("decayAmount"))
        assertEquals(7, updated.getJSONObject("redPriorityDecayPolicy").getInt("decayAmount"))
    }
}
