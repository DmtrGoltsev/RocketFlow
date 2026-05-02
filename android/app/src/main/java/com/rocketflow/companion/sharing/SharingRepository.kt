package com.rocketflow.companion.sharing

import android.net.Uri
import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.SessionBoundResult
import org.json.JSONArray
import org.json.JSONObject

class SharingRepository(
    private val authRepository: AuthRepository
) {

    suspend fun inviteByEmail(
        session: AuthSession,
        target: ShareTarget,
        email: String
    ): SessionBoundResult<ShareInvitation> {
        val result = authRepository.authorizedPost(
            session,
            "/${target.type.invitePathSegment}/${target.id}/share",
            JSONObject().put("email", email)
        )
        return SessionBoundResult(result.session, result.value.toInvitation())
    }

    suspend fun inviteByUserId(
        session: AuthSession,
        target: ShareTarget,
        userId: String
    ): SessionBoundResult<ShareInvitation> {
        val result = authRepository.authorizedPost(
            session,
            "/${target.type.invitePathSegment}/${target.id}/share",
            JSONObject().put("userId", userId)
        )
        return SessionBoundResult(result.session, result.value.toInvitation())
    }

    suspend fun createLink(
        session: AuthSession,
        target: ShareTarget,
        expiresAt: String? = null
    ): SessionBoundResult<CreatedShareLink> {
        val body = JSONObject()
        if (!expiresAt.isNullOrBlank()) {
            body.put("expiresAt", expiresAt)
        }
        val result = authRepository.authorizedPost(session, linkPath(target), body)
        return SessionBoundResult(result.session, result.value.toCreatedLink())
    }

    suspend fun listLinks(session: AuthSession, target: ShareTarget): SessionBoundResult<List<ShareLink>> {
        val result = authRepository.authorizedGet(session, linkPath(target))
        return SessionBoundResult(result.session, result.value.optJSONArray("items").toLinks())
    }

    suspend fun resolveLink(session: AuthSession, token: String): SessionBoundResult<ResolvedShareLink> {
        val result = authRepository.authorizedGet(session, "/shares/links/${Uri.encode(token)}")
        return SessionBoundResult(result.session, result.value.toResolvedLink())
    }

    suspend fun acceptLink(session: AuthSession, token: String): SessionBoundResult<AcceptedShareLink> {
        val result = authRepository.authorizedPost(session, "/shares/links/${Uri.encode(token)}/accept", JSONObject())
        return SessionBoundResult(result.session, result.value.toAcceptedLink())
    }

    suspend fun revokeLink(session: AuthSession, linkId: String): SessionBoundResult<String> {
        val result = authRepository.authorizedPost(session, "/shares/links/$linkId/revoke", JSONObject())
        return SessionBoundResult(result.session, result.value.optString("status", "revoked"))
    }

    private fun linkPath(target: ShareTarget): String {
        return "/${target.type.apiSegment}/${target.id}/share-links"
    }

    private fun JSONObject.toInvitation(): ShareInvitation {
        return ShareInvitation(
            id = getString("id"),
            targetType = optString("targetType"),
            targetId = optString("targetId"),
            targetEmail = nullableText("targetEmail"),
            targetUserId = nullableText("targetUserId"),
            status = optString("status"),
            createdAt = nullableText("createdAt"),
            expiresAt = nullableText("expiresAt")
        )
    }

    private fun JSONObject.toCreatedLink(): CreatedShareLink {
        return CreatedShareLink(
            id = getString("id"),
            targetType = optString("targetType"),
            targetId = optString("targetId"),
            token = optString("token"),
            status = optString("status"),
            createdAt = nullableText("createdAt"),
            expiresAt = nullableText("expiresAt")
        )
    }

    private fun JSONObject.toLink(): ShareLink {
        return ShareLink(
            id = getString("id"),
            targetType = optString("targetType"),
            targetId = optString("targetId"),
            status = optString("status"),
            createdAt = nullableText("createdAt"),
            expiresAt = nullableText("expiresAt"),
            revokedAt = nullableText("revokedAt")
        )
    }

    private fun JSONObject.toResolvedLink(): ResolvedShareLink {
        return ResolvedShareLink(
            id = getString("id"),
            targetType = optString("targetType"),
            targetId = optString("targetId"),
            status = optString("status"),
            expiresAt = nullableText("expiresAt")
        )
    }

    private fun JSONObject.toAcceptedLink(): AcceptedShareLink {
        return AcceptedShareLink(
            shareId = getString("shareId"),
            targetType = optString("targetType"),
            targetId = optString("targetId"),
            status = optString("status")
        )
    }

    private fun JSONArray?.toLinks(): List<ShareLink> {
        if (this == null) return emptyList()
        return List(length()) { index -> getJSONObject(index).toLink() }
    }

    private fun JSONObject.nullableText(key: String): String? {
        return if (has(key) && !isNull(key)) optString(key).ifBlank { null } else null
    }
}
