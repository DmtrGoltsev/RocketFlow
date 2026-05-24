package com.rocketflow.companion.notifications

import org.json.JSONObject
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.YearMonth
import java.time.temporal.ChronoUnit
import kotlin.math.min

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
    val enabled: Boolean = true,
    val anchorAtMillis: Long = triggerAtMillis
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
            .put("anchorAtMillis", setting.anchorAtMillis)
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
                enabled = json.optBoolean("enabled", true),
                anchorAtMillis = json.optLong("anchorAtMillis", json.optLong("triggerAtMillis", 0L))
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
    fun nextSettingAtOrAfter(
        setting: TaskReminderSetting,
        nowMillis: Long,
        zone: ZoneId = ZoneId.systemDefault()
    ): TaskReminderSetting? {
        val nextTrigger = nextTriggerAtOrAfter(
            triggerAtMillis = setting.triggerAtMillis,
            repeat = setting.repeat,
            nowMillis = nowMillis,
            zone = zone,
            anchorAtMillis = setting.anchorAtMillis
        ) ?: return null
        return if (nextTrigger == setting.triggerAtMillis) {
            setting
        } else {
            setting.copy(triggerAtMillis = nextTrigger)
        }
    }

    fun nextTriggerAtOrAfter(
        triggerAtMillis: Long,
        repeat: TaskReminderRepeat,
        nowMillis: Long,
        zone: ZoneId = ZoneId.systemDefault(),
        anchorAtMillis: Long = triggerAtMillis
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

        val anchorMillis = anchorAtMillis.takeIf { it > 0L } ?: triggerAtMillis
        val anchor = Instant.ofEpochMilli(anchorMillis).atZone(zone).toLocalDateTime()
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDateTime()
        val next = when (repeat) {
            TaskReminderRepeat.None -> return null
            TaskReminderRepeat.Hourly -> anchor.plusHours(ChronoUnit.HOURS.between(anchor, now).coerceAtLeast(0) + 1)
            TaskReminderRepeat.Daily -> anchor.plusDays(ChronoUnit.DAYS.between(anchor, now).coerceAtLeast(0) + 1)
            TaskReminderRepeat.Weekly -> anchor.plusWeeks(ChronoUnit.WEEKS.between(anchor, now).coerceAtLeast(0) + 1)
            TaskReminderRepeat.Monthly -> {
                val anchorMonth = YearMonth.from(anchor)
                val nowMonth = YearMonth.from(now)
                var months = ChronoUnit.MONTHS.between(anchorMonth, nowMonth).coerceAtLeast(0)
                var candidate = anchor.plusAnchoredMonths(months)
                if (!candidate.isAfter(now)) {
                    months += 1
                    candidate = anchor.plusAnchoredMonths(months)
                }
                candidate
            }
        }

        return if (next.isAfter(now)) next.atZone(zone).toInstant().toEpochMilli() else null
    }

    private fun LocalDateTime.plusAnchoredMonths(months: Long): LocalDateTime {
        val targetMonth = YearMonth.from(this).plusMonths(months)
        val targetDay = min(dayOfMonth, targetMonth.lengthOfMonth())
        return LocalDateTime.of(
            targetMonth.year,
            targetMonth.monthValue,
            targetDay,
            hour,
            minute,
            second,
            nano
        )
    }
}
