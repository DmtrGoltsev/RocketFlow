package com.rocketflow.companion

import android.app.Application
import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.LanguageStore
import com.rocketflow.companion.auth.SessionStore
import com.rocketflow.companion.browse.BrowseRepository
import com.rocketflow.companion.detail.TaskDetailRepository
import com.rocketflow.companion.network.HttpJsonClient
import com.rocketflow.companion.notifications.DeviceRegistrationStore
import com.rocketflow.companion.notifications.FirebasePushCoordinator
import com.rocketflow.companion.notifications.NotificationRuntime
import com.rocketflow.companion.notifications.NotificationsRepository
import com.rocketflow.companion.notifications.PushTokenStore
import com.rocketflow.companion.planning.PlanningLocalStore
import com.rocketflow.companion.planning.PlanningRepository
import com.rocketflow.companion.planning.PlanningSyncReason
import com.rocketflow.companion.planning.PlanningSyncScheduler
import com.rocketflow.companion.settings.UserSettingsRepository
import com.rocketflow.companion.sharing.SharingRepository

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
        val languageStore = LanguageStore(this)
        val pushTokenStore = PushTokenStore(this)
        val firebasePushCoordinator = FirebasePushCoordinator(this, pushTokenStore)
        val planningLocalStore = PlanningLocalStore(this)
        val planningSyncScheduler = PlanningSyncScheduler(this)
        notificationRuntime.ensureChannel()
        firebasePushCoordinator.initialize()
        container = AppContainer(
            authRepository = authRepository,
            languageStore = languageStore,
            browseRepository = BrowseRepository(authRepository),
            taskDetailRepository = TaskDetailRepository(authRepository),
            planningRepository = PlanningRepository(authRepository, planningLocalStore, planningSyncScheduler),
            userSettingsRepository = UserSettingsRepository(authRepository),
            sharingRepository = SharingRepository(authRepository),
            notificationsRepository = NotificationsRepository(
                authRepository = authRepository,
                deviceRegistrationStore = DeviceRegistrationStore(this),
                pushTokenStore = pushTokenStore,
                firebasePushCoordinator = firebasePushCoordinator
            ),
            notificationRuntime = notificationRuntime,
            firebasePushCoordinator = firebasePushCoordinator,
            planningSyncScheduler = planningSyncScheduler
        )
        planningSyncScheduler.enqueuePlanningSync(PlanningSyncReason.Startup)
    }
}

data class AppContainer(
    val authRepository: AuthRepository,
    val languageStore: LanguageStore,
    val browseRepository: BrowseRepository,
    val taskDetailRepository: TaskDetailRepository,
    val planningRepository: PlanningRepository,
    val userSettingsRepository: UserSettingsRepository,
    val sharingRepository: SharingRepository,
    val notificationsRepository: NotificationsRepository,
    val notificationRuntime: NotificationRuntime,
    val firebasePushCoordinator: FirebasePushCoordinator,
    val planningSyncScheduler: PlanningSyncScheduler
)
