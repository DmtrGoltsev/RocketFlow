package com.rocketflow.companion.planning

enum class SyncState {
    Synced,
    PendingCreate,
    PendingUpdate,
    PendingDelete,
    Conflict
}

data class PlanningFolder(
    val id: String,
    val name: String,
    val description: String,
    val displayOrder: Int,
    val archived: Boolean,
    val shared: Boolean,
    val version: Long,
    val createdAt: String,
    val updatedAt: String,
    val syncState: SyncState,
    val lastError: String?
)

data class PlanningGoal(
    val id: String,
    val folderId: String,
    val name: String,
    val description: String,
    val archived: Boolean,
    val shared: Boolean,
    val canCreateTasks: Boolean,
    val version: Long,
    val createdAt: String,
    val updatedAt: String,
    val syncState: SyncState,
    val lastError: String?
)

data class PlanningTask(
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
    val creatorUserId: String?,
    val creatorEmail: String?,
    val creatorName: String?,
    val version: Long,
    val tagIds: List<String>,
    val recurrenceJson: String?,
    val remindersJson: String?,
    val createdAt: String,
    val updatedAt: String,
    val syncState: SyncState,
    val lastError: String?
)

data class TaskTag(
    val id: String,
    val name: String,
    val color: String,
    val syncState: SyncState,
    val lastError: String?
)

data class PlanningSnapshot(
    val folders: List<PlanningFolder>,
    val goals: List<PlanningGoal>,
    val tasks: List<PlanningTask>,
    val sharedFolders: List<PlanningFolder>,
    val sharedGoals: List<PlanningGoal>,
    val sharedTasks: List<PlanningTask>,
    val taskTags: List<TaskTag>,
    val pendingCount: Int,
    val offline: Boolean,
    val lastSyncError: String?
)

data class PlanningLoadResult(
    val session: com.rocketflow.companion.auth.AuthSession,
    val snapshot: PlanningSnapshot
)

data class TaskRescheduleResult(
    val session: com.rocketflow.companion.auth.AuthSession,
    val snapshot: PlanningSnapshot,
    val priorityDecayApplied: Boolean
)

data class FolderDraft(
    val name: String,
    val description: String
)

data class GoalDraft(
    val name: String,
    val description: String
)

data class TaskDraft(
    val title: String,
    val description: String,
    val type: String,
    val priority: Int,
    val status: String,
    val plannedTime: String?,
    val dueTime: String?,
    val tagIds: List<String>? = null,
    val recurrenceJson: String? = null,
    val remindersJson: String? = null
)

data class TaskTagDraft(
    val name: String,
    val color: String
)

fun SyncState.isPending(): Boolean {
    return this == SyncState.PendingCreate ||
        this == SyncState.PendingUpdate ||
        this == SyncState.PendingDelete ||
        this == SyncState.Conflict
}
