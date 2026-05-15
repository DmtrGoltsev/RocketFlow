package com.rocketflow.companion.notifications

import org.junit.Assert.assertEquals
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
    fun monthlyAlarmUsesJavaTimeMonthClamping() {
        val trigger = millis(2026, 1, 31, 8, 0)
        val now = millis(2026, 2, 28, 8, 0)
        val expected = millis(2026, 3, 28, 8, 0)

        assertEquals(
            expected,
            TaskReminderSchedule.nextTriggerAtOrAfter(trigger, TaskReminderRepeat.Monthly, now, zone)
        )
    }

    @Test
    fun jsonRoundTripKeepsUserAndTaskScope() {
        val setting = TaskReminderSetting(
            userId = "user-1",
            taskId = "task-1",
            taskTitle = "Prepare release",
            triggerAtMillis = millis(2026, 5, 14, 9, 30),
            repeat = TaskReminderRepeat.Weekly,
            enabled = true
        )

        assertEquals(setting, TaskReminderJson.decode(TaskReminderJson.encode(setting)))
    }

    private fun millis(year: Int, month: Int, day: Int, hour: Int, minute: Int): Long {
        return LocalDateTime.of(year, month, day, hour, minute)
            .atZone(zone)
            .toInstant()
            .toEpochMilli()
    }
}
