package com.rocketflow.companion.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.rocketflow.companion.planning.PlanningLocalStore

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
        val scheduler = TaskReminderAlarmScheduler(context, store)
        val task = PlanningLocalStore(context).use { localStore ->
            localStore.findTask(userId, taskId)
        }
        if (task == null || task.archived || task.status == "done" || task.status == "cancelled") {
            store.readAll(userId, taskId).forEach(scheduler::cancel)
            store.clear(userId, taskId)
            return
        }

        NotificationRuntime(context).showTaskReminderNotification(
            taskId = setting.taskId,
            title = task.title.ifBlank { setting.taskTitle },
            body = "Open the task in RocketFlow Companion.",
            fullScreenAlarm = true
        )

        if (setting.repeat == TaskReminderRepeat.None) {
            store.clear(setting.userId, setting.taskId, setting.reminderId)
            return
        }

        val nextSetting = TaskReminderSchedule.nextSettingAtOrAfter(
            setting = setting,
            nowMillis = System.currentTimeMillis() + 1L
        ) ?: return
        store.save(nextSetting)
        scheduler.schedule(nextSetting)
    }
}
