package com.rocketflow.companion.auth

import com.rocketflow.companion.network.ApiException
import com.rocketflow.companion.network.HttpJsonClient
import org.json.JSONObject

class AuthRepository(
    private val httpJsonClient: HttpJsonClient,
    private val sessionStore: SessionStore
) {
    private var onSessionClearedListener: (() -> Unit)? = null

    fun setOnSessionClearedListener(listener: (() -> Unit)?) {
        onSessionClearedListener = listener
    }

    fun readStoredSession(): AuthSession? = sessionStore.readSession()

    suspend fun bootstrapSession(): AuthSession? {
        val stored = sessionStore.readSession() ?: return null
        return try {
            val currentUser = fetchCurrentUser(stored.tokens.accessToken)
            val restored = stored.copy(user = currentUser)
            sessionStore.writeSession(restored)
            restored
        } catch (error: ApiException) {
            if (error.status != 401) {
                return stored
            }

            try {
                val refreshedTokens = refreshTokens(stored.tokens.refreshToken)
                val currentUser = fetchCurrentUser(refreshedTokens.accessToken)
                val restored = AuthSession(currentUser, refreshedTokens)
                sessionStore.writeSession(restored)
                restored
            } catch (refreshError: ApiException) {
                clearStoredSession(notifyListener = refreshError.status == 401)
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
        sessionStore.writeSession(session)
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
        sessionStore.writeSession(session)
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

        clearStoredSession(notifyListener = false)
    }

    suspend fun refreshCurrentUser(session: AuthSession): AuthSession {
        return try {
            val user = fetchCurrentUser(session.tokens.accessToken)
            val refreshed = session.copy(user = user)
            sessionStore.writeSession(refreshed)
            refreshed
        } catch (error: ApiException) {
            if (error.status != 401) {
                throw error
            }

            try {
                val tokens = refreshTokens(session.tokens.refreshToken)
                val user = fetchCurrentUser(tokens.accessToken)
                val refreshed = AuthSession(user, tokens)
                sessionStore.writeSession(refreshed)
                refreshed
            } catch (refreshError: ApiException) {
                if (refreshError.status == 401) {
                    clearStoredSession(notifyListener = true)
                }
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
                val tokens = refreshTokens(session.tokens.refreshToken)
                val user = fetchCurrentUser(tokens.accessToken)
                val refreshed = AuthSession(user, tokens)
                sessionStore.writeSession(refreshed)
                SessionBoundResult(
                    session = refreshed,
                    value = httpJsonClient.get(path = path, accessToken = refreshed.tokens.accessToken)
                )
            } catch (refreshError: ApiException) {
                if (refreshError.status == 401) {
                    clearStoredSession(notifyListener = true)
                }
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
                val tokens = refreshTokens(session.tokens.refreshToken)
                val user = fetchCurrentUser(tokens.accessToken)
                val refreshed = AuthSession(user, tokens)
                sessionStore.writeSession(refreshed)
                SessionBoundResult(
                    session = refreshed,
                    value = httpJsonClient.post(path = path, body = body, accessToken = refreshed.tokens.accessToken)
                )
            } catch (refreshError: ApiException) {
                if (refreshError.status == 401) {
                    clearStoredSession(notifyListener = true)
                }
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
                val tokens = refreshTokens(session.tokens.refreshToken)
                val user = fetchCurrentUser(tokens.accessToken)
                val refreshed = AuthSession(user, tokens)
                sessionStore.writeSession(refreshed)
                SessionBoundResult(
                    session = refreshed,
                    value = httpJsonClient.patch(path = path, body = body, accessToken = refreshed.tokens.accessToken)
                )
            } catch (refreshError: ApiException) {
                if (refreshError.status == 401) {
                    clearStoredSession(notifyListener = true)
                }
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
                val tokens = refreshTokens(session.tokens.refreshToken)
                val user = fetchCurrentUser(tokens.accessToken)
                val refreshed = AuthSession(user, tokens)
                sessionStore.writeSession(refreshed)
                SessionBoundResult(
                    session = refreshed,
                    value = httpJsonClient.put(path = path, body = body, accessToken = refreshed.tokens.accessToken)
                )
            } catch (refreshError: ApiException) {
                if (refreshError.status == 401) {
                    clearStoredSession(notifyListener = true)
                }
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
                val tokens = refreshTokens(session.tokens.refreshToken)
                val user = fetchCurrentUser(tokens.accessToken)
                val refreshed = AuthSession(user, tokens)
                sessionStore.writeSession(refreshed)
                httpJsonClient.delete(path = path, accessToken = refreshed.tokens.accessToken)
                refreshed
            } catch (refreshError: ApiException) {
                if (refreshError.status == 401) {
                    clearStoredSession(notifyListener = true)
                }
                throw refreshError
            }
        }
    }

    private fun clearStoredSession(notifyListener: Boolean) {
        sessionStore.clear()
        if (notifyListener) {
            onSessionClearedListener?.invoke()
        }
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
}
