package com.rocketflow.companion.notifications

import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

enum class TaskReminderRepeat(val wireValue: String) {
    None("none"),
    Hourly("hourly"),
    Daily("daily"),
    Weekly("weekly"),
    Monthly("monthly");

    companion object {
        fun fromWireValue(value: String?): TaskReminderRepeat {
            return entries.firstOrNull { it.wireValue == value } ?: None
        }
    }
}

data class TaskReminderSetting(
    val userId: String,
    val taskId: String,
    val reminderId: String,
    val taskTitle: String,
    val triggerAtMillis: Long,
    val repeat: TaskReminderRepeat,
    val enabled: Boolean = true
)

object TaskReminderJson {
    fun encode(setting: TaskReminderSetting): String {
        return JSONObject()
            .put("userId", setting.userId)
            .put("taskId", setting.taskId)
            .put("reminderId", setting.reminderId)
            .put("taskTitle", setting.taskTitle)
            .put("triggerAtMillis", setting.triggerAtMillis)
            .put("repeat", setting.repeat.wireValue)
            .put("enabled", setting.enabled)
            .toString()
    }

    fun decode(raw: String?): TaskReminderSetting? {
        if (raw.isNullOrBlank()) {
            return null
        }

        return runCatching {
            val json = JSONObject(raw)
            val userId = json.optString("userId").trim()
            val taskId = json.optString("taskId").trim()
            if (userId.isBlank() || taskId.isBlank()) {
                return@runCatching null
            }

            TaskReminderSetting(
                userId = userId,
                taskId = taskId,
                reminderId = json.optString("reminderId").trim().ifBlank { legacyReminderId(taskId) },
                taskTitle = json.optString("taskTitle").trim().ifBlank { "RocketFlow task" },
                triggerAtMillis = json.optLong("triggerAtMillis", 0L),
                repeat = TaskReminderRepeat.fromWireValue(json.optString("repeat")),
                enabled = json.optBoolean("enabled", true)
            )
        }.getOrNull()
    }

    fun encodeList(settings: List<TaskReminderSetting>): String {
        val array = org.json.JSONArray()
        settings.forEach { array.put(JSONObject(encode(it))) }
        return array.toString()
    }

    fun decodeList(raw: String?): List<TaskReminderSetting> {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching {
            val trimmed = raw.trim()
            if (trimmed.startsWith("[")) {
                val array = org.json.JSONArray(trimmed)
                (0 until array.length()).mapNotNull { index ->
                    decode(array.optJSONObject(index)?.toString())
                }
            } else {
                listOfNotNull(decode(trimmed))
            }
        }.getOrDefault(emptyList())
    }

    fun legacyReminderId(taskId: String): String {
        return "legacy-$taskId"
    }
}

object TaskReminderSchedule {
    fun nextTriggerAtOrAfter(
        triggerAtMillis: Long,
        repeat: TaskReminderRepeat,
        nowMillis: Long,
        zone: ZoneId = ZoneId.systemDefault()
    ): Long? {
        if (triggerAtMillis <= 0L) {
            return null
        }
        if (triggerAtMillis >= nowMillis) {
            return triggerAtMillis
        }
        if (repeat == TaskReminderRepeat.None) {
            return null
        }

        var next = Instant.ofEpochMilli(triggerAtMillis).atZone(zone).toLocalDateTime()
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDateTime()
        if (repeat == TaskReminderRepeat.Hourly) {
            val skippedHours = ChronoUnit.HOURS.between(next, now).coerceAtLeast(0) + 1
            next = next.plusHours(skippedHours)
        }
        var guard = 0
        while (!next.isAfter(now) && guard < 4096) {
            next = when (repeat) {
                TaskReminderRepeat.None -> next
                TaskReminderRepeat.Hourly -> next.plusHours(1)
                TaskReminderRepeat.Daily -> next.plusDays(1)
                TaskReminderRepeat.Weekly -> next.plusWeeks(1)
                TaskReminderRepeat.Monthly -> next.plusMonths(1)
            }
            guard += 1
        }

        return if (next.isAfter(now)) next.atZone(zone).toInstant().toEpochMilli() else null
    }
}
