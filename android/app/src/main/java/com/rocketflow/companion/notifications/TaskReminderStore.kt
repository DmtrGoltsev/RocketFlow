package com.rocketflow.companion.notifications

import android.content.Context

class TaskReminderStore(context: Context) {

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun read(userId: String, taskId: String): TaskReminderSetting? {
        return TaskReminderJson.decode(prefs.getString(key(userId, taskId), null))
    }

    fun save(setting: TaskReminderSetting) {
        prefs.edit()
            .putString(key(setting.userId, setting.taskId), TaskReminderJson.encode(setting))
            .apply()
    }

    fun clear(userId: String, taskId: String) {
        prefs.edit().remove(key(userId, taskId)).apply()
    }

    fun readActive(): List<TaskReminderSetting> {
        return prefs.all.values
            .mapNotNull { value -> TaskReminderJson.decode(value as? String) }
            .filter { it.enabled }
    }

    private fun key(userId: String, taskId: String): String {
        return "$KEY_PREFIX$userId::$taskId"
    }

    private companion object {
        const val PREFS_NAME = "rocketflow_local_task_reminders"
        const val KEY_PREFIX = "task_reminder::"
    }
}
