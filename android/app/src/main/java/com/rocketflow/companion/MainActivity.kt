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
import android.os.LocaleList
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.text.TextUtils
import android.text.method.HideReturnsTransformationMethod
import android.text.method.TransformationMethod
import android.view.Gravity
import android.view.View
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
import com.rocketflow.companion.planning.FolderDraft
import com.rocketflow.companion.planning.GoalDraft
import com.rocketflow.companion.planning.PlanningFolder
import com.rocketflow.companion.planning.PlanningGoal
import com.rocketflow.companion.planning.PlanningLoadResult
import com.rocketflow.companion.planning.PlanningLocalStore
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

    private enum class Screen {
        Auth,
        Planner,
        Detail,
        Settings
    }

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
        val create: String,
        val newFolder: String,
        val newGoal: String,
        val newTask: String,
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
    private var sharedFolders: List<PlanningFolder> = emptyList()
    private var sharedGoals: List<PlanningGoal> = emptyList()
    private var sharedTasks: List<PlanningTask> = emptyList()
    private var taskTags: List<TaskTag> = emptyList()
    private var planningOffline = false
    private var planningPendingCount = 0
    private var planningLastSyncError: String? = null

    private var selectedFolderId: String? = null
    private var selectedGoalId: String? = null
    private var selectedTaskId: String? = null
    private var selectedTaskDetail: PlanningTask? = null
    private var pendingTaskOpenId: String? = null

    private val collapsedFolderIds = mutableSetOf<String>()
    private val collapsedGoalIds = mutableSetOf<String>()
    private var detailsExpanded = false
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

    override fun onBackPressed() {
        when (currentScreen) {
            Screen.Detail, Screen.Settings -> {
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
            inputTypeOverride = stableTextInputType(),
            imeOptionsOverride = EditorInfo.IME_ACTION_NEXT
        )
        val password = dialogInput(c.password, "", isPassword = true)
        val passwordRow = passwordInputRow(password, initialVisible = false)
        val name = dialogInput(c.displayName, "")
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
        sharedFolders = snapshot.sharedFolders
        sharedGoals = snapshot.sharedGoals
        sharedTasks = snapshot.sharedTasks
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
    }

    private fun clearPlannerState() {
        folders = emptyList()
        goals = emptyList()
        tasks = emptyList()
        sharedFolders = emptyList()
        sharedGoals = emptyList()
        sharedTasks = emptyList()
        taskTags = emptyList()
        planningOffline = false
        planningPendingCount = 0
        planningLastSyncError = null
        selectedFolderId = null
        selectedGoalId = null
        selectedTaskId = null
        selectedTaskDetail = null
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
                inputType = stableTextInputType(),
                imeOptions = EditorInfo.IME_ACTION_NEXT
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
            applyPasswordVisibility(passwordVisible)
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

        val ownFolders = filteredFolders()
        val sharedFolderList = filteredSharedFolders()
        val looseSharedGoals = filteredSharedGoals()
            .filter { goal -> sharedFolderList.none { it.id == goal.folderId } }
        val looseSharedTasks = filteredSharedTasks()
            .filter { task -> looseSharedGoals.none { it.id == task.goalId } && sharedGoals.none { it.id == task.goalId } }
        val hasVisibleRows = ownFolders.isNotEmpty() ||
            sharedFolderList.isNotEmpty() ||
            looseSharedGoals.isNotEmpty() ||
            looseSharedTasks.isNotEmpty()

        if (!hasVisibleRows) {
            list.addView(emptyPlannerView())
        } else {
            ownFolders.forEach { folder -> renderFolder(list, folder) }
            if (sharedFolderList.isNotEmpty() || looseSharedGoals.isNotEmpty() || looseSharedTasks.isNotEmpty()) {
                list.addView(sectionLabel(if (currentLanguage == "en") "Shared" else "\u041e\u0431\u0449\u0438\u0435"))
                sharedFolderList.forEach { folder -> renderFolder(list, folder) }
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

    private fun renderFolder(parent: LinearLayout, folder: PlanningFolder) {
        parent.addView(folderRow(folder))
        parent.addView(rowDivider(indentLevel = 0))
        if (folder.id in collapsedFolderIds) return

        val folderGoals = goalsForFolder(folder.id, includeShared = folder.shared)
        if (folderGoals.isEmpty()) {
            parent.addView(hintRow(copy().noGoalYet, indentLevel = 1))
            parent.addView(rowDivider(indentLevel = 1))
        } else {
            folderGoals.forEach { goal -> renderGoal(parent, goal, shared = folder.shared || goal.shared) }
        }
    }

    private fun renderGoal(parent: LinearLayout, goal: PlanningGoal, shared: Boolean) {
        parent.addView(goalRow(goal, shared = shared))
        parent.addView(rowDivider(indentLevel = 1))
        if (goal.id in collapsedGoalIds) return

        val goalTasks = tasksForGoal(goal.id, includeShared = shared)
        if (goalTasks.isEmpty()) {
            parent.addView(hintRow(copy().noTaskYet, indentLevel = 2))
            parent.addView(rowDivider(indentLevel = 2))
        } else {
            goalTasks.forEach { task ->
                parent.addView(taskRow(task, indentLevel = 2))
                parent.addView(rowDivider(indentLevel = 2))
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
            content.addView(propertyRow(c.details, if (detailsExpanded) c.cancel else "", clickable = true) {
                detailsExpanded = !detailsExpanded
                render()
            })
            if (detailsExpanded) {
                content.addView(propertyRow(c.status, localizedStatus(task.status), clickable = true) {
                    showStatusDialog(task)
                })
                content.addView(propertyRow(c.taskType, taskTypeLabel(task.type), clickable = !task.shared) {
                    showTaskTypeDialog(task)
                })
                content.addView(propertyRow(c.priority, "${c.priorityShort}${task.priority}", clickable = !task.shared) {
                    showPriorityDialog(task)
                })
                content.addView(propertyRow(c.planned, formatDateTime(task.plannedTime), clickable = !task.shared) {
                    showPlannedDialog(task)
                })
                content.addView(propertyRow(c.due, formatDateTime(task.dueTime), clickable = !task.shared) {
                    showDueDialog(task)
                })
                content.addView(propertyRow(c.tags, describeTaskTags(task), clickable = !task.shared) {
                    showTaskTagsDialog(task)
                })
                content.addView(propertyRow(c.recurrence, describeRecurrence(task.recurrenceJson), clickable = !task.shared) {
                    showRecurrenceDialog(task)
                })
                content.addView(propertyRow(c.reminders, describeReminders(task.remindersJson), clickable = !task.shared) {
                    showRemindersDialog(task)
                })
                content.addView(propertyRow(c.reschedule, c.later3h, clickable = !task.shared) {
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
        return "$enabled � ${thresholdLabel(policy.thresholdPreset)} � -${policy.decayAmount}"
    }

    private fun thresholdLabel(preset: String): String {
        return when (preset) {
            "day" -> if (currentLanguage == "en") "day" else "����"
            "week" -> if (currentLanguage == "en") "week" else "������"
            "month" -> if (currentLanguage == "en") "month" else "�����"
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
                        if (!task.shared) {
                            addView(iconButton(R.drawable.ic_share, c.share) { showShareDialog(task.toShareTarget()) })
                            addView(iconButton(R.drawable.ic_edit, c.edit) { showTaskDialog(task) })
                            addView(iconButton(R.drawable.ic_more_horiz, c.details) { showTaskActions(task) })
                        }
                    }
                }
                Screen.Settings -> Unit
                Screen.Auth -> Unit
            }
        }
    }

    private fun folderRow(folder: PlanningFolder): View {
        val c = copy()
        val folderGoals = goalsForFolder(folder.id, includeShared = folder.shared)
        val totalTasks = folderGoals.sumOf { tasksForGoal(it.id, includeShared = folder.shared || it.shared).size }
        val doneTasks = folderGoals.sumOf { goal -> tasksForGoal(goal.id, includeShared = folder.shared || goal.shared).count { isDone(it) } }
        return hierarchyContainer(indentLevel = 0, heightDp = 56, selected = false).apply {
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
                    render()
                }
            })
            addView(counterText(if (totalTasks == 0) "0" else "$doneTasks/$totalTasks"))
            if (!folder.shared) {
                addView(iconButton(R.drawable.ic_more_horiz, c.details) { showFolderActions(folder) })
            }
        }
    }

    private fun goalRow(goal: PlanningGoal, shared: Boolean): View {
        val c = copy()
        val goalTasks = tasksForGoal(goal.id, includeShared = shared)
        val doneTasks = goalTasks.count { isDone(it) }
        return hierarchyContainer(indentLevel = 1, heightDp = 52, selected = false).apply {
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
                    render()
                }
            })
            addView(counterText(if (goalTasks.isEmpty()) "0" else "$doneTasks/${goalTasks.size}"))
            if (!shared) {
                addView(iconButton(R.drawable.ic_more_horiz, c.details) { showGoalActions(goal) })
            }
        }
    }

    private fun taskRow(task: PlanningTask, indentLevel: Int): View {
        val c = copy()
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
            })
            dueChip(task)?.let { addView(it) }
            addView(counterText("${c.priorityShort}${task.priority}"))
            if (!task.shared) {
                addView(iconButton(R.drawable.ic_more_horiz, c.details) { showTaskActions(task) })
            }
        }
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
        dialog.show()
    }

    private fun showGoalFolderDialog() {
        val c = copy()
        if (folders.isEmpty()) {
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
        folders.forEach { folder ->
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
            sharedGoals.filter { goal -> goal.canCreateTasks }
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
            .setItems(arrayOf(c.details, c.share, c.edit, c.delete)) { _, which ->
                when (which) {
                    0 -> showFolderDetails(folder)
                    1 -> showShareDialog(folder.toShareTarget())
                    2 -> showFolderDialog(folder)
                    else -> confirmDelete(folder.name, deleteFolderMessage(folder)) { deleteFolder(folder) }
                }
            }
            .show()
    }

    private fun showGoalActions(goal: PlanningGoal) {
        val c = copy()
        AlertDialog.Builder(this)
            .setTitle(goal.name)
            .setItems(arrayOf(c.details, c.share, c.edit, c.delete)) { _, which ->
                when (which) {
                    0 -> showGoalDetails(goal)
                    1 -> showShareDialog(goal.toShareTarget())
                    2 -> showGoalDialog(goal)
                    else -> confirmDelete(goal.name, deleteGoalMessage(goal)) { deleteGoal(goal) }
                }
            }
            .show()
    }

    private fun showFolderDetails(folder: PlanningFolder) {
        val c = copy()
        val folderGoals = goalsForFolder(folder.id)
        val taskCount = folderGoals.sumOf { tasksForGoal(it.id).size }
        AlertDialog.Builder(this)
            .setTitle(folder.name)
            .setView(
                dialogForm(
                    detailDialogText(c.notes, folder.description.ifBlank { c.noDate }),
                    detailDialogText(c.goal, folderGoals.size.toString()),
                    detailDialogText(c.task, taskCount.toString())
                )
            )
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.edit) { _, _ -> showFolderDialog(folder) }
            .show()
    }

    private fun showGoalDetails(goal: PlanningGoal) {
        val c = copy()
        val folder = folders.firstOrNull { it.id == goal.folderId }
        val taskCount = tasksForGoal(goal.id).size
        AlertDialog.Builder(this)
            .setTitle(goal.name)
            .setView(
                dialogForm(
                    detailDialogText(c.folder, folder?.name ?: c.folder),
                    detailDialogText(c.notes, goal.description.ifBlank { c.noDate }),
                    detailDialogText(c.task, taskCount.toString())
                )
            )
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.edit) { _, _ -> showGoalDialog(goal) }
            .show()
    }

    private fun showTaskActions(task: PlanningTask) {
        val c = copy()
        AlertDialog.Builder(this)
            .setTitle(task.title)
            .setItems(arrayOf(c.share, c.edit, c.reschedule, c.delete)) { _, which ->
                when (which) {
                    0 -> showShareDialog(task.toShareTarget())
                    1 -> showTaskDialog(task)
                    2 -> showRescheduleDialog(task)
                    else -> confirmDelete(task.title) { deleteTask(task) }
                }
            }
            .show()
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
            inputTypeOverride = stableTextInputType(),
            imeOptionsOverride = EditorInfo.IME_ACTION_DONE
        )

        AlertDialog.Builder(this)
            .setTitle(if (byEmail) c.shareByEmail else c.shareByUserId)
            .setView(dialogForm(input))
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.invite) { _, _ ->
                val value = input.text.toString().trim()
                if (value.isBlank()) {
                    message = if (byEmail) c.email else c.userId
                    render()
                    return@setPositiveButton
                }
                sendShareInvite(target, value, byEmail)
            }
            .show()
    }

    private fun sendShareInvite(target: ShareTarget, value: String, byEmail: Boolean) {
        val session = currentSession ?: return
        setBusy(true)
        message = null
        scope.launch {
            try {
                val result = if (byEmail) {
                    sharingRepository.inviteByEmail(session, target, value)
                } else {
                    sharingRepository.inviteByUserId(session, target, value)
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
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            addView(textButton(c.createLink, primary = true) {
                createShareLink(target, status, tokenContainer, linksContainer)
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
        linksContainer: LinearLayout
    ) {
        val session = currentSession ?: return
        status.text = copy().loading
        scope.launch {
            try {
                val result = sharingRepository.createLink(session, target)
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
            inputTypeOverride = stableTextInputType()
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

    private fun showFolderDialog(folder: PlanningFolder?, onSaved: ((PlanningFolder) -> Unit)? = null) {
        val c = copy()
        val nameInput = dialogInput(c.nameField, folder?.name.orEmpty())
        val notesInput = dialogInput(c.notesField, folder?.description.orEmpty(), multiline = true)
        val dialog = AlertDialog.Builder(this)
            .setTitle(if (folder == null) c.newFolder else c.edit)
            .setView(dialogForm(nameInput, notesInput))
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.save) { _, _ ->
                val draft = FolderDraft(nameInput.text.toString().trim(), notesInput.text.toString().trim())
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
        val dialog = AlertDialog.Builder(this)
            .setTitle(if (goal == null) c.newGoal else c.edit)
            .setView(dialogForm(dialogContextLine(c.folder, folder?.name ?: c.folder), nameInput, notesInput))
            .setNegativeButton(c.cancel, null)
            .setPositiveButton(c.save) { _, _ ->
                val draft = GoalDraft(nameInput.text.toString().trim(), notesInput.text.toString().trim())
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
            inputTypeOverride = stableTextInputType()
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
            .setSingleChoiceItems(labels, checked) { dialog, which ->
                val payload = recurrencePayload(task, modes[which], active = which != 0)
                saveTask(task.goalId, task, task.toDraft(recurrenceJson = payload.toString()))
                dialog.dismiss()
            }
            .show()
    }

    private fun showRemindersDialog(task: PlanningTask) {
        val c = copy()
        val labels = arrayOf(
            c.noDate,
            "15 min ${c.remindersBeforeDue.lowercase(Locale.ROOT)}",
            "30 min ${c.remindersBeforeDue.lowercase(Locale.ROOT)}",
            "60 min ${c.remindersBeforeDue.lowercase(Locale.ROOT)}",
            "30 min ${c.remindersBeforePlanned.lowercase(Locale.ROOT)}"
        )
        AlertDialog.Builder(this)
            .setTitle(c.reminders)
            .setItems(labels) { _, which ->
                val reminders = JSONArray()
                when (which) {
                    1 -> reminders.put(reminderPayload("before_due_time", 15))
                    2 -> reminders.put(reminderPayload("before_due_time", 30))
                    3 -> reminders.put(reminderPayload("before_due_time", 60))
                    4 -> reminders.put(reminderPayload("before_planned_time", 30))
                }
                saveTask(task.goalId, task, task.toDraft(remindersJson = reminders.toString()))
            }
            .show()
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
            inputTypeOverride = stableTextInputType(),
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
        lateinit var pickerButton: Button
        lateinit var clearButton: Button

        fun buttonText(): String {
            val formatted = value?.let { formatDateTime(it.atZone(zone).toInstant().toString()) } ?: copy().noDate
            return "$label: $formatted"
        }

        fun updateButtons() {
            pickerButton.text = buttonText()
            clearButton.visibility = if (value == null) View.GONE else View.VISIBLE
        }

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            pickerButton = textButton(buttonText(), quiet = true) {
                pickDateTime(value ?: LocalDateTime.now(zone).plusHours(1).withMinute(0).withSecond(0).withNano(0)) {
                    value = it
                    updateButtons()
                }
            }
            addView(pickerButton)
            clearButton = textButton(copy().clearDate, quiet = true) {
                value = null
                updateButtons()
            }.apply {
                visibility = if (value == null) View.GONE else View.VISIBLE
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(38)
                ).apply { topMargin = dp(4) }
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
        isPassword: Boolean = false,
        inputTypeOverride: Int? = null,
        imeOptionsOverride: Int? = null
    ): EditText {
        return EditText(this).apply {
            this.hint = hint
            setText(value)
            styleInput()
            val resolvedInputType = inputTypeOverride ?: when {
                isPassword -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                else -> stableTextInputType()
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
                singleLine = !multiline
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
                applyPasswordVisibility(visible = false)
            }
            openKeyboardOnUserFocus()
        }
    }

    private fun dialogForm(vararg inputs: View): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(8), dp(20), 0)
            inputs.forEach { input ->
                (input.parent as? ViewGroup)?.removeView(input)
                addView(input)
            }
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
            InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD or
            InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
    }

    private fun EditText.applyInputOptions(inputType: Int, imeOptions: Int, singleLine: Boolean = true) {
        if (singleLine) {
            setSingleLine(true)
            maxLines = 1
            setHorizontallyScrolling(true)
        } else {
            setSingleLine(false)
            isSingleLine = false
            setHorizontallyScrolling(false)
        }
        setRawInputType(inputType)
        this.imeOptions = imeOptions or EditorInfo.IME_FLAG_NO_EXTRACT_UI
        imeHintLocales = if (currentLanguage == "en") {
            LocaleList(Locale.US, Locale("ru", "RU"))
        } else {
            LocaleList(Locale("ru", "RU"), Locale.US)
        }
        showSoftInputOnFocus = true
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

    private fun EditText.applyPasswordVisibility(visible: Boolean, cursorPosition: Int? = null) {
        val cursor = cursorPosition?.takeIf { it >= 0 } ?: (text?.length ?: 0)
        val preservedImeOptions = imeOptions.takeIf { it != EditorInfo.IME_NULL } ?: EditorInfo.IME_ACTION_DONE
        applyInputOptions(
            inputType = InputType.TYPE_CLASS_TEXT or if (visible) {
                InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
            } else {
                InputType.TYPE_TEXT_VARIATION_PASSWORD
            },
            imeOptions = preservedImeOptions
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

    private fun filteredFolders(): List<PlanningFolder> {
        val query = searchQuery.trim().lowercase(Locale.ROOT)
        if (query.isBlank()) return folders
        return folders.filter { folder ->
            folder.name.lowercase(Locale.ROOT).contains(query) ||
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

    private fun goalsForFolder(folderId: String, includeShared: Boolean = false): List<PlanningGoal> {
        val own = goals.filter { it.folderId == folderId }
        return if (includeShared) own + sharedGoals.filter { it.folderId == folderId } else own
    }

    private fun tasksForGoal(goalId: String, includeShared: Boolean = false): List<PlanningTask> {
        val own = tasks.filter { it.goalId == goalId }
        return if (includeShared) own + sharedTasks.filter { it.goalId == goalId } else own
    }

    private fun allTasks(): List<PlanningTask> = tasks + sharedTasks

    private fun findTask(taskId: String?): PlanningTask? {
        if (taskId == null) return null
        return allTasks().firstOrNull { it.id == taskId }
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
        val prefix = when (json.optString("mode")) {
            "weekly" -> "${copy().weekly}: ${weekdaySummary(json.optJSONArray("daysOfWeek"))}"
            "monthly" -> "${copy().monthly}: ${json.optInt("dayOfMonth", 1)}"
            else -> copy().daily
        }
        val every = if (currentLanguage == "en") "every $interval" else "����. $interval"
        return "$prefix, $every, $start"
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

    private fun weekdaySummary(days: JSONArray?): String {
        if (days == null || days.length() == 0) return copy().noDate
        return (0 until days.length()).joinToString(", ") { index ->
            when (days.optString(index)) {
                "MONDAY" -> if (currentLanguage == "en") "Mon" else "��"
                "TUESDAY" -> if (currentLanguage == "en") "Tue" else "��"
                "WEDNESDAY" -> if (currentLanguage == "en") "Wed" else "��"
                "THURSDAY" -> if (currentLanguage == "en") "Thu" else "��"
                "FRIDAY" -> if (currentLanguage == "en") "Fri" else "��"
                "SATURDAY" -> if (currentLanguage == "en") "Sat" else "��"
                "SUNDAY" -> if (currentLanguage == "en") "Sun" else "��"
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
            priority <= 2 -> if (currentLanguage == "en") "high" else "�������"
            priority <= 5 -> if (currentLanguage == "en") "medium" else "�������"
            else -> if (currentLanguage == "en") "low" else "������"
        }
        return if (currentLanguage == "en") "Priority $level" else "���������: $level"
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
        return "${BuildConfig.ROCKETFLOW_API_BASE_URL.trimEnd('/')}/shares/links/$token"
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
        if (isTerminalSessionFailure(error)) return copy().signInAgain
        return when (error) {
            is ApiException -> when (error.status) {
                401 -> copy().signInAgain
                else -> copy().requestFailed
            }
            else -> humanText(error.message)
        }
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
                create = "Create",
                newFolder = "New folder",
                newGoal = "New goal",
                newTask = "New task",
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
                create = "Создать",
                newFolder = "Новая папка",
                newGoal = "Новая цель",
                newTask = "Новая задача",
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
                planned = "План",
                due = "Срок",
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
                invalidDate = "Используйте day, week или month и число больше 0.",
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
        private const val PLANNER_REFRESH_INTERVAL_MS = 30_000L
        private const val EXTRA_ACCEPTANCE_SEED = "rocketflow_acceptance_seed"
        private const val EXTRA_ACCEPTANCE_EMPTY = "rocketflow_acceptance_empty"
        private const val EXTRA_ACCEPTANCE_LANGUAGE = "rocketflow_acceptance_language"
    }
}
