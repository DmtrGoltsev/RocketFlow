package com.rocketflow.companion.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class TaskReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) {
            return
        }

        val store = TaskReminderStore(context)
        TaskReminderAlarmScheduler(context, store).rescheduleActive()
    }
}
