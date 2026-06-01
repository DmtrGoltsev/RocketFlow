package com.rocketflow.companion.notifications

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

class TaskReminderScheduleUnitTest {

    private val zone = ZoneId.of("Europe/Moscow")

    @Test
    fun oneShotFutureAlarmKeepsSelectedTime() {
        val trigger = millis(2026, 5, 14, 9, 30)
        val now = millis(2026, 5, 14, 8, 0)

        assertEquals(
            trigger,
            TaskReminderSchedule.nextTriggerAtOrAfter(trigger, TaskReminderRepeat.None, now, zone)
        )
    }

    @Test
    fun oneShotPastAlarmDoesNotReschedule() {
        val trigger = millis(2026, 5, 14, 9, 30)
        val now = millis(2026, 5, 14, 10, 0)

        assertNull(TaskReminderSchedule.nextTriggerAtOrAfter(trigger, TaskReminderRepeat.None, now, zone))
    }

    @Test
    fun dailyAlarmAdvancesToNextFutureOccurrence() {
        val trigger = millis(2026, 5, 12, 9, 30)
        val now = millis(2026, 5, 14, 10, 0)
        val expected = millis(2026, 5, 15, 9, 30)

        assertEquals(
            expected,
            TaskReminderSchedule.nextTriggerAtOrAfter(trigger, TaskReminderRepeat.Daily, now, zone)
        )
    }

    @Test
    fun hourlyAlarmAdvancesToNextFutureOccurrence() {
        val trigger = millis(2026, 5, 14, 9, 30)
        val now = millis(2026, 5, 14, 12, 5)
        val expected = millis(2026, 5, 14, 12, 30)

        assertEquals(
            expected,
            TaskReminderSchedule.nextTriggerAtOrAfter(trigger, TaskReminderRepeat.Hourly, now, zone)
        )
    }

    @Test
    fun hourlyAlarmAdvancesAfterLongOfflineGap() {
        val trigger = millis(2025, 1, 1, 9, 30)
        val now = millis(2026, 5, 14, 12, 5)
        val expected = millis(2026, 5, 14, 12, 30)

        assertEquals(
            expected,
            TaskReminderSchedule.nextTriggerAtOrAfter(trigger, TaskReminderRepeat.Hourly, now, zone)
        )
    }

    @Test
    fun weeklyAlarmPreservesWeekdayAndTime() {
        val trigger = millis(2026, 5, 7, 18, 45)
        val now = millis(2026, 5, 14, 18, 45)
        val expected = millis(2026, 5, 21, 18, 45)

        assertEquals(
            expected,
            TaskReminderSchedule.nextTriggerAtOrAfter(trigger, TaskReminderRepeat.Weekly, now, zone)
        )
    }

    @Test
    fun monthlyAlarmPreservesOriginalDayAfterClampedMonth() {
        val trigger = millis(2026, 1, 31, 8, 0)
        val now = millis(2026, 2, 28, 8, 0)
        val expected = millis(2026, 3, 31, 8, 0)

        assertEquals(
            expected,
            TaskReminderSchedule.nextTriggerAtOrAfter(trigger, TaskReminderRepeat.Monthly, now, zone)
        )
    }

    @Test
    fun monthlyAlarmKeepsAnchorAfterDeliveredClampedOccurrence() {
        val anchor = millis(2026, 1, 31, 8, 0)
        val delivered = millis(2026, 2, 28, 8, 0)
        val now = delivered + 1L
        val expected = millis(2026, 3, 31, 8, 0)

        assertEquals(
            expected,
            TaskReminderSchedule.nextTriggerAtOrAfter(
                triggerAtMillis = delivered,
                repeat = TaskReminderRepeat.Monthly,
                nowMillis = now,
                zone = zone,
                anchorAtMillis = anchor
            )
        )
    }

    @Test
    fun recurringRescheduleAdvancesPastMissedTicksAndKeepsAnchor() {
        val anchor = millis(2026, 5, 12, 9, 30)
        val setting = TaskReminderSetting(
            userId = "user-1",
            taskId = "task-1",
            reminderId = "reminder-1",
            taskTitle = "Prepare release",
            triggerAtMillis = anchor,
            repeat = TaskReminderRepeat.Daily,
            enabled = true,
            anchorAtMillis = anchor
        )
        val now = millis(2026, 5, 14, 10, 0)
        val expected = setting.copy(triggerAtMillis = millis(2026, 5, 15, 9, 30))

        assertEquals(expected, TaskReminderSchedule.nextSettingAtOrAfter(setting, now, zone))
    }

    @Test
    fun oneShotRescheduleExpiresAfterMissedTick() {
        val setting = TaskReminderSetting(
            userId = "user-1",
            taskId = "task-1",
            reminderId = "reminder-1",
            taskTitle = "Prepare release",
            triggerAtMillis = millis(2026, 5, 12, 9, 30),
            repeat = TaskReminderRepeat.None,
            enabled = true
        )
        val now = millis(2026, 5, 14, 10, 0)

        assertNull(TaskReminderSchedule.nextSettingAtOrAfter(setting, now, zone))
    }

