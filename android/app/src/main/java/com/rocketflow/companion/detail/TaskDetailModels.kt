package com.rocketflow.companion.detail

data class TaskTag(
    val id: String,
    val name: String,
    val color: String
)

data class TaskRecurrence(
    val mode: String,
    val interval: Int?,
    val daysOfWeek: List<String>,
    val startAt: String?,
    val endAt: String?,
    val active: Boolean?
)

data class TaskReminder(
    val id: String,
    val mode: String,
    val offsetMinutes: Int,
    val active: Boolean
)

data class TaskDetail(
    val id: String,
    val goalId: String,
    val title: String,
    val description: String,
    val type: String,
    val priority: Int,
    val status: String,
    val plannedTime: String?,
    val dueTime: String?,
    val archived: Boolean,
    val shared: Boolean,
    val tags: List<TaskTag>,
    val recurrence: TaskRecurrence?,
    val reminders: List<TaskReminder>
)
