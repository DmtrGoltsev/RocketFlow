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
    val parentFolderId: String?,
    val name: String,
    val description: String,
    val displayOrder: Int,
    val archived: Boolean,
    val shared: Boolean,
    val fullAccess: Boolean,
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
    val status: String,
    val archived: Boolean,
    val shared: Boolean,
    val canCreateTasks: Boolean,
    val fullAccess: Boolean,
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
    val fullAccess: Boolean,
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

data class PlanningIdea(
    val id: String,
    val folderId: String,
    val title: String,
    val body: String,
    val status: String,
    val displayOrder: Int,
    val archived: Boolean,
    val shared: Boolean,
    val fullAccess: Boolean,
    val allowAuthorNoteEdits: Boolean,
    val version: Long,
    val createdAt: String,
    val updatedAt: String,
    val syncState: SyncState,
    val lastError: String?
)

data class IdeaNote(
    val id: String,
    val ideaId: String,
    val eventType: String,
    val body: String,
    val metadataJson: String,
    val authorUserId: String?,
    val authorEmail: String?,
    val authorName: String?,
    val version: Long,
    val createdAt: String,
    val updatedAt: String
)

data class PlanningNote(
    val id: String,
    val folderId: String,
    val authorUserId: String?,
    val authorEmail: String?,
    val authorName: String?,
    val title: String,
    val body: String,
    val displayOrder: Int,
    val archived: Boolean,
    val shared: Boolean,
    val fullAccess: Boolean,
    val version: Long,
    val createdAt: String,
    val updatedAt: String,
    val syncState: SyncState,
    val lastError: String?
)

data class EntityRef(
    val type: String?,
    val id: String?,
    val title: String?,
    val subtitle: String?,
    val status: String? = null,
    val path: String? = null,
    val archived: Boolean? = null,
    val accessible: Boolean = true,
    val redacted: Boolean = false
)

data class EntityLink(
    val id: String,
    val sourceType: String,
    val sourceId: String,
    val targetType: String,
    val targetId: String,
    val relationType: String,
    val source: EntityRef?,
    val target: EntityRef?,
    val createdByUserId: String?,
    val archived: Boolean,
    val version: Long,
    val createdAt: String,
    val updatedAt: String,
    val syncState: SyncState = SyncState.Synced,
    val lastError: String? = null
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
    val ideas: List<PlanningIdea>,
    val ideaNotes: List<IdeaNote>,
    val notes: List<PlanningNote>,
    val entityLinks: List<EntityLink>,
    val sharedFolders: List<PlanningFolder>,
    val sharedGoals: List<PlanningGoal>,
    val sharedTasks: List<PlanningTask>,
    val sharedIdeas: List<PlanningIdea>,
    val sharedIdeaNotes: List<IdeaNote>,
    val sharedNotes: List<PlanningNote>,
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
    val description: String,
    val parentFolderId: String? = null
)

data class GoalDraft(
    val name: String,
    val description: String,
    val status: String = "todo"
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

data class IdeaDraft(
    val title: String,
    val body: String,
    val status: String = "active",
    val allowAuthorNoteEdits: Boolean = false
)

data class IdeaNoteDraft(
    val body: String,
    val eventType: String = "note",
    val metadataJson: String = "{}"
)

data class NoteDraft(
    val title: String,
    val body: String
)

data class EntityLinkDraft(
    val sourceType: String,
    val sourceId: String,
    val targetType: String,
    val targetId: String,
    val relationType: String = "related"
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
