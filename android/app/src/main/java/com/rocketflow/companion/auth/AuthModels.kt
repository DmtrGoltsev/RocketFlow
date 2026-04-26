package com.rocketflow.companion.auth

data class CurrentUser(
    val id: String,
    val email: String,
    val displayName: String,
    val timezone: String,
    val language: String
)

data class AuthTokens(
    val accessToken: String,
    val refreshToken: String,
    val expiresAt: String
)

data class AuthSession(
    val user: CurrentUser,
    val tokens: AuthTokens
)

data class SessionBoundResult<T>(
    val session: AuthSession,
    val value: T
)
