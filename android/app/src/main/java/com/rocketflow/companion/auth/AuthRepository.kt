package com.rocketflow.companion.auth

import com.rocketflow.companion.network.ApiException
import com.rocketflow.companion.network.HttpJsonClient
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

interface AuthSessionStorage {
    fun readSession(): AuthSession?
    fun writeSession(session: AuthSession)
    fun clear()
}

class AuthRepository(
    private val httpJsonClient: HttpJsonClient,
    private val sessionStore: AuthSessionStorage
) {
    constructor(
        httpJsonClient: HttpJsonClient,
        sessionStore: SessionStore
    ) : this(httpJsonClient, SessionStoreAuthSessionStorage(sessionStore))

    private var onSessionClearedListener: (() -> Unit)? = null

    fun setOnSessionClearedListener(listener: (() -> Unit)?) {
        onSessionClearedListener = listener
    }

    fun readStoredSession(): AuthSession? = sessionStore.readSession()

    suspend fun bootstrapSession(): AuthSession? {
        val stored = sessionStore.readSession() ?: return null
        return try {
            val currentUser = fetchCurrentUser(stored.tokens.accessToken)
            writeUserIfRefreshTokenCurrentOrReturnStored(stored.tokens.refreshToken, currentUser)
        } catch (error: ApiException) {
            if (error.status != 401) {
                return stored
            }

            try {
                refreshStoredSession(stored, notifyListener = true)
            } catch (refreshError: ApiException) {
                if (refreshError.status == 401) {
                    return null
                }
                return stored
            }
        } catch (_: Exception) {
            stored
        }
    }

    suspend fun login(email: String, password: String): AuthSession {
        val response = httpJsonClient.post(
            path = "/auth/login",
            body = JSONObject()
                .put("email", email)
                .put("password", password)
        )

        val session = parseAuthSession(response)
        writeSession(session)
        return session
    }

    suspend fun register(
        email: String,
        password: String,
        displayName: String,
        timezone: String,
        language: String
    ): AuthSession {
        val response = httpJsonClient.post(
            path = "/auth/register",
            body = JSONObject()
                .put("email", email)
                .put("password", password)
                .put("displayName", displayName)
                .put("timezone", timezone)
                .put("language", language)
        )

        val session = parseAuthSession(response)
        writeSession(session)
        return session
    }

    suspend fun logout() {
        val session = sessionStore.readSession()

        if (session != null) {
            try {
                httpJsonClient.post(
                    path = "/auth/logout",
                    body = JSONObject().put("refreshToken", session.tokens.refreshToken)
                )
            } catch (_: Exception) {
                // Local logout should still succeed if the network call fails.
            }
        }

        if (session != null) {
            clearStoredSessionIfRefreshTokenCurrent(
                failedRefreshToken = session.tokens.refreshToken,
                notifyListener = false
            )
        }
    }

    suspend fun refreshCurrentUser(session: AuthSession): AuthSession {
        return try {
            val user = fetchCurrentUser(session.tokens.accessToken)
            writeUserIfRefreshTokenCurrent(session.tokens.refreshToken, user)
        } catch (error: ApiException) {
            if (error.status != 401) {
                throw error
            }

            try {
                refreshStoredSession(session, notifyListener = true)
            } catch (refreshError: ApiException) {
                throw refreshError
            }
        }
    }

    suspend fun authorizedGet(session: AuthSession, path: String): SessionBoundResult<JSONObject> {
        return try {
            SessionBoundResult(
                session = session,
                value = httpJsonClient.get(path = path, accessToken = session.tokens.accessToken)
            )
        } catch (error: ApiException) {
            if (error.status != 401) {
                throw error
            }

            try {
                val refreshed = refreshStoredSession(session, notifyListener = true)
                SessionBoundResult(
                    session = refreshed,
                    value = httpJsonClient.get(path = path, accessToken = refreshed.tokens.accessToken)
                )
            } catch (refreshError: ApiException) {
                throw refreshError
            }
        }
    }

    suspend fun authorizedPost(
        session: AuthSession,
        path: String,
        body: JSONObject
    ): SessionBoundResult<JSONObject> {
        return try {
            SessionBoundResult(
                session = session,
                value = httpJsonClient.post(path = path, body = body, accessToken = session.tokens.accessToken)
            )
        } catch (error: ApiException) {
            if (error.status != 401) {
                throw error
            }

            try {
                val refreshed = refreshStoredSession(session, notifyListener = true)
                SessionBoundResult(
                    session = refreshed,
                    value = httpJsonClient.post(path = path, body = body, accessToken = refreshed.tokens.accessToken)
                )
            } catch (refreshError: ApiException) {
                throw refreshError
            }
        }
    }

    suspend fun authorizedPatch(
        session: AuthSession,
        path: String,
        body: JSONObject
    ): SessionBoundResult<JSONObject> {
        return try {
            SessionBoundResult(
                session = session,
                value = httpJsonClient.patch(path = path, body = body, accessToken = session.tokens.accessToken)
            )
        } catch (error: ApiException) {
            if (error.status != 401) {
                throw error
            }

            try {
                val refreshed = refreshStoredSession(session, notifyListener = true)
                SessionBoundResult(
                    session = refreshed,
                    value = httpJsonClient.patch(path = path, body = body, accessToken = refreshed.tokens.accessToken)
                )
            } catch (refreshError: ApiException) {
                throw refreshError
            }
        }
    }

    suspend fun authorizedPut(
        session: AuthSession,
        path: String,
        body: JSONObject
    ): SessionBoundResult<JSONObject> {
        return try {
            SessionBoundResult(
                session = session,
                value = httpJsonClient.put(path = path, body = body, accessToken = session.tokens.accessToken)
            )
        } catch (error: ApiException) {
            if (error.status != 401) {
                throw error
            }

            try {
                val refreshed = refreshStoredSession(session, notifyListener = true)
                SessionBoundResult(
                    session = refreshed,
                    value = httpJsonClient.put(path = path, body = body, accessToken = refreshed.tokens.accessToken)
                )
            } catch (refreshError: ApiException) {
                throw refreshError
            }
        }
    }

    suspend fun authorizedDelete(session: AuthSession, path: String): AuthSession {
        return try {
            httpJsonClient.delete(path = path, accessToken = session.tokens.accessToken)
            session
        } catch (error: ApiException) {
            if (error.status != 401) {
                throw error
            }

            try {
                val refreshed = refreshStoredSession(session, notifyListener = true)
                httpJsonClient.delete(path = path, accessToken = refreshed.tokens.accessToken)
                refreshed
            } catch (refreshError: ApiException) {
                throw refreshError
            }
        }
    }

    private suspend fun refreshStoredSession(
        session: AuthSession,
        notifyListener: Boolean
    ): AuthSession = refreshMutex.withLock {
        val storedBeforeRefresh = readStoredSessionOrMissing()

        if (storedBeforeRefresh.tokens.refreshToken != session.tokens.refreshToken) {
            return@withLock storedBeforeRefresh
        }

        val tokens = try {
            refreshTokens(storedBeforeRefresh.tokens.refreshToken)
        } catch (error: ApiException) {
            if (error.status == 401) {
                val newerSession = newerSessionOrClearIfRefreshTokenCurrent(
                    failedRefreshToken = storedBeforeRefresh.tokens.refreshToken,
                    notifyListener = notifyListener
                )
                if (newerSession != null) {
                    return@withLock newerSession
                }
            }
            throw error
        }

        val provisional = writeRotatedTokensIfRefreshTokenCurrent(
            expectedRefreshToken = storedBeforeRefresh.tokens.refreshToken,
            tokens = tokens
        )
        if (provisional.tokens.refreshToken != tokens.refreshToken) {
            return@withLock provisional
        }

        try {
            val user = fetchCurrentUser(tokens.accessToken)
            writeUserIfRefreshTokenCurrent(tokens.refreshToken, user)
        } catch (error: ApiException) {
            if (error.status == 401) {
                val newerSession = newerSessionOrClearIfRefreshTokenCurrent(
                    failedRefreshToken = tokens.refreshToken,
                    notifyListener = notifyListener
                )
                if (newerSession != null) {
                    return@withLock newerSession
                }
            }
            throw error
        }
    }

    private fun readStoredSessionOrMissing(): AuthSession {
        return sessionStore.readSession()
            ?: throw ApiException(
                status = 401,
                code = "session_missing",
                message = "Stored session is missing.",
                fieldErrors = emptyMap(),
                traceId = null
            )
    }

    private suspend fun writeSession(session: AuthSession) {
        sessionMutationMutex.withLock {
            sessionStore.writeSession(session)
        }
    }

    private suspend fun writeUserIfRefreshTokenCurrent(
        expectedRefreshToken: String,
        user: CurrentUser
    ): AuthSession {
        return sessionMutationMutex.withLock {
            val stored = readStoredSessionOrMissing()
            if (stored.tokens.refreshToken != expectedRefreshToken) {
                return@withLock stored
            }

            val refreshed = stored.copy(user = user)
            sessionStore.writeSession(refreshed)
            refreshed
        }
    }

    private suspend fun writeUserIfRefreshTokenCurrentOrReturnStored(
        expectedRefreshToken: String,
        user: CurrentUser
    ): AuthSession? {
        return sessionMutationMutex.withLock {
            val stored = sessionStore.readSession() ?: return@withLock null
            if (stored.tokens.refreshToken != expectedRefreshToken) {
                return@withLock stored
            }

            val refreshed = stored.copy(user = user)
            sessionStore.writeSession(refreshed)
            refreshed
        }
    }

    private suspend fun writeRotatedTokensIfRefreshTokenCurrent(
        expectedRefreshToken: String,
        tokens: AuthTokens
    ): AuthSession {
        return sessionMutationMutex.withLock {
            val stored = readStoredSessionOrMissing()
            if (stored.tokens.refreshToken != expectedRefreshToken) {
                return@withLock stored
            }

            val provisional = AuthSession(stored.user, tokens)
            sessionStore.writeSession(provisional)
            provisional
        }
    }

    private suspend fun clearStoredSessionIfRefreshTokenCurrent(
        failedRefreshToken: String,
        notifyListener: Boolean
    ) {
        val cleared = sessionMutationMutex.withLock {
            val stored = sessionStore.readSession()
            if (stored?.tokens?.refreshToken == failedRefreshToken) {
                sessionStore.clear()
                true
            } else {
                false
            }
        }

        if (cleared && notifyListener) {
            onSessionClearedListener?.invoke()
        }
    }

    private suspend fun newerSessionOrClearIfRefreshTokenCurrent(
        failedRefreshToken: String,
        notifyListener: Boolean
    ): AuthSession? {
        var shouldNotify = false
        val newerSession = sessionMutationMutex.withLock {
            val stored = sessionStore.readSession()
            when {
                stored == null -> null
                stored.tokens.refreshToken != failedRefreshToken -> stored
                else -> {
                    sessionStore.clear()
                    shouldNotify = notifyListener
                    null
                }
            }
        }

        if (shouldNotify) {
            onSessionClearedListener?.invoke()
        }
        return newerSession
    }

    private suspend fun refreshTokens(refreshToken: String): AuthTokens {
        val response = httpJsonClient.post(
            path = "/auth/refresh",
            body = JSONObject().put("refreshToken", refreshToken)
        )

        return parseTokens(response.getJSONObject("tokens"))
    }

    private suspend fun fetchCurrentUser(accessToken: String): CurrentUser {
        val response = httpJsonClient.get(path = "/me", accessToken = accessToken)
        return parseCurrentUser(response)
    }

    private fun parseAuthSession(response: JSONObject): AuthSession {
        return AuthSession(
            user = parseCurrentUser(response.getJSONObject("user")),
            tokens = parseTokens(response.getJSONObject("tokens"))
        )
    }

    private fun parseCurrentUser(payload: JSONObject): CurrentUser {
        return CurrentUser(
            id = payload.getString("id"),
            email = payload.getString("email"),
            displayName = payload.getString("displayName"),
            timezone = payload.getString("timezone"),
            language = payload.optString("language", "ru")
        )
    }

    private fun parseTokens(payload: JSONObject): AuthTokens {
        return AuthTokens(
            accessToken = payload.getString("accessToken"),
            refreshToken = payload.getString("refreshToken"),
            expiresAt = payload.getString("expiresAt")
        )
    }

    companion object {
        private val refreshMutex = Mutex()
        private val sessionMutationMutex = Mutex()
    }
}

private class SessionStoreAuthSessionStorage(
    private val sessionStore: SessionStore
) : AuthSessionStorage {
    override fun readSession(): AuthSession? = sessionStore.readSession()

    override fun writeSession(session: AuthSession) {
        sessionStore.writeSession(session)
    }

    override fun clear() {
        sessionStore.clear()
    }
}
