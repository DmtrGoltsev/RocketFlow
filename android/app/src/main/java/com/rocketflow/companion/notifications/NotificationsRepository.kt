package com.rocketflow.companion.notifications

import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.SessionBoundResult
import com.rocketflow.companion.network.ApiException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

class NotificationsRepository(
    private val authRepository: AuthRepository,
    private val deviceRegistrationStore: DeviceRegistrationStore,
    private val pushTokenStore: PushTokenStore,
    private val firebasePushCoordinator: FirebasePushCoordinator
) {
    private val registrationMutex = Mutex()

    fun readStoredRegistration(): DeviceRegistration? = deviceRegistrationStore.read()

    fun readStoredPushToken(): PushTokenSnapshot? = pushTokenStore.read()

    fun isFirebaseConfigured(): Boolean = firebasePushCoordinator.isConfigured()

    fun refreshPushToken(onComplete: (PushTokenRefreshResult) -> Unit) {
        firebasePushCoordinator.refreshToken(onComplete)
    }

    fun clearStoredRegistration() {
        deviceRegistrationStore.clear()
    }

    suspend fun registerDevice(
        session: AuthSession,
        pushToken: String,
        deviceName: String
    ): SessionBoundResult<DeviceRegistration> {
        return registrationMutex.withLock {
            registerDeviceLocked(session, pushToken, deviceName)
        }
    }

    suspend fun unregisterDevice(session: AuthSession, registrationId: String): AuthSession {
        return registrationMutex.withLock {
            try {
                val refreshedSession = authRepository.authorizedDelete(session, "/devices/$registrationId")
                deviceRegistrationStore.clear()
                refreshedSession
            } catch (error: ApiException) {
                if (error.status == 404) {
                    deviceRegistrationStore.clear()
                }
                throw error
            }
        }
    }

    suspend fun syncStoredDeviceRegistration(
        session: AuthSession,
        deviceName: String
    ): SessionBoundResult<DeviceRegistration>? {
        val token = readStoredPushToken()?.value ?: return null
        return registerDevice(session, token, deviceName)
    }

    suspend fun syncDeviceRegistrationWithStoredSession(deviceName: String): SessionBoundResult<DeviceRegistration>? {
        val session = authRepository.readStoredSession() ?: return null
        return syncStoredDeviceRegistration(session, deviceName)
    }

    private suspend fun registerDeviceLocked(
        session: AuthSession,
        pushToken: String,
        deviceName: String
    ): SessionBoundResult<DeviceRegistration> {
        val normalizedPushToken = pushToken.trim()
        val normalizedDeviceName = deviceName.trim().ifBlank { null }
        val installationId = deviceRegistrationStore.readOrCreateInstallationId()
        val storedState = deviceRegistrationStore.readState()

        if (storedState.matches(session, normalizedPushToken, normalizedDeviceName)) {
            return SessionBoundResult(session, storedState?.registration ?: error("Stored registration disappeared"))
        }

        val sessionAfterCleanup = cleanupStoredRegistrationBeforeRegister(session, storedState)
        val result = authRepository.authorizedPost(
            session = sessionAfterCleanup,
            path = "/devices",
            body = JSONObject()
                .put("platform", "android")
                .put("pushToken", normalizedPushToken)
                .put("installationId", installationId)
                .put("deviceName", normalizedDeviceName ?: JSONObject.NULL)
        )

        val registration = result.value.toDeviceRegistration()
        deviceRegistrationStore.write(
            registration = registration,
            userId = result.session.user.id,
            pushToken = normalizedPushToken,
            deviceName = normalizedDeviceName ?: registration.deviceName
        )
        return SessionBoundResult(result.session, registration)
    }

    private suspend fun cleanupStoredRegistrationBeforeRegister(
        session: AuthSession,
        storedState: StoredDeviceRegistration?
    ): AuthSession {
        if (storedState == null) {
            return session
        }

        if (storedState.userId != null && storedState.userId != session.user.id) {
            return session
        }

        return try {
            val refreshedSession = authRepository.authorizedDelete(session, "/devices/${storedState.registration.id}")
            deviceRegistrationStore.clear()
            refreshedSession
        } catch (error: ApiException) {
            if (error.status == 404) {
                deviceRegistrationStore.clear()
                return session
            }
            throw error
        }
    }
}

private fun StoredDeviceRegistration?.matches(
    session: AuthSession,
    pushToken: String,
    deviceName: String?
): Boolean {
    if (this == null) {
        return false
    }

    if (userId != session.user.id || !registration.active) {
        return false
    }

    return pushToken == this.pushToken?.trim() &&
        deviceName == this.deviceName?.trim()?.ifBlank { null }
}

private fun JSONObject.toDeviceRegistration(): DeviceRegistration {
    return DeviceRegistration(
        id = getString("id"),
        platform = getString("platform"),
        deviceName = optString("deviceName").ifBlank { null },
        active = optBoolean("active", true),
        createdAt = getString("createdAt")
    )
}
