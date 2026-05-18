package com.rocketflow.companion

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.graphics.Color
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.ConnectivityManager
import android.net.Network
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.LocaleList
import android.os.Looper
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.text.TextUtils
import android.text.method.HideReturnsTransformationMethod
import android.text.method.TransformationMethod
import android.util.Log
import android.view.Gravity
import android.view.DragEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import com.rocketflow.companion.auth.AuthTokens
import com.rocketflow.companion.auth.CurrentUser
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.SessionStore
import com.rocketflow.companion.network.ApiException
import com.rocketflow.companion.notifications.DeviceRegistration
import com.rocketflow.companion.notifications.NotificationIntents
import com.rocketflow.companion.notifications.NotificationRuntime
import com.rocketflow.companion.notifications.PushTokenSnapshot
import com.rocketflow.companion.notifications.TaskReminderRepeat
import com.rocketflow.companion.notifications.TaskReminderSetting
import com.rocketflow.companion.planning.EntityLink
import com.rocketflow.companion.planning.EntityLinkDraft
import com.rocketflow.companion.planning.FolderDraft
import com.rocketflow.companion.planning.GoalDraft
import com.rocketflow.companion.planning.IdeaDraft
import com.rocketflow.companion.planning.IdeaNote
import com.rocketflow.companion.planning.IdeaNoteDraft
import com.rocketflow.companion.planning.NoteDraft
import com.rocketflow.companion.planning.PlanningFolder
import com.rocketflow.companion.planning.PlanningGoal
import com.rocketflow.companion.planning.PlanningIdea
import com.rocketflow.companion.planning.PlanningLoadResult
import com.rocketflow.companion.planning.PlanningLocalStore
import com.rocketflow.companion.planning.PlanningNote
import com.rocketflow.companion.planning.PlanningSnapshot
import com.rocketflow.companion.planning.PlanningSyncReason
import com.rocketflow.companion.planning.PlanningTask
import com.rocketflow.companion.planning.SyncState
import com.rocketflow.companion.planning.TaskDraft
import com.rocketflow.companion.planning.TaskTag
import com.rocketflow.companion.planning.TaskTagDraft
import com.rocketflow.companion.settings.PriorityDecayPolicy
import com.rocketflow.companion.settings.UserSettings
import com.rocketflow.companion.sharing.ShareLink
import com.rocketflow.companion.sharing.ShareTarget
import com.rocketflow.companion.sharing.ShareTargetType
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale

class MainActivity : Activity() {
    private object Ui {
        const val CANVAS = "#F8F4EC"
        const val SURFACE = "#FFFDF7"
        const val ELEVATED = "#FFFDF7"
        const val TEXT = "#20201D"
        const val MUTED = "#716B61"
        const val HAIRLINE = "#D9D0C1"
        const val ACCENT = "#2F6B57"
        const val ACCENT_SOFT = "#E7EFE8"
        const val ROW_PRESSED = "#F1ECE2"
        const val DANGER = "#9B4A43"
        const val TASK_STATUS_GREEN = "#2FAF6A"
        const val TASK_STATUS_RED = "#C44F48"
        const val INFO = "#456D8B"
        const val AMBER = "#9A7A32"
        const val LOW = "#8C887F"
        const val INK = "#171713"
    }

    private object AuthRules {
        const val MIN_PASSWORD_LENGTH = 8
    }

    private enum class Screen {
        Auth,
        Planner,
        Detail,
        IdeaDetail,
        NoteDetail,
        Settings
    }

    private enum class TextInputPurpose {
        Text,
        Notes,
        Email,
        Password,
        Code,
        Search,
        Number,
        Name,
        Username
    }

    private object AutofillHints {
        const val CODE = "oneTimeCode"
        const val NOTE = "note"
        const val NUMBER = "number"
        const val SEARCH = "search"
        const val TEXT = "text"
        const val TITLE = "title"
    }

    private data class EntityDragPayload(
        val type: String,
        val id: String,
        val label: String
    )

    private data class EntityDropTarget(
        val type: String,
        val id: String
    )

    private data class ManualDragState(
        val payload: EntityDragPayload,
        val source: View,
        val downRawX: Float,
        val downRawY: Float,
        val downAt: Long,
        var currentRawX: Float,
        var currentRawY: Float,
        var active: Boolean = false
    )

