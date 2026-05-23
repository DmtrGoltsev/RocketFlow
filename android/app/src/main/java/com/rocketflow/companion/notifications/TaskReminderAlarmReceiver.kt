package com.rocketflow.companion.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class TaskReminderAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TaskReminderAlarmScheduler.ACTION_TASK_REMINDER) {
            return
        }

        val userId = intent.getStringExtra(TaskReminderAlarmScheduler.EXTRA_USER_ID)?.trim().orEmpty()
        val taskId = intent.getStringExtra(TaskReminderAlarmScheduler.EXTRA_TASK_ID)?.trim().orEmpty()
        val reminderId = intent.getStringExtra(TaskReminderAlarmScheduler.EXTRA_REMINDER_ID)?.trim().orEmpty()
        if (userId.isBlank() || taskId.isBlank()) {
            return
        }

        val store = TaskReminderStore(context)
        val setting = store.readAll(userId, taskId)
            .firstOrNull { it.enabled && (reminderId.isBlank() || it.reminderId == reminderId) }
            ?: return
        NotificationRuntime(context).showTaskReminderNotification(
            taskId = setting.taskId,
            title = setting.taskTitle,
            body = "Open the task in RocketFlow Companion."
        )

        if (setting.repeat == TaskReminderRepeat.None) {
            store.clear(setting.userId, setting.taskId, setting.reminderId)
            return
        }

        val nextTrigger = TaskReminderSchedule.nextTriggerAtOrAfter(
            triggerAtMillis = setting.triggerAtMillis,
            repeat = setting.repeat,
            nowMillis = System.currentTimeMillis() + 1L
        ) ?: return
        val nextSetting = setting.copy(triggerAtMillis = nextTrigger)
        store.save(nextSetting)
        TaskReminderAlarmScheduler(context, store).schedule(nextSetting)
    }
}
