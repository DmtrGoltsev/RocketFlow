package com.rocketflow.companion.notifications

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class TaskReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!intent.action.shouldRescheduleReminders()) {
            return
        }

        Log.i(TAG, "Rescheduling local task reminders after ${intent.action}.")
        val store = TaskReminderStore(context)
        TaskReminderAlarmScheduler(context, store).rescheduleActive()
    }

    private fun String?.shouldRescheduleReminders(): Boolean {
        return this == Intent.ACTION_BOOT_COMPLETED ||
            this == Intent.ACTION_MY_PACKAGE_REPLACED ||
            this == Intent.ACTION_TIME_CHANGED ||
            this == Intent.ACTION_TIMEZONE_CHANGED ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                this == AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)
    }

    private companion object {
        const val TAG = "TaskReminderBootReceiver"
    }
}
