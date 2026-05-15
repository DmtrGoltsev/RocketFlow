package com.rocketflow.companion.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.time.ZoneId

class TaskReminderAlarmScheduler(
    private val context: Context,
    private val store: TaskReminderStore
) {

    data class ScheduleResult(
        val scheduled: Boolean,
        val exact: Boolean,
        val triggerAtMillis: Long?
    )

    private val alarmManager: AlarmManager? =
        context.getSystemService(AlarmManager::class.java)

    fun schedule(setting: TaskReminderSetting, nowMillis: Long = System.currentTimeMillis()): ScheduleResult {
        val alarmManager = alarmManager ?: return ScheduleResult(false, exact = false, triggerAtMillis = null)
        val nextTrigger = TaskReminderSchedule.nextTriggerAtOrAfter(
            triggerAtMillis = setting.triggerAtMillis,
            repeat = setting.repeat,
            nowMillis = nowMillis,
            zone = ZoneId.systemDefault()
        ) ?: return ScheduleResult(false, exact = canScheduleExactAlarms(), triggerAtMillis = null)

        val exact = canScheduleExactAlarms()
        val pendingIntent = alarmIntent(setting)
        if (exact) {
            try {
                alarmManager.setAlarmClock(
                    AlarmManager.AlarmClockInfo(nextTrigger, taskOpenIntent(setting)),
                    pendingIntent
                )
                return ScheduleResult(scheduled = true, exact = true, triggerAtMillis = nextTrigger)
            } catch (_: SecurityException) {
                scheduleFallback(alarmManager, nextTrigger, pendingIntent)
                return ScheduleResult(scheduled = true, exact = false, triggerAtMillis = nextTrigger)
            }
        }

        scheduleFallback(alarmManager, nextTrigger, pendingIntent)
        return ScheduleResult(scheduled = true, exact = false, triggerAtMillis = nextTrigger)
    }

    private fun scheduleFallback(
        alarmManager: AlarmManager,
        nextTrigger: Long,
        pendingIntent: PendingIntent
    ) {
        alarmManager.set(AlarmManager.RTC_WAKEUP, nextTrigger, pendingIntent)
    }

    fun cancel(setting: TaskReminderSetting) {
        alarmManager?.cancel(alarmIntent(setting))
    }

    fun rescheduleActive(nowMillis: Long = System.currentTimeMillis()) {
        store.readActive().forEach { setting ->
            val nextTrigger = TaskReminderSchedule.nextTriggerAtOrAfter(
                triggerAtMillis = setting.triggerAtMillis,
                repeat = setting.repeat,
                nowMillis = nowMillis,
                zone = ZoneId.systemDefault()
            )
            if (nextTrigger == null) {
                return@forEach
            }
            val nextSetting = if (nextTrigger == setting.triggerAtMillis) {
                setting
            } else {
                setting.copy(triggerAtMillis = nextTrigger)
                    .also(store::save)
            }
            schedule(nextSetting, nowMillis)
        }
    }

    fun canScheduleExactAlarms(): Boolean {
        val manager = alarmManager ?: return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
    }

    fun exactAlarmSettingsIntent(): Intent {
        return Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
            data = Uri.parse("package:${context.packageName}")
        }
    }

    private fun alarmIntent(setting: TaskReminderSetting): PendingIntent {
        val intent = Intent(context, TaskReminderAlarmReceiver::class.java).apply {
            action = ACTION_TASK_REMINDER
            putExtra(EXTRA_USER_ID, setting.userId)
            putExtra(EXTRA_TASK_ID, setting.taskId)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode(setting.userId, setting.taskId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun taskOpenIntent(setting: TaskReminderSetting): PendingIntent {
        val intent = Intent(context, com.rocketflow.companion.MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("taskId", setting.taskId)
            data = NotificationIntents.taskDeepLink(setting.taskId)
        }
        return PendingIntent.getActivity(
            context,
            requestCode(setting.userId, setting.taskId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    companion object {
        const val ACTION_TASK_REMINDER = "com.rocketflow.companion.notifications.TASK_REMINDER"
        const val EXTRA_USER_ID = "userId"
        const val EXTRA_TASK_ID = "taskId"

        fun requestCode(userId: String, taskId: String): Int {
            return "$userId::$taskId".hashCode()
        }
    }
}
