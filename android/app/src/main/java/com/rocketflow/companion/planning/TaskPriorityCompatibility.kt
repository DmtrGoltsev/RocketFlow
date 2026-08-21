package com.rocketflow.companion.planning

import org.json.JSONObject

internal object TaskPriorityCompatibility {
    const val DEFAULT_SHADOW = 5

    fun readShadow(json: JSONObject): Int = json.optInt("priority", DEFAULT_SHADOW)
}
