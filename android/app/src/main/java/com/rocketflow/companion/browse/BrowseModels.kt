package com.rocketflow.companion.browse

data class FolderSummary(
    val id: String,
    val name: String,
    val description: String,
    val archived: Boolean
)

data class GoalSummary(
    val id: String,
    val folderId: String,
    val name: String,
    val description: String,
    val archived: Boolean,
    val shared: Boolean
)

data class TaskSummary(
    val id: String,
    val goalId: String,
    val title: String,
    val description: String,
    val type: String,
    val priority: Int,
    val status: String,
    val plannedTime: String?,
    val dueTime: String?,
    val shared: Boolean
)

data class SharedResources(
    val goals: List<GoalSummary>,
    val tasks: List<TaskSummary>
)
