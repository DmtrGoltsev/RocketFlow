package com.rocketflow.companion.planning

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class TaskPriorityCompatibilityUnitTest {
    @Test
    fun missingWirePriorityFallsBackToV20ShadowDefault() {
        assertEquals(5, TaskPriorityCompatibility.readShadow(JSONObject()))
    }

    @Test
    fun existingWirePriorityIsRetainedAsOpaqueShadow() {
        assertEquals(9, TaskPriorityCompatibility.readShadow(JSONObject().put("priority", 9)))
    }
}
