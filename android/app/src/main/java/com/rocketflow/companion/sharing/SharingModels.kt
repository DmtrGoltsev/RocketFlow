package com.rocketflow.companion.sharing

enum class ShareTargetType(
    val apiSegment: String,
    val invitePathSegment: String
) {
    Folder("folders", "folders"),
    Goal("goals", "goals"),
    Task("tasks", "tasks")
}

data class ShareTarget(
    val type: ShareTargetType,
    val id: String,
    val title: String
)

data class ShareInvitation(
    val id: String,
    val targetType: String,
    val targetId: String,
    val targetEmail: String?,
    val targetUserId: String?,
    val fullAccess: Boolean,
    val status: String,
    val createdAt: String?,
    val expiresAt: String?
)

data class ShareLink(
    val id: String,
    val targetType: String,
    val targetId: String,
    val fullAccess: Boolean,
    val status: String,
    val createdAt: String?,
    val expiresAt: String?,
    val revokedAt: String?
)

data class CreatedShareLink(
    val id: String,
    val targetType: String,
    val targetId: String,
    val token: String,
    val fullAccess: Boolean,
    val status: String,
    val createdAt: String?,
    val expiresAt: String?
)

data class ResolvedShareLink(
    val id: String,
    val targetType: String,
    val targetId: String,
    val fullAccess: Boolean,
    val status: String,
    val expiresAt: String?
)

data class AcceptedShareLink(
    val shareId: String,
    val targetType: String,
    val targetId: String,
    val fullAccess: Boolean,
    val status: String
)
