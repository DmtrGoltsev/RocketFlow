package com.rocketflow.companion.notifications

import android.content.Context

class TaskReminderStore(context: Context) {

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun read(userId: String, taskId: String): TaskReminderSetting? {
        return readAll(userId, taskId).firstOrNull()
    }

    fun readAll(userId: String, taskId: String): List<TaskReminderSetting> {
        return TaskReminderJson.decodeList(prefs.getString(key(userId, taskId), null))
    }

    fun save(setting: TaskReminderSetting) {
        val settings = readAll(setting.userId, setting.taskId)
            .filterNot { it.reminderId == setting.reminderId } + setting
        saveAll(setting.userId, setting.taskId, settings)
    }

    fun saveAll(userId: String, taskId: String, settings: List<TaskReminderSetting>) {
        val active = settings.filter { it.enabled }
        if (active.isEmpty()) {
            clear(userId, taskId)
            return
        }
        prefs.edit()
            .putString(key(userId, taskId), TaskReminderJson.encodeList(active))
            .apply()
    }

    fun clear(userId: String, taskId: String, reminderId: String) {
        val remaining = readAll(userId, taskId).filterNot { it.reminderId == reminderId }
        saveAll(userId, taskId, remaining)
    }

    fun clear(userId: String, taskId: String) {
        prefs.edit().remove(key(userId, taskId)).apply()
    }

    fun readActive(): List<TaskReminderSetting> {
        return prefs.all.values
            .flatMap { value -> TaskReminderJson.decodeList(value as? String) }
            .filter { it.enabled }
    }

    fun readDefault(userId: String): DefaultTaskReminderSetting? {
        return DefaultTaskReminderJson.decode(prefs.getString(defaultKey(userId), null))
            ?.takeIf { it.enabled }
    }

    fun saveDefault(setting: DefaultTaskReminderSetting) {
        if (!setting.enabled) {
            clearDefault(setting.userId)
            return
        }
        prefs.edit()
            .putString(defaultKey(setting.userId), DefaultTaskReminderJson.encode(setting))
            .apply()
    }

    fun clearDefault(userId: String) {
        prefs.edit().remove(defaultKey(userId)).apply()
    }

    private fun key(userId: String, taskId: String): String {
        return "$KEY_PREFIX$userId::$taskId"
    }

    private fun defaultKey(userId: String): String {
        return "$DEFAULT_KEY_PREFIX$userId"
    }

    private companion object {
        const val PREFS_NAME = "rocketflow_local_task_reminders"
        const val KEY_PREFIX = "task_reminder::"
        const val DEFAULT_KEY_PREFIX = "default_task_reminder::"
    }
}
