package com.rocketflow.companion

import android.app.Application
import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.SessionStore
import com.rocketflow.companion.browse.BrowseRepository
import com.rocketflow.companion.detail.TaskDetailRepository
import com.rocketflow.companion.network.HttpJsonClient
import com.rocketflow.companion.notifications.DeviceRegistrationStore
import com.rocketflow.companion.notifications.NotificationRuntime
import com.rocketflow.companion.notifications.NotificationsRepository

class RocketFlowCompanionApp : Application() {

    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        val httpJsonClient = HttpJsonClient(BuildConfig.ROCKETFLOW_API_BASE_URL)
        val authRepository = AuthRepository(
            httpJsonClient = httpJsonClient,
            sessionStore = SessionStore(this)
        )
        val notificationRuntime = NotificationRuntime(this)
        notificationRuntime.ensureChannel()
        container = AppContainer(
            authRepository = authRepository,
            browseRepository = BrowseRepository(authRepository),
            taskDetailRepository = TaskDetailRepository(authRepository),
            notificationsRepository = NotificationsRepository(
                authRepository = authRepository,
                deviceRegistrationStore = DeviceRegistrationStore(this)
            ),
            notificationRuntime = notificationRuntime
        )
    }
}

data class AppContainer(
    val authRepository: AuthRepository,
    val browseRepository: BrowseRepository,
    val taskDetailRepository: TaskDetailRepository,
    val notificationsRepository: NotificationsRepository,
    val notificationRuntime: NotificationRuntime
)
