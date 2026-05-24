package com.rocketflow.companion.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import java.time.ZoneId

class TaskReminderAlarmScheduler(
    private val context: Context,
    private val store: TaskReminderStore
) {
    enum class DeliveryMode {
        AlarmClockExact,
        ExactAllowWhileIdle,
        WhileIdleFallback,
        Unavailable,
        Expired
    }

    data class ScheduleResult(
        val scheduled: Boolean,
        val exact: Boolean,
        val triggerAtMillis: Long?,
        val mode: DeliveryMode = DeliveryMode.Unavailable,
        val status: String = mode.name
    )

    private val alarmManager: AlarmManager? =
        context.getSystemService(AlarmManager::class.java)

    fun schedule(setting: TaskReminderSetting, nowMillis: Long = System.currentTimeMillis()): ScheduleResult {
        val alarmManager = alarmManager ?: return ScheduleResult(
            scheduled = false,
            exact = false,
            triggerAtMillis = null,
            mode = DeliveryMode.Unavailable,
            status = "AlarmManager unavailable"
        )
        val nextSetting = TaskReminderSchedule.nextSettingAtOrAfter(
            setting = setting,
            nowMillis = nowMillis,
            zone = ZoneId.systemDefault()
        ) ?: return ScheduleResult(
            scheduled = false,
            exact = canScheduleExactAlarms(),
            triggerAtMillis = null,
            mode = DeliveryMode.Expired,
            status = "Reminder is expired and non-recurring"
        )
        val nextTrigger = nextSetting.triggerAtMillis

        val pendingIntent = alarmIntent(nextSetting)
        if (canScheduleExactAlarms()) {
            scheduleExact(alarmManager, nextTrigger, nextSetting, pendingIntent)?.let { mode ->
                return ScheduleResult(
                    scheduled = true,
                    exact = true,
                    triggerAtMillis = nextTrigger,
                    mode = mode,
                    status = "Scheduled exact local alarm"
                )
            }
        }

        val mode = scheduleFallback(alarmManager, nextTrigger, pendingIntent)
            ?: return ScheduleResult(
                scheduled = false,
                exact = false,
                triggerAtMillis = nextTrigger,
                mode = DeliveryMode.Unavailable,
                status = "Unable to schedule local reminder alarm"
            )
        return ScheduleResult(
            scheduled = true,
            exact = false,
            triggerAtMillis = nextTrigger,
            mode = mode,
            status = "Scheduled inexact while-idle fallback; Android may defer delivery"
        )
    }

    private fun scheduleExact(
        alarmManager: AlarmManager,
        nextTrigger: Long,
        setting: TaskReminderSetting,
        pendingIntent: PendingIntent
    ): DeliveryMode? {
        return try {
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(nextTrigger, taskOpenIntent(setting)),
                pendingIntent
            )
            DeliveryMode.AlarmClockExact
        } catch (alarmClockFailure: SecurityException) {
            Log.w(TAG, "Exact alarm-clock scheduling denied; trying exact while-idle.", alarmClockFailure)
            try {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextTrigger, pendingIntent)
                DeliveryMode.ExactAllowWhileIdle
            } catch (exactFailure: SecurityException) {
                Log.w(TAG, "Exact while-idle scheduling denied; falling back to inexact while-idle.", exactFailure)
                null
            }
        }
    }

    private fun scheduleFallback(
        alarmManager: AlarmManager,
        nextTrigger: Long,
        pendingIntent: PendingIntent
    ): DeliveryMode? {
        return try {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextTrigger, pendingIntent)
            DeliveryMode.WhileIdleFallback
        } catch (failure: RuntimeException) {
            Log.e(TAG, "Unable to schedule fallback reminder alarm.", failure)
            null
        }
    }

    fun cancel(setting: TaskReminderSetting) {
        val manager = alarmManager ?: return
        alarmIntentsForCancel(setting).forEach(manager::cancel)
    }

    fun rescheduleActive(nowMillis: Long = System.currentTimeMillis()) {
        store.readActive().forEach { setting ->
            val nextSetting = TaskReminderSchedule.nextSettingAtOrAfter(
                setting = setting,
                nowMillis = nowMillis,
                zone = ZoneId.systemDefault()
            )
            if (nextSetting == null) {
                if (
                    setting.repeat == TaskReminderRepeat.None &&
                    setting.triggerAtMillis + DUE_REMINDER_RECEIVER_GRACE_MILLIS >= nowMillis
                ) {
                    return@forEach
                }
                store.clear(setting.userId, setting.taskId, setting.reminderId)
                return@forEach
            }
            if (nextSetting.triggerAtMillis != setting.triggerAtMillis ||
                nextSetting.anchorAtMillis != setting.anchorAtMillis
            ) {
                store.save(nextSetting)
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
        return alarmIntent(setting, includeIdentityData = true)
    }

    private fun alarmIntent(setting: TaskReminderSetting, includeIdentityData: Boolean): PendingIntent {
        val intent = Intent(context, TaskReminderAlarmReceiver::class.java).apply {
            action = ACTION_TASK_REMINDER
            if (includeIdentityData) {
                data = reminderIdentityUri(setting)
            }
            putExtra(EXTRA_USER_ID, setting.userId)
            putExtra(EXTRA_TASK_ID, setting.taskId)
            putExtra(EXTRA_REMINDER_ID, setting.reminderId)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode(setting.userId, setting.taskId, setting.reminderId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun alarmIntentsForCancel(setting: TaskReminderSetting): List<PendingIntent> {
        return listOf(
            alarmIntent(setting, includeIdentityData = true),
            alarmIntent(setting, includeIdentityData = false)
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
            requestCode(setting.userId, setting.taskId, setting.reminderId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun reminderIdentityUri(setting: TaskReminderSetting): Uri {
        return Uri.Builder()
            .scheme("rocketflow")
            .authority("local-reminder")
            .appendPath(setting.userId)
            .appendPath(setting.taskId)
            .appendPath(setting.reminderId)
            .build()
    }

    companion object {
        private const val TAG = "TaskReminderScheduler"
        private const val DUE_REMINDER_RECEIVER_GRACE_MILLIS = 5 * 60 * 1000L
        const val ACTION_TASK_REMINDER = "com.rocketflow.companion.notifications.TASK_REMINDER"
        const val EXTRA_USER_ID = "userId"
        const val EXTRA_TASK_ID = "taskId"
        const val EXTRA_REMINDER_ID = "reminderId"

        fun requestCode(userId: String, taskId: String, reminderId: String): Int {
            return "$userId::$taskId::$reminderId".hashCode()
        }
    }
}
