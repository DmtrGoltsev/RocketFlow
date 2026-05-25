package com.rocketflow.companion.notifications

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class NotificationRuntimeUnitTest {

    @Test
    fun taskReminderAlarmChannelUsesVersionedId() {
        assertEquals("rocketflow.task.alarms.v2", NotificationRuntime.CHANNEL_ID)
    }

    @Test
    fun taskReminderAlarmChannelHasAlarmVibrationPattern() {
        assertArrayEquals(
            longArrayOf(0L, 700L, 250L, 700L, 250L, 1000L),
            NotificationRuntime.ALARM_VIBRATION_PATTERN
        )
    }
}