    @Test
    fun requestCodesDifferForMultipleRemindersOnSameTask() {
        assertNotEquals(
            TaskReminderAlarmScheduler.requestCode("user-1", "task-1", "reminder-1"),
            TaskReminderAlarmScheduler.requestCode("user-1", "task-1", "reminder-2")
        )
    }

    @Test
    fun jsonRoundTripKeepsUserAndTaskScope() {
        val anchor = millis(2026, 5, 14, 9, 30)
        val setting = TaskReminderSetting(
            userId = "user-1",
            taskId = "task-1",
            reminderId = "reminder-1",
            taskTitle = "Prepare release",
            triggerAtMillis = anchor,
            repeat = TaskReminderRepeat.Weekly,
            enabled = true,
            anchorAtMillis = anchor
        )

        assertEquals(setting, TaskReminderJson.decode(TaskReminderJson.encode(setting)))
    }

    @Test
    fun legacyJsonDefaultsAnchorToTrigger() {
        val trigger = millis(2026, 5, 14, 9, 30)
        val decoded = TaskReminderJson.decode(
            """
            {
              "userId": "user-1",
              "taskId": "task-1",
              "reminderId": "reminder-1",
              "taskTitle": "Prepare release",
              "triggerAtMillis": $trigger,
              "repeat": "weekly",
              "enabled": true
            }
            """.trimIndent()
        )

        assertEquals(trigger, decoded?.anchorAtMillis)
    }

    @Test
    fun defaultReminderJsonRoundTripKeepsRepeatAndOffset() {
        val setting = DefaultTaskReminderSetting(
            userId = "user-1",
            offsetMinutes = 180,
            repeat = TaskReminderRepeat.Daily,
            enabled = true
        )

        assertEquals(setting, DefaultTaskReminderJson.decode(DefaultTaskReminderJson.encode(setting)))
    }

    @Test
    fun legacyDefaultReminderJsonKeepsRepeatAndUsesSafeOffset() {
        val trigger = millis(2026, 5, 14, 9, 30)
        val decoded = DefaultTaskReminderJson.decode(
            """
            {
              "userId": "user-1",
              "triggerAtMillis": $trigger,
              "repeat": "hourly",
              "enabled": true,
              "anchorAtMillis": $trigger
            }
            """.trimIndent()
        )

        assertEquals(TaskReminderSchedule.DEFAULT_TASK_REMINDER_OFFSET_MINUTES, decoded?.offsetMinutes)
        assertEquals(TaskReminderRepeat.Hourly, decoded?.repeat)
        assertEquals(true, decoded?.enabled)
    }

    @Test
    fun legacyDefaultReminderJsonPreservesDisabledState() {
        val trigger = millis(2026, 5, 14, 9, 30)
        val decoded = DefaultTaskReminderJson.decode(
            """
            {
              "userId": "user-1",
              "triggerAtMillis": $trigger,
              "repeat": "daily",
              "enabled": false,
              "anchorAtMillis": $trigger
            }
            """.trimIndent()
        )

        assertEquals(TaskReminderRepeat.Daily, decoded?.repeat)
        assertEquals(false, decoded?.enabled)
    }

    @Test
    fun defaultReminderMaterializesFromDueTimeAndOffset() {
        val due = millis(2026, 5, 14, 9, 30)
        val setting = DefaultTaskReminderSetting(
            userId = "user-1",
            offsetMinutes = 60,
            repeat = TaskReminderRepeat.Daily,
            enabled = true
        )

        val materialized = TaskReminderSchedule.materializeDefaultReminder(
            userId = "user-1",
            taskId = "task-1",
            taskTitle = "Prepare release",
            dueTimeMillis = due,
            defaultSetting = setting
        )

        assertEquals(millis(2026, 5, 14, 8, 30), materialized?.triggerAtMillis)
        assertEquals(millis(2026, 5, 14, 8, 30), materialized?.anchorAtMillis)
        assertEquals(TaskReminderRepeat.Daily, materialized?.repeat)
    }

    @Test
    fun defaultReminderDoesNotMaterializeWithoutDueTime() {
        val setting = DefaultTaskReminderSetting(
            userId = "user-1",
            offsetMinutes = 60,
            repeat = TaskReminderRepeat.None,
            enabled = true
        )

        assertNull(
            TaskReminderSchedule.materializeDefaultReminder(
                userId = "user-1",
                taskId = "task-1",
                taskTitle = "Prepare release",
                dueTimeMillis = null,
                defaultSetting = setting
            )
        )
    }

    @Test
    fun touchedReminderCanSkipDefaultMaterialization() {
        val due = millis(2026, 5, 14, 9, 30)
        val setting = DefaultTaskReminderSetting(
            userId = "user-1",
            offsetMinutes = 60,
            repeat = TaskReminderRepeat.None,
            enabled = true
        )
        val reminderTouched = true

        val materialized = if (reminderTouched) {
            null
        } else {
            TaskReminderSchedule.materializeDefaultReminder(
                userId = "user-1",
                taskId = "task-1",
                taskTitle = "Prepare release",
                dueTimeMillis = due,
                defaultSetting = setting
            )
        }

        assertNull(materialized)
    }

    private fun millis(year: Int, month: Int, day: Int, hour: Int, minute: Int): Long {
        return LocalDateTime.of(year, month, day, hour, minute)
            .atZone(zone)
            .toInstant()
            .toEpochMilli()
    }
}
