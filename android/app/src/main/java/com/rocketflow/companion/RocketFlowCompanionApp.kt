package com.rocketflow.companion

import android.app.Application
import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.LanguageStore
import com.rocketflow.companion.auth.SessionStore
import com.rocketflow.companion.calendar.CalendarRepository
import com.rocketflow.companion.browse.BrowseRepository
import com.rocketflow.companion.detail.TaskDetailRepository
import com.rocketflow.companion.focus.FocusLocalDataSource
import com.rocketflow.companion.focus.FocusRepository
import com.rocketflow.companion.focus.FocusSyncScheduler
import com.rocketflow.companion.network.HttpJsonClient
import com.rocketflow.companion.notifications.DeviceRegistrationStore
import com.rocketflow.companion.notifications.FirebasePushCoordinator
import com.rocketflow.companion.notifications.NotificationRuntime
import com.rocketflow.companion.notifications.NotificationsRepository
import com.rocketflow.companion.notifications.PushTokenStore
import com.rocketflow.companion.notifications.TaskReminderAlarmScheduler
import com.rocketflow.companion.notifications.TaskReminderStore
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
        val taskReminderStore = TaskReminderStore(this)
        val taskReminderAlarmScheduler = TaskReminderAlarmScheduler(this, taskReminderStore)
        val firebasePushCoordinator = FirebasePushCoordinator(this, pushTokenStore)
        val planningLocalStore = PlanningLocalStore(this)
        val planningSyncScheduler = PlanningSyncScheduler(this)
        val focusSyncScheduler = FocusSyncScheduler(this)
        val focusLocalDataSource = FocusLocalDataSource(planningLocalStore)
        notificationRuntime.ensureChannel()
        firebasePushCoordinator.initialize()
        container = AppContainer(
            authRepository = authRepository,
            languageStore = languageStore,
            browseRepository = BrowseRepository(authRepository),
            taskDetailRepository = TaskDetailRepository(authRepository),
            planningRepository = PlanningRepository(authRepository, planningLocalStore, planningSyncScheduler),
            focusRepository = FocusRepository(authRepository, focusLocalDataSource, focusSyncScheduler),
            calendarRepository = CalendarRepository(authRepository, focusLocalDataSource),
            userSettingsRepository = UserSettingsRepository(authRepository),
            sharingRepository = SharingRepository(authRepository),
            notificationsRepository = NotificationsRepository(
                authRepository = authRepository,
                deviceRegistrationStore = DeviceRegistrationStore(this),
                pushTokenStore = pushTokenStore,
                firebasePushCoordinator = firebasePushCoordinator
            ),
            notificationRuntime = notificationRuntime,
            taskReminderStore = taskReminderStore,
            taskReminderAlarmScheduler = taskReminderAlarmScheduler,
            firebasePushCoordinator = firebasePushCoordinator,
            planningSyncScheduler = planningSyncScheduler,
            focusSyncScheduler = focusSyncScheduler
        )
        taskReminderAlarmScheduler.rescheduleActive()
        planningSyncScheduler.enqueuePlanningSync(PlanningSyncReason.Startup)
        focusSyncScheduler.enqueueFocusSync()
    }
}

data class AppContainer(
    val authRepository: AuthRepository,
    val languageStore: LanguageStore,
    val browseRepository: BrowseRepository,
    val taskDetailRepository: TaskDetailRepository,
    val planningRepository: PlanningRepository,
    val focusRepository: FocusRepository,
    val calendarRepository: CalendarRepository,
    val userSettingsRepository: UserSettingsRepository,
    val sharingRepository: SharingRepository,
    val notificationsRepository: NotificationsRepository,
    val notificationRuntime: NotificationRuntime,
    val taskReminderStore: TaskReminderStore,
    val taskReminderAlarmScheduler: TaskReminderAlarmScheduler,
    val firebasePushCoordinator: FirebasePushCoordinator,
    val planningSyncScheduler: PlanningSyncScheduler,
    val focusSyncScheduler: FocusSyncScheduler
)
