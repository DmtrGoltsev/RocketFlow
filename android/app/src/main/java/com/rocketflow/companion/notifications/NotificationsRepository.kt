package com.rocketflow.companion.notifications

import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.SessionBoundResult
import com.rocketflow.companion.network.ApiException
import org.json.JSONObject

class NotificationsRepository(
    private val authRepository: AuthRepository,
    private val deviceRegistrationStore: DeviceRegistrationStore
) {

    fun readStoredRegistration(): DeviceRegistration? = deviceRegistrationStore.read()

    fun clearStoredRegistration() {
        deviceRegistrationStore.clear()
    }

    suspend fun registerDevice(
        session: AuthSession,
        pushToken: String,
        deviceName: String
    ): SessionBoundResult<DeviceRegistration> {
        val result = authRepository.authorizedPost(
            session = session,
            path = "/devices",
            body = JSONObject()
                .put("platform", "android")
                .put("pushToken", pushToken)
                .put("deviceName", deviceName)
        )

        val registration = result.value.toDeviceRegistration()
        deviceRegistrationStore.write(registration)
        return SessionBoundResult(result.session, registration)
    }

    suspend fun unregisterDevice(session: AuthSession, registrationId: String): AuthSession {
        return try {
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

private fun JSONObject.toDeviceRegistration(): DeviceRegistration {
    return DeviceRegistration(
        id = getString("id"),
        platform = getString("platform"),
        deviceName = optString("deviceName").ifBlank { null },
        active = optBoolean("active", true),
        createdAt = getString("createdAt")
    )
}