    private data class Copy(
        val signInTitle: String,
        val email: String,
        val password: String,
        val signIn: String,
        val createAccount: String,
        val displayName: String,
        val plan: String,
        val settings: String,
        val syncDiagnostics: String,
        val folder: String,
        val goal: String,
        val task: String,
        val idea: String,
        val note: String,
        val create: String,
        val add: String = "\u0414\u043e\u0431\u0430\u0432\u0438\u0442\u044c",
        val newFolder: String,
        val newGoal: String,
        val newTask: String,
        val newIdea: String,
        val newNote: String,
        val addNote: String,
        val editNote: String,
        val ideaHistory: String,
        val links: String = "\u0421\u0432\u044f\u0437\u0438",
        val linkedNotes: String = "\u0421\u0432\u044f\u0437\u0430\u043d\u043d\u044b\u0435 \u0437\u0430\u043c\u0435\u0442\u043a\u0438",
        val related: String = "\u0421\u0432\u044f\u0437\u044c",
        val dependency: String = "\u0417\u0430\u0432\u0438\u0441\u0438\u043c\u043e\u0441\u0442\u044c",
        val move: String = "\u041f\u0435\u0440\u0435\u043c\u0435\u0441\u0442\u0438\u0442\u044c",
        val clone: String = "\u041a\u043b\u043e\u043d\u0438\u0440\u043e\u0432\u0430\u0442\u044c",
        val fullAccess: String = "\u041f\u043e\u043b\u043d\u044b\u0439 \u0434\u043e\u0441\u0442\u0443\u043f",
        val dependencyBlocked: String = "\u0421\u043d\u0430\u0447\u0430\u043b\u0430 \u0437\u0430\u043a\u0440\u043e\u0439\u0442\u0435 \u0431\u043b\u043e\u043a\u0438\u0440\u0443\u044e\u0449\u0438\u0435 \u0437\u0430\u0434\u0430\u0447\u0438.",
        val cannotMoveHere: String = "\u0421\u044e\u0434\u0430 \u043d\u0435\u043b\u044c\u0437\u044f \u043f\u0435\u0440\u0435\u043c\u0435\u0441\u0442\u0438.",
        val dragMoveStarted: String = "\u041f\u0435\u0440\u0435\u0442\u0430\u0449\u0438\u0442\u0435 \u0432 \u0434\u043e\u043f\u0443\u0441\u0442\u0438\u043c\u043e\u0435 \u043c\u0435\u0441\u0442\u043e.",
        val allowAuthorNoteEdits: String,
        val allowAuthorNoteEditsHint: String,
        val noteRequired: String,
        val edit: String,
        val delete: String,
        val cancel: String,
        val save: String,
        val search: String,
        val searchHint: String,
        val clearSearch: String,
        val nothingHere: String,
        val emptyBody: String,
        val selectTask: String,
        val taskDetail: String,
        val notes: String,
        val status: String,
        val priority: String,
        val planned: String = "����",
        val due: String,
        val tags: String = "����",
        val recurrence: String = "������",
        val noRecurrence: String = "��� �������",
        val daily: String = "������ ����",
        val weekly: String = "������ ������",
        val monthly: String = "������ �����",
        val remindersBeforeDue: String = "�� �����",
        val remindersBeforePlanned: String = "�� �����",
        val addTag: String = "�������� ���",
        val newTag: String = "����� ���",
        val colorField: String = "����, �������� #2F6B57",
        val metadata: String = "����������",
        val path: String,
        val details: String,
        val collapse: String = "Collapse",
        val creator: String = "Creator",
        val created: String,
        val updated: String,
        val synced: String,
        val syncStatus: String = "Sync",
        val syncOk: String = "Up to date",
        val syncHelp: String = "Shows whether planner changes are uploaded, pending, or offline.",
        val lastSyncError: String = "Last sync error",
        val offline: String,
        val pending: String,
        val savedOffline: String,
        val couldNotSync: String,
        val account: String,
        val language: String,
        val sharingHelp: String = "Accept an invitation link to add shared folders, goals, or tasks.",
        val reminders: String,
        val remindersHelp: String = "Android permission allows notifications; this phone connects task reminder delivery.",
        val androidPermission: String = "Android permission",
        val accountReminders: String = "Account reminders",
        val deviceRegistration: String = "This phone",
        val taskType: String = "Task type",
        val greenTask: String = "Green",
        val redTask: String = "Red",
        val taskNeedsGoal: String = "A task must belong to a goal. Select an existing goal or create one first.",
        val deleteFolderWarning: String = "This folder contains %1\$d goals and %2\$d tasks. They will be deleted with the folder.",
        val deleteGoalWarning: String = "This goal contains %1\$d tasks. They will be deleted with the goal.",
        val priorityDecay: String = "�������� ����������",
        val priorityDecayHelp: String = "�������� ��������� ����� �������� ��������.",
        val greenTasks: String = "������� ������",
        val redTasks: String = "������� ������",
        val threshold: String = "�����",
        val decayAmount: String = "���",
        val remindersOn: String,
        val remindersOff: String,
        val enableNotifications: String,
        val registerDevice: String,
        val unregisterDevice: String,
        val firebaseUnavailable: String,
        val remindersEnableFailed: String = "Could not enable reminders. Check sync and try again.",
        val signedOut: String,
        val signInAgain: String,
        val requestFailed: String,
        val invalidCredentials: String,
        val passwordTooShort: String,
        val emailAlreadyExists: String,
        val loading: String,
        val noGoalYet: String,
        val noTaskYet: String,
        val nameRequired: String,
        val titleRequired: String,
        val folderFirst: String,
        val goalFirst: String,
        val noDate: String,
        val pickDate: String = "������� ����",
        val clearDate: String = "��������",
        val invalidDate: String = "������: yyyy-MM-dd HH:mm.",
        val today: String,
        val tomorrow: String,
        val reschedule: String = "���������",
        val later30m: String = "30 ���",
        val later1h: String = "1 ���",
        val later3h: String = "3 ����",
        val later24h: String = "24 ����",
        val decayApplied: String = "��������� ������",
        val decayNotApplied: String = "��������� ��� ���������",
        val statusTodo: String,
        val statusInProgress: String,
        val statusDone: String,
        val statusCancelled: String,
        val openingTask: String,
        val syncNow: String,
        val signOut: String,
        val titleField: String,
        val nameField: String,
        val notesField: String,
        val dueField: String,
        val plannedField: String = "����, �������� 2026-05-01 09:00",
        val priorityField: String = "��������� 1-10",
        val priorityRequired: String = "��������� ������ ���� �� 1 �� 10.",
        val priorityShort: String,
        val sharing: String,
        val share: String,
        val shareByEmail: String,
        val shareByUserId: String,
        val shareLink: String,
        val invite: String,
        val inviteSent: String,
        val userId: String,
        val userIdField: String,
        val createLink: String,
        val existingLinks: String,
        val noLinks: String,
        val linkCreated: String,
        val linkCopied: String,
        val copyLink: String,
        val revoke: String,
        val revoked: String,
        val acceptLink: String,
        val tokenField: String,
        val resolve: String,
        val accept: String,
        val linkAccepted: String,
        val linkResolved: String,
        val expires: String,
        val active: String,
        val noExpiry: String,
        val offlineSharing: String
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val appContainer by lazy { (application as RocketFlowCompanionApp).container }
    private val authRepository by lazy { appContainer.authRepository }
    private val languageStore by lazy { appContainer.languageStore }
    private val planningRepository by lazy { appContainer.planningRepository }
    private val userSettingsRepository by lazy { appContainer.userSettingsRepository }
    private val sharingRepository by lazy { appContainer.sharingRepository }
    private val planningSyncScheduler by lazy { appContainer.planningSyncScheduler }
    private val notificationsRepository by lazy { appContainer.notificationsRepository }
    private val notificationRuntime by lazy { appContainer.notificationRuntime }
    private val taskReminderStore by lazy { appContainer.taskReminderStore }
    private val taskReminderAlarmScheduler by lazy { appContainer.taskReminderAlarmScheduler }
    private val connectivityManager by lazy { getSystemService(ConnectivityManager::class.java) }
    private val zone: ZoneId by lazy { ZoneId.systemDefault() }

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            runOnUiThread {
                if (currentSession != null) {
                    planningSyncScheduler.enqueuePlanningSync(PlanningSyncReason.NetworkRestore)
                    reloadPlanner(showBusy = false)
                }
            }
        }
    }

    private var currentLanguage = "ru"
    private var currentScreen = Screen.Auth
    private var currentSession: AuthSession? = null
    private var currentDeviceRegistration: DeviceRegistration? = null
    private var currentPushToken: PushTokenSnapshot? = null
    private var currentSettings: UserSettings? = null
    private var settingsLoading = false
    private var settingsLoadAttempted = false

    private var folders: List<PlanningFolder> = emptyList()
    private var goals: List<PlanningGoal> = emptyList()
    private var tasks: List<PlanningTask> = emptyList()
    private var ideas: List<PlanningIdea> = emptyList()
    private var ideaNotes: List<IdeaNote> = emptyList()
    private var notes: List<PlanningNote> = emptyList()
    private var entityLinks: List<EntityLink> = emptyList()
    private var sharedFolders: List<PlanningFolder> = emptyList()
    private var sharedGoals: List<PlanningGoal> = emptyList()
    private var sharedTasks: List<PlanningTask> = emptyList()
    private var sharedIdeas: List<PlanningIdea> = emptyList()
    private var sharedIdeaNotes: List<IdeaNote> = emptyList()
    private var sharedNotes: List<PlanningNote> = emptyList()
    private var taskTags: List<TaskTag> = emptyList()
    private var planningOffline = false
    private var planningPendingCount = 0
    private var planningLastSyncError: String? = null

    private var selectedFolderId: String? = null
    private var selectedGoalId: String? = null
    private var selectedTaskId: String? = null
    private var selectedTaskDetail: PlanningTask? = null
    private var selectedIdeaId: String? = null
    private var selectedIdeaDetail: PlanningIdea? = null
    private var selectedNoteId: String? = null
    private var selectedNoteDetail: PlanningNote? = null
    private var pendingTaskOpenId: String? = null

    private val collapsedFolderIds = mutableSetOf<String>()
    private val collapsedGoalIds = mutableSetOf<String>()
    private var detailsExpanded = false
    private var linkedNotesExpanded = false
    private var linksExpanded = false
    private var lastDragDropHandledAt = 0L
    private val dragHandler = Handler(Looper.getMainLooper())
    private var manualDragState: ManualDragState? = null
    private var diagnosticsExpanded = false
    private var searchQuery = ""
    private var busy = false
    private var message: String? = null
    private var plannerRefreshJob: Job? = null

    private var emailInput: EditText? = null
    private var passwordInput: EditText? = null
    private var emailDraft = ""
    private var passwordDraft = ""
    private var passwordVisible = false
    private var keyboardShowSerial = 0
    private var activeTextInput: EditText? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        currentLanguage = languageStore.readLanguage()
        seedAcceptanceScenarioIfRequested(intent)
        authRepository.setOnSessionClearedListener(::handleTerminalSessionFailure)
        currentDeviceRegistration = notificationsRepository.readStoredRegistration()
        currentPushToken = notificationsRepository.readStoredPushToken()
        window.statusBarColor = color(Ui.CANVAS)
        window.navigationBarColor = color(Ui.CANVAS)
        handleIncomingIntent(intent)
        render()
        registerNetworkRestore()
        refreshPushToken(showProgress = false)
        bootstrapSession()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
        render()
        maybeOpenPendingTask()
    }

    override fun onDestroy() {
        stopPlannerRefresh()
        authRepository.setOnSessionClearedListener(null)
        unregisterNetworkRestore()
        scope.cancel()
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        taskReminderAlarmScheduler.rescheduleActive()
    }

    override fun onBackPressed() {
        when (currentScreen) {
            Screen.Detail, Screen.IdeaDetail, Screen.NoteDetail, Screen.Settings -> {
                currentScreen = Screen.Planner
                render()
            }
            else -> super.onBackPressed()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NotificationRuntime.REQUEST_CODE) {
            message = if (notificationRuntime.hasNotificationPermission()) copy().remindersOn else copy().remindersOff
            if (notificationRuntime.hasNotificationPermission()) {
                maybeSyncRegisteredDevice()
            }
            render()
        }
    }

    private fun bootstrapSession() {
        setBusy(true)
        scope.launch {
            try {
                currentSession = authRepository.bootstrapSession()
                if (currentSession != null) {
                    currentScreen = Screen.Planner
                    loadPlannerData()
                    startPlannerRefresh()
                    syncRegisteredDeviceIfPossible(currentSession ?: return@launch)
                    maybeOpenPendingTask()
                }
            } catch (error: Exception) {
                currentSession = null
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun submitLogin() {
        emailDraft = emailInput?.text?.toString()?.trim().orEmpty()
        passwordDraft = passwordInput?.text?.toString().orEmpty()

        if (emailDraft.isBlank() || passwordDraft.isBlank()) {
            message = copy().signInAgain
            render()
            return
        }

        setBusy(true)
        message = null
        scope.launch {
            try {
                currentSession = authRepository.login(emailDraft, passwordDraft)
                passwordDraft = ""
                currentScreen = Screen.Planner
                loadPlannerData()
                startPlannerRefresh()
                syncRegisteredDeviceIfPossible(currentSession ?: return@launch)
                maybeOpenPendingTask()
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun showRegisterDialog() {
        val c = copy()
        val email = dialogInput(
            c.email,
            emailInput?.text?.toString().orEmpty(),
            inputPurpose = TextInputPurpose.Email,
            inputTypeOverride = emailInputType(),
            imeOptionsOverride = EditorInfo.IME_ACTION_NEXT
        )
        val password = dialogInput(c.password, "", inputPurpose = TextInputPurpose.Password, isPassword = true)
        val passwordRow = passwordInputRow(password, initialVisible = false)
        val name = dialogInput(c.displayName, "", inputPurpose = TextInputPurpose.Name)
        val form = dialogForm(email, passwordRow, name)

        val dialog = AlertDialog.Builder(this)
            .setTitle(c.createAccount)
            .setView(form)
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.createAccount) { _, _ ->
                val registerEmail = email.text.toString().trim()
                val registerPassword = password.text.toString()
                val displayName = name.text.toString().trim().ifBlank { "RocketFlow" }
                if (registerEmail.isBlank() || registerPassword.isBlank()) {
                    message = c.signInAgain
                    render()
                    return@setPositiveButton
                }
                if (registerPassword.length < AuthRules.MIN_PASSWORD_LENGTH) {
                    message = c.passwordTooShort
                    render()
                    return@setPositiveButton
                }
                register(registerEmail, registerPassword, displayName)
            }
            .show()
        focusDialogInput(dialog, email)
    }

    private fun register(email: String, password: String, displayName: String) {
        setBusy(true)
        message = null
        scope.launch {
            try {
                currentSession = authRepository.register(
                    email = email,
                    password = password,
                    displayName = displayName,
                    timezone = zone.id,
                    language = currentLanguage
                )
                currentScreen = Screen.Planner
                loadPlannerData()
                startPlannerRefresh()
                syncRegisteredDeviceIfPossible(currentSession ?: return@launch)
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private suspend fun loadPlannerData() {
        val session = currentSession ?: return
        val result = planningRepository.syncAndLoad(session)
        currentSession = result.session
        applyPlanningSnapshot(result.snapshot)
    }

    private fun applyPlanningSnapshot(snapshot: PlanningSnapshot) {
        folders = snapshot.folders
        goals = snapshot.goals
        tasks = snapshot.tasks
        ideas = snapshot.ideas
        ideaNotes = snapshot.ideaNotes
        notes = snapshot.notes
        entityLinks = snapshot.entityLinks
        sharedFolders = snapshot.sharedFolders
        sharedGoals = snapshot.sharedGoals
        sharedTasks = snapshot.sharedTasks
        sharedIdeas = snapshot.sharedIdeas
        sharedIdeaNotes = snapshot.sharedIdeaNotes
        sharedNotes = snapshot.sharedNotes
        taskTags = snapshot.taskTags
        planningOffline = snapshot.offline
        planningPendingCount = snapshot.pendingCount
        planningLastSyncError = snapshot.lastSyncError

        selectedFolderId = selectedFolderId
            ?.takeIf { id -> folders.any { it.id == id } || sharedFolders.any { it.id == id } }
            ?: folders.firstOrNull()?.id

        selectedGoalId = selectedGoalId
            ?.takeIf { id -> goals.any { it.id == id } || sharedGoals.any { it.id == id } }

        selectedTaskId = selectedTaskId?.takeIf { id -> allTasks().any { it.id == id } }
        selectedTaskDetail = selectedTaskId?.let(::findTask)
        selectedIdeaId = selectedIdeaId?.takeIf { id -> allIdeas().any { it.id == id } }
        selectedIdeaDetail = selectedIdeaId?.let(::findIdea)
        selectedNoteId = selectedNoteId?.takeIf { id -> allNotes().any { it.id == id } }
        selectedNoteDetail = selectedNoteId?.let(::findNote)
    }

    private fun clearPlannerState() {
        folders = emptyList()
        goals = emptyList()
        tasks = emptyList()
        ideas = emptyList()
        ideaNotes = emptyList()
        notes = emptyList()
        entityLinks = emptyList()
        sharedFolders = emptyList()
        sharedGoals = emptyList()
        sharedTasks = emptyList()
        sharedIdeas = emptyList()
        sharedIdeaNotes = emptyList()
        sharedNotes = emptyList()
        taskTags = emptyList()
        planningOffline = false
        planningPendingCount = 0
        planningLastSyncError = null
        selectedFolderId = null
        selectedGoalId = null
        selectedTaskId = null
        selectedTaskDetail = null
        selectedIdeaId = null
        selectedIdeaDetail = null
        selectedNoteId = null
        selectedNoteDetail = null
        collapsedFolderIds.clear()
        collapsedGoalIds.clear()
        searchQuery = ""
        stopPlannerRefresh()
    }

    private fun reloadPlanner(showBusy: Boolean = true) {
        if (currentSession == null) return
        planningSyncScheduler.enqueuePlanningSync(PlanningSyncReason.Manual)
        if (showBusy) setBusy(true)
        message = null
        scope.launch {
            try {
                loadPlannerData()
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                if (showBusy) setBusy(false) else render()
            }
        }
    }

    private fun logout() {
        setBusy(true)
        message = null
        scope.launch {
            try {
                val session = currentSession
                val registration = currentDeviceRegistration
                if (session != null && registration != null) {
                    try {
                        currentSession = notificationsRepository.unregisterDevice(session, registration.id)
                        currentDeviceRegistration = null
                    } catch (_: Exception) {
                        currentDeviceRegistration = notificationsRepository.readStoredRegistration()
                    }
                }
                authRepository.logout()
            } finally {
                currentSession = null
                currentSettings = null
                settingsLoadAttempted = false
                currentScreen = Screen.Auth
                clearPlannerState()
                message = copy().signedOut
                setBusy(false)
            }
        }
    }

    private fun render() {
        val session = currentSession
        if (session == null) {
            currentScreen = Screen.Auth
            renderAuth()
            return
        }

        when (currentScreen) {
            Screen.Auth, Screen.Planner -> renderPlanner()
            Screen.Detail -> renderDetail()
            Screen.IdeaDetail -> renderIdeaDetail()
            Screen.NoteDetail -> renderNoteDetail()
            Screen.Settings -> renderSettings(session)
        }
    }

    private fun renderAuth() {
        val c = copy()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(color(Ui.CANVAS))
            setPadding(dp(16), dp(32), dp(16), dp(24))
        }

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        header.addView(
            TextView(this).apply {
                text = "RocketFlow"
                textSize = 34f
                setTextColor(color(Ui.INK))
                setTypeface(Typeface.create(Typeface.SERIF, Typeface.BOLD), Typeface.BOLD)
                includeFontPadding = false
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            }
        )
        header.addView(languageSegment(compact = true))
        root.addView(header)

        root.addView(
            TextView(this).apply {
                text = c.signInTitle
                textSize = 23f
                setTextColor(color(Ui.TEXT))
                setTypeface(typeface, Typeface.BOLD)
                includeFontPadding = false
                setPadding(0, dp(46), 0, dp(10))
            }
        )

        emailInput = EditText(this).apply {
            hint = c.email
            setText(emailDraft)
            styleInput()
            applyInputOptions(
                inputType = emailInputType(),
                imeOptions = EditorInfo.IME_ACTION_NEXT,
                inputPurpose = TextInputPurpose.Email
            )
            setSelection(text?.length ?: 0)
            keepDraftUpdated { emailDraft = it }
            openKeyboardOnUserFocus()
        }
        val passwordField = EditText(this).apply {
            hint = c.password
            setText(passwordDraft)
            imeOptions = EditorInfo.IME_ACTION_DONE
            styleInput()
            applyPasswordVisibility(passwordVisible, autofillPurpose = TextInputPurpose.Password)
            keepDraftUpdated { passwordDraft = it }
            openKeyboardOnUserFocus()
        }
        passwordInput = passwordField
        val passwordToggle = Button(this).apply {
            text = passwordVisibilityToggleText(passwordVisible)
            contentDescription = passwordVisibilityToggleDescription(passwordVisible)
            setAllCaps(false)
            textSize = 13f
            includeFontPadding = false
            minHeight = dp(48)
            setTextColor(color(Ui.TEXT))
            background = roundedDrawable(Ui.SURFACE, strokeColorHex = Ui.HAIRLINE, radiusDp = 8)
            setOnClickListener {
                val input = passwordInput ?: return@setOnClickListener
                passwordDraft = input.text?.toString().orEmpty()
                val cursor = input.selectionStart
                passwordVisible = !passwordVisible
                input.applyPasswordVisibility(passwordVisible, cursor)
                text = passwordVisibilityToggleText(passwordVisible)
                contentDescription = passwordVisibilityToggleDescription(passwordVisible)
                input.ensureKeyboardVisible()
            }
        }
        val passwordRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(48)
            ).apply { topMargin = dp(10) }
        }
        passwordField.layoutParams = LinearLayout.LayoutParams(
            0,
            LinearLayout.LayoutParams.MATCH_PARENT,
            1f
        )
        passwordToggle.layoutParams = LinearLayout.LayoutParams(
            dp(104),
            LinearLayout.LayoutParams.MATCH_PARENT
        ).apply { leftMargin = dp(8) }
        passwordRow.addView(passwordField)
        passwordRow.addView(passwordToggle)
        root.addView(emailInput)
        root.addView(passwordRow)

        root.addView(
            textButton(c.signIn, primary = true) { submitLogin() }.apply {
                isEnabled = !busy
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(48)
                ).apply { topMargin = dp(12) }
            }
        )
        root.addView(
            textButton(c.createAccount, quiet = true) { showRegisterDialog() }.apply {
                gravity = Gravity.CENTER_VERTICAL or Gravity.START
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(44)
                )
            }
        )

        messageLine()?.let { root.addView(it) }

        setContentView(
            ScrollView(this).apply {
                isFillViewport = true
                setBackgroundColor(color(Ui.CANVAS))
                addView(root)
            }
        )
    }

    private fun renderPlanner() {
        val c = copy()
        val frame = FrameLayout(this).apply { setBackgroundColor(color(Ui.CANVAS)) }
        val shell = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(color(Ui.CANVAS))
        }
        shell.addView(appBar(title = c.plan, showBack = false, mode = Screen.Planner))
        shell.addView(divider())
        messageLine(inset = true)?.let { shell.addView(it) }

        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(6), 0, dp(96))
        }

        val ownFolders = filteredFolders().filter { it.parentFolderId == null }
        val sharedFolderList = filteredSharedFolders().filter { it.parentFolderId == null }
        val looseSharedGoals = filteredSharedGoals()
            .filter { goal -> sharedFolderList.none { it.id == goal.folderId } }
        val looseSharedTasks = filteredSharedTasks()
            .filter { task -> looseSharedGoals.none { it.id == task.goalId } && sharedGoals.none { it.id == task.goalId } }
        val hasVisibleRows = ownFolders.isNotEmpty() ||
            sharedFolderList.isNotEmpty() ||
            looseSharedGoals.isNotEmpty() ||
            looseSharedTasks.isNotEmpty() ||
            filteredIdeas().isNotEmpty() ||
            filteredNotes().isNotEmpty() ||
            filteredSharedIdeas().isNotEmpty() ||
            filteredSharedNotes().isNotEmpty()

        if (!hasVisibleRows) {
            list.addView(emptyPlannerView())
        } else {
            ownFolders.forEach { folder -> renderFolder(list, folder, indentLevel = 0) }
            if (sharedFolderList.isNotEmpty() || looseSharedGoals.isNotEmpty() || looseSharedTasks.isNotEmpty()) {
                list.addView(sectionLabel(if (currentLanguage == "en") "Shared" else "\u041e\u0431\u0449\u0438\u0435"))
                sharedFolderList.forEach { folder -> renderFolder(list, folder, indentLevel = 0) }
                looseSharedGoals.forEach { goal -> renderGoal(list, goal, shared = true) }
                looseSharedTasks.forEach { task ->
                    list.addView(taskRow(task, indentLevel = 1))
                    list.addView(rowDivider(indentLevel = 1))
                }
            }
        }

        shell.addView(
            ScrollView(this).apply {
                setBackgroundColor(color(Ui.CANVAS))
                addView(list)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    0,
                    1f
                )
            }
        )
        frame.addView(shell)
        frame.addView(
            ImageButton(this).apply {
                setImageResource(R.drawable.ic_add)
                setColorFilter(color(Ui.ELEVATED))
                contentDescription = c.create
                background = roundedDrawable(Ui.ACCENT, radiusDp = 28)
                setOnClickListener { showCreateDialog() }
                layoutParams = FrameLayout.LayoutParams(dp(56), dp(56), Gravity.BOTTOM or Gravity.END).apply {
                    marginEnd = dp(16)
                    bottomMargin = dp(16)
                }
            }
        )

        setContentView(frame)
    }

    private fun renderFolder(parent: LinearLayout, folder: PlanningFolder, indentLevel: Int) {
        parent.addView(folderRow(folder, indentLevel))
        parent.addView(rowDivider(indentLevel = indentLevel))
        if (folder.id in collapsedFolderIds) return

        val childFolders = childFoldersForFolder(folder.id, includeShared = folder.shared)
        val folderGoals = goalsForFolder(folder.id, includeShared = folder.shared)
        val folderIdeas = ideasForFolder(folder.id, includeShared = folder.shared)
        val plainNotes = notesForFolder(folder.id, includeShared = folder.shared)
        if (childFolders.isEmpty() && folderGoals.isEmpty() && folderIdeas.isEmpty() && plainNotes.isEmpty()) {
            parent.addView(hintRow(copy().noGoalYet, indentLevel = indentLevel + 1))
            parent.addView(rowDivider(indentLevel = indentLevel + 1))
        } else {
            childFolders.forEach { child -> renderFolder(parent, child, indentLevel + 1) }
            plainNotes.forEach { note ->
                parent.addView(noteRow(note, indentLevel = indentLevel + 1))
                parent.addView(rowDivider(indentLevel = indentLevel + 1))
            }
            folderIdeas.forEach { idea ->
                parent.addView(ideaRow(idea, indentLevel = indentLevel + 1))
                parent.addView(rowDivider(indentLevel = indentLevel + 1))
            }
            folderGoals.forEach { goal -> renderGoal(parent, goal, shared = folder.shared || goal.shared, indentLevel = indentLevel + 1) }
        }
    }

    private fun renderGoal(parent: LinearLayout, goal: PlanningGoal, shared: Boolean, indentLevel: Int = 1) {
        parent.addView(goalRow(goal, shared = shared, indentLevel = indentLevel))
        parent.addView(rowDivider(indentLevel = indentLevel))
        if (goal.id in collapsedGoalIds) return

        val goalTasks = tasksForGoal(goal.id, includeShared = shared)
        if (goalTasks.isEmpty()) {
            parent.addView(hintRow(copy().noTaskYet, indentLevel = indentLevel + 1))
            parent.addView(rowDivider(indentLevel = indentLevel + 1))
        } else {
            goalTasks.forEach { task ->
                parent.addView(taskRow(task, indentLevel = indentLevel + 1))
                parent.addView(rowDivider(indentLevel = indentLevel + 1))
            }
        }
    }

    private fun renderDetail() {
        val c = copy()
        val task = selectedTaskDetail ?: selectedTaskId?.let(::findTask)
        selectedTaskDetail = task
        val shell = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(color(Ui.CANVAS))
        }
        shell.addView(appBar(title = task?.title ?: c.taskDetail, showBack = true, mode = Screen.Detail))
        shell.addView(divider())
        messageLine(inset = true)?.let { shell.addView(it) }

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(32))
        }

        if (task == null) {
            content.addView(emptyDetailView())
        } else {
            content.addView(
                TextView(this).apply {
                    text = task.title
                    textSize = 22f
                    setTextColor(color(Ui.TEXT))
                    setTypeface(typeface, Typeface.BOLD)
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                    includeFontPadding = false
                    setPadding(0, dp(4), 0, dp(18))
                }
            )
            content.addView(detailMarkerStrip(task))
            content.addView(pathLine(taskPath(task)))
            content.addView(sectionLabel(c.notes))
            content.addView(
                TextView(this).apply {
                    text = task.description.ifBlank { c.noDate }
                    textSize = 15f
                    setTextColor(color(if (task.description.isBlank()) Ui.MUTED else Ui.TEXT))
                    setLineSpacing(dp(2).toFloat(), 1f)
                    setPadding(0, dp(8), 0, dp(16))
                }
            )
            content.addView(linksSection("task", task.id))
            content.addView(linkedNotesSection("task", task.id))
            content.addView(propertyRow(c.details, if (detailsExpanded) c.cancel else "", clickable = true) {
                detailsExpanded = !detailsExpanded
                render()
            })
            if (detailsExpanded) {
                content.addView(propertyRow(c.status, localizedStatus(task.status), clickable = true) {
                    showStatusDialog(task)
                })
                content.addView(propertyRow(c.taskType, taskTypeLabel(task.type), clickable = canWrite(task)) {
                    showTaskTypeDialog(task)
                })
                content.addView(propertyRow(c.priority, "${c.priorityShort}${task.priority}", clickable = canWrite(task)) {
                    showPriorityDialog(task)
                })
                content.addView(propertyRow(c.planned, formatDateTime(task.plannedTime), clickable = canWrite(task)) {
                    showPlannedDialog(task)
                })
                content.addView(propertyRow(c.due, formatDateTime(task.dueTime), clickable = canWrite(task)) {
                    showDueDialog(task)
                })
                content.addView(propertyRow(c.tags, describeTaskTags(task), clickable = canWrite(task)) {
                    showTaskTagsDialog(task)
                })
                content.addView(propertyRow(c.recurrence, describeRecurrence(task.recurrenceJson), clickable = canWrite(task)) {
                    showRecurrenceDialog(task)
                })
                content.addView(propertyRow(c.reminders, describeLocalReminder(task), clickable = true) {
                    showRemindersDialog(task)
                })
                content.addView(propertyRow(c.reschedule, c.later3h, clickable = canWrite(task)) {
                    showRescheduleDialog(task)
                })
                task.creatorLabel()?.let { creator ->
                    content.addView(propertyRow(c.creator, creator, clickable = false))
                }
                content.addView(propertyRow(c.created, formatDateTime(task.createdAt), clickable = false))
                content.addView(propertyRow(c.updated, formatDateTime(task.updatedAt), clickable = false))
                content.addView(propertyRow(c.syncDiagnostics, syncLabel(task.syncState), clickable = false))
            }
        }

        shell.addView(
            ScrollView(this).apply {
                addView(content)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    0,
                    1f
                )
            }
        )
        setContentView(shell)
    }

    private fun renderIdeaDetail() {
        val c = copy()
        val idea = selectedIdeaDetail ?: selectedIdeaId?.let(::findIdea)
        selectedIdeaDetail = idea
        val shell = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(color(Ui.CANVAS))
        }
        shell.addView(appBar(title = idea?.title ?: c.idea, showBack = true, mode = Screen.IdeaDetail))
        shell.addView(divider())
        messageLine(inset = true)?.let { shell.addView(it) }

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(32))
        }

        if (idea == null) {
            content.addView(emptyDetailView())
        } else {
            content.addView(
                TextView(this).apply {
                    text = idea.title
                    textSize = 22f
                    setTextColor(color(Ui.TEXT))
                    setTypeface(typeface, Typeface.BOLD)
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                    includeFontPadding = false
                    setPadding(0, dp(4), 0, dp(12))
                }
            )
            content.addView(pathLine(ideaPath(idea)))
            content.addView(propertyRow(c.status, idea.status.ifBlank { "active" }, clickable = canEditIdea(idea)) {
                showIdeaDialog(idea.folderId, idea)
            })
            if (canEditIdea(idea)) {
                content.addView(propertyRow(c.allowAuthorNoteEdits, if (idea.allowAuthorNoteEdits) c.remindersOn else c.remindersOff, clickable = true) {
                    saveIdea(idea.folderId, idea, idea.toDraft(allowAuthorNoteEdits = !idea.allowAuthorNoteEdits))
                })
            }
            content.addView(sectionLabel(c.notes))
            content.addView(
                TextView(this).apply {
                    text = idea.body.ifBlank { c.noDate }
                    textSize = 15f
                    setTextColor(color(if (idea.body.isBlank()) Ui.MUTED else Ui.TEXT))
                    setLineSpacing(dp(2).toFloat(), 1f)
                    setPadding(0, dp(8), 0, dp(16))
                }
            )
            content.addView(linksSection("idea", idea.id))
            content.addView(linkedNotesSection("idea", idea.id))
            content.addView(textButton(c.addNote, primary = true) { showIdeaNoteDialog(idea) })
            content.addView(sectionLabel(c.ideaHistory))
            val notes = ideaNotesForIdea(idea.id)
            if (notes.isEmpty()) {
                content.addView(hintRow(c.nothingHere, indentLevel = 0))
            } else {
                notes.forEach { note -> content.addView(ideaHistoryRow(idea, note)) }
            }
        }

        shell.addView(
            ScrollView(this).apply {
                addView(content)
                setBackgroundColor(color(Ui.CANVAS))
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    0,
                    1f
                )
            }
        )
        setContentView(shell)
    }

    private fun renderNoteDetail() {
        val c = copy()
        val note = selectedNoteDetail ?: selectedNoteId?.let(::findNote)
        selectedNoteDetail = note
        val shell = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(color(Ui.CANVAS))
        }
        shell.addView(appBar(title = note?.title ?: c.notes, showBack = true, mode = Screen.NoteDetail))
        shell.addView(divider())
        messageLine(inset = true)?.let { shell.addView(it) }

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(32))
        }

        if (note == null) {
            content.addView(emptyDetailView())
        } else {
            content.addView(
                TextView(this).apply {
                    text = note.title
                    textSize = 22f
                    setTextColor(color(Ui.TEXT))
                    setTypeface(typeface, Typeface.BOLD)
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                    includeFontPadding = false
                    setPadding(0, dp(4), 0, dp(12))
                }
            )
            content.addView(pathLine(notePath(note)))
            content.addView(sectionLabel(c.notes))
            content.addView(
                TextView(this).apply {
                    text = note.body.ifBlank { c.noDate }
                    textSize = 15f
                    setTextColor(color(if (note.body.isBlank()) Ui.MUTED else Ui.TEXT))
                    setLineSpacing(dp(2).toFloat(), 1f)
                    setPadding(0, dp(8), 0, dp(16))
                }
            )
            content.addView(linksSection("note", note.id))
            content.addView(propertyRow(c.created, formatDateTime(note.createdAt), clickable = false))
            content.addView(propertyRow(c.updated, formatDateTime(note.updatedAt), clickable = false))
            content.addView(propertyRow(c.syncDiagnostics, syncLabel(note.syncState), clickable = false))
        }

        shell.addView(
            ScrollView(this).apply {
                addView(content)
                setBackgroundColor(color(Ui.CANVAS))
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    0,
                    1f
                )
            }
        )
        setContentView(shell)
    }

    private fun renderSettings(session: AuthSession) {
        val c = copy()
        if (currentSettings == null && !settingsLoading && !settingsLoadAttempted) {
            loadUserSettings()
        }
        val shell = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(color(Ui.CANVAS))
        }
        shell.addView(appBar(title = c.settings, showBack = true, mode = Screen.Settings))
        shell.addView(divider())
        messageLine(inset = true)?.let { shell.addView(it) }

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(10), dp(16), dp(32))
        }
        content.addView(sectionLabel(c.language))
        content.addView(languageSegment(compact = false))

        content.addView(sectionLabel(c.account))
        content.addView(settingsRow(c.email, session.user.email))

        content.addView(sectionLabel(c.syncStatus))
        content.addView(settingsHelp(c.syncHelp))
        content.addView(settingsRow(c.syncStatus, planningStatusText()))

        content.addView(sectionLabel(c.sharing))
        content.addView(settingsHelp(c.sharingHelp))
        content.addView(settingsRow(c.acceptLink, c.shareLink) { showAcceptShareLinkDialog() })

        content.addView(sectionLabel(c.priorityDecay))
        content.addView(settingsHelp(c.priorityDecayHelp))
        val settings = currentSettings
        if (settings == null) {
            content.addView(settingsRow(c.priorityDecay, if (settingsLoading) c.loading else c.couldNotSync))
        } else {
            content.addView(settingsRow(c.greenTasks, readableDecayPolicySummary(settings.greenPriorityDecayPolicy)) {
                showDecayPolicyDialog(settings.greenPriorityDecayPolicy)
            })
            content.addView(settingsRow(c.redTasks, readableDecayPolicySummary(settings.redPriorityDecayPolicy)) {
                showDecayPolicyDialog(settings.redPriorityDecayPolicy)
            })
        }
        content.addView(
            settingsRow(c.syncDiagnostics, if (diagnosticsExpanded) c.collapse else c.details) {
                diagnosticsExpanded = !diagnosticsExpanded
                render()
            }
        )
        if (diagnosticsExpanded) {
            content.addView(settingsRow(c.lastSyncError, planningLastSyncError?.let { syncErrorText(it) } ?: c.syncOk))
            content.addView(settingsRow(c.androidPermission, notificationPermissionLabel()))
            if (!notificationsRepository.isFirebaseConfigured()) {
                content.addView(settingsRow(c.deviceRegistration, c.firebaseUnavailable))
            }
        }

        content.addView(sectionLabel(c.reminders))
        content.addView(settingsHelp(c.remindersHelp))
        settings?.let {
            content.addView(settingsRow(c.accountReminders, if (it.notificationsEnabled) c.remindersOn else c.remindersOff))
        }
        content.addView(settingsRow(c.androidPermission, notificationPermissionLabel()))
        if (!notificationRuntime.hasNotificationPermission()) {
            content.addView(textButton(c.enableNotifications, primary = true) {
                notificationRuntime.requestNotificationPermission(this)
            })
        }
        content.addView(settingsRow(c.deviceRegistration, notificationRegistrationLabel()))
        val registration = currentDeviceRegistration
        if (notificationsRepository.isFirebaseConfigured()) {
            content.addView(
                textButton(if (registration == null) c.registerDevice else c.unregisterDevice, primary = registration == null) {
                    if (registration == null) registerDevice() else unregisterDevice()
                }
            )
        }
        content.addView(textButton(c.syncNow, quiet = true) { reloadPlanner(showBusy = true) })
        content.addView(textButton(c.signOut, danger = true) { logout() })

        shell.addView(
            ScrollView(this).apply {
                addView(content)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    0,
                    1f
                )
            }
        )
        setContentView(shell)
    }

    private fun loadUserSettings() {
        val session = currentSession ?: return
        settingsLoading = true
        settingsLoadAttempted = true
        scope.launch {
            try {
                val result = userSettingsRepository.getSettings(session)
                currentSession = result.session
                currentSettings = result.value
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                settingsLoading = false
                if (currentScreen == Screen.Settings) render()
            }
        }
    }

    private fun showDecayPolicyDialog(policy: PriorityDecayPolicy) {
        val c = copy()
        val enabledInput = CheckBox(this).apply {
            text = c.remindersOn
            isChecked = policy.enabled
            setTextColor(color(Ui.TEXT))
            textSize = 15f
            setPadding(0, dp(8), 0, dp(4))
        }
        val thresholdInput = dialogInput(c.threshold, policy.thresholdPreset)
        val amountInput = dialogInput(
            c.decayAmount,
            policy.decayAmount.toString(),
            inputPurpose = TextInputPurpose.Number,
            inputTypeOverride = InputType.TYPE_CLASS_NUMBER
        )
        AlertDialog.Builder(this)
            .setTitle(if (policy.taskType == "red") c.redTasks else c.greenTasks)
            .setView(dialogForm(enabledInput, thresholdInput, amountInput))
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.save) { _, _ ->
                val preset = thresholdInput.text.toString().trim().lowercase(Locale.ROOT)
                val amount = amountInput.text.toString().trim().toIntOrNull()
                if (preset !in setOf("day", "week", "month") || amount == null || amount < 1) {
                    message = c.invalidDate
                    render()
                    return@setPositiveButton
                }
                updateDecayPolicy(
                    policy.copy(
                        enabled = enabledInput.isChecked,
                        thresholdPreset = preset,
                        decayAmount = amount
                    )
                )
            }
            .show()
    }

    private fun updateDecayPolicy(policy: PriorityDecayPolicy) {
        val session = currentSession ?: return
        val settings = currentSettings ?: return
        val next = if (policy.taskType == "red") {
            settings.copy(language = currentLanguage, redPriorityDecayPolicy = policy)
        } else {
            settings.copy(language = currentLanguage, greenPriorityDecayPolicy = policy)
        }
        setBusy(true)
        scope.launch {
            try {
                val result = userSettingsRepository.updateSettings(session, next)
                currentSession = result.session
                currentSettings = result.value
                message = copy().synced
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun decayPolicySummary(policy: PriorityDecayPolicy): String {
        val enabled = if (policy.enabled) copy().remindersOn else copy().remindersOff
        return "$enabled / ${thresholdLabel(policy.thresholdPreset)} / -${policy.decayAmount}"
    }

    private fun thresholdLabel(preset: String): String {
        return when (preset) {
            "day" -> if (currentLanguage == "en") "day" else "\u0434\u0435\u043d\u044c"
            "week" -> if (currentLanguage == "en") "week" else "\u043d\u0435\u0434\u0435\u043b\u044f"
            "month" -> if (currentLanguage == "en") "month" else "\u043c\u0435\u0441\u044f\u0446"
            else -> preset
        }
    }

    private fun readableDecayPolicySummary(policy: PriorityDecayPolicy): String {
        val enabled = if (policy.enabled) copy().remindersOn else copy().remindersOff
        val threshold = readableThresholdLabel(policy.thresholdPreset)
        return if (currentLanguage == "en") {
            "$enabled; threshold: $threshold; -${policy.decayAmount}"
        } else {
            "$enabled; \u043f\u043e\u0440\u043e\u0433: $threshold; -${policy.decayAmount}"
        }
    }

    private fun startPlannerRefresh() {
        if (plannerRefreshJob?.isActive == true) return
        plannerRefreshJob = scope.launch {
            while (true) {
                delay(PLANNER_REFRESH_INTERVAL_MS)
                refreshPlannerQuietly()
            }
        }
    }

    private fun stopPlannerRefresh() {
        plannerRefreshJob?.cancel()
        plannerRefreshJob = null
    }

    private suspend fun refreshPlannerQuietly() {
        if (currentSession == null || busy || hasActiveTextInput()) return
        try {
            loadPlannerData()
            if (!hasActiveTextInput() && currentScreen != Screen.Auth) {
                render()
            }
        } catch (_: Exception) {
            // Quiet refresh should never interrupt typing or surface transient network noise.
        }
    }

    private fun hasActiveTextInput(): Boolean {
        val trackedInput = activeTextInput
        return currentFocus is EditText ||
            (trackedInput != null && trackedInput.isFocused && trackedInput.windowToken != null)
    }

    private fun readableThresholdLabel(preset: String): String {
        return when (preset) {
            "day" -> if (currentLanguage == "en") "day" else "\u0434\u0435\u043d\u044c"
            "week" -> if (currentLanguage == "en") "week" else "\u043d\u0435\u0434\u0435\u043b\u044f"
            "month" -> if (currentLanguage == "en") "month" else "\u043c\u0435\u0441\u044f\u0446"
            else -> preset
        }
    }

    private fun appBar(title: String, showBack: Boolean, mode: Screen): LinearLayout {
        val c = copy()
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(4), 0, dp(4), 0)
            background = bottomBorderDrawable(Ui.CANVAS)
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(56))

            if (showBack) {
                addView(iconButton(R.drawable.ic_arrow_back, if (currentLanguage == "en") "Back" else "\u041d\u0430\u0437\u0430\u0434") {
                    currentScreen = Screen.Planner
                    render()
                })
            } else {
                addView(
                    TextView(context).apply {
                        text = "RF"
                        textSize = 18f
                        setTextColor(color(Ui.INK))
                        setTypeface(Typeface.create(Typeface.SERIF, Typeface.BOLD), Typeface.BOLD)
                        gravity = Gravity.CENTER
                        layoutParams = LinearLayout.LayoutParams(dp(48), dp(48))
                    }
                )
            }

            addView(
                TextView(context).apply {
                    text = title
                    textSize = 20f
                    setTextColor(color(Ui.TEXT))
                    setTypeface(typeface, Typeface.BOLD)
                    maxLines = if (mode == Screen.Detail) 2 else 1
                    ellipsize = TextUtils.TruncateAt.END
                    includeFontPadding = false
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                }
            )

            when (mode) {
                Screen.Planner -> {
                    addView(iconButton(R.drawable.ic_search, c.search) { showSearchDialog() })
                    addView(iconButton(R.drawable.ic_settings, c.settings) {
                        currentScreen = Screen.Settings
                        render()
                    })
                }
                Screen.Detail -> {
                    selectedTaskDetail?.let { task ->
                        if (canWrite(task)) {
                            addView(iconButton(R.drawable.ic_share, c.share) { showShareDialog(task.toShareTarget()) })
                            addView(iconButton(R.drawable.ic_edit, c.edit) { showTaskDialog(task) })
                            addView(iconButton(R.drawable.ic_more_horiz, c.details) { showTaskActions(task) })
                        }
                    }
                }
                Screen.IdeaDetail -> {
                    selectedIdeaDetail?.let { idea ->
                        if (canEditIdea(idea)) {
                            addView(iconButton(R.drawable.ic_edit, c.edit) { showIdeaDialog(idea.folderId, idea) })
                            addView(iconButton(R.drawable.ic_more_horiz, c.details) { showIdeaActions(idea) })
                        }
                        addView(iconButton(R.drawable.ic_add, c.addNote) { showIdeaNoteDialog(idea) })
                    }
                }
                Screen.NoteDetail -> {
                    selectedNoteDetail?.let { note ->
                        if (canWrite(note)) {
                            addView(iconButton(R.drawable.ic_edit, c.edit) { showNoteDialog(note.folderId, note) })
                            addView(iconButton(R.drawable.ic_more_horiz, c.details) { showNoteActions(note) })
                        }
                    }
                }
                Screen.Settings -> Unit
                Screen.Auth -> Unit
            }
        }
    }

    private fun folderRow(folder: PlanningFolder, indentLevel: Int): View {
        val c = copy()
        val folderGoals = goalsForFolder(folder.id, includeShared = folder.shared)
        val totalTasks = folderGoals.sumOf { tasksForGoal(it.id, includeShared = folder.shared || it.shared).size }
        val doneTasks = folderGoals.sumOf { goal -> tasksForGoal(goal.id, includeShared = folder.shared || goal.shared).count { isDone(it) } }
        val ideaCount = ideasForFolder(folder.id, includeShared = folder.shared).size
        val noteCount = notesForFolder(folder.id, includeShared = folder.shared).size
        val childCount = childFoldersForFolder(folder.id, includeShared = folder.shared).size
        val dragPayload = EntityDragPayload("folder", folder.id, folder.name)
        return hierarchyContainer(indentLevel = indentLevel, heightDp = 56, selected = false).apply {
            addView(
                iconButton(
                    if (folder.id in collapsedFolderIds) R.drawable.ic_chevron_right else R.drawable.ic_chevron_down,
                    folder.name
                ) {
                    if (folder.id in collapsedFolderIds) collapsedFolderIds.remove(folder.id) else collapsedFolderIds.add(folder.id)
                    render()
                }
            )
            addView(iconView(R.drawable.ic_folder))
            addView(rowText(folder.name, folder.description, weight = 1f, titleSize = 16f, titleStyle = Typeface.BOLD).apply {
                setOnClickListener {
                    selectedFolderId = folder.id
                    selectedGoalId = null
                    selectedTaskId = null
                    selectedTaskDetail = null
                    selectedIdeaId = null
                    selectedIdeaDetail = null
                    showFolderDetails(folder)
                }
                if (canWrite(folder)) enableEntityDragSource(dragPayload)
            })
            addView(counterText(listOfNotNull(
                if (totalTasks == 0) "0" else "$doneTasks/$totalTasks",
                childCount.takeIf { it > 0 }?.let { "${c.folder}:$it" },
                ideaCount.takeIf { it > 0 }?.let { "${c.idea}:$it" },
                noteCount.takeIf { it > 0 }?.let { "${c.notes}:$it" }
            ).joinToString(" ")))
            if (canWrite(folder)) {
                addView(iconButton(R.drawable.ic_more_horiz, c.details) { showFolderActions(folder) })
                enableEntityDragSource(dragPayload)
            }
            enableFolderDropTarget(folder)
        }
    }

    private fun goalRow(goal: PlanningGoal, shared: Boolean, indentLevel: Int): View {
        val c = copy()
        val goalTasks = tasksForGoal(goal.id, includeShared = shared)
        val doneTasks = goalTasks.count { isDone(it) }
        val dragPayload = EntityDragPayload("goal", goal.id, goal.name)
        return hierarchyContainer(indentLevel = indentLevel, heightDp = 52, selected = false).apply {
            addView(
                iconButton(
                    if (goal.id in collapsedGoalIds) R.drawable.ic_chevron_right else R.drawable.ic_chevron_down,
                    goal.name
                ) {
                    if (goal.id in collapsedGoalIds) collapsedGoalIds.remove(goal.id) else collapsedGoalIds.add(goal.id)
                    render()
                }
            )
            addView(iconView(R.drawable.ic_target))
            addView(rowText(goal.name, goal.description, weight = 1f, titleSize = 15f, titleStyle = Typeface.BOLD).apply {
                setOnClickListener {
                    selectedGoalId = goal.id
                    selectedFolderId = goal.folderId.takeIf { it.isNotBlank() } ?: selectedFolderId
                    selectedTaskId = null
                    selectedTaskDetail = null
                    selectedIdeaId = null
                    selectedIdeaDetail = null
                    showGoalDetails(goal)
                }
                if (canWrite(goal)) enableEntityDragSource(dragPayload)
            })
            addView(counterText(if (goalTasks.isEmpty()) "0" else "$doneTasks/${goalTasks.size}"))
            if (canWrite(goal)) {
                addView(iconButton(R.drawable.ic_more_horiz, c.details) { showGoalActions(goal) })
                enableEntityDragSource(dragPayload)
            }
            enableGoalDropTarget(goal)
        }
    }

    private fun taskRow(task: PlanningTask, indentLevel: Int): View {
        val c = copy()
        val dragPayload = EntityDragPayload("task", task.id, task.title)
        return hierarchyContainer(indentLevel = indentLevel, heightDp = 48, selected = task.id == selectedTaskId).apply {
            addView(
                iconButton(
                    if (isDone(task)) R.drawable.ic_check_circle else R.drawable.ic_radio_button_unchecked,
                    localizedStatus(task.status)
                ) {
                    toggleTaskDone(task)
                }
            )
            addView(markerDot(taskTypeColor(task), taskTypeA11y(task)))
            addView(rowText(task.title, "", weight = 1f, titleSize = 15.5f, titleStyle = Typeface.NORMAL).apply {
                setOnClickListener { openTaskDetail(task.id) }
                if (canWrite(task)) enableEntityDragSource(dragPayload)
            })
            dueChip(task)?.let { addView(it) }
            addView(counterText("${c.priorityShort}${task.priority}"))
            if (canWrite(task)) {
                addView(iconButton(R.drawable.ic_more_horiz, c.details) { showTaskActions(task) })
                enableEntityDragSource(dragPayload)
            }
        }
    }

    private fun ideaRow(idea: PlanningIdea, indentLevel: Int): View {
        val c = copy()
        val dragPayload = EntityDragPayload("idea", idea.id, idea.title)
        return hierarchyContainer(indentLevel = indentLevel, heightDp = 48, selected = idea.id == selectedIdeaId).apply {
            addView(iconView(R.drawable.ic_radio_button_unchecked, sizeDp = 24, tint = Ui.INFO))
            addView(markerDot(Ui.INFO, c.idea, sizeDp = 7))
            addView(rowText(idea.title, c.idea, weight = 1f, titleSize = 15.5f, titleStyle = Typeface.BOLD).apply {
                setOnClickListener { openIdeaDetail(idea.id) }
                if (canWrite(idea)) enableEntityDragSource(dragPayload)
            })
            addView(counterText(ideaNotesForIdea(idea.id).size.toString()))
            if (canWrite(idea)) enableEntityDragSource(dragPayload)
        }
    }

    private fun noteRow(note: PlanningNote, indentLevel: Int): View {
        val c = copy()
        val dragPayload = EntityDragPayload("note", note.id, note.title)
        return hierarchyContainer(indentLevel = indentLevel, heightDp = 38, selected = false).apply {
            addView(iconView(R.drawable.ic_content_copy, sizeDp = 24, tint = Ui.AMBER))
            addView(rowText(note.title, note.body, weight = 1f, titleSize = 15.5f, titleStyle = Typeface.BOLD).apply {
                setOnClickListener { openNoteDetail(note.id) }
                if (canWrite(note)) enableEntityDragSource(dragPayload)
            })
            if (canWrite(note)) {
                addView(iconButton(R.drawable.ic_more_horiz, c.details) { showNoteActions(note) })
                enableEntityDragSource(dragPayload)
            }
        }
    }

    private fun View.enableEntityDragSource(payload: EntityDragPayload) {
        isLongClickable = false
        isClickable = true
        val longPressTimeout = ViewConfiguration.getLongPressTimeout().toLong()
        setOnTouchListener { source, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    val state = ManualDragState(
                        payload = payload,
                        source = source,
                        downRawX = event.rawX,
                        downRawY = event.rawY,
                        downAt = event.eventTime,
                        currentRawX = event.rawX,
                        currentRawY = event.rawY
                    )
                    manualDragState = state
                    requestParentDragInterception(source, disallow = true)
                    dragHandler.postDelayed({
                        if (manualDragState === state && !state.active) {
                            beginManualEntityDrag(state)
                        }
                    }, longPressTimeout)
                    false
                }
                MotionEvent.ACTION_MOVE -> {
                    val state = manualDragState?.takeIf { it.source === source && it.payload == payload }
                        ?: return@setOnTouchListener false
                    state.currentRawX = event.rawX
                    state.currentRawY = event.rawY
                    if (!state.active && event.eventTime - state.downAt >= longPressTimeout) {
                        beginManualEntityDrag(state)
                    }
                    state.active
                }
                MotionEvent.ACTION_UP -> {
                    val state = manualDragState?.takeIf { it.source === source && it.payload == payload }
                        ?: return@setOnTouchListener false
                    dragHandler.removeCallbacksAndMessages(null)
                    requestParentDragInterception(source, disallow = false)
                    manualDragState = null
                    state.source.alpha = 1f
                    state.source.isPressed = false
                    state.currentRawX = event.rawX
                    state.currentRawY = event.rawY
                    if (state.active) {
                        val handled = handleManualDrop(state.payload, event.rawX.toInt(), event.rawY.toInt())
                        if (!handled) showInvalidDrop()
                        true
                    } else {
                        false
                    }
                }
                MotionEvent.ACTION_CANCEL -> {
                    val state = manualDragState?.takeIf { it.source === source && it.payload == payload }
                    dragHandler.removeCallbacksAndMessages(null)
                    requestParentDragInterception(source, disallow = false)
                    manualDragState = null
                    state?.source?.alpha = 1f
                    state?.source?.isPressed = false
                    state?.active == true
                }
                else -> false
            }
        }
    }

    private fun beginManualEntityDrag(state: ManualDragState) {
        state.active = true
        state.source.isPressed = true
        state.source.alpha = 0.7f
        requestParentDragInterception(state.source, disallow = true)
        Toast.makeText(this, copy().dragMoveStarted, Toast.LENGTH_SHORT).show()
        Log.d(TAG, "manual-dnd-start type=${state.payload.type} id=${state.payload.id}")
    }

    private fun requestParentDragInterception(source: View, disallow: Boolean) {
        var parent = source.parent
        while (parent != null) {
            parent.requestDisallowInterceptTouchEvent(disallow)
            parent = parent.parent
        }
    }

    private fun startEntityDrag(source: View, payload: EntityDragPayload): Boolean {
        val data = ClipData.newPlainText("rocketflow/entity", "${payload.type}:${payload.id}")
        val shadow = View.DragShadowBuilder(source)
        val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            source.startDragAndDrop(data, shadow, payload, 0)
        } else {
            @Suppress("DEPRECATION")
            source.startDrag(data, shadow, payload, 0)
        }
        if (started) {
            Toast.makeText(this, copy().dragMoveStarted, Toast.LENGTH_SHORT).show()
        }
        return started
    }

    private fun View.enableFolderDropTarget(folder: PlanningFolder) {
        tag = EntityDropTarget("folder", folder.id)
        setOnDragListener { _, event ->
            val payload = event.entityDragPayload() ?: return@setOnDragListener false
            when (event.action) {
                DragEvent.ACTION_DRAG_STARTED -> true
                DragEvent.ACTION_DROP -> {
                    handleFolderDrop(folder, payload)
                    true
                }
                DragEvent.ACTION_DRAG_ENDED -> true
                else -> true
            }
        }
    }

    private fun View.enableGoalDropTarget(goal: PlanningGoal) {
        tag = EntityDropTarget("goal", goal.id)
        setOnDragListener { _, event ->
            val payload = event.entityDragPayload() ?: return@setOnDragListener false
            when (event.action) {
                DragEvent.ACTION_DRAG_STARTED -> true
                DragEvent.ACTION_DROP -> {
                    handleGoalDrop(goal, payload)
                    true
                }
                DragEvent.ACTION_DRAG_ENDED -> true
                else -> true
            }
        }
    }

    private fun DragEvent.entityDragPayload(): EntityDragPayload? {
        (localState as? EntityDragPayload)?.let { return it }
        val text = clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString() ?: return null
        val type = text.substringBefore(":", missingDelimiterValue = "")
        val id = text.substringAfter(":", missingDelimiterValue = "")
        if (type.isBlank() || id.isBlank()) return null
        return EntityDragPayload(type, id, id)
    }

    private fun handleManualDrop(payload: EntityDragPayload, rawX: Int, rawY: Int): Boolean {
        val target = findDropTargetAt(window.decorView, rawX, rawY)
        Log.d(TAG, "manual-dnd-drop payload=${payload.type}:${payload.id} raw=$rawX,$rawY target=${target?.type}:${target?.id}")
        target ?: return false
        return when (target.type) {
            "folder" -> {
                val folder = findFolder(target.id) ?: return false
                handleFolderDrop(folder, payload)
                true
            }
            "goal" -> {
                val goal = findGoal(target.id) ?: return false
                handleGoalDrop(goal, payload)
                true
            }
            else -> false
        }
    }

    private fun findDropTargetAt(view: View, rawX: Int, rawY: Int): EntityDropTarget? {
        if (view.visibility != View.VISIBLE) return null
        val bounds = Rect()
        if (!view.getGlobalVisibleRect(bounds) || !bounds.contains(rawX, rawY)) return null
        if (view is ViewGroup) {
            for (index in view.childCount - 1 downTo 0) {
                findDropTargetAt(view.getChildAt(index), rawX, rawY)?.let { return it }
            }
        }
        return view.tag as? EntityDropTarget
    }

    private fun handleFolderDrop(targetFolder: PlanningFolder, payload: EntityDragPayload) {
        lastDragDropHandledAt = System.currentTimeMillis()
        when (payload.type) {
            "folder" -> {
                val source = findFolder(payload.id)
                if (source == null || !canMoveFolderToFolder(source, targetFolder)) {
                    showInvalidDrop()
                    return
                }
                Log.d(TAG, "manual-dnd-move folder ${source.id} -> folder ${targetFolder.id}")
                runPlanningAction { session -> planningRepository.moveFolder(session, source, targetFolder.id) }
            }
            "goal" -> {
                val source = findGoal(payload.id)
                if (source == null || !canWrite(source) || !canWrite(targetFolder)) {
                    showInvalidDrop()
                    return
                }
                Log.d(TAG, "manual-dnd-move goal ${source.id} -> folder ${targetFolder.id}")
                runPlanningAction { session -> planningRepository.moveGoal(session, source, targetFolder.id) }
            }
            "idea" -> {
                val source = findIdea(payload.id)
                if (source == null || !canWrite(source) || !canWrite(targetFolder)) {
                    showInvalidDrop()
                    return
                }
                Log.d(TAG, "manual-dnd-move idea ${source.id} -> folder ${targetFolder.id}")
                runPlanningAction { session -> planningRepository.moveIdea(session, source, targetFolder.id) }
            }
            "note" -> {
                val source = findNote(payload.id)
                if (source == null || !canWrite(source) || !canWrite(targetFolder)) {
                    showInvalidDrop()
                    return
                }
                Log.d(TAG, "manual-dnd-move note ${source.id} -> folder ${targetFolder.id}")
                runPlanningAction { session -> planningRepository.moveNote(session, source, targetFolder.id) }
            }
            else -> showInvalidDrop()
        }
    }

    private fun handleGoalDrop(targetGoal: PlanningGoal, payload: EntityDragPayload) {
        lastDragDropHandledAt = System.currentTimeMillis()
        val source = if (payload.type == "task") findTask(payload.id) else null
        if (source == null || !canWrite(source) || !canWrite(targetGoal) || source.goalId == targetGoal.id) {
            showInvalidDrop()
            return
        }
        Log.d(TAG, "manual-dnd-move task ${source.id} -> goal ${targetGoal.id}")
        runPlanningAction { session -> planningRepository.moveTask(session, source, targetGoal.id) }
    }

    private fun canMoveFolderToFolder(source: PlanningFolder, target: PlanningFolder): Boolean {
        return canWrite(source) &&
            canWrite(target) &&
            source.id != target.id &&
            !isFolderDescendant(candidateFolderId = target.id, ancestorFolderId = source.id)
    }

    private fun isFolderDescendant(candidateFolderId: String, ancestorFolderId: String): Boolean {
        var current = findFolder(candidateFolderId)
        val seen = mutableSetOf<String>()
        while (current != null && current.id !in seen) {
            if (current.parentFolderId == ancestorFolderId) return true
            seen += current.id
            current = findFolder(current.parentFolderId)
        }
        return false
    }

    private fun showInvalidDrop() {
        Log.d(TAG, "manual-dnd-invalid-drop")
        message = copy().cannotMoveHere
        Toast.makeText(this, copy().cannotMoveHere, Toast.LENGTH_SHORT).show()
        render()
    }

    private fun hierarchyContainer(indentLevel: Int, heightDp: Int, selected: Boolean): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16 + indentLevel * 18), 0, dp(4), 0)
            background = if (selected) roundedDrawable(Ui.ACCENT_SOFT, radiusDp = 6) else roundedDrawable("#00FFFFFF", radiusDp = 0)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(heightDp)
            ).apply {
                topMargin = if (selected) dp(2) else 0
                bottomMargin = if (selected) dp(2) else 0
            }
        }
    }

    private fun rowText(
        title: String,
        subtitle: String,
        weight: Float,
        titleSize: Float = 15.5f,
        titleStyle: Int = Typeface.NORMAL
    ): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, weight)
            addView(
                TextView(context).apply {
                    text = title
                    textSize = titleSize
                    setTextColor(color(Ui.TEXT))
                    setTypeface(typeface, titleStyle)
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    includeFontPadding = false
                }
            )
            if (subtitle.isNotBlank()) {
                addView(
                    TextView(context).apply {
                        text = subtitle
                        textSize = 12.5f
                        setTextColor(color(Ui.MUTED))
                        maxLines = 1
                        ellipsize = TextUtils.TruncateAt.END
                        includeFontPadding = false
                        setPadding(0, dp(3), 0, 0)
                    }
                )
            }
        }
    }

    private fun counterText(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 12.5f
            setTextColor(color(Ui.MUTED))
            gravity = Gravity.CENTER
            minWidth = dp(34)
            includeFontPadding = false
        }
    }

    private fun rowDivider(indentLevel: Int): View {
        return View(this).apply {
            setBackgroundColor(color(Ui.HAIRLINE))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(1)
            ).apply {
                marginStart = dp(16 + indentLevel * 18)
            }
        }
    }

    private fun markerDot(colorHex: String, description: String, sizeDp: Int = 8): View {
        return View(this).apply {
            contentDescription = description
            background = ovalDrawable(colorHex)
            layoutParams = LinearLayout.LayoutParams(dp(sizeDp), dp(sizeDp)).apply {
                marginEnd = dp(10)
            }
        }
    }

    private fun dueChip(task: PlanningTask): TextView? {
        val due = task.dueTime ?: task.plannedTime ?: return null
        val label = formatDateTime(due)
        return TextView(this).apply {
            text = label
            contentDescription = "${copy().due}: $label"
            textSize = 12f
            setTextColor(color(Ui.MUTED))
            gravity = Gravity.CENTER
            includeFontPadding = false
            background = roundedDrawable("#00FFFFFF", strokeColorHex = Ui.HAIRLINE, radiusDp = 8)
            setPadding(dp(8), 0, dp(8), 0)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(26)).apply {
                marginEnd = dp(10)
                width = LinearLayout.LayoutParams.WRAP_CONTENT
            }
        }
    }

    private fun hintRow(text: String, indentLevel: Int): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 13f
            setTextColor(color(Ui.MUTED))
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16 + indentLevel * 18), 0, dp(16), 0)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(44)
            )
        }
    }

    private fun ideaHistoryRow(idea: PlanningIdea, note: IdeaNote): LinearLayout {
        val author = note.authorName ?: note.authorEmail ?: copy().creator
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(10), 0, dp(10))
            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    addView(
                        TextView(context).apply {
                            text = "$author - ${formatDateTime(note.updatedAt)}"
                            textSize = 12.5f
                            setTextColor(color(Ui.MUTED))
                            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                        }
                    )
                    if (canEditIdeaNote(idea, note)) {
                        addView(iconButton(R.drawable.ic_edit, copy().editNote) { showIdeaNoteDialog(idea, note) })
                    }
                }
            )
            addView(
                TextView(context).apply {
                    text = note.body
                    textSize = 15f
                    setTextColor(color(Ui.TEXT))
                    setLineSpacing(dp(2).toFloat(), 1f)
                    setPadding(0, dp(4), 0, 0)
                }
            )
        }
    }

    private fun emptyPlannerView(): LinearLayout {
        val c = copy()
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(96), dp(24), 0)
            addView(iconView(R.drawable.ic_folder, sizeDp = 42, tint = Ui.ACCENT))
            addView(
                TextView(context).apply {
                    text = c.nothingHere
                    textSize = 20f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(color(Ui.TEXT))
                    includeFontPadding = false
                    gravity = Gravity.CENTER
                    setPadding(0, dp(18), 0, 0)
                }
            )
            addView(
                TextView(context).apply {
                    text = c.emptyBody
                    textSize = 14f
                    setTextColor(color(Ui.MUTED))
                    gravity = Gravity.CENTER
                    setLineSpacing(dp(2).toFloat(), 1f)
                    setPadding(0, dp(8), 0, dp(16))
                }
            )
            addView(textButton(c.newFolder, primary = true) { showFolderDialog(null) })
        }
    }

    private fun emptyDetailView(): LinearLayout {
        val c = copy()
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(20), dp(110), dp(20), 0)
            addView(iconView(R.drawable.ic_radio_button_unchecked, sizeDp = 40, tint = Ui.ACCENT))
            addView(
                TextView(context).apply {
                    text = c.selectTask
                    textSize = 20f
                    setTextColor(color(Ui.TEXT))
                    setTypeface(typeface, Typeface.BOLD)
                    setPadding(0, dp(16), 0, 0)
                }
            )
        }
    }

    private fun showCreateDialog() {
        val c = copy()
        val dialogContent = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            addView(sheetHeader(c.create))
        }

        val dialog = AlertDialog.Builder(this).setView(dialogContent).create()
        dialogContent.addView(createOption(R.drawable.ic_folder, c.folder) {
            dialog.dismiss()
            showFolderDialog(null)
        })
        dialogContent.addView(createOption(R.drawable.ic_target, c.goal) {
            dialog.dismiss()
            showGoalFolderDialog()
        })
        dialogContent.addView(createOption(R.drawable.ic_radio_button_unchecked, c.task) {
            dialog.dismiss()
            showTaskTargetDialog()
        })
        dialogContent.addView(createOption(R.drawable.ic_radio_button_unchecked, c.idea) {
            dialog.dismiss()
            showIdeaFolderDialog()
        })
        dialogContent.addView(createOption(R.drawable.ic_content_copy, c.note) {
            dialog.dismiss()
            showNoteFolderDialog()
        })
        dialog.show()
    }

    private fun showGoalFolderDialog() {
        val c = copy()
        val availableFolders = (folders + sharedFolders).filter { canWrite(it) }
        if (availableFolders.isEmpty()) {
            AlertDialog.Builder(this)
                .setTitle(c.newGoal)
                .setMessage(c.folderFirst)
                .setNegativeButton(c.cancel, null)
                .setPositiveButton(c.newFolder) { _, _ -> window.decorView.post { showFolderDialog(null) } }
                .show()
            return
        }

        lateinit var dialog: AlertDialog
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            addView(sheetHeader(c.newGoal))
            addView(dialogContextLine(c.folder, c.folderFirst))
        }
        availableFolders.forEach { folder ->
            content.addView(selectionOption(R.drawable.ic_folder, folder.name, folder.description) {
                dialog.dismiss()
                selectedFolderId = folder.id
                window.decorView.postDelayed({ showGoalDialog(null, folder.id) }, 120)
            })
        }
        content.addView(selectionOption(R.drawable.ic_folder, c.newFolder, c.newGoal) {
            dialog.dismiss()
            window.decorView.postDelayed(
                {
                    showFolderDialog(null) { folder ->
                        selectedFolderId = folder.id
                        showGoalDialog(null, folder.id)
                    }
                },
                120
            )
        })
        dialog = AlertDialog.Builder(this)
            .setView(content)
            .create()
        dialog.show()
    }

    private fun showTaskTargetDialog() {
        val c = copy()
        val availableGoals = goals.filter { goal -> folders.any { it.id == goal.folderId } } +
            sharedGoals.filter { goal -> canWrite(goal) }
        if (availableGoals.isEmpty()) {
            showTaskNeedsGoalDialog()
            return
        }

        lateinit var dialog: AlertDialog
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            addView(sheetHeader(c.newTask))
            addView(dialogContextLine(c.goal, c.taskNeedsGoal))
        }
        availableGoals.forEach { goal ->
            val folderName = folders.firstOrNull { it.id == goal.folderId }?.name
                ?: sharedFolders.firstOrNull { it.id == goal.folderId }?.name
                ?: c.folder
            content.addView(selectionOption(R.drawable.ic_target, goal.name, folderName) {
                dialog.dismiss()
                selectedFolderId = goal.folderId
                selectedGoalId = goal.id
                window.decorView.postDelayed({ showTaskDialog(null, goal.id) }, 120)
            })
        }
        content.addView(selectionOption(R.drawable.ic_target, c.newGoal, c.folder) {
            dialog.dismiss()
            window.decorView.postDelayed({ showGoalFolderDialog() }, 120)
        })
        dialog = AlertDialog.Builder(this)
            .setView(content)
            .create()
        dialog.show()
    }

    private fun showTaskNeedsGoalDialog() {
        val c = copy()
        AlertDialog.Builder(this)
            .setTitle(c.newTask)
            .setMessage(c.taskNeedsGoal)
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.newGoal) { _, _ -> window.decorView.post { showGoalFolderDialog() } }
            .show()
    }

    private fun sheetHeader(title: String): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14), dp(8), dp(4), dp(8))
            addView(
                TextView(context).apply {
                    text = title
                    textSize = 20f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(color(Ui.TEXT))
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                }
            )
        }
    }

    private fun createOption(icon: Int, label: String, onClick: () -> Unit): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14), 0, dp(14), 0)
            minimumHeight = dp(48)
            addView(iconView(icon, sizeDp = 24, tint = Ui.ACCENT))
            addView(
                TextView(context).apply {
                    text = label
                    textSize = 16f
                    setTextColor(color(Ui.TEXT))
                    setPadding(dp(14), 0, 0, 0)
                }
            )
            setOnClickListener { onClick() }
        }
    }

    private fun selectionOption(icon: Int, title: String, subtitle: String, onClick: () -> Unit): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14), dp(8), dp(14), dp(8))
            minimumHeight = dp(56)
            addView(iconView(icon, sizeDp = 24, tint = Ui.ACCENT))
            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                    addView(
                        TextView(context).apply {
                            text = title
                            textSize = 16f
                            setTextColor(color(Ui.TEXT))
                            setTypeface(typeface, Typeface.BOLD)
                            maxLines = 1
                            ellipsize = TextUtils.TruncateAt.END
                        }
                    )
                    if (subtitle.isNotBlank()) {
                        addView(
                            TextView(context).apply {
                                text = subtitle
                                textSize = 13f
                                setTextColor(color(Ui.MUTED))
                                maxLines = 2
                                ellipsize = TextUtils.TruncateAt.END
                            }
                        )
                    }
                }
            )
            background = roundedDrawable("#00FFFFFF", radiusDp = 8)
            isClickable = true
            setOnClickListener { onClick() }
        }
    }

    private fun showFolderActions(folder: PlanningFolder) {
        val c = copy()
        AlertDialog.Builder(this)
            .setTitle(folder.name)
            .setItems(arrayOf(c.details, c.add, c.share, c.edit, c.move, c.clone, c.links, c.delete)) { _, which ->
                when (which) {
                    0 -> showFolderDetails(folder)
                    1 -> showFolderAddMenu(folder)
                    2 -> showShareDialog(folder.toShareTarget())
                    3 -> showFolderDialog(folder)
                    4 -> showMoveFolderDialog(folder)
                    5 -> showCloneFolderDialog(folder)
                    else -> confirmDelete(folder.name, deleteFolderMessage(folder)) { deleteFolder(folder) }
                }
            }
            .show()
    }

    private fun showGoalActions(goal: PlanningGoal) {
        val c = copy()
        AlertDialog.Builder(this)
            .setTitle(goal.name)
            .setItems(arrayOf(c.details, c.add, c.share, c.edit, c.move, c.clone, c.delete)) { _, which ->
                when (which) {
                    0 -> showGoalDetails(goal)
                    1 -> showTaskDialog(null, goal.id)
                    2 -> showShareDialog(goal.toShareTarget())
                    3 -> showGoalDialog(goal)
                    4 -> showMoveGoalDialog(goal)
                    5 -> showCloneGoalDialog(goal)
                    6 -> showCreateLinkDialog("goal", goal.id)
                    else -> confirmDelete(goal.name, deleteGoalMessage(goal)) { deleteGoal(goal) }
                }
            }
            .show()
    }

    private fun showFolderDetails(folder: PlanningFolder) {
        val c = copy()
        val folderGoals = goalsForFolder(folder.id)
        val taskCount = folderGoals.sumOf { tasksForGoal(it.id).size }
        lateinit var dialog: AlertDialog
        val actions = if (canWrite(folder)) {
            detailDialogActions(
                c.cancel to { dialog.dismiss() },
                c.add to {
                    dialog.dismiss()
                    showFolderAddMenu(folder)
                },
                c.edit to {
                    dialog.dismiss()
                    showFolderDialog(folder)
                }
            )
        } else {
            detailDialogActions(c.cancel to { dialog.dismiss() })
        }
        dialog = AlertDialog.Builder(this)
            .setTitle(folder.name)
            .setView(
                dialogForm(
                    detailDialogText(c.notes, folder.description.ifBlank { c.noDate }),
                    detailDialogText(c.goal, folderGoals.size.toString()),
                    detailDialogText(c.task, taskCount.toString()),
                    actions
                )
            )
            .create()
        dialog.show()
    }

    private fun showGoalDetails(goal: PlanningGoal) {
        val c = copy()
        val folder = folders.firstOrNull { it.id == goal.folderId }
        val taskCount = tasksForGoal(goal.id).size
        val goalLinks = linksForEntity("goal", goal.id)
        val linkedNotes = goalLinks.mapNotNull { linkedNoteFor("goal", goal.id, it) }.distinctBy { it.id }
        lateinit var dialog: AlertDialog
        val actions = if (canWrite(goal)) {
            detailDialogActions(
                c.cancel to { dialog.dismiss() },
                c.add to {
                    dialog.dismiss()
                    showTaskDialog(null, goal.id)
                },
                c.edit to {
                    dialog.dismiss()
                    showGoalDialog(goal)
                }
            )
        } else {
            detailDialogActions(c.cancel to { dialog.dismiss() })
        }
        dialog = AlertDialog.Builder(this)
            .setTitle(goal.name)
            .setView(
                dialogForm(
                    detailDialogText(c.folder, folder?.name ?: c.folder),
                    detailDialogText(c.notes, goal.description.ifBlank { c.noDate }),
                    detailDialogText(c.status, localizedStatus(goal.status)),
                    detailDialogText(c.task, taskCount.toString()),
                    detailDialogText(c.links, goalLinks.size.toString()),
                    detailDialogText(c.linkedNotes, linkedNotes.size.toString()),
                    actions
                )
            )
            .create()
        dialog.show()
    }

    private fun showTaskActions(task: PlanningTask) {
        val c = copy()
        AlertDialog.Builder(this)
            .setTitle(task.title)
            .setItems(arrayOf(c.share, c.edit, c.reschedule, c.move, c.clone, c.links, c.delete)) { _, which ->
                when (which) {
                    0 -> showShareDialog(task.toShareTarget())
                    1 -> showTaskDialog(task)
                    2 -> showRescheduleDialog(task)
                    3 -> showMoveTaskDialog(task)
                    4 -> showCloneTaskDialog(task)
                    5 -> showCreateLinkDialog("task", task.id)
                    else -> confirmDelete(task.title) { deleteTask(task) }
                }
            }
            .show()
    }

    private fun showIdeaActions(idea: PlanningIdea) {
        val c = copy()
        AlertDialog.Builder(this)
            .setTitle(idea.title)
            .setItems(arrayOf(c.edit, c.move, c.clone, c.links)) { _, which ->
                when (which) {
                    0 -> showIdeaDialog(idea.folderId, idea)
                    1 -> showMoveIdeaDialog(idea)
                    2 -> showCloneIdeaDialog(idea)
                    else -> showCreateLinkDialog("idea", idea.id)
                }
            }
            .show()
    }

    private fun showNoteActions(note: PlanningNote) {
        val c = copy()
        AlertDialog.Builder(this)
            .setTitle(note.title)
            .setItems(arrayOf(c.edit, c.move, c.clone, c.links, c.delete)) { _, which ->
                when (which) {
                    0 -> showNoteDialog(note.folderId, note)
                    1 -> showMoveNoteDialog(note)
                    2 -> showCloneNoteDialog(note)
                    3 -> showCreateLinkDialog("note", note.id)
                    else -> confirmDelete(note.title) { deleteNote(note) }
                }
            }
            .show()
    }

    private fun showFolderAddMenu(folder: PlanningFolder) {
        val c = copy()
        AlertDialog.Builder(this)
            .setTitle(folder.name)
            .setItems(arrayOf(c.folder, c.goal, c.idea, c.note)) { _, which ->
                when (which) {
                    0 -> showFolderDialog(null, parentFolderId = folder.id)
                    1 -> showGoalDialog(null, folder.id)
                    2 -> showIdeaDialog(folder.id)
                    else -> showNoteDialog(folder.id)
                }
            }
            .show()
    }

    private fun showMoveFolderDialog(folder: PlanningFolder) = showFolderTargetDialog(copy().move, excludeFolderId = folder.id) { target ->
        runPlanningAction { planningRepository.moveFolder(it, folder, target.id) }
    }

    private fun showCloneFolderDialog(folder: PlanningFolder) = showFolderTargetDialog(copy().clone, excludeFolderId = folder.id) { target ->
        runPlanningAction { planningRepository.cloneFolder(it, folder, target.id) }
    }

    private fun showMoveGoalDialog(goal: PlanningGoal) = showFolderTargetDialog(copy().move) { target ->
        runPlanningAction { planningRepository.moveGoal(it, goal, target.id) }
    }

    private fun showCloneGoalDialog(goal: PlanningGoal) = showFolderTargetDialog(copy().clone) { target ->
        runPlanningAction { planningRepository.cloneGoal(it, goal, target.id) }
    }

    private fun showMoveIdeaDialog(idea: PlanningIdea) = showFolderTargetDialog(copy().move) { target ->
        runPlanningAction { planningRepository.moveIdea(it, idea, target.id) }
    }

    private fun showCloneIdeaDialog(idea: PlanningIdea) = showFolderTargetDialog(copy().clone) { target ->
        runPlanningAction { planningRepository.cloneIdea(it, idea, target.id) }
    }

    private fun showMoveNoteDialog(note: PlanningNote) = showFolderTargetDialog(copy().move) { target ->
        runPlanningAction { planningRepository.moveNote(it, note, target.id) }
    }

    private fun showCloneNoteDialog(note: PlanningNote) = showFolderTargetDialog(copy().clone) { target ->
        runPlanningAction { planningRepository.cloneNote(it, note, target.id) }
    }

    private fun showMoveTaskDialog(task: PlanningTask) = showGoalTargetDialog(copy().move, excludeGoalId = task.goalId) { target ->
        runPlanningAction { planningRepository.moveTask(it, task, target.id) }
    }

    private fun showCloneTaskDialog(task: PlanningTask) = showGoalTargetDialog(copy().clone) { target ->
        runPlanningAction { planningRepository.cloneTask(it, task, target.id) }
    }

    private fun showFolderTargetDialog(title: String, excludeFolderId: String? = null, onSelect: (PlanningFolder) -> Unit) {
        val available = (folders + sharedFolders)
            .filter { canWrite(it) && it.id != excludeFolderId && it.parentFolderId != excludeFolderId }
        if (available.isEmpty()) {
            message = copy().folderFirst
            render()
            return
        }
        lateinit var dialog: AlertDialog
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            addView(sheetHeader(title))
        }
        available.forEach { folder ->
            content.addView(selectionOption(R.drawable.ic_folder, folder.name, folderPath(folder)) {
                dialog.dismiss()
                onSelect(folder)
            })
        }
        dialog = AlertDialog.Builder(this).setView(content).create()
        dialog.show()
    }

    private fun showGoalTargetDialog(title: String, excludeGoalId: String? = null, onSelect: (PlanningGoal) -> Unit) {
        val available = (goals + sharedGoals).filter { canWrite(it) && it.id != excludeGoalId }
        if (available.isEmpty()) {
            showTaskNeedsGoalDialog()
            return
        }
        lateinit var dialog: AlertDialog
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            addView(sheetHeader(title))
        }
        available.forEach { goal ->
            content.addView(selectionOption(R.drawable.ic_target, goal.name, folderPath(findFolder(goal.folderId))) {
                dialog.dismiss()
                onSelect(goal)
            })
        }
        dialog = AlertDialog.Builder(this).setView(content).create()
        dialog.show()
    }

    private fun runPlanningAction(action: suspend (AuthSession) -> PlanningLoadResult) {
        val session = currentSession ?: return
        setBusy(true)
        message = null
        scope.launch {
            try {
                applyPlanningResult(action(session))
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun showCreateLinkDialog(sourceType: String, sourceId: String) {
        val c = copy()
        val candidates = linkCandidates(sourceType, sourceId)
        if (candidates.isEmpty()) {
            message = c.nothingHere
            render()
            return
        }
        lateinit var dialog: AlertDialog
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            addView(sheetHeader(c.links))
        }
        candidates.forEach { (targetType, targetId, title) ->
            content.addView(selectionOption(iconForEntity(targetType), title, localizedEntityType(targetType)) {
                dialog.dismiss()
                if (sourceType == "task" && targetType == "task") {
                    showRelationTypeDialog(sourceType, sourceId, targetType, targetId)
                } else {
                    createEntityLink(EntityLinkDraft(sourceType, sourceId, targetType, targetId, "related"))
                }
            })
        }
        dialog = AlertDialog.Builder(this).setView(content).create()
        dialog.show()
    }

    private fun showRelationTypeDialog(sourceType: String, sourceId: String, targetType: String, targetId: String) {
        val c = copy()
        AlertDialog.Builder(this)
            .setTitle(c.links)
            .setItems(arrayOf(c.related, c.dependency)) { _, which ->
                createEntityLink(
                    EntityLinkDraft(
                        sourceType = sourceType,
                        sourceId = sourceId,
                        targetType = targetType,
                        targetId = targetId,
                        relationType = if (which == 1) "dependency" else "related"
                    )
                )
            }
            .show()
    }

    private fun createEntityLink(draft: EntityLinkDraft) {
        runPlanningAction { planningRepository.createEntityLink(it, draft) }
    }

    private fun showShareDialog(target: ShareTarget) {
        val c = copy()
        AlertDialog.Builder(this)
            .setTitle("${c.share}: ${target.title}")
            .setItems(arrayOf(c.shareByEmail, c.shareByUserId, c.shareLink)) { _, which ->
                when (which) {
                    0 -> showShareInviteDialog(target, byEmail = true)
                    1 -> showShareInviteDialog(target, byEmail = false)
                    else -> showShareLinksDialog(target)
                }
            }
            .show()
    }

    private fun showShareInviteDialog(target: ShareTarget, byEmail: Boolean) {
        val c = copy()
        val input = dialogInput(
            hint = if (byEmail) c.email else c.userIdField,
            value = "",
            inputPurpose = if (byEmail) TextInputPurpose.Email else TextInputPurpose.Username,
            inputTypeOverride = if (byEmail) emailInputType() else usernameInputType(),
            imeOptionsOverride = EditorInfo.IME_ACTION_DONE
        )
        val fullAccessInput = CheckBox(this).apply {
            text = c.fullAccess
            setTextColor(color(Ui.TEXT))
            textSize = 15f
        }

        AlertDialog.Builder(this)
            .setTitle(if (byEmail) c.shareByEmail else c.shareByUserId)
            .setView(dialogForm(input, fullAccessInput))
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.invite) { _, _ ->
                val value = input.text.toString().trim()
                if (value.isBlank()) {
                    message = if (byEmail) c.email else c.userId
                    render()
                    return@setPositiveButton
                }
                sendShareInvite(target, value, byEmail, fullAccessInput.isChecked)
            }
            .show()
    }

    private fun sendShareInvite(target: ShareTarget, value: String, byEmail: Boolean, fullAccess: Boolean) {
        val session = currentSession ?: return
        setBusy(true)
        message = null
        scope.launch {
            try {
                val result = if (byEmail) {
                    sharingRepository.inviteByEmail(session, target, value, fullAccess)
                } else {
                    sharingRepository.inviteByUserId(session, target, value, fullAccess)
                }
                currentSession = result.session
                message = copy().inviteSent
            } catch (error: Exception) {
                message = sharingError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun showShareLinksDialog(target: ShareTarget) {
        val c = copy()
        val status = TextView(this).apply {
            textSize = 13f
            setTextColor(color(Ui.MUTED))
            setLineSpacing(dp(2).toFloat(), 1f)
            setPadding(dp(14), dp(6), dp(14), dp(4))
        }
        val tokenContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        val linksContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        val fullAccessInput = CheckBox(this).apply {
            text = c.fullAccess
            setTextColor(color(Ui.TEXT))
            textSize = 15f
            setPadding(dp(14), 0, dp(14), 0)
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            addView(fullAccessInput)
            addView(textButton(c.createLink, primary = true) {
                createShareLink(target, status, tokenContainer, linksContainer, fullAccessInput.isChecked)
            })
            addView(status)
            addView(tokenContainer)
            addView(sectionLabel(c.existingLinks))
            addView(linksContainer)
        }

        AlertDialog.Builder(this)
            .setTitle("${c.shareLink}: ${target.title}")
            .setView(
                ScrollView(this).apply {
                    addView(content)
                }
            )
            .setNegativeButton(c.cancel, null)
            .show()

        loadShareLinks(target, status, linksContainer)
    }

    private fun createShareLink(
        target: ShareTarget,
        status: TextView,
        tokenContainer: LinearLayout,
        linksContainer: LinearLayout,
        fullAccess: Boolean
    ) {
        val session = currentSession ?: return
        status.text = copy().loading
        scope.launch {
            try {
                val result = sharingRepository.createLink(session, target, fullAccess = fullAccess)
                currentSession = result.session
                val linkText = shareLinkText(result.value.token)
                status.text = copy().linkCreated
                tokenContainer.removeAllViews()
                tokenContainer.addView(shareCreatedLinkView(linkText))
                loadShareLinks(target, status, linksContainer)
            } catch (error: Exception) {
                status.text = sharingError(error)
            }
        }
    }

    private fun loadShareLinks(target: ShareTarget, status: TextView, linksContainer: LinearLayout) {
        val session = currentSession ?: return
        status.text = copy().loading
        scope.launch {
            try {
                val result = sharingRepository.listLinks(session, target)
                currentSession = result.session
                status.text = ""
                renderShareLinks(result.value, linksContainer)
            } catch (error: Exception) {
                status.text = sharingError(error)
            }
        }
    }

    private fun renderShareLinks(links: List<ShareLink>, container: LinearLayout) {
        val c = copy()
        container.removeAllViews()
        if (links.isEmpty()) {
            container.addView(hintRow(c.noLinks, indentLevel = 0))
            return
        }
        links.forEach { link ->
            container.addView(shareLinkRow(link))
            container.addView(rowDivider(indentLevel = 0))
        }
    }

    private fun shareCreatedLinkView(linkText: String): LinearLayout {
        val c = copy()
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(6), dp(14), dp(4))
            addView(
                TextView(context).apply {
                    text = linkText
                    textSize = 13f
                    setTextColor(color(Ui.TEXT))
                    maxLines = 3
                    ellipsize = TextUtils.TruncateAt.MIDDLE
                    setPadding(0, dp(4), 0, dp(4))
                }
            )
            addView(textButton(c.copyLink, quiet = true) {
                copyToClipboard(c.shareLink, linkText)
            })
        }
    }

    private fun shareLinkRow(link: ShareLink): LinearLayout {
        val c = copy()
        val revoked = link.revokedAt != null || link.status.equals("revoked", ignoreCase = true)
        val status = if (revoked) c.revoked else c.active
        val expires = link.expiresAt?.let(::formatDateTime) ?: c.noExpiry
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(56)
            setPadding(dp(14), 0, dp(4), 0)
            addView(
                rowText(
                    title = status,
                    subtitle = "${c.expires}: $expires",
                    weight = 1f,
                    titleSize = 14.5f,
                    titleStyle = Typeface.BOLD
                )
            )
            if (!revoked) {
                addView(textButton(c.revoke, danger = true) {
                    revokeShareLink(link.id)
                }.apply {
                    layoutParams = LinearLayout.LayoutParams(dp(112), dp(42))
                })
            }
        }
    }

    private fun revokeShareLink(linkId: String) {
        val session = currentSession ?: return
        setBusy(true)
        scope.launch {
            try {
                val result = sharingRepository.revokeLink(session, linkId)
                currentSession = result.session
                message = copy().revoked
            } catch (error: Exception) {
                message = sharingError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun showAcceptShareLinkDialog() {
        val c = copy()
        val input = dialogInput(
            c.tokenField,
            "",
            inputPurpose = TextInputPurpose.Code,
            inputTypeOverride = codeInputType()
        )
        AlertDialog.Builder(this)
            .setTitle(c.acceptLink)
            .setView(dialogForm(input))
            .setNegativeButton(c.cancel, null)
            .setNeutralButton(c.resolve) { _, _ ->
                resolveShareLinkInput(input.text.toString())
            }
            .setPositiveButton(c.accept) { _, _ ->
                acceptShareLinkInput(input.text.toString())
            }
            .show()
    }

    private fun resolveShareLinkInput(raw: String) {
        val session = currentSession ?: return
        val token = extractShareToken(raw)
        if (token.isBlank()) {
            message = copy().tokenField
            render()
            return
        }
        setBusy(true)
        scope.launch {
            try {
                val result = sharingRepository.resolveLink(session, token)
                currentSession = result.session
                message = "${copy().linkResolved} ${localizedShareTargetType(result.value.targetType)}"
            } catch (error: Exception) {
                message = sharingError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun acceptShareLinkInput(raw: String) {
        val session = currentSession ?: return
        val token = extractShareToken(raw)
        if (token.isBlank()) {
            message = copy().tokenField
            render()
            return
        }
        setBusy(true)
        scope.launch {
            try {
                val result = sharingRepository.acceptLink(session, token)
                currentSession = result.session
                message = "${copy().linkAccepted} ${localizedShareTargetType(result.value.targetType)}"
                loadPlannerData()
            } catch (error: Exception) {
                message = sharingError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun showFolderDialog(folder: PlanningFolder?, parentFolderId: String? = folder?.parentFolderId, onSaved: ((PlanningFolder) -> Unit)? = null) {
        val c = copy()
        val parentFolder = parentFolderId?.let(::findFolder)
        val nameInput = dialogInput(c.nameField, folder?.name.orEmpty())
        val notesInput = dialogInput(c.notesField, folder?.description.orEmpty(), multiline = true)
        val dialog = AlertDialog.Builder(this)
            .setTitle(if (folder == null) c.newFolder else c.edit)
            .setView(dialogForm(parentFolder?.let { dialogContextLine(c.folder, it.name) } ?: View(this), nameInput, notesInput))
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.save) { _, _ ->
                val draft = FolderDraft(nameInput.text.toString().trim(), notesInput.text.toString().trim(), parentFolderId)
                if (draft.name.isBlank()) {
                    message = c.nameRequired
                    render()
                    return@setPositiveButton
                }
                saveFolder(folder, draft, onSaved)
            }
            .show()
        focusDialogInput(dialog, nameInput)
    }

    private fun showGoalDialog(goal: PlanningGoal?, folderIdOverride: String? = null) {
        val folderId = goal?.folderId ?: folderIdOverride ?: selectedFolderId ?: run {
            message = copy().folderFirst
            render()
            return
        }
        val folder = folders.firstOrNull { it.id == folderId }
        val c = copy()
        val nameInput = dialogInput(c.nameField, goal?.name.orEmpty())
        val notesInput = dialogInput(c.notesField, goal?.description.orEmpty(), multiline = true)
        val statusInput = dialogInput(c.status, goal?.status ?: "todo", inputPurpose = TextInputPurpose.Text)
        val dialog = AlertDialog.Builder(this)
            .setTitle(if (goal == null) c.newGoal else c.edit)
            .setView(dialogForm(dialogContextLine(c.folder, folder?.name ?: c.folder), nameInput, notesInput, statusInput))
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.save) { _, _ ->
                val draft = GoalDraft(
                    nameInput.text.toString().trim(),
                    notesInput.text.toString().trim(),
                    statusInput.text.toString().trim().ifBlank { goal?.status ?: "todo" }
                )
                if (draft.name.isBlank()) {
                    message = c.nameRequired
                    render()
                    return@setPositiveButton
                }
                saveGoal(folderId, goal, draft)
            }
            .show()
        focusDialogInput(dialog, nameInput)
    }

    private fun showTaskDialog(task: PlanningTask?, goalIdOverride: String? = null) {
        val goalId = task?.goalId ?: goalIdOverride ?: selectedGoalId ?: run {
            message = copy().goalFirst
            render()
            return
        }
        val goal = goals.firstOrNull { it.id == goalId } ?: sharedGoals.firstOrNull { it.id == goalId }
        val c = copy()
        val titleInput = dialogInput(c.titleField, task?.title.orEmpty())
        val notesInput = dialogInput(c.notesField, task?.description.orEmpty(), multiline = true)
        val typeGroup = taskTypeGroup(task?.type ?: "green")
        val priorityInput = dialogInput(
            c.priorityField,
            (task?.priority ?: 5).toString(),
            inputPurpose = TextInputPurpose.Number,
            inputTypeOverride = InputType.TYPE_CLASS_NUMBER
        )
        val plannedField = dateTimeField(c.plannedField, task?.plannedTime)
        val dueField = dateTimeField(c.dueField, task?.dueTime)
        val dialog = AlertDialog.Builder(this)
            .setTitle(if (task == null) c.newTask else c.edit)
            .setView(
                dialogForm(
                    dialogContextLine(c.goal, goal?.name ?: c.goal),
                    titleInput,
                    notesInput,
                    dialogLabel(c.taskType),
                    typeGroup,
                    priorityInput,
                    plannedField.view,
                    dueField.view
                )
            )
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.save) { _, _ ->
                val priority = priorityInput.text.toString().trim().toIntOrNull()
                val draft = TaskDraft(
                    title = titleInput.text.toString().trim(),
                    description = notesInput.text.toString().trim(),
                    type = typeGroup.selectedTaskType(),
                    priority = priority ?: 5,
                    status = task?.status ?: "todo",
                    plannedTime = plannedField.isoValue(),
                    dueTime = dueField.isoValue()
                )
                if (draft.title.isBlank()) {
                    message = c.titleRequired
                    render()
                    return@setPositiveButton
                }
                if (priority == null || priority !in 1..10) {
                    message = c.priorityRequired
                    render()
                    return@setPositiveButton
                }
                saveTask(goalId, task, draft)
            }
            .show()
        focusDialogInput(dialog, titleInput)
    }

    private fun showIdeaDialog(folderId: String, idea: PlanningIdea? = null) {
        val c = copy()
        val folder = folders.firstOrNull { it.id == folderId } ?: sharedFolders.firstOrNull { it.id == folderId }
        val titleInput = dialogInput(c.titleField, idea?.title.orEmpty(), inputPurpose = TextInputPurpose.Name)
        val notesInput = dialogInput(c.notesField, idea?.body.orEmpty(), multiline = true, inputPurpose = TextInputPurpose.Notes)
        val statusInput = dialogInput(c.status, idea?.status ?: "active", inputPurpose = TextInputPurpose.Text)
        val authorEditInput = CheckBox(this).apply {
            text = c.allowAuthorNoteEdits
            isChecked = idea?.allowAuthorNoteEdits ?: false
            setTextColor(color(Ui.TEXT))
            textSize = 15f
            setPadding(0, dp(8), 0, dp(2))
        }
        val authorEditHint = TextView(this).apply {
            text = c.allowAuthorNoteEditsHint
            textSize = 12.5f
            setTextColor(color(Ui.MUTED))
            setPadding(0, 0, 0, dp(4))
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle(if (idea == null) c.newIdea else c.edit)
            .setView(dialogForm(dialogContextLine(c.folder, folder?.name ?: c.folder), titleInput, notesInput, statusInput, authorEditInput, authorEditHint))
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.save) { _, _ ->
                val draft = IdeaDraft(
                    title = titleInput.text.toString().trim(),
                    body = notesInput.text.toString().trim(),
                    status = statusInput.text.toString().trim().ifBlank { idea?.status ?: "active" },
                    allowAuthorNoteEdits = authorEditInput.isChecked
                )
                if (draft.title.isBlank()) {
                    message = c.titleRequired
                    render()
                    return@setPositiveButton
                }
                saveIdea(folderId, idea, draft)
            }
            .show()
        focusDialogInput(dialog, titleInput)
    }

    private fun showIdeaNoteDialog(idea: PlanningIdea, note: IdeaNote? = null) {
        val c = copy()
        val input = dialogInput(c.notesField, note?.body.orEmpty(), multiline = true, inputPurpose = TextInputPurpose.Notes)
        val dialog = AlertDialog.Builder(this)
            .setTitle(if (note == null) c.addNote else c.editNote)
            .setView(dialogForm(input))
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.save) { _, _ ->
                val draft = IdeaNoteDraft(
                    body = input.text.toString().trim(),
                    eventType = note?.eventType ?: "note",
                    metadataJson = note?.metadataJson ?: "{}"
                )
                if (draft.body.isBlank()) {
                    message = c.noteRequired
                    render()
                    return@setPositiveButton
                }
                if (note == null) {
                    saveIdeaNote(idea, draft)
                } else {
                    updateIdeaNote(idea, note, draft)
                }
            }
            .show()
        focusDialogInput(dialog, input)
    }

    private fun showNoteDialog(folderId: String, note: PlanningNote? = null) {
        val c = copy()
        val folder = folders.firstOrNull { it.id == folderId } ?: sharedFolders.firstOrNull { it.id == folderId }
        val titleInput = dialogInput(c.titleField, note?.title.orEmpty(), inputPurpose = TextInputPurpose.Name)
        val notesInput = dialogInput(c.notesField, note?.body.orEmpty(), multiline = true, inputPurpose = TextInputPurpose.Notes)
        val dialog = AlertDialog.Builder(this)
            .setTitle(if (note == null) c.newNote else c.editNote)
            .setView(dialogForm(dialogContextLine(c.folder, folder?.name ?: c.folder), titleInput, notesInput))
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.save) { _, _ ->
                val draft = NoteDraft(
                    title = titleInput.text.toString().trim(),
                    body = notesInput.text.toString().trim()
                )
                if (draft.title.isBlank()) {
                    message = c.titleRequired
                    render()
                    return@setPositiveButton
                }
                saveNote(folderId, note, draft)
            }
            .show()
        focusDialogInput(dialog, titleInput)
    }

    private fun showStatusDialog(task: PlanningTask) {
        val labels = arrayOf(copy().statusTodo, copy().statusInProgress, copy().statusDone, copy().statusCancelled)
        val values = arrayOf("todo", "in_progress", "done", "cancelled")
        val checked = values.indexOf(task.status).coerceAtLeast(0)
        AlertDialog.Builder(this)
            .setTitle(copy().status)
            .setSingleChoiceItems(labels, checked) { dialog, which ->
                saveTask(
                    task.goalId,
                    task,
                    task.toDraft(status = values[which]),
                    successMessage = "${copy().status}: ${labels[which]}"
                )
                dialog.dismiss()
            }
            .show()
    }

    private fun showTaskTypeDialog(task: PlanningTask) {
        val labels = arrayOf(copy().greenTask, copy().redTask)
        val values = arrayOf("green", "red")
        val checked = values.indexOf(normalizeTaskType(task.type)).coerceAtLeast(0)
        AlertDialog.Builder(this)
            .setTitle(copy().taskType)
            .setSingleChoiceItems(labels, checked) { dialog, which ->
                saveTask(task.goalId, task, task.toDraft(type = values[which]))
                dialog.dismiss()
            }
            .show()
    }

    private fun showPriorityDialog(task: PlanningTask) {
        val labels = (1..10).map { "${copy().priorityShort}$it" }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle(copy().priority)
            .setSingleChoiceItems(labels, (task.priority - 1).coerceIn(0, 9)) { dialog, which ->
                saveTask(task.goalId, task, task.toDraft(priority = which + 1))
                dialog.dismiss()
            }
            .show()
    }

    private fun showDueDialog(task: PlanningTask) {
        val c = copy()
        val dueField = dateTimeField(c.dueField, task.dueTime)
        AlertDialog.Builder(this)
            .setTitle(c.due)
            .setView(dialogForm(dueField.view))
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.save) { _, _ ->
                saveTask(task.goalId, task, task.toDraft(dueTime = dueField.isoValue()))
            }
            .show()
    }

    private fun showPlannedDialog(task: PlanningTask) {
        val c = copy()
        val plannedField = dateTimeField(c.plannedField, task.plannedTime)
        AlertDialog.Builder(this)
            .setTitle(c.planned)
            .setView(dialogForm(plannedField.view))
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.save) { _, _ ->
                saveTask(task.goalId, task, task.toDraft(plannedTime = plannedField.isoValue()))
            }
            .show()
    }

    private fun showTaskTagsDialog(task: PlanningTask) {
        val c = copy()
        val tags = taskTags
        if (tags.isEmpty()) {
            showCreateTagDialog { tagId ->
                saveTask(task.goalId, task, task.toDraft(tagIds = (task.tagIds + tagId).distinct()))
            }
            return
        }

        val selected = task.tagIds.toMutableSet()
        AlertDialog.Builder(this)
            .setTitle(c.tags)
            .setMultiChoiceItems(
                tags.map { it.name }.toTypedArray(),
                tags.map { it.id in selected }.toBooleanArray()
            ) { _, which, isChecked ->
                if (isChecked) selected += tags[which].id else selected -= tags[which].id
            }
            .setNeutralButton(c.newTag) { _, _ ->
                showCreateTagDialog { tagId ->
                    saveTask(task.goalId, task, task.toDraft(tagIds = (selected + tagId).toList()))
                }
            }
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.save) { _, _ ->
                saveTask(task.goalId, task, task.toDraft(tagIds = selected.toList()))
            }
            .show()
    }

    private fun showCreateTagDialog(onCreated: (String) -> Unit) {
        val c = copy()
        val nameInput = dialogInput(c.newTag, "")
        val colorInput = dialogInput(
            c.colorField,
            "#2F6B57",
            inputPurpose = TextInputPurpose.Code,
            inputTypeOverride = codeInputType()
        )
        val beforeIds = taskTags.map { it.id }.toSet()
        AlertDialog.Builder(this)
            .setTitle(c.newTag)
            .setView(dialogForm(nameInput, colorInput))
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.save) { _, _ ->
                val session = currentSession ?: return@setPositiveButton
                val draft = TaskTagDraft(
                    name = nameInput.text.toString().trim(),
                    color = colorInput.text.toString().trim().ifBlank { "#2F6B57" }
                )
                if (draft.name.isBlank()) {
                    message = c.nameRequired
                    render()
                    return@setPositiveButton
                }
                setBusy(true)
                message = null
                scope.launch {
                    try {
                        val result = planningRepository.createTag(session, draft)
                        applyPlanningResult(result)
                        val tagId = result.snapshot.taskTags.firstOrNull { it.id !in beforeIds && it.name == draft.name }?.id
                            ?: result.snapshot.taskTags.firstOrNull { it.name == draft.name }?.id
                        tagId?.let(onCreated)
                    } catch (error: Exception) {
                        message = humanError(error)
                    } finally {
                        setBusy(false)
                    }
                }
            }
            .show()
    }

    private fun showRecurrenceDialog(task: PlanningTask) {
        val c = copy()
        val labels = arrayOf(c.noRecurrence, c.daily, c.weekly, c.monthly)
        val modes = arrayOf("", "daily", "weekly", "monthly")
        val currentMode = recurrenceMode(task.recurrenceJson)
        val checked = modes.indexOf(currentMode).coerceAtLeast(0)
        AlertDialog.Builder(this)
            .setTitle(c.recurrence)
            .setMessage(recurrenceHelpText(task))
            .setSingleChoiceItems(labels, checked) { dialog, which ->
                val payload = recurrencePayload(task, modes[which], active = which != 0)
                saveTask(task.goalId, task, task.toDraft(recurrenceJson = payload.toString()))
                dialog.dismiss()
            }
            .show()
    }

    private fun recurrenceHelpText(task: PlanningTask): String {
        val anchor = when {
            !task.plannedTime.isNullOrBlank() -> copy().planned
            !task.dueTime.isNullOrBlank() -> copy().due
            else -> if (currentLanguage == "en") "current time" else "текущее время"
        }
        return if (currentLanguage == "en") {
            "Recurrence starts from Planned time. If it is empty, RocketFlow uses Deadline; if both are empty, it uses the current time. Current source: $anchor."
        } else {
            "Повтор начинается от поля «Когда делать». Если оно пустое, используется дедлайн; если оба поля пустые, текущее время. Сейчас источник: $anchor."
        }
    }

    private fun showRemindersDialog(task: PlanningTask) {
        val session = currentSession ?: return
        val c = copy()
        val current = taskReminderStore.read(session.user.id, task.id)
        var selectedDateTime = current?.triggerAtMillis
            ?.let { Instant.ofEpochMilli(it).atZone(zone).toLocalDateTime() }
            ?: defaultReminderDateTime(task)
        var selectedRepeat = current?.repeat ?: TaskReminderRepeat.None

        val selectedTime = TextView(this).apply {
            textSize = 16f
            setTextColor(color(Ui.TEXT))
            setPadding(0, 0, 0, dp(8))
        }
        fun updateSelectedTime() {
            selectedTime.text = formatReminderDateTime(selectedDateTime)
        }
        updateSelectedTime()

        val pickTime = Button(this).apply {
            text = c.pickDate
            setOnClickListener {
                pickReminderDateTime(selectedDateTime) { picked ->
                    selectedDateTime = picked
                    updateSelectedTime()
                }
            }
        }

        val repeats = listOf(
            TaskReminderRepeat.None to c.noRecurrence,
            TaskReminderRepeat.Daily to c.daily,
            TaskReminderRepeat.Weekly to c.weekly,
            TaskReminderRepeat.Monthly to c.monthly
        )
        val repeatIds = mutableMapOf<Int, TaskReminderRepeat>()
        val repeatGroup = RadioGroup(this).apply {
            orientation = RadioGroup.VERTICAL
            repeats.forEach { (repeat, label) ->
                val id = View.generateViewId()
                repeatIds[id] = repeat
                addView(RadioButton(this@MainActivity).apply {
                    this.id = id
                    text = label
                    textSize = 15f
                    setTextColor(color(Ui.TEXT))
                    isChecked = repeat == selectedRepeat
                })
            }
            setOnCheckedChangeListener { _, checkedId ->
                selectedRepeat = repeatIds[checkedId] ?: TaskReminderRepeat.None
            }
        }

        val form = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(12), dp(20), 0)
            addView(selectedTime)
            addView(pickTime)
            addView(TextView(this@MainActivity).apply {
                text = c.recurrence
                textSize = 13f
                setTextColor(color(Ui.MUTED))
                setPadding(0, dp(14), 0, dp(4))
            })
            addView(repeatGroup)
        }

        val dialog = AlertDialog.Builder(this)
            .setTitle(c.reminders)
            .setView(form)
            .setNegativeButton(c.cancel, null)
            .setNeutralButton(c.clearDate, null)
            .setPositiveButton(c.save, null)
            .show()

        dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
            current?.let(taskReminderAlarmScheduler::cancel)
            taskReminderStore.clear(session.user.id, task.id)
            message = c.remindersOff
            dialog.dismiss()
            render()
        }
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            val triggerAtMillis = selectedDateTime.atZone(zone).toInstant().toEpochMilli()
            if (triggerAtMillis <= System.currentTimeMillis()) {
                Toast.makeText(this, reminderFutureTimeMessage(), Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            val setting = TaskReminderSetting(
                userId = session.user.id,
                taskId = task.id,
                taskTitle = task.title,
                triggerAtMillis = triggerAtMillis,
                repeat = selectedRepeat,
                enabled = true
            )
            current?.let(taskReminderAlarmScheduler::cancel)
            taskReminderStore.save(setting)
            val result = taskReminderAlarmScheduler.schedule(setting)
            message = if (result.exact) c.remindersOn else reminderApproximateMessage()
            dialog.dismiss()
            render()
            if (!notificationRuntime.hasNotificationPermission()) {
                notificationRuntime.requestNotificationPermission(this)
            }
            if (!result.exact && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                showExactAlarmSettingsDialog()
            }
        }
    }

    private fun pickReminderDateTime(
        initial: LocalDateTime,
        onPicked: (LocalDateTime) -> Unit
    ) {
        DatePickerDialog(
            this,
            { _, year, month, dayOfMonth ->
                TimePickerDialog(
                    this,
                    { _, hourOfDay, minute ->
                        onPicked(LocalDateTime.of(year, month + 1, dayOfMonth, hourOfDay, minute))
                    },
                    initial.hour,
                    initial.minute,
                    true
                ).show()
            },
            initial.year,
            initial.monthValue - 1,
            initial.dayOfMonth
        ).show()
    }

    private fun showRescheduleDialog(task: PlanningTask) {
        val c = copy()
        val labels = arrayOf(c.later30m, c.later1h, c.later3h, c.later24h)
        val presets = arrayOf("30m", "1h", "3h", "24h")
        AlertDialog.Builder(this)
            .setTitle(c.reschedule)
            .setItems(labels) { _, which -> quickRescheduleTask(task, presets[which]) }
            .show()
    }

    private fun saveFolder(folder: PlanningFolder?, draft: FolderDraft, onSaved: ((PlanningFolder) -> Unit)? = null) {
        val session = currentSession ?: return
        val existingFolderIds = folders.map { it.id }.toSet()
        setBusy(true)
        message = null
        scope.launch {
            try {
                val result = if (folder == null) {
                    planningRepository.createFolder(session, draft)
                } else {
                    planningRepository.updateFolder(session, folder, draft)
                }
                applyPlanningResult(result)
                val savedFolder = folder?.id?.let { folderId ->
                    result.snapshot.folders.firstOrNull { it.id == folderId }
                } ?: result.snapshot.folders.firstOrNull { it.id !in existingFolderIds && it.name == draft.name }
                    ?: result.snapshot.folders.firstOrNull { it.name == draft.name }
                if (savedFolder != null) {
                    selectedFolderId = savedFolder.id
                    onSaved?.invoke(savedFolder)
                }
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun saveGoal(folderId: String, goal: PlanningGoal?, draft: GoalDraft) {
        val session = currentSession ?: return
        setBusy(true)
        message = null
        scope.launch {
            try {
                val result = if (goal == null) {
                    planningRepository.createGoal(session, folderId, draft)
                } else {
                    planningRepository.updateGoal(session, goal, draft)
                }
                applyPlanningResult(result)
                val savedGoal = goal?.id?.let { goalId ->
                    result.snapshot.goals.firstOrNull { it.id == goalId }
                } ?: result.snapshot.goals.firstOrNull { it.folderId == folderId && it.name == draft.name }
                if (savedGoal != null) {
                    selectedFolderId = savedGoal.folderId
                    selectedGoalId = savedGoal.id
                }
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun saveTask(goalId: String, task: PlanningTask?, draft: TaskDraft, successMessage: String? = null) {
        val session = currentSession ?: return
        setBusy(true)
        message = null
        scope.launch {
            try {
                val result = if (task == null) {
                    planningRepository.createTask(session, goalId, draft)
                } else {
                    planningRepository.updateTask(session, task, draft)
                }
                applyPlanningResult(result)
                if (successMessage != null) {
                    message = if (result.snapshot.offline || result.snapshot.pendingCount > 0) {
                        "$successMessage ${copy().pending}"
                    } else {
                        successMessage
                    }
                }
                val parentGoal = result.snapshot.goals.firstOrNull { it.id == goalId }
                    ?: result.snapshot.sharedGoals.firstOrNull { it.id == goalId }
                selectedFolderId = parentGoal?.folderId ?: selectedFolderId
                selectedGoalId = goalId
                selectedTaskId = result.snapshot.tasks.firstOrNull { it.title == draft.title }?.id ?: selectedTaskId
                selectedTaskDetail = selectedTaskId?.let(::findTask)
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun saveIdea(folderId: String, idea: PlanningIdea?, draft: IdeaDraft) {
        val session = currentSession ?: return
        setBusy(true)
        message = null
        scope.launch {
            try {
                val result = if (idea == null) {
                    planningRepository.createIdea(session, folderId, draft)
                } else {
                    planningRepository.updateIdea(session, idea, draft)
                }
                applyPlanningResult(result)
                val savedIdea = if (idea == null) {
                    result.snapshot.ideas.firstOrNull { it.folderId == folderId && it.title == draft.title }
                        ?: result.snapshot.sharedIdeas.firstOrNull { it.folderId == folderId && it.title == draft.title }
                } else {
                    result.snapshot.ideas.firstOrNull { it.id == idea.id }
                        ?: result.snapshot.sharedIdeas.firstOrNull { it.id == idea.id }
                }
                selectedFolderId = folderId
                selectedGoalId = null
                selectedTaskId = null
                selectedTaskDetail = null
                selectedIdeaId = savedIdea?.id
                selectedIdeaDetail = savedIdea
                currentScreen = Screen.IdeaDetail
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun linksSection(entityType: String, entityId: String): LinearLayout {
        val c = copy()
        val links = linksForEntity(entityType, entityId).filterNot { linkedNoteFor(entityType, entityId, it) != null }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(propertyRow(c.links, if (linksExpanded) c.cancel else links.size.toString(), clickable = true) {
                linksExpanded = !linksExpanded
                render()
            })
            if (linksExpanded) {
                if (links.isEmpty()) {
                    addView(hintRow(c.nothingHere, indentLevel = 0))
                } else {
                    links.forEach { link -> addView(entityLinkRow(entityType, entityId, link)) }
                }
            }
        }
    }

    private fun linkedNotesSection(entityType: String, entityId: String): LinearLayout {
        val c = copy()
        val linked = linksForEntity(entityType, entityId).mapNotNull { linkedNoteFor(entityType, entityId, it) }.distinctBy { it.id }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(propertyRow(c.linkedNotes, if (linkedNotesExpanded) c.cancel else linked.size.toString(), clickable = true) {
                linkedNotesExpanded = !linkedNotesExpanded
                render()
            })
            if (linkedNotesExpanded) {
                if (linked.isEmpty()) {
                    addView(hintRow(c.nothingHere, indentLevel = 0))
                } else {
                    linked.forEach { note -> addView(noteRow(note, indentLevel = 0)) }
                }
            }
        }
    }

    private fun entityLinkRow(currentType: String, currentId: String, link: EntityLink): LinearLayout {
        val otherType = if (link.sourceType == currentType && link.sourceId == currentId) link.targetType else link.sourceType
        val otherId = if (link.sourceType == currentType && link.sourceId == currentId) link.targetId else link.sourceId
        val title = entityTitle(otherType, otherId).ifBlank {
            if (link.sourceType == currentType && link.sourceId == currentId) {
                link.target?.title.orEmpty()
            } else {
                link.source?.title.orEmpty()
            }
        }.ifBlank { otherType }
        val label = if (link.relationType == "dependency") copy().dependency else copy().related
        return hierarchyContainer(indentLevel = 0, heightDp = 44, selected = false).apply {
            addView(iconView(if (link.relationType == "dependency") R.drawable.ic_link else R.drawable.ic_content_copy, sizeDp = 22, tint = Ui.ACCENT))
            addView(rowText(title, label, weight = 1f, titleSize = 14.5f, titleStyle = Typeface.BOLD).apply {
                setOnClickListener { openEntityDetail(otherType, otherId) }
            })
        }
    }

    private fun updateIdeaNote(idea: PlanningIdea, note: IdeaNote, draft: IdeaNoteDraft) {
        val session = currentSession ?: return
        setBusy(true)
        message = null
        scope.launch {
            try {
                val result = planningRepository.updateIdeaNote(session, note, draft)
                applyPlanningResult(result)
                selectedIdeaId = idea.id
                selectedIdeaDetail = findIdea(idea.id)
                currentScreen = Screen.IdeaDetail
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun saveIdeaNote(idea: PlanningIdea, draft: IdeaNoteDraft) {
        val session = currentSession ?: return
        setBusy(true)
        message = null
        scope.launch {
            try {
                val result = planningRepository.createIdeaNote(session, idea.id, draft)
                applyPlanningResult(result)
                selectedIdeaId = idea.id
                selectedIdeaDetail = findIdea(idea.id)
                currentScreen = Screen.IdeaDetail
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun saveNote(folderId: String, note: PlanningNote?, draft: NoteDraft) {
        val session = currentSession ?: return
        setBusy(true)
        message = null
        scope.launch {
            try {
                val result = if (note == null) {
                    planningRepository.createNote(session, folderId, draft)
                } else {
                    planningRepository.updateNote(session, note, draft)
                }
                applyPlanningResult(result)
                selectedFolderId = folderId
                selectedNoteId = note?.id ?: result.snapshot.notes.firstOrNull { it.folderId == folderId && it.title == draft.title }?.id
                    ?: result.snapshot.sharedNotes.firstOrNull { it.folderId == folderId && it.title == draft.title }?.id
                selectedNoteDetail = selectedNoteId?.let(::findNote)
                if (selectedNoteDetail != null) currentScreen = Screen.NoteDetail
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun deleteFolder(folder: PlanningFolder) {
        val session = currentSession ?: return
        setBusy(true)
        scope.launch {
            try {
                applyPlanningResult(planningRepository.deleteFolder(session, folder))
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun deleteGoal(goal: PlanningGoal) {
        val session = currentSession ?: return
        setBusy(true)
        scope.launch {
            try {
                applyPlanningResult(planningRepository.deleteGoal(session, goal))
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun deleteTask(task: PlanningTask) {
        val session = currentSession ?: return
        setBusy(true)
        scope.launch {
            try {
                applyPlanningResult(planningRepository.deleteTask(session, task))
                if (selectedTaskId == task.id) {
                    selectedTaskId = null
                    selectedTaskDetail = null
                    currentScreen = Screen.Planner
                }
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun deleteNote(note: PlanningNote) {
        val session = currentSession ?: return
        setBusy(true)
        scope.launch {
            try {
                applyPlanningResult(planningRepository.deleteNote(session, note))
                currentScreen = Screen.Planner
                selectedNoteId = null
                selectedNoteDetail = null
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun toggleTaskDone(task: PlanningTask) {
        val nextStatus = if (isDone(task)) "todo" else "done"
        val c = copy()
        saveTask(
            task.goalId,
            task,
            task.toDraft(status = nextStatus),
            successMessage = "${c.status}: ${localizedStatus(nextStatus)}"
        )
    }

    private fun quickRescheduleTask(task: PlanningTask, preset: String) {
        val session = currentSession ?: return
        setBusy(true)
        message = null
        scope.launch {
            try {
                val result = planningRepository.quickRescheduleTask(session, task, preset)
                currentSession = result.session
                applyPlanningSnapshot(result.snapshot)
                selectedTaskId = task.id
                selectedTaskDetail = findTask(task.id)
                message = if (result.priorityDecayApplied) copy().decayApplied else copy().decayNotApplied
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun applyPlanningResult(result: PlanningLoadResult) {
        currentSession = result.session
        applyPlanningSnapshot(result.snapshot)
        message = if (result.snapshot.offline) copy().savedOffline else null
    }

    private fun confirmDelete(name: String, message: String = name, onConfirm: () -> Unit) {
        AlertDialog.Builder(this)
            .setTitle(copy().delete)
            .setMessage(message)
            .setNegativeButton(copy().cancel, null)
            .setPositiveButton(copy().delete) { _, _ -> onConfirm() }
            .show()
    }

    private fun deleteFolderMessage(folder: PlanningFolder): String {
        val folderGoals = goalsForFolder(folder.id)
        val taskCount = folderGoals.sumOf { tasksForGoal(it.id).size }
        return if (folderGoals.isEmpty() && taskCount == 0) {
            folder.name
        } else {
            String.format(Locale.ROOT, copy().deleteFolderWarning, folderGoals.size, taskCount)
        }
    }

    private fun deleteGoalMessage(goal: PlanningGoal): String {
        val taskCount = tasksForGoal(goal.id).size
        return if (taskCount == 0) {
            goal.name
        } else {
            String.format(Locale.ROOT, copy().deleteGoalWarning, taskCount)
        }
    }

    private fun openTaskDetail(taskId: String, consumePendingOnSuccess: Boolean = false) {
        val session = currentSession ?: return
        selectedTaskId = taskId
        selectedTaskDetail = findTask(taskId)
        currentScreen = Screen.Detail
        render()

        scope.launch {
            try {
                val result = planningRepository.getTask(session, taskId)
                currentSession = result.first
                selectedTaskDetail = result.second
                if (consumePendingOnSuccess && pendingTaskOpenId == taskId) {
                    pendingTaskOpenId = null
                    message = null
                }
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                render()
            }
        }
    }

    private fun handleIncomingIntent(intent: Intent?) {
        val taskId = NotificationIntents.extractTaskId(intent) ?: return
        pendingTaskOpenId = taskId
        message = copy().openingTask
    }

    private fun seedAcceptanceScenarioIfRequested(intent: Intent?) {
        if (!BuildConfig.DEBUG || intent?.getBooleanExtra(EXTRA_ACCEPTANCE_SEED, false) != true) {
            return
        }
        val language = intent.getStringExtra(EXTRA_ACCEPTANCE_LANGUAGE)
            ?.takeIf { it == "ru" || it == "en" }
            ?: currentLanguage
        currentLanguage = language
        languageStore.writeLanguage(language)

        val session = AuthSession(
            user = CurrentUser(
                id = "acceptance-user",
                email = "design@rocketflow.app",
                displayName = "RocketFlow",
                timezone = zone.id,
                language = language
            ),
            tokens = AuthTokens(
                accessToken = "acceptance-access",
                refreshToken = "acceptance-refresh",
                expiresAt = "2026-12-31T21:00:00Z"
            )
        )
        SessionStore(this).writeSession(session)
        currentSession = session

        val localStore = PlanningLocalStore(this)
        val existing = localStore.snapshot(session.user.id, offline = true, lastSyncError = null)
        if (intent.getBooleanExtra(EXTRA_ACCEPTANCE_EMPTY, false)) {
            return
        }
        if (existing.folders.isNotEmpty()) {
            return
        }

        val data = if (language == "en") {
            AcceptanceData(
                folder = "Product launch",
                goal = "Soft release",
                firstTask = "Prepare the sign-in screen",
                secondTask = "Check Pixel 7",
                thirdTask = "Team call",
                notes = "Review copy, error states, and the first empty screen."
            )
        } else {
            AcceptanceData(
                folder = "������ ��������",
                goal = "������ �����",
                firstTask = "����������� �������� �����",
                secondTask = "��������� Pixel 7",
                thirdTask = "������ � ��������",
                notes = "�������� ������, ��������� ������ � ������ ������ �����."
            )
        }

        val folderId = localStore.createFolder(session.user.id, FolderDraft(data.folder, ""))
        val goalId = localStore.createGoal(session.user.id, folderId, GoalDraft(data.goal, ""))
        val tagId = localStore.createTag(
            session.user.id,
            TaskTagDraft(
                name = if (language == "en") "QA" else "QA",
                color = "#2F6B57"
            )
        )
        val recurrenceJson = JSONObject()
            .put("mode", "weekly")
            .put("interval", 1)
            .put("daysOfWeek", JSONArray().put("SATURDAY"))
            .put("dayOfMonth", JSONObject.NULL)
            .put("startAt", "2026-05-02T09:00:00Z")
            .put("endAt", JSONObject.NULL)
            .put("active", true)
            .toString()
        val remindersJson = JSONArray()
            .put(reminderPayload("before_due_time", 30))
            .toString()
        localStore.createTask(
            session.user.id,
            goalId,
            TaskDraft(
                title = data.firstTask,
                description = data.notes,
                type = "green",
                priority = 2,
                status = "in_progress",
                plannedTime = "2026-05-02T09:00:00Z",
                dueTime = "2026-05-02T09:00:00Z",
                tagIds = listOf(tagId),
                recurrenceJson = recurrenceJson,
                remindersJson = remindersJson
            )
        )
        localStore.createTask(
            session.user.id,
            goalId,
            TaskDraft(
                title = data.secondTask,
                description = "",
                type = "green",
                priority = 3,
                status = "todo",
                plannedTime = null,
                dueTime = null
            )
        )
        localStore.createTask(
            session.user.id,
            goalId,
            TaskDraft(
                title = data.thirdTask,
                description = "",
                type = "green",
                priority = 5,
                status = "done",
                plannedTime = null,
                dueTime = null
            )
        )
    }

    private fun maybeOpenPendingTask() {
        val taskId = pendingTaskOpenId ?: return
        if (currentSession == null) return
        openTaskDetail(taskId, consumePendingOnSuccess = true)
    }

    private fun showSearchDialog() {
        val c = copy()
        val input = dialogInput(
            c.searchHint,
            searchQuery,
            inputPurpose = TextInputPurpose.Search,
            inputTypeOverride = searchInputType(),
            imeOptionsOverride = EditorInfo.IME_ACTION_SEARCH
        )
        AlertDialog.Builder(this)
            .setTitle(c.search)
            .setView(dialogForm(input))
            .setNegativeButton(c.clearSearch) { _, _ ->
                searchQuery = ""
                render()
            }
            .setPositiveButton(c.search) { _, _ ->
                searchQuery = input.text.toString().trim()
                render()
            }
            .show()
    }

    private fun registerDevice() {
        val session = currentSession ?: return
        val c = copy()
        if (!notificationRuntime.hasNotificationPermission()) {
            message = c.remindersOff
            notificationRuntime.requestNotificationPermission(this)
            render()
            return
        }
        if (!notificationsRepository.isFirebaseConfigured()) {
            message = c.firebaseUnavailable
            render()
            return
        }

        val token = currentPushToken?.value ?: notificationsRepository.readStoredPushToken()?.value
        if (token.isNullOrBlank()) {
            refreshPushToken(showProgress = true)
            return
        }

        setBusy(true)
        scope.launch {
            try {
                val activeSession = enableAccountRemindersIfNeeded(session)
                val result = notificationsRepository.registerDevice(activeSession, token, defaultDeviceName())
                currentSession = result.session
                currentDeviceRegistration = result.value
                message = c.remindersOn
            } catch (error: Exception) {
                message = notificationRegistrationError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private suspend fun enableAccountRemindersIfNeeded(session: AuthSession): AuthSession {
        val settings = currentSettings ?: return session
        if (settings.notificationsEnabled) return session
        val result = userSettingsRepository.updateSettings(
            session,
            settings.copy(language = currentLanguage, notificationsEnabled = true)
        )
        currentSettings = result.value
        return result.session
    }

    private fun unregisterDevice() {
        val session = currentSession ?: return
        val registration = currentDeviceRegistration ?: return
        setBusy(true)
        scope.launch {
            try {
                currentSession = notificationsRepository.unregisterDevice(session, registration.id)
                currentDeviceRegistration = null
                message = copy().remindersOff
            } catch (error: Exception) {
                currentDeviceRegistration = notificationsRepository.readStoredRegistration()
                message = humanError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun refreshPushToken(showProgress: Boolean) {
        if (showProgress) {
            message = copy().loading
            render()
        }
        notificationsRepository.refreshPushToken { result ->
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                currentPushToken = result.token ?: notificationsRepository.readStoredPushToken()
                if (showProgress) {
                    message = if (result.errorMessage == null) copy().remindersOn else humanText(result.errorMessage)
                }
                maybeSyncRegisteredDevice()
                render()
            }
        }
    }

    private fun maybeSyncRegisteredDevice() {
        val session = currentSession ?: return
        if (!notificationRuntime.hasNotificationPermission()) return
        scope.launch {
            try {
                syncRegisteredDeviceIfPossible(session)
                render()
            } catch (error: Exception) {
                message = humanError(error)
                render()
            }
        }
    }

    private suspend fun syncRegisteredDeviceIfPossible(session: AuthSession) {
        if (!notificationRuntime.hasNotificationPermission()) return
        val result = notificationsRepository.syncStoredDeviceRegistration(session, defaultDeviceName()) ?: return
        currentSession = result.session
        currentDeviceRegistration = result.value
    }

    private fun setBusy(value: Boolean) {
        busy = value
        render()
    }

    private fun languageSegment(compact: Boolean): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            background = roundedDrawable(Ui.SURFACE, strokeColorHex = Ui.HAIRLINE, radiusDp = 8)
            layoutParams = LinearLayout.LayoutParams(
                if (compact) dp(92) else LinearLayout.LayoutParams.WRAP_CONTENT,
                dp(32)
            ).apply {
                if (!compact) topMargin = dp(4)
            }
            addView(languageButton("ru", "RU"))
            addView(languageButton("en", "EN"))
        }
    }

    private fun languageButton(language: String, label: String): TextView {
        return TextView(this).apply {
            text = label
            textSize = 13f
            gravity = Gravity.CENTER
            setTextColor(color(if (currentLanguage == language) Ui.ELEVATED else Ui.TEXT))
            background = if (currentLanguage == language) roundedDrawable(Ui.ACCENT, radiusDp = 7) else null
            layoutParams = LinearLayout.LayoutParams(dp(44), dp(30))
            setOnClickListener {
                emailDraft = emailInput?.text?.toString().orEmpty()
                passwordDraft = passwordInput?.text?.toString().orEmpty()
                currentLanguage = language
                languageStore.writeLanguage(language)
                message = null
                render()
            }
        }
    }

    private fun textButton(
        label: String,
        primary: Boolean = false,
        quiet: Boolean = false,
        danger: Boolean = false,
        onClick: () -> Unit
    ): Button {
        return Button(this).apply {
            text = label
            setAllCaps(false)
            textSize = 14.5f
            includeFontPadding = false
            minHeight = dp(44)
            isEnabled = !busy
            setTextColor(
                color(
                    when {
                        primary -> Ui.ELEVATED
                        danger -> Ui.DANGER
                        else -> Ui.TEXT
                    }
                )
            )
            background = roundedDrawable(
                fillColorHex = when {
                    primary -> Ui.ACCENT
                    quiet -> "#00FFFFFF"
                    else -> Ui.SURFACE
                },
                strokeColorHex = when {
                    primary -> Ui.ACCENT
                    quiet -> "#00FFFFFF"
                    danger -> Ui.DANGER
                    else -> Ui.HAIRLINE
                },
                radiusDp = 8
            )
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(44)
            ).apply { topMargin = dp(10) }
        }
    }

    private fun iconButton(icon: Int, description: String, onClick: () -> Unit): ImageButton {
        return ImageButton(this).apply {
            setImageResource(icon)
            setColorFilter(color(Ui.TEXT))
            contentDescription = description
            background = roundedDrawable("#00FFFFFF", radiusDp = 8)
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(dp(48), dp(48))
            scaleType = ImageView.ScaleType.CENTER
        }
    }

    private fun syncIconButton(): ImageButton {
        val c = copy()
        val hasError = planningLastSyncError != null
        val drawable = when {
            hasError -> R.drawable.ic_warning
            planningOffline || planningPendingCount > 0 -> R.drawable.ic_cloud_off
            else -> R.drawable.ic_cloud_done
        }
        val description = when {
            hasError -> c.couldNotSync
            planningOffline -> c.offline
            planningPendingCount > 0 -> "${planningPendingCount} ${c.pending}"
            else -> c.synced
        }
        return iconButton(drawable, description) {
            currentScreen = Screen.Settings
            diagnosticsExpanded = hasError
            render()
        }.apply {
            setColorFilter(color(if (hasError) Ui.DANGER else Ui.ACCENT))
        }
    }

    private fun iconView(icon: Int, sizeDp: Int = 24, tint: String = Ui.TEXT): ImageView {
        return ImageView(this).apply {
            setImageResource(icon)
            setColorFilter(color(tint))
            layoutParams = LinearLayout.LayoutParams(dp(sizeDp), dp(sizeDp)).apply {
                marginEnd = dp(10)
            }
        }
    }

    private fun messageLine(inset: Boolean = false): TextView? {
        val text = when {
            busy -> copy().loading
            !message.isNullOrBlank() -> message
            else -> null
        } ?: return null
        return TextView(this).apply {
            this.text = text
            textSize = 13f
            setTextColor(color(Ui.ACCENT))
            setLineSpacing(dp(2).toFloat(), 1f)
            setPadding(dp(12), dp(9), dp(12), dp(9))
            background = roundedDrawable(Ui.ACCENT_SOFT, radiusDp = 8)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                val side = if (inset) dp(16) else 0
                setMargins(side, dp(12), side, 0)
            }
        }
    }

    private fun sectionLabel(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 13f
            setTextColor(color(Ui.MUTED))
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER_VERTICAL
            includeFontPadding = false
            setPadding(dp(16), dp(18), dp(16), dp(6))
        }
    }

    private fun propertyRow(label: String, value: String, clickable: Boolean, onClick: (() -> Unit)? = null): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(46)
            addView(
                TextView(context).apply {
                    text = label
                    textSize = 14f
                    setTextColor(color(Ui.MUTED))
                    includeFontPadding = false
                    layoutParams = LinearLayout.LayoutParams(dp(112), LinearLayout.LayoutParams.WRAP_CONTENT)
                }
            )
            addView(
                TextView(context).apply {
                    text = value
                    textSize = 15f
                    setTextColor(color(Ui.TEXT))
                    includeFontPadding = false
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                }
            )
            if (clickable && onClick != null) {
                background = roundedDrawable("#00FFFFFF", radiusDp = 6)
                setOnClickListener { onClick() }
            }
        }
    }

    private fun detailMarkerStrip(task: PlanningTask): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(38)
            setPadding(0, 0, 0, dp(6))
            addView(
                iconButton(
                    if (isDone(task)) R.drawable.ic_check_circle else R.drawable.ic_radio_button_unchecked,
                    localizedStatus(task.status)
                ) {
                    showStatusDialog(task)
                }.apply {
                    layoutParams = LinearLayout.LayoutParams(dp(40), dp(40)).apply { marginEnd = dp(4) }
                }
            )
            addView(markerDot(taskTypeColor(task), taskTypeA11y(task)))
            addView(counterText("${copy().priorityShort}${task.priority}"))
            dueChip(task)?.let {
                addView(it.apply {
                    if (!task.shared) {
                        setOnClickListener { showDueDialog(task) }
                    }
                })
            }
            addView(
                View(context).apply {
                    layoutParams = LinearLayout.LayoutParams(0, 1, 1f)
                }
            )
            if (!task.shared) {
                addView(iconButton(R.drawable.ic_edit, copy().edit) { showTaskDialog(task) }.apply {
                    layoutParams = LinearLayout.LayoutParams(dp(40), dp(40))
                })
                addView(iconButton(R.drawable.ic_chevron_right, copy().reschedule) { showRescheduleDialog(task) }.apply {
                    layoutParams = LinearLayout.LayoutParams(dp(40), dp(40))
                })
            }
        }
    }

    private fun pathLine(path: String): TextView {
        return TextView(this).apply {
            text = path
            textSize = 13f
            setTextColor(color(Ui.MUTED))
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            includeFontPadding = false
            setPadding(0, dp(2), 0, dp(14))
        }
    }

    private fun settingsRow(label: String, value: String, onClick: (() -> Unit)? = null): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(52)
            setPadding(0, 0, 0, 0)
            addView(
                TextView(context).apply {
                    text = label
                    textSize = 15f
                    setTextColor(color(Ui.TEXT))
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                }
            )
            addView(
                TextView(context).apply {
                    text = value
                    textSize = 14f
                    setTextColor(color(Ui.MUTED))
                    gravity = Gravity.END
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                }
            )
            onClick?.let { click ->
                setOnClickListener { click() }
            }
        }
    }

    private fun settingsHelp(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 13f
            setTextColor(color(Ui.MUTED))
            setLineSpacing(dp(2).toFloat(), 1f)
            setPadding(0, dp(2), 0, dp(8))
        }
    }

    private data class DateTimeField(
        val view: View,
        val isoValue: () -> String?
    )

    private fun dateTimeField(label: String, initialIso: String?): DateTimeField {
        var value = parseInstant(initialIso)?.atZone(zone)?.toLocalDateTime()
        val c = copy()
        lateinit var pickerLabel: TextView
        lateinit var clearButton: ImageButton

        fun buttonText(): String {
            val formatted = value?.let { formatDateTime(it.atZone(zone).toInstant().toString()) } ?: c.noDate
            return "$label: $formatted"
        }

        fun updateButtons() {
            pickerLabel.text = buttonText()
            clearButton.visibility = if (value == null) View.INVISIBLE else View.VISIBLE
            clearButton.isEnabled = value != null
        }

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(48)
            ).apply { topMargin = dp(10) }
            pickerLabel = TextView(context).apply {
                text = buttonText()
                textSize = 14.5f
                gravity = Gravity.CENTER
                includeFontPadding = false
                setTextColor(color(Ui.TEXT))
                background = roundedDrawable("#00FFFFFF", strokeColorHex = Ui.HAIRLINE, radiusDp = 8)
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f)
            }
            setOnClickListener {
                hideKeyboardAndClearFocus()
                pickDateTime(value ?: LocalDateTime.now(zone).plusHours(1).withMinute(0).withSecond(0).withNano(0)) {
                    value = it
                    updateButtons()
                }
            }
            addView(pickerLabel)
            clearButton = iconButton(R.drawable.ic_delete, c.clearDate) {
                hideKeyboardAndClearFocus()
                value = null
                updateButtons()
            }.apply {
                setColorFilter(color(Ui.DANGER))
                visibility = if (value == null) View.INVISIBLE else View.VISIBLE
                isEnabled = value != null
                layoutParams = LinearLayout.LayoutParams(
                    dp(44),
                    dp(44)
                ).apply { leftMargin = dp(6) }
            }
            addView(clearButton)
        }

        return DateTimeField(
            view = container,
            isoValue = { value?.atZone(zone)?.toInstant()?.toString() }
        )
    }

    private fun pickDateTime(initial: LocalDateTime, onSelected: (LocalDateTime) -> Unit) {
        DatePickerDialog(
            this,
            { _, year, month, day ->
                TimePickerDialog(
                    this,
                    { _, hour, minute ->
                        onSelected(LocalDateTime.of(year, month + 1, day, hour, minute))
                    },
                    initial.hour,
                    initial.minute,
                    currentLanguage != "en"
                ).show()
            },
            initial.year,
            initial.monthValue - 1,
            initial.dayOfMonth
        ).show()
    }

    private fun dialogInput(
        hint: String,
        value: String,
        multiline: Boolean = false,
        inputPurpose: TextInputPurpose = if (multiline) TextInputPurpose.Notes else TextInputPurpose.Text,
        isPassword: Boolean = false,
        inputTypeOverride: Int? = null,
        imeOptionsOverride: Int? = null
    ): EditText {
        return EditText(this).apply {
            this.hint = hint
            setText(value)
            styleInput()
            val resolvedInputType = inputTypeOverride ?: when {
                isPassword -> inputTypeForPurpose(TextInputPurpose.Password)
                else -> inputTypeForPurpose(inputPurpose)
            }
            val resolvedImeOptions = imeOptionsOverride
                ?: if (multiline) {
                    EditorInfo.IME_ACTION_NONE or EditorInfo.IME_FLAG_NO_EXTRACT_UI
                } else {
                    EditorInfo.IME_ACTION_DONE
                }
            applyInputOptions(
                inputType = resolvedInputType,
                imeOptions = resolvedImeOptions,
                singleLine = !multiline,
                inputPurpose = inputPurpose
            )
            if (multiline) {
                gravity = Gravity.TOP or Gravity.START
                minLines = 3
                maxLines = 6
                setPadding(dp(12), dp(10), dp(12), dp(10))
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { topMargin = dp(10) }
            }
            if (isPassword) {
                applyPasswordVisibility(visible = false, autofillPurpose = TextInputPurpose.Password)
            }
            openKeyboardOnUserFocus()
        }
    }

    private fun openIdeaDetail(ideaId: String) {
        val session = currentSession ?: return
        selectedIdeaId = ideaId
        selectedIdeaDetail = findIdea(ideaId)
        selectedTaskId = null
        selectedTaskDetail = null
        currentScreen = Screen.IdeaDetail
        render()

        scope.launch {
            try {
                val result = planningRepository.getIdea(session, ideaId)
                currentSession = result.first
                selectedIdeaDetail = result.second
            } catch (error: Exception) {
                message = humanError(error)
            } finally {
                render()
            }
        }
    }

    private fun openNoteDetail(noteId: String) {
        selectedNoteId = noteId
        selectedNoteDetail = findNote(noteId)
        selectedTaskId = null
        selectedTaskDetail = null
        selectedIdeaId = null
        selectedIdeaDetail = null
        currentScreen = Screen.NoteDetail
        render()
    }

    private fun dialogForm(vararg inputs: View): ScrollView {
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(8), dp(20), 0)
            inputs.forEach { input ->
                (input.parent as? ViewGroup)?.removeView(input)
                addView(input)
            }
        }
        return ScrollView(this).apply {
            isFillViewport = false
            addView(content)
            hideKeyboardWhenTouchingOutsideInputs()
        }
    }

    private fun dialogContextLine(label: String, value: String): TextView {
        return TextView(this).apply {
            text = "$label: $value"
            textSize = 13f
            setTextColor(color(Ui.MUTED))
            setLineSpacing(dp(2).toFloat(), 1f)
            setPadding(0, dp(2), 0, dp(8))
        }
    }

    private fun detailDialogText(label: String, value: String): TextView {
        return TextView(this).apply {
            text = "$label: $value"
            textSize = 15f
            setTextColor(color(Ui.TEXT))
            setLineSpacing(dp(2).toFloat(), 1f)
            setPadding(0, dp(8), 0, dp(6))
        }
    }

    private fun detailDialogActions(vararg actions: Pair<String, () -> Unit>): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, dp(14), 0, dp(4))
            actions.forEachIndexed { index, action ->
                addView(
                    Button(context).apply {
                        text = action.first
                        setAllCaps(false)
                        textSize = 13.5f
                        includeFontPadding = false
                        minHeight = dp(42)
                        setTextColor(color(Ui.TEXT))
                        background = roundedDrawable(Ui.SURFACE, strokeColorHex = Ui.HAIRLINE, radiusDp = 8)
                        setOnClickListener { action.second() }
                        layoutParams = LinearLayout.LayoutParams(0, dp(42), 1f).apply {
                            if (index > 0) leftMargin = dp(8)
                        }
                    }
                )
            }
        }
    }

    private fun dialogLabel(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 13f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(color(Ui.MUTED))
            setPadding(0, dp(10), 0, dp(2))
        }
    }

    private fun taskTypeGroup(selectedType: String): RadioGroup {
        val selected = normalizeTaskType(selectedType)
        return RadioGroup(this).apply {
            orientation = RadioGroup.HORIZONTAL
            setPadding(0, 0, 0, dp(2))
            addView(taskTypeRadioButton("green", selected == "green"))
            addView(taskTypeRadioButton("red", selected == "red"))
        }
    }

    private fun taskTypeRadioButton(type: String, checked: Boolean): RadioButton {
        return RadioButton(this).apply {
            id = View.generateViewId()
            tag = type
            text = taskTypeLabel(type)
            isChecked = checked
            textSize = 15f
            setTextColor(color(Ui.TEXT))
            layoutParams = RadioGroup.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
    }

    private fun RadioGroup.selectedTaskType(): String {
        val selected = findViewById<RadioButton>(checkedRadioButtonId)?.tag as? String
        return normalizeTaskType(selected ?: "green")
    }

    private fun passwordInputRow(passwordField: EditText, initialVisible: Boolean): LinearLayout {
        var visible = initialVisible
        passwordField.applyPasswordVisibility(visible)
        passwordField.layoutParams = LinearLayout.LayoutParams(
            0,
            LinearLayout.LayoutParams.MATCH_PARENT,
            1f
        )
        val toggle = Button(this).apply {
            text = passwordVisibilityToggleText(visible)
            contentDescription = passwordVisibilityToggleDescription(visible)
            setAllCaps(false)
            textSize = 13f
            includeFontPadding = false
            minHeight = dp(48)
            setTextColor(color(Ui.TEXT))
            background = roundedDrawable(Ui.SURFACE, strokeColorHex = Ui.HAIRLINE, radiusDp = 8)
            layoutParams = LinearLayout.LayoutParams(
                dp(104),
                LinearLayout.LayoutParams.MATCH_PARENT
            ).apply { leftMargin = dp(8) }
            setOnClickListener {
                val cursor = passwordField.selectionStart
                visible = !visible
                passwordField.applyPasswordVisibility(visible, cursor)
                text = passwordVisibilityToggleText(visible)
                contentDescription = passwordVisibilityToggleDescription(visible)
                passwordField.requestFocus()
                passwordField.post { showKeyboard(passwordField) }
            }
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(48)
            ).apply { topMargin = dp(10) }
            addView(passwordField)
            addView(toggle)
        }
    }

    private fun EditText.styleInput() {
        textSize = 15f
        setTextColor(color(Ui.TEXT))
        setHintTextColor(color(Ui.MUTED))
        imeHintLocales = if (currentLanguage == "en") {
            LocaleList(Locale.US, Locale("ru", "RU"))
        } else {
            LocaleList(Locale("ru", "RU"), Locale.US)
        }
        background = roundedDrawable(Ui.SURFACE, strokeColorHex = Ui.HAIRLINE, radiusDp = 8)
        setPadding(dp(12), 0, dp(12), 0)
        minHeight = dp(48)
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(48)
        ).apply { topMargin = dp(10) }
    }

    private fun stableTextInputType(): Int {
        return InputType.TYPE_CLASS_TEXT or
            InputType.TYPE_TEXT_VARIATION_NORMAL or
            InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or
            InputType.TYPE_TEXT_FLAG_AUTO_CORRECT
    }

    private fun notesInputType(): Int {
        return stableTextInputType() or InputType.TYPE_TEXT_FLAG_MULTI_LINE
    }

    private fun emailInputType(): Int {
        return InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
    }

    private fun codeInputType(): Int {
        return InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_NORMAL
    }

    private fun searchInputType(): Int {
        return InputType.TYPE_CLASS_TEXT or
            InputType.TYPE_TEXT_VARIATION_NORMAL or
            InputType.TYPE_TEXT_FLAG_AUTO_CORRECT
    }

    private fun usernameInputType(): Int {
        return InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_NORMAL
    }

    private fun inputTypeForPurpose(purpose: TextInputPurpose): Int {
        return when (purpose) {
            TextInputPurpose.Text, TextInputPurpose.Name -> stableTextInputType()
            TextInputPurpose.Notes -> notesInputType()
            TextInputPurpose.Email -> emailInputType()
            TextInputPurpose.Password -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            TextInputPurpose.Code -> codeInputType()
            TextInputPurpose.Search -> searchInputType()
            TextInputPurpose.Number -> InputType.TYPE_CLASS_NUMBER
            TextInputPurpose.Username -> usernameInputType()
        }
    }

    private fun EditText.applyInputOptions(
        inputType: Int,
        imeOptions: Int,
        singleLine: Boolean = true,
        inputPurpose: TextInputPurpose = TextInputPurpose.Text
    ) {
        this.inputType = inputType
        if (singleLine) {
            setSingleLine(true)
            maxLines = 1
            setHorizontallyScrolling(true)
        } else {
            setSingleLine(false)
            isSingleLine = false
            setHorizontallyScrolling(false)
        }
        this.imeOptions = imeOptions or EditorInfo.IME_FLAG_NO_EXTRACT_UI
        imeHintLocales = if (currentLanguage == "en") {
            LocaleList(Locale.US, Locale("ru", "RU"))
        } else {
            LocaleList(Locale("ru", "RU"), Locale.US)
        }
        applyAutofill(inputPurpose)
        showSoftInputOnFocus = true
    }

    private fun EditText.applyAutofill(inputPurpose: TextInputPurpose) {
        importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_YES
        setAutofillHints(*autofillHintsFor(inputPurpose, hint?.toString().orEmpty()))
    }

    private fun autofillHintsFor(inputPurpose: TextInputPurpose, fieldHint: String): Array<String> {
        val hints = when (inputPurpose) {
            TextInputPurpose.Text -> listOf(AutofillHints.TEXT, AutofillHints.TITLE, fieldHint)
            TextInputPurpose.Notes -> listOf(AutofillHints.NOTE, fieldHint)
            TextInputPurpose.Email -> listOf(View.AUTOFILL_HINT_EMAIL_ADDRESS, View.AUTOFILL_HINT_USERNAME, fieldHint)
            TextInputPurpose.Password -> listOf(View.AUTOFILL_HINT_PASSWORD)
            TextInputPurpose.Code -> listOf(AutofillHints.CODE, fieldHint)
            TextInputPurpose.Search -> listOf(AutofillHints.SEARCH, fieldHint)
            TextInputPurpose.Number -> listOf(AutofillHints.NUMBER, fieldHint)
            TextInputPurpose.Name -> listOf(View.AUTOFILL_HINT_NAME, fieldHint)
            TextInputPurpose.Username -> listOf(View.AUTOFILL_HINT_USERNAME, fieldHint)
        }
        return hints.map { it.trim() }.filter { it.isNotEmpty() }.distinct().toTypedArray()
    }

    private fun View.hideKeyboardWhenTouchingOutsideInputs() {
        setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_DOWN) {
                val focused = currentFocus
                if (focused is EditText) {
                    val focusedBounds = Rect()
                    focused.getGlobalVisibleRect(focusedBounds)
                    if (!focusedBounds.contains(event.rawX.toInt(), event.rawY.toInt())) {
                        hideKeyboardAndClearFocus(focused)
                    }
                }
            }
            false
        }
    }

    private fun focusDialogInput(dialog: AlertDialog, input: EditText) {
        dialog.window?.setSoftInputMode(
            WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE or
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        )
        input.ensureKeyboardVisible()
    }

    private fun EditText.keepDraftUpdated(update: (String) -> Unit) {
        addTextChangedListener(
            object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit

                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit

                override fun afterTextChanged(s: Editable?) {
                    update(s?.toString().orEmpty())
                }
            }
        )
    }

    private fun EditText.applyPasswordVisibility(
        visible: Boolean,
        cursorPosition: Int? = null,
        autofillPurpose: TextInputPurpose = TextInputPurpose.Password
    ) {
        val cursor = cursorPosition?.takeIf { it >= 0 } ?: (text?.length ?: 0)
        val preservedImeOptions = imeOptions.takeIf { it != EditorInfo.IME_NULL } ?: EditorInfo.IME_ACTION_DONE
        applyInputOptions(
            inputType = InputType.TYPE_CLASS_TEXT or if (visible) {
                InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
            } else {
                InputType.TYPE_TEXT_VARIATION_PASSWORD
            },
            imeOptions = preservedImeOptions,
            inputPurpose = autofillPurpose
        )
        transformationMethod = if (visible) {
            HideReturnsTransformationMethod.getInstance()
        } else {
            FullyHiddenPasswordTransformationMethod
        }
        typeface = Typeface.DEFAULT
        setSelection(cursor.coerceIn(0, text?.length ?: 0))
    }

    private object FullyHiddenPasswordTransformationMethod : TransformationMethod {
        override fun getTransformation(source: CharSequence?, view: View?): CharSequence {
            return HiddenPasswordCharSequence(source ?: "")
        }

        override fun onFocusChanged(
            view: View?,
            sourceText: CharSequence?,
            focused: Boolean,
            direction: Int,
            previouslyFocusedRect: Rect?
        ) = Unit
    }

    private class HiddenPasswordCharSequence(private val source: CharSequence) : CharSequence {
        override val length: Int
            get() = source.length

        override fun get(index: Int): Char = '\u2022'

        override fun subSequence(startIndex: Int, endIndex: Int): CharSequence {
            return "\u2022".repeat((endIndex - startIndex).coerceAtLeast(0))
        }

        override fun toString(): String = "\u2022".repeat(length)
    }

    private fun passwordVisibilityToggleText(visible: Boolean): String {
        return if (visible) {
            if (currentLanguage == "en") "Hide" else "\u0421\u043a\u0440\u044b\u0442\u044c"
        } else {
            if (currentLanguage == "en") "Show" else "\u041f\u043e\u043a\u0430\u0437\u0430\u0442\u044c"
        }
    }

    private fun passwordVisibilityToggleDescription(visible: Boolean): String {
        return if (visible) {
            "Hide password / \u0421\u043a\u0440\u044b\u0442\u044c \u043f\u0430\u0440\u043e\u043b\u044c"
        } else {
            "Show password / \u041f\u043e\u043a\u0430\u0437\u0430\u0442\u044c \u043f\u0430\u0440\u043e\u043b\u044c"
        }
    }

    private fun EditText.openKeyboardOnUserFocus() {
        isFocusable = true
        isFocusableInTouchMode = true
        showSoftInputOnFocus = true
        setOnFocusChangeListener { view, hasFocus ->
            if (hasFocus) {
                activeTextInput = this
                view.ensureKeyboardVisible()
            } else if (activeTextInput === this) {
                activeTextInput = null
            }
        }
        setOnClickListener {
            activeTextInput = this
            ensureKeyboardVisible()
        }
    }

    private fun View.ensureKeyboardVisible() {
        if (!isFocused) {
            requestFocusFromTouch()
        }
        val serial = ++keyboardShowSerial
        postKeyboardShowIfFocused(serial, 90)
        postKeyboardShowIfFocused(serial, 240)
        postKeyboardShowIfFocused(serial, 520)
    }

    private fun View.postKeyboardShowIfFocused(serial: Int, delayMs: Long) {
        postDelayed(
            {
                if (keyboardShowSerial == serial && isFocused && windowToken != null) {
                    showKeyboard(this)
                }
            },
            delayMs
        )
    }

    private fun showKeyboard(view: View) {
        if (!view.isFocused || view.windowToken == null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            view.windowInsetsController?.show(WindowInsets.Type.ime())
        }
        getSystemService(InputMethodManager::class.java)
            ?.showSoftInput(view, InputMethodManager.SHOW_FORCED)
    }

    private fun hideKeyboardAndClearFocus(view: View? = currentFocus) {
        val focused = view ?: window.decorView
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            focused.windowInsetsController?.hide(WindowInsets.Type.ime())
        }
        getSystemService(InputMethodManager::class.java)
            ?.hideSoftInputFromWindow(focused.windowToken, 0)
        focused.clearFocus()
    }

    private fun filteredFolders(): List<PlanningFolder> {
        val query = searchQuery.trim().lowercase(Locale.ROOT)
        if (query.isBlank()) return folders
        return folders.filter { folder ->
            folder.name.lowercase(Locale.ROOT).contains(query) ||
                ideasForFolder(folder.id).any { it.title.lowercase(Locale.ROOT).contains(query) } ||
                notesForFolder(folder.id).any { it.title.lowercase(Locale.ROOT).contains(query) || it.body.lowercase(Locale.ROOT).contains(query) } ||
                goalsForFolder(folder.id).any { goal ->
                    goal.name.lowercase(Locale.ROOT).contains(query) ||
                        tasksForGoal(goal.id).any { it.title.lowercase(Locale.ROOT).contains(query) }
                }
        }
    }

    private fun filteredSharedFolders(): List<PlanningFolder> {
        val query = searchQuery.trim().lowercase(Locale.ROOT)
        if (query.isBlank()) return sharedFolders
        return sharedFolders.filter { folder ->
            folder.name.lowercase(Locale.ROOT).contains(query) ||
                ideasForFolder(folder.id, includeShared = true).any { it.title.lowercase(Locale.ROOT).contains(query) } ||
                notesForFolder(folder.id, includeShared = true).any { it.title.lowercase(Locale.ROOT).contains(query) || it.body.lowercase(Locale.ROOT).contains(query) } ||
                goalsForFolder(folder.id, includeShared = true).any { goal ->
                    goal.name.lowercase(Locale.ROOT).contains(query) ||
                        tasksForGoal(goal.id, includeShared = true).any { it.title.lowercase(Locale.ROOT).contains(query) }
                }
        }
    }

    private fun filteredSharedGoals(): List<PlanningGoal> {
        val query = searchQuery.trim().lowercase(Locale.ROOT)
        if (query.isBlank()) return sharedGoals
        return sharedGoals.filter { goal ->
            goal.name.lowercase(Locale.ROOT).contains(query) ||
                tasksForGoal(goal.id, includeShared = true).any { it.title.lowercase(Locale.ROOT).contains(query) }
        }
    }

    private fun filteredSharedTasks(): List<PlanningTask> {
        val query = searchQuery.trim().lowercase(Locale.ROOT)
        if (query.isBlank()) return sharedTasks
        return sharedTasks.filter { it.title.lowercase(Locale.ROOT).contains(query) }
    }

    private fun filteredIdeas(): List<PlanningIdea> {
        val query = searchQuery.trim().lowercase(Locale.ROOT)
        if (query.isBlank()) return ideas
        return ideas.filter { it.title.lowercase(Locale.ROOT).contains(query) || it.body.lowercase(Locale.ROOT).contains(query) }
    }

    private fun filteredSharedIdeas(): List<PlanningIdea> {
        val query = searchQuery.trim().lowercase(Locale.ROOT)
        if (query.isBlank()) return sharedIdeas
        return sharedIdeas.filter { it.title.lowercase(Locale.ROOT).contains(query) || it.body.lowercase(Locale.ROOT).contains(query) }
    }

    private fun filteredNotes(): List<PlanningNote> {
        val query = searchQuery.trim().lowercase(Locale.ROOT)
        if (query.isBlank()) return notes
        return notes.filter { it.title.lowercase(Locale.ROOT).contains(query) || it.body.lowercase(Locale.ROOT).contains(query) }
    }

    private fun filteredSharedNotes(): List<PlanningNote> {
        val query = searchQuery.trim().lowercase(Locale.ROOT)
        if (query.isBlank()) return sharedNotes
        return sharedNotes.filter { it.title.lowercase(Locale.ROOT).contains(query) || it.body.lowercase(Locale.ROOT).contains(query) }
    }

    private fun goalsForFolder(folderId: String, includeShared: Boolean = false): List<PlanningGoal> {
        val own = goals.filter { it.folderId == folderId }
        return if (includeShared) own + sharedGoals.filter { it.folderId == folderId } else own
    }

    private fun childFoldersForFolder(folderId: String, includeShared: Boolean = false): List<PlanningFolder> {
        val own = folders.filter { it.parentFolderId == folderId }
        return if (includeShared) own + sharedFolders.filter { it.parentFolderId == folderId } else own
    }

    private fun tasksForGoal(goalId: String, includeShared: Boolean = false): List<PlanningTask> {
        val own = tasks.filter { it.goalId == goalId }
        return if (includeShared) own + sharedTasks.filter { it.goalId == goalId } else own
    }

    private fun ideasForFolder(folderId: String, includeShared: Boolean = false): List<PlanningIdea> {
        val own = ideas.filter { it.folderId == folderId }
        return if (includeShared) own + sharedIdeas.filter { it.folderId == folderId } else own
    }

    private fun notesForFolder(folderId: String, includeShared: Boolean = false): List<PlanningNote> {
        val own = notes.filter { it.folderId == folderId }
        return if (includeShared) own + sharedNotes.filter { it.folderId == folderId } else own
    }

    private fun ideaNotesForIdea(ideaId: String): List<IdeaNote> {
        return (ideaNotes + sharedIdeaNotes).filter { it.ideaId == ideaId }
    }

    private fun allTasks(): List<PlanningTask> = tasks + sharedTasks

    private fun allIdeas(): List<PlanningIdea> = ideas + sharedIdeas

    private fun allNotes(): List<PlanningNote> = notes + sharedNotes

    private fun allFolders(): List<PlanningFolder> = folders + sharedFolders

    private fun allGoals(): List<PlanningGoal> = goals + sharedGoals

    private fun findTask(taskId: String?): PlanningTask? {
        if (taskId == null) return null
        return allTasks().firstOrNull { it.id == taskId }
    }

    private fun findIdea(ideaId: String?): PlanningIdea? {
        if (ideaId == null) return null
        return allIdeas().firstOrNull { it.id == ideaId }
    }

    private fun findNote(noteId: String?): PlanningNote? {
        if (noteId == null) return null
        return allNotes().firstOrNull { it.id == noteId }
    }

    private fun findFolder(folderId: String?): PlanningFolder? {
        if (folderId == null) return null
        return allFolders().firstOrNull { it.id == folderId }
    }

    private fun findGoal(goalId: String?): PlanningGoal? {
        if (goalId == null) return null
        return allGoals().firstOrNull { it.id == goalId }
    }

    private fun isDone(task: PlanningTask): Boolean = task.status == "done"

    private fun taskSubtitle(task: PlanningTask): String {
        val due = task.dueTime ?: task.plannedTime
        return due?.let(::formatDateTime) ?: localizedStatus(task.status)
    }

    private fun describeTaskTags(task: PlanningTask): String {
        val names = task.tagIds.mapNotNull { id -> taskTags.firstOrNull { it.id == id }?.name }
        return names.joinToString(", ").ifBlank { copy().noDate }
    }

    private fun describeRecurrence(raw: String?): String {
        val json = raw?.let(::jsonObjectOrNull) ?: return copy().noRecurrence
        if (!json.optBoolean("active", false)) return copy().noRecurrence
        val interval = json.optInt("interval", 1).coerceAtLeast(1)
        val start = formatDateTime(json.optString("startAt").ifBlank { null })
        return when (json.optString("mode")) {
            "weekly" -> {
                val days = weekdaySummary(json.optJSONArray("daysOfWeek"))
                if (currentLanguage == "en") {
                    if (interval == 1) "Weekly on $days from $start" else "Every $interval weeks on $days from $start"
                } else {
                    if (interval == 1) "Еженедельно: $days, с $start" else "Каждые $interval нед.: $days, с $start"
                }
            }
            "monthly" -> {
                val day = json.optInt("dayOfMonth", 1)
                if (currentLanguage == "en") {
                    if (interval == 1) "Monthly on day $day from $start" else "Every $interval months on day $day from $start"
                } else {
                    if (interval == 1) "Ежемесячно: $day-го числа, с $start" else "Каждые $interval мес.: $day-го числа, с $start"
                }
            }
            else -> {
                if (currentLanguage == "en") {
                    if (interval == 1) "Daily from $start" else "Every $interval days from $start"
                } else {
                    if (interval == 1) "Ежедневно с $start" else "Каждые $interval дн. с $start"
                }
            }
        }
    }

    private fun describeLocalReminder(task: PlanningTask): String {
        val userId = currentSession?.user?.id ?: return copy().noDate
        val setting = taskReminderStore.read(userId, task.id)?.takeIf { it.enabled } ?: return copy().noDate
        val repeat = when (setting.repeat) {
            TaskReminderRepeat.None -> null
            TaskReminderRepeat.Daily -> copy().daily
            TaskReminderRepeat.Weekly -> copy().weekly
            TaskReminderRepeat.Monthly -> copy().monthly
        }
        return listOfNotNull(formatReminderDateTime(setting.triggerAtMillis), repeat).joinToString(", ")
    }

    private fun describeReminders(raw: String?): String {
        val reminders = raw?.let(::jsonArrayOrNull) ?: return copy().noDate
        if (reminders.length() == 0) return copy().noDate
        return (0 until reminders.length()).joinToString("; ") { index ->
            val item = reminders.optJSONObject(index) ?: JSONObject()
            val mode = if (item.optString("mode") == "before_planned_time") {
                copy().remindersBeforePlanned
            } else {
                copy().remindersBeforeDue
            }
            val paused = if (item.optBoolean("active", true)) "" else " (${copy().remindersOff.lowercase(Locale.ROOT)})"
            "${item.optInt("offsetMinutes", 0)} min $mode$paused"
        }
    }

    private fun recurrenceMode(raw: String?): String {
        val json = raw?.let(::jsonObjectOrNull) ?: return ""
        return if (json.optBoolean("active", false)) json.optString("mode") else ""
    }

    private fun recurrencePayload(task: PlanningTask, selectedMode: String, active: Boolean): JSONObject {
        val mode = selectedMode.ifBlank { recurrenceMode(task.recurrenceJson).ifBlank { "daily" } }
        val startAt = task.plannedTime ?: task.dueTime ?: Instant.now().toString()
        val startDate = parseInstant(startAt)?.atZone(zone)?.toLocalDate() ?: LocalDate.now(zone)
        return JSONObject()
            .put("mode", mode)
            .put("interval", 1)
            .put("daysOfWeek", if (mode == "weekly") JSONArray().put(startDate.dayOfWeek.name) else JSONArray())
            .put("dayOfMonth", if (mode == "monthly") startDate.dayOfMonth else JSONObject.NULL)
            .put("startAt", startAt)
            .put("endAt", JSONObject.NULL)
            .put("active", active)
    }

    private fun reminderPayload(mode: String, offsetMinutes: Int): JSONObject {
        return JSONObject()
            .put("mode", mode)
            .put("offsetMinutes", offsetMinutes)
            .put("active", true)
    }

    private fun defaultReminderDateTime(task: PlanningTask): LocalDateTime {
        val taskTime = (task.dueTime ?: task.plannedTime)
            ?.let(::parseInstant)
            ?.atZone(zone)
            ?.toLocalDateTime()
        val fallback = LocalDateTime.now(zone).plusHours(1)
        return (taskTime ?: fallback).withSecond(0).withNano(0)
    }

    private fun formatReminderDateTime(dateTime: LocalDateTime): String {
        val locale = if (currentLanguage == "en") Locale.ENGLISH else Locale("ru")
        val pattern = if (currentLanguage == "en") "MMM d, yyyy h:mm a" else "dd.MM.yyyy HH:mm"
        return DateTimeFormatter.ofPattern(pattern, locale).format(dateTime)
    }

    private fun formatReminderDateTime(triggerAtMillis: Long): String {
        return formatReminderDateTime(Instant.ofEpochMilli(triggerAtMillis).atZone(zone).toLocalDateTime())
    }

    private fun reminderFutureTimeMessage(): String {
        return if (currentLanguage == "en") {
            "Choose a future time."
        } else {
            "Выберите время в будущем."
        }
    }

    private fun reminderApproximateMessage(): String {
        return if (currentLanguage == "en") {
            "Reminder saved. Android may deliver it approximately until exact alarms are allowed."
        } else {
            "Напоминание сохранено. Android может сработать примерно, пока точные будильники не разрешены."
        }
    }

    private fun showExactAlarmSettingsDialog() {
        val title = if (currentLanguage == "en") "Exact alarms" else "Точные будильники"
        val body = if (currentLanguage == "en") {
            "RocketFlow saved the reminder and scheduled a safe fallback. Allow exact alarms in Android settings for alarm-like delivery."
        } else {
            "RocketFlow сохранил напоминание и поставил безопасный резервный таймер. Разрешите точные будильники в настройках Android."
        }
        val settings = if (currentLanguage == "en") "Settings" else "Настройки"
        AlertDialog.Builder(this)
            .setTitle(title)
            .setMessage(body)
            .setNegativeButton(copy().cancel, null)
            .setPositiveButton(settings) { _, _ ->
                runCatching { startActivity(taskReminderAlarmScheduler.exactAlarmSettingsIntent()) }
            }
            .show()
    }

    private fun showIdeaFolderDialog() {
        val c = copy()
        val availableFolders = (folders + sharedFolders).filter { canWrite(it) }
        if (availableFolders.isEmpty()) {
            AlertDialog.Builder(this)
                .setTitle(c.newIdea)
                .setMessage(c.folderFirst)
                .setNegativeButton(c.cancel, null)
                .setPositiveButton(c.newFolder) { _, _ -> window.decorView.post { showFolderDialog(null) } }
                .show()
            return
        }

        lateinit var dialog: AlertDialog
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            addView(sheetHeader(c.newIdea))
            addView(dialogContextLine(c.folder, c.folderFirst))
        }
        availableFolders.forEach { folder ->
            content.addView(selectionOption(R.drawable.ic_folder, folder.name, folder.description) {
                dialog.dismiss()
                selectedFolderId = folder.id
                window.decorView.postDelayed({ showIdeaDialog(folder.id) }, 120)
            })
        }
        dialog = AlertDialog.Builder(this).setView(content).create()
        dialog.show()
    }

    private fun showNoteFolderDialog() {
        val c = copy()
        val availableFolders = (folders + sharedFolders).filter { canWrite(it) }
        if (availableFolders.isEmpty()) {
            message = c.folderFirst
            render()
            return
        }

        lateinit var dialog: AlertDialog
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            addView(sheetHeader(c.newNote))
            addView(dialogContextLine(c.folder, c.folderFirst))
        }
        availableFolders.forEach { folder ->
            content.addView(selectionOption(R.drawable.ic_folder, folder.name, folder.description) {
                dialog.dismiss()
                selectedFolderId = folder.id
                window.decorView.postDelayed({ showNoteDialog(folder.id) }, 120)
            })
        }
        dialog = AlertDialog.Builder(this).setView(content).create()
        dialog.show()
    }

    private fun weekdaySummary(days: JSONArray?): String {
        if (days == null || days.length() == 0) return copy().noDate
        return (0 until days.length()).joinToString(", ") { index ->
            when (days.optString(index)) {
                "MONDAY" -> if (currentLanguage == "en") "Mon" else "Пн"
                "TUESDAY" -> if (currentLanguage == "en") "Tue" else "Вт"
                "WEDNESDAY" -> if (currentLanguage == "en") "Wed" else "Ср"
                "THURSDAY" -> if (currentLanguage == "en") "Thu" else "Чт"
                "FRIDAY" -> if (currentLanguage == "en") "Fri" else "Пт"
                "SATURDAY" -> if (currentLanguage == "en") "Sat" else "Сб"
                "SUNDAY" -> if (currentLanguage == "en") "Sun" else "Вс"
                else -> days.optString(index)
            }
        }
    }

    private fun jsonObjectOrNull(raw: String): JSONObject? {
        return try {
            JSONObject(raw)
        } catch (_: Exception) {
            null
        }
    }

    private fun jsonArrayOrNull(raw: String): JSONArray? {
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            null
        }
    }

    private fun taskTypeColor(task: PlanningTask): String {
        return if (normalizeTaskType(task.type) == "red") Ui.TASK_STATUS_RED else Ui.TASK_STATUS_GREEN
    }

    private fun taskTypeA11y(task: PlanningTask): String {
        return taskTypeLabel(task.type)
    }

    private fun taskTypeLabel(type: String): String {
        return if (normalizeTaskType(type) == "red") copy().redTask else copy().greenTask
    }

    private fun normalizeTaskType(type: String): String {
        return when (type.lowercase(Locale.ROOT)) {
            "red", "risk", "blocked" -> "red"
            else -> "green"
        }
    }

    private fun priorityColor(priority: Int): String {
        return when {
            priority <= 2 -> Ui.DANGER
            priority <= 5 -> Ui.AMBER
            else -> Ui.LOW
        }
    }

    private fun priorityA11y(priority: Int): String {
        val level = when {
            priority <= 2 -> if (currentLanguage == "en") "high" else "высокий"
            priority <= 5 -> if (currentLanguage == "en") "medium" else "средний"
            else -> if (currentLanguage == "en") "low" else "низкий"
        }
        return if (currentLanguage == "en") "Priority $level" else "Приоритет: $level"
    }

    private fun dueChipColor(raw: String?): String {
        val date = parseInstant(raw)?.atZone(zone)?.toLocalDate() ?: return Ui.MUTED
        val today = LocalDate.now(zone)
        return when {
            date.isBefore(today) -> Ui.DANGER
            date == today -> Ui.AMBER
            else -> Ui.ACCENT
        }
    }

    private fun taskPath(task: PlanningTask): String {
        val goal = goals.firstOrNull { it.id == task.goalId } ?: sharedGoals.firstOrNull { it.id == task.goalId }
        val folder = goal?.let { g -> folders.firstOrNull { it.id == g.folderId } ?: sharedFolders.firstOrNull { it.id == g.folderId } }
        return listOfNotNull(folder?.name, goal?.name).joinToString(" / ").ifBlank { copy().plan }
    }

    private fun ideaPath(idea: PlanningIdea): String {
        val folder = folders.firstOrNull { it.id == idea.folderId } ?: sharedFolders.firstOrNull { it.id == idea.folderId }
        return listOfNotNull(folder?.name, copy().idea).joinToString(" / ").ifBlank { copy().plan }
    }

    private fun notePath(note: PlanningNote): String {
        val folder = findFolder(note.folderId)
        return listOfNotNull(folderPath(folder), copy().note).joinToString(" / ").ifBlank { copy().plan }
    }

    private fun folderPath(folder: PlanningFolder?): String {
        if (folder == null) return copy().folder
        val names = mutableListOf<String>()
        var current: PlanningFolder? = folder
        val seen = mutableSetOf<String>()
        while (current != null && current.id !in seen) {
            names += current.name
            seen += current.id
            current = findFolder(current.parentFolderId)
        }
        return names.asReversed().joinToString(" / ")
    }

    private fun linksForEntity(type: String, id: String): List<EntityLink> {
        return entityLinks.filter {
            !it.archived && ((it.sourceType == type && it.sourceId == id) || (it.targetType == type && it.targetId == id))
        }
    }

    private fun linkedNoteFor(entityType: String, entityId: String, link: EntityLink): PlanningNote? {
        val noteId = when {
            link.sourceType == "note" && link.targetType == entityType && link.targetId == entityId -> link.sourceId
            link.targetType == "note" && link.sourceType == entityType && link.sourceId == entityId -> link.targetId
            else -> return null
        }
        return findNote(noteId)
    }

    private fun entityTitle(type: String, id: String): String {
        return when (type) {
            "goal" -> findGoal(id)?.name
            "task" -> findTask(id)?.title
            "idea" -> findIdea(id)?.title
            "note" -> findNote(id)?.title
            else -> null
        }.orEmpty()
    }

    private fun openEntityDetail(type: String, id: String) {
        when (type) {
            "goal" -> findGoal(id)?.let { showGoalDetails(it) }
            "task" -> openTaskDetail(id)
            "idea" -> openIdeaDetail(id)
            "note" -> openNoteDetail(id)
        }
    }

    private fun linkCandidates(sourceType: String, sourceId: String): List<Triple<String, String, String>> {
        return buildList {
            addAll(allGoals().filter { sourceType != "goal" || it.id != sourceId }.map { Triple("goal", it.id, it.name) })
            addAll(allTasks().filter { sourceType != "task" || it.id != sourceId }.map { Triple("task", it.id, it.title) })
            addAll(allIdeas().filter { sourceType != "idea" || it.id != sourceId }.map { Triple("idea", it.id, it.title) })
            addAll(allNotes().filter { sourceType != "note" || it.id != sourceId }.map { Triple("note", it.id, it.title) })
        }
    }

    private fun iconForEntity(type: String): Int {
        return when (type) {
            "folder" -> R.drawable.ic_folder
            "goal" -> R.drawable.ic_target
            "task" -> R.drawable.ic_radio_button_unchecked
            "idea" -> R.drawable.ic_radio_button_unchecked
            "note" -> R.drawable.ic_content_copy
            else -> R.drawable.ic_link
        }
    }

    private fun localizedEntityType(type: String): String {
        val c = copy()
        return when (type) {
            "folder" -> c.folder
            "goal" -> c.goal
            "task" -> c.task
            "idea" -> c.idea
            "note" -> c.note
            else -> type
        }
    }

    private fun canWrite(folder: PlanningFolder): Boolean = !folder.shared || folder.fullAccess
    private fun canWrite(goal: PlanningGoal): Boolean = !goal.shared || goal.fullAccess || goal.canCreateTasks
    private fun canWrite(task: PlanningTask): Boolean = !task.shared || task.fullAccess
    private fun canWrite(idea: PlanningIdea): Boolean = !idea.shared || idea.fullAccess
    private fun canWrite(note: PlanningNote): Boolean = !note.shared || note.fullAccess

    private fun PlanningTask.creatorLabel(): String? {
        return listOf(creatorName, creatorEmail, creatorUserId)
            .firstOrNull { !it.isNullOrBlank() }
    }

    private fun localizedStatus(status: String): String {
        val c = copy()
        return when (status) {
            "todo" -> c.statusTodo
            "in_progress" -> c.statusInProgress
            "done" -> c.statusDone
            "cancelled" -> c.statusCancelled
            else -> c.statusTodo
        }
    }

    private fun syncLabel(state: SyncState): String {
        val c = copy()
        return when (state) {
            SyncState.Synced -> c.synced
            SyncState.PendingCreate, SyncState.PendingUpdate, SyncState.PendingDelete -> c.pending
            SyncState.Conflict -> c.couldNotSync
        }
    }

    private fun planningStatusText(): String {
        val c = copy()
        return when {
            planningLastSyncError != null -> c.couldNotSync
            planningOffline -> c.offline
            planningPendingCount > 0 -> "${planningPendingCount} ${c.pending}"
            else -> c.syncOk
        }
    }

    private fun notificationPermissionLabel(): String {
        return if (notificationRuntime.hasNotificationPermission()) copy().remindersOn else copy().remindersOff
    }

    private fun notificationRegistrationLabel(): String {
        return if (currentDeviceRegistration?.active == true) copy().remindersOn else copy().remindersOff
    }

    private fun canEditIdea(idea: PlanningIdea): Boolean {
        return canWrite(idea)
    }

    private fun canEditIdeaNote(idea: PlanningIdea, note: IdeaNote): Boolean {
        val user = currentSession?.user ?: return false
        return canEditIdea(idea) ||
            (idea.allowAuthorNoteEdits && (note.authorUserId == user.id || note.authorEmail == user.email))
    }

    private fun PlanningIdea.toDraft(
        title: String = this.title,
        body: String = this.body,
        status: String = this.status,
        allowAuthorNoteEdits: Boolean = this.allowAuthorNoteEdits
    ): IdeaDraft {
        return IdeaDraft(
            title = title,
            body = body,
            status = status.ifBlank { "active" },
            allowAuthorNoteEdits = allowAuthorNoteEdits
        )
    }

    private fun PlanningTask.toDraft(
        title: String = this.title,
        description: String = this.description,
        type: String = this.type,
        status: String = this.status,
        priority: Int = this.priority,
        plannedTime: String? = this.plannedTime,
        dueTime: String? = this.dueTime,
        tagIds: List<String>? = this.tagIds,
        recurrenceJson: String? = this.recurrenceJson,
        remindersJson: String? = this.remindersJson
    ): TaskDraft {
        return TaskDraft(
            title = title,
            description = description,
            type = normalizeTaskType(type),
            priority = priority,
            status = status,
            plannedTime = plannedTime,
            dueTime = dueTime,
            tagIds = tagIds,
            recurrenceJson = recurrenceJson,
            remindersJson = remindersJson
        )
    }

    private fun formatDateTime(raw: String?): String {
        if (raw.isNullOrBlank()) return copy().noDate
        val zoned = parseInstant(raw)?.atZone(zone) ?: return if (raw.contains("T")) copy().noDate else raw
        val date = zoned.toLocalDate()
        val today = LocalDate.now(zone)
        val locale = if (currentLanguage == "en") Locale.ENGLISH else Locale("ru")
        val timePattern = if (currentLanguage == "en") "h:mm a" else "HH:mm"
        val time = DateTimeFormatter.ofPattern(timePattern, locale).format(zoned)
        return when (date) {
            today -> "${copy().today}, $time"
            today.plusDays(1) -> "${copy().tomorrow}, $time"
            else -> {
                val pattern = if (currentLanguage == "en") "MMM d, h:mm a" else "d MMM, HH:mm"
                DateTimeFormatter.ofPattern(pattern, locale).format(zoned)
            }
        }
    }

    private fun formatDateInput(raw: String?): String {
        val zoned = parseInstant(raw)?.atZone(zone) ?: return ""
        return DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm", Locale.ROOT).format(zoned)
    }

    private fun parseDateInput(input: String): String? {
        if (input.isBlank()) return null
        parseInstant(input)?.let { return it.toString() }
        return try {
            LocalDateTime.parse(input, DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm", Locale.ROOT))
                .atZone(zone)
                .toInstant()
                .toString()
        } catch (_: DateTimeParseException) {
            null
        }
    }

    private fun parseInstant(raw: String?): Instant? {
        if (raw.isNullOrBlank()) return null
        return try {
            Instant.parse(raw)
        } catch (_: Exception) {
            null
        }
    }

    private fun PlanningFolder.toShareTarget(): ShareTarget {
        return ShareTarget(ShareTargetType.Folder, id, name)
    }

    private fun PlanningGoal.toShareTarget(): ShareTarget {
        return ShareTarget(ShareTargetType.Goal, id, name)
    }

    private fun PlanningTask.toShareTarget(): ShareTarget {
        return ShareTarget(ShareTargetType.Task, id, title)
    }

    private fun shareLinkText(token: String): String {
        return "${rocketFlowWebBaseUrl()}/app/sharing?token=${Uri.encode(token)}"
    }

    private fun rocketFlowWebBaseUrl(): String {
        return BuildConfig.ROCKETFLOW_API_BASE_URL
            .trimEnd('/')
            .removeSuffix("/api")
    }

    private fun copyToClipboard(label: String, value: String) {
        getSystemService(ClipboardManager::class.java)
            .setPrimaryClip(ClipData.newPlainText(label, value))
        Toast.makeText(this, copy().linkCopied, Toast.LENGTH_SHORT).show()
    }

    private fun extractShareToken(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isBlank()) return ""

        val queryToken = runCatching {
            if ("://" in trimmed) Uri.parse(trimmed).getQueryParameter("token") else null
        }.getOrNull()
        if (!queryToken.isNullOrBlank()) return queryToken.trim()

        val marker = "/shares/links/"
        val candidate = if (marker in trimmed) trimmed.substringAfter(marker) else trimmed
        return candidate
            .substringBefore("/accept")
            .substringBefore("/")
            .substringBefore("?")
            .substringBefore("#")
            .trim()
    }

    private fun localizedShareTargetType(raw: String): String {
        return when (raw.lowercase(Locale.ROOT)) {
            "folder" -> copy().folder
            "goal" -> copy().goal
            "task" -> copy().task
            else -> raw
        }
    }

    private fun sharingError(error: Exception): String {
        val raw = error.message.orEmpty().lowercase(Locale.ROOT)
        return if (
            "network" in raw ||
            "failed to connect" in raw ||
            "timeout" in raw ||
            "unable to resolve host" in raw ||
            "connection refused" in raw
        ) {
            copy().offlineSharing
        } else {
            humanError(error)
        }
    }

    private fun notificationRegistrationError(error: Exception): String {
        if (isTerminalSessionFailure(error)) return copy().signInAgain
        if (error is ApiException && error.status == 401) return copy().signInAgain
        return copy().remindersEnableFailed
    }

    private fun humanError(error: Exception): String {
        return when (error) {
            is ApiException -> {
                localizedApiError(error)
                    ?: if (isTerminalSessionFailure(error)) {
                        copy().signInAgain
                    } else {
                        when (error.status) {
                            401 -> copy().signInAgain
                            else -> copy().requestFailed
                        }
                    }
            }
            else -> humanText(error.message)
        }
    }

    private fun localizedApiError(error: ApiException): String? {
        val c = copy()
        if (
            error.code == "authentication_failed" &&
            "email or password" in error.message.lowercase(Locale.ROOT)
        ) {
            return c.invalidCredentials
        }
        if (error.code == "validation_error") {
            val passwordError = error.fieldErrors["password"].orEmpty().lowercase(Locale.ROOT)
            if ("8" in passwordError || "size" in passwordError) {
                return c.passwordTooShort
            }
        }
        if (error.status == 409 && "email" in error.message.lowercase(Locale.ROOT)) {
            return c.emailAlreadyExists
        }
        if (
            error.code == "dependency_blocked" ||
            "dependency_blocked" in error.message.lowercase(Locale.ROOT)
        ) {
            return c.dependencyBlocked
        }
        return null
    }

    private fun humanText(raw: String?): String {
        if (raw.isNullOrBlank()) return copy().requestFailed
        val lower = raw.lowercase(Locale.ROOT)
        return when {
            "network" in lower || "failed to connect" in lower || "timeout" in lower -> copy().couldNotSync
            "firebase" in lower -> copy().firebaseUnavailable
            else -> copy().requestFailed
        }
    }

    private fun syncErrorText(raw: String): String {
        if (raw.isBlank()) return copy().couldNotSync
        val lower = raw.lowercase(Locale.ROOT)
        return when {
            "network" in lower || "failed to connect" in lower || "timeout" in lower -> copy().couldNotSync
            else -> raw
        }
    }

    private fun isTerminalSessionFailure(error: Exception): Boolean {
        return error is ApiException && error.status == 401 && authRepository.readStoredSession() == null
    }

    private fun defaultDeviceName(): String {
        return listOfNotNull(Build.MANUFACTURER, Build.MODEL)
            .joinToString(" ")
            .trim()
            .ifBlank { "Android" }
    }

    private fun handleTerminalSessionFailure() {
        runOnUiThread {
            currentSession = null
            currentSettings = null
            settingsLoadAttempted = false
            currentDeviceRegistration = notificationsRepository.readStoredRegistration()
            currentPushToken = notificationsRepository.readStoredPushToken()
            currentScreen = Screen.Auth
            clearPlannerState()
            message = copy().signedOut
            busy = false
            render()
        }
    }

    private fun registerNetworkRestore() {
        try {
            connectivityManager.registerDefaultNetworkCallback(networkCallback)
        } catch (_: Exception) {
            Toast.makeText(this, copy().couldNotSync, Toast.LENGTH_SHORT).show()
        }
    }

    private fun unregisterNetworkRestore() {
        try {
            connectivityManager.unregisterNetworkCallback(networkCallback)
        } catch (_: Exception) {
            // The callback may not have been registered on this device.
        }
    }

    private fun bottomBorderDrawable(fillColorHex: String): GradientDrawable {
        return roundedDrawable(fillColorHex, radiusDp = 0)
    }

    private fun divider(): View {
        return View(this).apply {
            setBackgroundColor(color(Ui.HAIRLINE))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(1)
            )
        }
    }

    private fun roundedDrawable(fillColorHex: String, strokeColorHex: String? = null, radiusDp: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(radiusDp).toFloat()
            setColor(color(fillColorHex))
            strokeColorHex?.let { setStroke(dp(1), color(it)) }
        }
    }

    private fun ovalDrawable(fillColorHex: String): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color(fillColorHex))
        }
    }

    private fun color(hex: String): Int = Color.parseColor(hex)

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private data class AcceptanceData(
        val folder: String,
        val goal: String,
        val firstTask: String,
        val secondTask: String,
        val thirdTask: String,
        val notes: String
    )

    private fun copy(): Copy {
        val en = currentLanguage == "en"
        return if (en) {
            Copy(
                signInTitle = "Sign in",
                email = "Email",
                password = "Password",
                signIn = "Sign in",
                createAccount = "Create account",
                displayName = "Name",
                plan = "Plan",
                settings = "Settings",
                syncDiagnostics = "Sync diagnostics",
                folder = "Folder",
                goal = "Goal",
                task = "Task",
                idea = "Idea",
                note = "Note",
                create = "Create",
                add = "Add",
                newFolder = "New folder",
                newGoal = "New goal",
                newTask = "New task",
                newIdea = "New idea",
                newNote = "New note",
                addNote = "Add note",
                editNote = "Edit note",
                ideaHistory = "History",
                links = "Links",
                linkedNotes = "Linked notes",
                related = "Related",
                dependency = "Dependency",
                move = "Move",
                clone = "Clone",
                fullAccess = "Full access",
                dependencyBlocked = "Complete blocking tasks first.",
                cannotMoveHere = "This item cannot be moved here.",
                dragMoveStarted = "Drag to a valid target.",
                allowAuthorNoteEdits = "Authors can edit their own history notes",
                allowAuthorNoteEditsHint = "The idea owner can always edit the history.",
                noteRequired = "Enter a note.",
                edit = "Edit",
                delete = "Delete",
                cancel = "Cancel",
                save = "Save",
                search = "Search",
                searchHint = "Task, goal, or folder",
                clearSearch = "Clear",
                nothingHere = "Nothing here yet",
                emptyBody = "Create a folder, then add a goal and tasks.",
                selectTask = "Select a task",
                taskDetail = "Task",
                notes = "Notes",
                status = "Status",
                priority = "Priority",
                planned = "Planned",
                due = "Due",
                tags = "Tags",
                recurrence = "Repeat",
                noRecurrence = "No repeat",
                daily = "Daily",
                weekly = "Weekly",
                monthly = "Monthly",
                remindersBeforeDue = "Before due",
                remindersBeforePlanned = "Before planned",
                addTag = "Add tag",
                newTag = "New tag",
                colorField = "Color, for example #2F6B57",
                metadata = "Scheduling",
                path = "Path",
                details = "Details",
                collapse = "Collapse",
                creator = "Creator",
                created = "Created",
                updated = "Updated",
                synced = "Synced",
                syncStatus = "Sync",
                syncOk = "Up to date",
                syncHelp = "Shows whether planner changes are uploaded, pending, or offline.",
                lastSyncError = "Last sync error",
                offline = "Offline",
                pending = "pending",
                savedOffline = "Saved offline",
                couldNotSync = "Could not sync",
                account = "Account",
                language = "Language",
                sharingHelp = "Accept an invitation link to add shared folders, goals, or tasks.",
                reminders = "Reminders",
                remindersHelp = "Android permission allows notifications; this phone connects task reminder delivery.",
                androidPermission = "Android permission",
                accountReminders = "Account reminders",
                deviceRegistration = "This phone",
                priorityDecay = "Priority decay",
                priorityDecayHelp = "When you postpone a task, RocketFlow totals the delay. After the selected threshold, priority drops by the chosen amount.",
                greenTasks = "Green tasks",
                redTasks = "Red tasks",
                taskType = "Task type",
                greenTask = "Green",
                redTask = "Red",
                taskNeedsGoal = "A task must belong to a goal. Select an existing goal or create one first.",
                deleteFolderWarning = "This folder contains %1\$d goals and %2\$d tasks. They will be deleted with the folder.",
                deleteGoalWarning = "This goal contains %1\$d tasks. They will be deleted with the goal.",
                threshold = "Threshold",
                decayAmount = "Decay",
                remindersOn = "On",
                remindersOff = "Off",
                enableNotifications = "Enable notifications",
                registerDevice = "Enable reminders",
                unregisterDevice = "Turn off reminders",
                firebaseUnavailable = "Reminders are not configured in this build.",
                remindersEnableFailed = "Could not enable reminders. Check sync and try again.",
                signedOut = "Signed out",
                signInAgain = "Sign in again to continue.",
                requestFailed = "Request failed.",
                invalidCredentials = "Invalid email or password.",
                passwordTooShort = "Password must be at least 8 characters.",
                emailAlreadyExists = "An account with this email already exists.",
                loading = "Loading...",
                noGoalYet = "No goals yet",
                noTaskYet = "No tasks yet",
                nameRequired = "Name is required.",
                titleRequired = "Title is required.",
                folderFirst = "Create or select a folder first.",
                goalFirst = "Create or select a goal first.",
                noDate = "None",
                pickDate = "Pick date",
                clearDate = "Clear",
                invalidDate = "Use day/week/month and a positive number.",
                today = "Today",
                tomorrow = "Tomorrow",
                reschedule = "Reschedule",
                later30m = "30 min",
                later1h = "1 hour",
                later3h = "3 hours",
                later24h = "24 hours",
                decayApplied = "Priority lowered",
                decayNotApplied = "Priority unchanged",
                statusTodo = "To do",
                statusInProgress = "In progress",
                statusDone = "Done",
                statusCancelled = "Cancelled",
                openingTask = "Opening task",
                syncNow = "Sync",
                signOut = "Sign out",
                titleField = "Title",
                nameField = "Name",
                notesField = "Notes",
                dueField = "Due",
                plannedField = "Plan",
                priorityField = "Priority 1-10",
                priorityRequired = "Priority must be from 1 to 10.",
                priorityShort = "P",
                sharing = "Sharing",
                share = "Share",
                shareByEmail = "Email",
                shareByUserId = "User ID",
                shareLink = "Link",
                invite = "Invite",
                inviteSent = "Invitation sent.",
                userId = "User ID",
                userIdField = "User ID",
                createLink = "Create link",
                existingLinks = "Existing links",
                noLinks = "No links yet",
                linkCreated = "Link created.",
                linkCopied = "Link copied.",
                copyLink = "Copy link",
                revoke = "Revoke",
                revoked = "Revoked",
                acceptLink = "Accept link",
                tokenField = "Token or link",
                resolve = "Check",
                accept = "Accept",
                linkAccepted = "Link accepted.",
                linkResolved = "Link is available.",
                expires = "Expires",
                active = "Active",
                noExpiry = "No expiry",
                offlineSharing = "Sharing needs a network connection."
            )
        } else {
            Copy(
                signInTitle = "\u0412\u0445\u043e\u0434",
                email = "Email",
                password = "\u041f\u0430\u0440\u043e\u043b\u044c",
                signIn = "\u0412\u043e\u0439\u0442\u0438",
                createAccount = "\u0421\u043e\u0437\u0434\u0430\u0442\u044c \u0430\u043a\u043a\u0430\u0443\u043d\u0442",
                displayName = "Имя",
                plan = "План",
                settings = "Настройки",
                syncDiagnostics = "Диагностика синхронизации",
                folder = "Папка",
                goal = "Цель",
                task = "Задача",
                idea = "\u0418\u0434\u0435\u044f",
                note = "\u0417\u0430\u043c\u0435\u0442\u043a\u0430",
                create = "Создать",
                newFolder = "Новая папка",
                newGoal = "Новая цель",
                newTask = "Новая задача",
                newIdea = "\u041d\u043e\u0432\u0430\u044f \u0438\u0434\u0435\u044f",
                newNote = "\u041d\u043e\u0432\u0430\u044f \u0437\u0430\u043c\u0435\u0442\u043a\u0430",
                addNote = "\u0414\u043e\u0431\u0430\u0432\u0438\u0442\u044c \u0437\u0430\u043c\u0435\u0442\u043a\u0443",
                editNote = "\u0418\u0437\u043c\u0435\u043d\u0438\u0442\u044c \u0437\u0430\u043c\u0435\u0442\u043a\u0443",
                ideaHistory = "\u0418\u0441\u0442\u043e\u0440\u0438\u044f",
                cannotMoveHere = "\u0421\u044e\u0434\u0430 \u043d\u0435\u043b\u044c\u0437\u044f \u043f\u0435\u0440\u0435\u043c\u0435\u0441\u0442\u0438.",
                dragMoveStarted = "\u041f\u0435\u0440\u0435\u0442\u0430\u0449\u0438\u0442\u0435 \u0432 \u0434\u043e\u043f\u0443\u0441\u0442\u0438\u043c\u043e\u0435 \u043c\u0435\u0441\u0442\u043e.",
                allowAuthorNoteEdits = "\u0410\u0432\u0442\u043e\u0440\u044b \u043c\u043e\u0433\u0443\u0442 \u0440\u0435\u0434\u0430\u043a\u0442\u0438\u0440\u043e\u0432\u0430\u0442\u044c \u0441\u0432\u043e\u0438 \u0437\u0430\u043c\u0435\u0442\u043a\u0438 \u0438\u0441\u0442\u043e\u0440\u0438\u0438",
                allowAuthorNoteEditsHint = "\u0412\u043b\u0430\u0434\u0435\u043b\u0435\u0446 \u0438\u0434\u0435\u0438 \u0432\u0441\u0435\u0433\u0434\u0430 \u043c\u043e\u0436\u0435\u0442 \u0440\u0435\u0434\u0430\u043a\u0442\u0438\u0440\u043e\u0432\u0430\u0442\u044c \u0438\u0441\u0442\u043e\u0440\u0438\u044e.",
                noteRequired = "\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u0437\u0430\u043c\u0435\u0442\u043a\u0443.",
                edit = "Изменить",
                delete = "Удалить",
                cancel = "Отмена",
                save = "Сохранить",
                search = "Поиск",
                searchHint = "Задача, цель или папка",
                clearSearch = "Очистить",
                nothingHere = "Пока пусто",
                emptyBody = "Создайте папку, затем добавьте цель и задачи.",
                selectTask = "Выберите задачу",
                taskDetail = "Задача",
                notes = "Заметки",
                status = "Статус",
                priority = "Приоритет",
                planned = "\u041a\u043e\u0433\u0434\u0430 \u0434\u0435\u043b\u0430\u0442\u044c",
                due = "\u0414\u0435\u0434\u043b\u0430\u0439\u043d",
                tags = "Теги",
                recurrence = "Повтор",
                noRecurrence = "Без повтора",
                daily = "Ежедневно",
                weekly = "Еженедельно",
                monthly = "Ежемесячно",
                remindersBeforeDue = "до срока",
                remindersBeforePlanned = "до плана",
                addTag = "Добавить тег",
                newTag = "Новый тег",
                colorField = "Цвет, например #2F6B57",
                metadata = "Расписание",
                path = "Путь",
                details = "Детали",
                collapse = "Свернуть",
                creator = "\u0421\u043e\u0437\u0434\u0430\u043b",
                created = "Создано",
                updated = "Обновлено",
                synced = "Синхронизировано",
                syncStatus = "Синхронизация",
                syncOk = "Данные актуальны",
                syncHelp = "Показывает, отправлены ли изменения, есть ли очередь на отправку или приложение сейчас офлайн.",
                lastSyncError = "Последняя ошибка",
                offline = "Офлайн",
                pending = "ожидают",
                savedOffline = "Сохранено офлайн",
                couldNotSync = "Не удалось синхронизировать",
                account = "Аккаунт",
                language = "Язык",
                sharingHelp = "Здесь можно принять ссылку-приглашение к папке, цели или задаче.",
                reminders = "Напоминания",
                remindersHelp = "Разрешение Android включает показ уведомлений, а подключение телефона привязывает напоминания к этому устройству.",
                androidPermission = "Разрешение Android",
                accountReminders = "Напоминания аккаунта",
                deviceRegistration = "Этот телефон",
                priorityDecay = "Снижение приоритета",
                priorityDecayHelp = "Если вы переносите задачу на позже, RocketFlow суммирует задержку. Когда набирается выбранный срок, приоритет уменьшается на указанное число.",
                greenTasks = "Зеленые задачи",
                redTasks = "Красные задачи",
                taskType = "\u0422\u0438\u043f \u0437\u0430\u0434\u0430\u0447\u0438",
                greenTask = "\u0417\u0435\u043b\u0435\u043d\u0430\u044f",
                redTask = "\u041a\u0440\u0430\u0441\u043d\u0430\u044f",
                taskNeedsGoal = "\u0417\u0430\u0434\u0430\u0447\u0430 \u0434\u043e\u043b\u0436\u043d\u0430 \u0431\u044b\u0442\u044c \u0432\u043d\u0443\u0442\u0440\u0438 \u0446\u0435\u043b\u0438. \u0412\u044b\u0431\u0435\u0440\u0438\u0442\u0435 \u0441\u0443\u0449\u0435\u0441\u0442\u0432\u0443\u044e\u0449\u0443\u044e \u0446\u0435\u043b\u044c \u0438\u043b\u0438 \u0441\u043e\u0437\u0434\u0430\u0439\u0442\u0435 \u043d\u043e\u0432\u0443\u044e.",
                deleteFolderWarning = "\u0412 \u043f\u0430\u043f\u043a\u0435 \u0435\u0441\u0442\u044c \u0446\u0435\u043b\u0438: %1\$d, \u0437\u0430\u0434\u0430\u0447\u0438: %2\$d. \u041e\u043d\u0438 \u0443\u0434\u0430\u043b\u044f\u0442\u0441\u044f \u0432\u043c\u0435\u0441\u0442\u0435 \u0441 \u043f\u0430\u043f\u043a\u043e\u0439.",
                deleteGoalWarning = "\u0412 \u0446\u0435\u043b\u0438 \u0435\u0441\u0442\u044c \u0437\u0430\u0434\u0430\u0447\u0438: %1\$d. \u041e\u043d\u0438 \u0443\u0434\u0430\u043b\u044f\u0442\u0441\u044f \u0432\u043c\u0435\u0441\u0442\u0435 \u0441 \u0446\u0435\u043b\u044c\u044e.",
                threshold = "Порог",
                decayAmount = "Снижение",
                remindersOn = "Включено",
                remindersOff = "Выключено",
                enableNotifications = "Включить уведомления",
                registerDevice = "Включить напоминания",
                unregisterDevice = "Отключить напоминания",
                firebaseUnavailable = "Напоминания не настроены в этой сборке.",
                remindersEnableFailed = "Не удалось включить напоминания. Проверьте синхронизацию и сеть, затем попробуйте снова.",
                signedOut = "Сессия завершена",
                signInAgain = "Войдите снова, чтобы продолжить.",
                requestFailed = "Запрос не выполнен.",
                invalidCredentials = "\u041d\u0435\u0432\u0435\u0440\u043d\u044b\u0439 email \u0438\u043b\u0438 \u043f\u0430\u0440\u043e\u043b\u044c.",
                passwordTooShort = "\u041f\u0430\u0440\u043e\u043b\u044c \u0434\u043e\u043b\u0436\u0435\u043d \u0431\u044b\u0442\u044c \u043d\u0435 \u043a\u043e\u0440\u043e\u0447\u0435 8 \u0441\u0438\u043c\u0432\u043e\u043b\u043e\u0432.",
                emailAlreadyExists = "\u0410\u043a\u043a\u0430\u0443\u043d\u0442 \u0441 \u0442\u0430\u043a\u0438\u043c email \u0443\u0436\u0435 \u0435\u0441\u0442\u044c.",
                loading = "Загрузка...",
                noGoalYet = "Целей пока нет",
                noTaskYet = "Задач пока нет",
                nameRequired = "Укажите название.",
                titleRequired = "Укажите заголовок.",
                folderFirst = "Сначала выберите или создайте папку.",
                goalFirst = "Сначала выберите или создайте цель.",
                noDate = "Нет",
                pickDate = "Выбрать дату",
                clearDate = "Очистить",
                invalidDate = "Укажите день, неделю или месяц и число больше 0.",
                today = "Сегодня",
                tomorrow = "Завтра",
                reschedule = "Перенести",
                later30m = "30 минут",
                later1h = "1 час",
                later3h = "3 часа",
                later24h = "24 часа",
                decayApplied = "Приоритет снижен",
                decayNotApplied = "Приоритет без изменений",
                statusTodo = "К выполнению",
                statusInProgress = "В работе",
                statusDone = "Готово",
                statusCancelled = "Отменено",
                openingTask = "Открываем задачу",
                syncNow = "Синхронизировать",
                signOut = "Выйти",
                titleField = "Заголовок",
                nameField = "Название",
                notesField = "Заметки",
                dueField = "Срок",
                plannedField = "План",
                priorityField = "Приоритет 1-10",
                priorityRequired = "Приоритет должен быть от 1 до 10.",
                priorityShort = "P",
                sharing = "Общий доступ",
                share = "Поделиться",
                shareByEmail = "Email",
                shareByUserId = "ID пользователя",
                shareLink = "Ссылка",
                invite = "Пригласить",
                inviteSent = "Приглашение отправлено.",
                userId = "ID пользователя",
                userIdField = "ID пользователя",
                createLink = "Создать ссылку",
                existingLinks = "Ссылки",
                noLinks = "Ссылок пока нет",
                linkCreated = "Ссылка создана.",
                linkCopied = "Ссылка скопирована.",
                copyLink = "Копировать ссылку",
                revoke = "Отозвать",
                revoked = "Отозвана",
                acceptLink = "Принять ссылку",
                tokenField = "Токен или ссылка",
                resolve = "Проверить",
                accept = "Принять",
                linkAccepted = "Ссылка принята.",
                linkResolved = "Ссылка доступна.",
                expires = "Истекает",
                active = "Активна",
                noExpiry = "Без срока",
                offlineSharing = "Для общего доступа нужна сеть."
            )
        }
    }

    companion object {
        private const val TAG = "RocketFlow"
        private const val PLANNER_REFRESH_INTERVAL_MS = 30_000L
        private const val EXTRA_ACCEPTANCE_SEED = "rocketflow_acceptance_seed"
        private const val EXTRA_ACCEPTANCE_EMPTY = "rocketflow_acceptance_empty"
        private const val EXTRA_ACCEPTANCE_LANGUAGE = "rocketflow_acceptance_language"
    }
}
