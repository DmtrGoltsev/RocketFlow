package com.rocketflow.companion

import android.app.Activity
import android.content.Intent
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.rocketflow.companion.auth.AuthCopy
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.authCopy
import com.rocketflow.companion.browse.FolderSummary
import com.rocketflow.companion.browse.GoalSummary
import com.rocketflow.companion.browse.SharedResources
import com.rocketflow.companion.browse.TaskSummary
import com.rocketflow.companion.detail.TaskDetail
import com.rocketflow.companion.network.ApiException
import com.rocketflow.companion.notifications.DeviceRegistration
import com.rocketflow.companion.notifications.NotificationIntents
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class MainActivity : Activity() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val appContainer by lazy { (application as RocketFlowCompanionApp).container }
    private val authRepository by lazy { appContainer.authRepository }
    private val browseRepository by lazy { appContainer.browseRepository }
    private val taskDetailRepository by lazy { appContainer.taskDetailRepository }
    private val notificationsRepository by lazy { appContainer.notificationsRepository }

    private lateinit var titleView: TextView
    private lateinit var subtitleView: TextView
    private lateinit var noticeView: TextView
    private lateinit var loadingView: TextView
    private lateinit var sessionCard: LinearLayout
    private lateinit var loginCard: LinearLayout
    private lateinit var browseCard: LinearLayout
    private lateinit var detailCard: LinearLayout
    private lateinit var notificationsCard: LinearLayout
    private lateinit var emailInput: EditText
    private lateinit var passwordInput: EditText
    private lateinit var pushTokenInput: EditText
    private lateinit var deviceNameInput: EditText
    private lateinit var sessionInfoView: TextView
    private lateinit var loginButton: Button
    private lateinit var refreshButton: Button
    private lateinit var logoutButton: Button
    private lateinit var registerDeviceButton: Button
    private lateinit var unregisterDeviceButton: Button

    private var currentSession: AuthSession? = null
    private var folders: List<FolderSummary> = emptyList()
    private var goals: List<GoalSummary> = emptyList()
    private var tasks: List<TaskSummary> = emptyList()
    private var sharedResources: SharedResources = SharedResources(emptyList(), emptyList())
    private var selectedFolderId: String? = null
    private var selectedGoalId: String? = null
    private var selectedTaskId: String? = null
    private var selectedTaskDetail: TaskDetail? = null
    private var loadingTaskDetail = false
    private var currentDeviceRegistration: DeviceRegistration? = null
    private var pendingTaskOpenId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        currentDeviceRegistration = notificationsRepository.readStoredRegistration()
        setupUi()
        handleIncomingIntent(intent)
        render()
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
        scope.cancel()
        super.onDestroy()
    }

    private fun setupUi() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(40, 48, 40, 48)
        }

        titleView = TextView(this).apply {
            textSize = 24f
        }
        subtitleView = TextView(this).apply {
            textSize = 15f
            setPadding(0, 12, 0, 0)
        }
        noticeView = TextView(this).apply {
            textSize = 14f
            setPadding(0, 24, 0, 0)
        }
        loadingView = TextView(this).apply {
            textSize = 14f
            setPadding(0, 24, 0, 0)
        }

        emailInput = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
        }
        passwordInput = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
        }
        pushTokenInput = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_TEXT
        }
        deviceNameInput = EditText(this).apply {
            setText(defaultDeviceName())
        }
        loginButton = Button(this).apply {
            setOnClickListener { submitLogin() }
        }
        refreshButton = Button(this).apply {
            setOnClickListener { refreshSession() }
        }
        logoutButton = Button(this).apply {
            setOnClickListener { logout() }
        }
        registerDeviceButton = Button(this).apply {
            setOnClickListener { registerDevice() }
        }
        unregisterDeviceButton = Button(this).apply {
            setOnClickListener { unregisterDevice() }
        }
        sessionInfoView = TextView(this).apply {
            textSize = 15f
        }

        loginCard = sectionCard(
            emailInput,
            passwordInput,
            buttonRow(loginButton)
        )

        sessionCard = sectionCard(
            sessionInfoView,
            buttonRow(refreshButton, logoutButton)
        )

        notificationsCard = sectionCard()
        browseCard = sectionCard()
        detailCard = sectionCard()

        root.addView(titleView)
        root.addView(subtitleView)
        root.addView(noticeView)
        root.addView(loadingView)
        root.addView(loginCard)
        root.addView(sessionCard)
        root.addView(notificationsCard)
        root.addView(browseCard)
        root.addView(detailCard)

        setContentView(
            ScrollView(this).apply {
                addView(root)
            }
        )
    }

    private fun bootstrapSession() {
        setBusy(true)
        noticeView.text = ""

        scope.launch {
            try {
                currentSession = authRepository.bootstrapSession()
                if (currentSession != null) {
                    loadBrowseData()
                    maybeOpenPendingTask()
                }
                render()
            } catch (error: Exception) {
                currentSession = null
                showError(error)
                render()
            } finally {
                setBusy(false)
            }
        }
    }

    private fun submitLogin() {
        val email = emailInput.text.toString().trim()
        val password = passwordInput.text.toString()

        if (email.isBlank() || password.isBlank()) {
            noticeView.text = authCopy(currentSession?.user?.language).loginRequired
            return
        }

        setBusy(true)
        noticeView.text = ""

        scope.launch {
            try {
                currentSession = authRepository.login(email, password)
                passwordInput.setText("")
                loadBrowseData()
                maybeOpenPendingTask()
                render()
            } catch (error: Exception) {
                showError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun refreshSession() {
        val session = currentSession ?: return
        setBusy(true)
        noticeView.text = ""

        scope.launch {
            try {
                currentSession = authRepository.refreshCurrentUser(session)
                loadBrowseData()
                render()
            } catch (error: Exception) {
                showError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun logout() {
        setBusy(true)
        noticeView.text = ""

        scope.launch {
            try {
                val session = currentSession
                val registration = currentDeviceRegistration
                if (session != null && registration != null) {
                    try {
                        currentSession = notificationsRepository.unregisterDevice(session, registration.id)
                    } catch (_: Exception) {
                        notificationsRepository.clearStoredRegistration()
                    }
                } else {
                    notificationsRepository.clearStoredRegistration()
                }
                authRepository.logout()
            } finally {
                currentSession = null
                currentDeviceRegistration = null
                clearBrowseState()
                render()
                setBusy(false)
            }
        }
    }

    private suspend fun loadBrowseData() {
        val session = currentSession ?: return

        val foldersResult = browseRepository.listFolders(session)
        currentSession = foldersResult.session
        folders = foldersResult.value.filterNot { it.archived }
        selectedFolderId = selectedFolderId
            ?.takeIf { candidate -> folders.any { it.id == candidate } }
            ?: folders.firstOrNull()?.id

        if (selectedFolderId != null) {
            val goalsResult = browseRepository.listGoals(currentSession ?: return, selectedFolderId ?: return)
            currentSession = goalsResult.session
            goals = goalsResult.value.filterNot { it.archived }
        } else {
            goals = emptyList()
        }

        selectedGoalId = selectedGoalId
            ?.takeIf { candidate -> goals.any { it.id == candidate } }
            ?: goals.firstOrNull()?.id

        if (selectedGoalId != null) {
            val tasksResult = browseRepository.listTasks(currentSession ?: return, selectedGoalId ?: return)
            currentSession = tasksResult.session
            tasks = tasksResult.value.filterNot { it.shared }
        } else {
            tasks = emptyList()
        }

        val sharedResult = browseRepository.getSharedResources(currentSession ?: return)
        currentSession = sharedResult.session
        sharedResources = sharedResult.value

        val visibleTaskIds = tasks.map { it.id }.toSet() + sharedResources.tasks.map { it.id }.toSet()
        if (selectedTaskId != null && selectedTaskId !in visibleTaskIds) {
            selectedTaskId = null
            selectedTaskDetail = null
        }
    }

    private fun clearBrowseState() {
        folders = emptyList()
        goals = emptyList()
        tasks = emptyList()
        sharedResources = SharedResources(emptyList(), emptyList())
        selectedFolderId = null
        selectedGoalId = null
        selectedTaskId = null
        selectedTaskDetail = null
        loadingTaskDetail = false
    }

    private fun reloadBrowse() {
        if (currentSession == null) {
            return
        }

        setBusy(true)
        noticeView.text = ""

        scope.launch {
            try {
                loadBrowseData()
                render()
            } catch (error: Exception) {
                showError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun registerDevice() {
        val session = currentSession ?: return
        val pushToken = pushTokenInput.text.toString().trim()
        val deviceName = deviceNameInput.text.toString().trim()
        val copy = authCopy(currentSession?.user?.language)

        if (pushToken.isBlank()) {
            noticeView.text = copy.pushTokenRequired
            return
        }

        setBusy(true)
        noticeView.text = ""

        scope.launch {
            try {
                val result = notificationsRepository.registerDevice(session, pushToken, deviceName)
                currentSession = result.session
                currentDeviceRegistration = result.value
                render()
            } catch (error: Exception) {
                showError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun unregisterDevice() {
        val session = currentSession ?: return
        val registration = currentDeviceRegistration ?: return

        setBusy(true)
        noticeView.text = ""

        scope.launch {
            try {
                currentSession = notificationsRepository.unregisterDevice(session, registration.id)
                currentDeviceRegistration = null
                render()
            } catch (error: Exception) {
                showError(error)
            } finally {
                setBusy(false)
            }
        }
    }

    private fun selectFolder(folderId: String) {
        selectedFolderId = folderId
        selectedGoalId = null
        selectedTaskId = null
        selectedTaskDetail = null
        reloadBrowse()
    }

    private fun selectGoal(goalId: String) {
        selectedGoalId = goalId
        selectedTaskId = null
        selectedTaskDetail = null
        reloadBrowse()
    }

    private fun openTaskDetail(taskId: String) {
        val session = currentSession ?: return
        selectedTaskId = taskId
        selectedTaskDetail = null
        loadingTaskDetail = true
        render()

        scope.launch {
            try {
                val result = taskDetailRepository.getTaskDetail(session, taskId)
                currentSession = result.session
                selectedTaskDetail = result.value
            } catch (error: Exception) {
                showError(error)
            } finally {
                loadingTaskDetail = false
                render()
            }
        }
    }

    private fun handleIncomingIntent(intent: Intent?) {
        val taskId = NotificationIntents.extractTaskId(intent) ?: return
        pendingTaskOpenId = taskId
        val copy = authCopy(currentSession?.user?.language)
        noticeView.text = "${copy.deepLinkPending}: $taskId"
    }

    private fun maybeOpenPendingTask() {
        val taskId = pendingTaskOpenId ?: return
        if (currentSession == null) {
            return
        }

        pendingTaskOpenId = null
        noticeView.text = "${authCopy(currentSession?.user?.language).deepLinkOpened}: $taskId"
        openTaskDetail(taskId)
    }

    private fun render() {
        val copy = authCopy(currentSession?.user?.language)
        titleView.text = copy.title
        subtitleView.text = copy.subtitle
        loadingView.text = if (loadingView.visibility == View.VISIBLE) copy.loading else ""

        loginButton.text = copy.login
        refreshButton.text = copy.restore
        logoutButton.text = copy.logout
        registerDeviceButton.text = copy.registerDevice
        unregisterDeviceButton.text = copy.unregisterDevice
        emailInput.hint = copy.email
        passwordInput.hint = copy.password
        pushTokenInput.hint = copy.pushToken
        deviceNameInput.hint = copy.deviceName

        if (currentSession == null) {
            loginCard.visibility = View.VISIBLE
            sessionCard.visibility = View.GONE
            notificationsCard.visibility = View.GONE
            browseCard.visibility = View.GONE
            detailCard.visibility = View.GONE
            if (noticeView.text.isNullOrBlank()) {
                noticeView.text = copy.noSession
            }
            return
        }

        val session = currentSession ?: return
        loginCard.visibility = View.GONE
        sessionCard.visibility = View.VISIBLE
        notificationsCard.visibility = View.VISIBLE
        browseCard.visibility = View.VISIBLE
        detailCard.visibility = View.VISIBLE
        if (noticeView.text.isNullOrBlank()) {
            noticeView.text = copy.ready
        }
        sessionInfoView.text = listOf(
            "${copy.sessionLabel}: ${session.user.displayName} <${session.user.email}>",
            "${copy.timezoneLabel}: ${session.user.timezone}",
            "${copy.expiresAtLabel}: ${session.tokens.expiresAt}"
        ).joinToString(separator = "\n")

        renderNotificationsCard(copy)
        renderBrowseCard(copy)
        renderDetailCard(copy)
    }

    private fun renderNotificationsCard(copy: AuthCopy) {
        notificationsCard.removeAllViews()
        notificationsCard.addView(sectionTitle(copy.notificationsTitle))
        notificationsCard.addView(bodyText("${copy.deepLinkTitle}: rocketflow://task/{taskId}"))

        val registration = currentDeviceRegistration
        if (registration == null) {
            notificationsCard.addView(bodyText(copy.noRegisteredDevice))
        } else {
            notificationsCard.addView(bodyText("${copy.currentDevice}: ${registration.id}"))
            notificationsCard.addView(bodyText("${copy.deviceName}: ${registration.deviceName ?: copy.none}"))
            notificationsCard.addView(bodyText("Platform: ${registration.platform}"))
            notificationsCard.addView(bodyText("Created: ${registration.createdAt}"))
            notificationsCard.addView(bodyText("Active: ${yesNo(registration.active, copy)}"))
        }

        notificationsCard.addView(pushTokenInput)
        notificationsCard.addView(deviceNameInput)
        notificationsCard.addView(buttonRow(registerDeviceButton, unregisterDeviceButton))
    }

    private fun renderBrowseCard(copy: AuthCopy) {
        browseCard.removeAllViews()
        browseCard.addView(sectionTitle(copy.browseTitle))
        browseCard.addView(buttonRow(button(copy.restore) { reloadBrowse() }))

        browseCard.addView(subsectionTitle(copy.foldersTitle))
        if (folders.isEmpty()) {
            browseCard.addView(bodyText(copy.noFolders))
        } else {
            folders.forEach { folder ->
                val label = if (folder.id == selectedFolderId) "[${folder.name}]" else folder.name
                browseCard.addView(button(label) { selectFolder(folder.id) })
            }
        }

        browseCard.addView(subsectionTitle(copy.goalsTitle))
        if (goals.isEmpty()) {
            browseCard.addView(bodyText(copy.noGoals))
        } else {
            goals.forEach { goal ->
                val label = buildString {
                    if (goal.id == selectedGoalId) {
                        append("[")
                    }
                    append(goal.name)
                    if (goal.shared) {
                        append(" | ")
                        append(copy.sharedLabel)
                    }
                    if (goal.id == selectedGoalId) {
                        append("]")
                    }
                }
                browseCard.addView(button(label) { selectGoal(goal.id) })
            }
        }

        browseCard.addView(subsectionTitle(copy.tasksTitle))
        if (tasks.isEmpty()) {
            browseCard.addView(bodyText(copy.noTasks))
        } else {
            tasks.forEach { task ->
                browseCard.addView(taskButton(copy, task))
            }
        }

        browseCard.addView(subsectionTitle(copy.sharedGoalsTitle))
        if (sharedResources.goals.isEmpty()) {
            browseCard.addView(bodyText(copy.none))
        } else {
            sharedResources.goals.forEach { goal ->
                browseCard.addView(bodyText(goal.name))
            }
        }

        browseCard.addView(subsectionTitle(copy.sharedTasksTitle))
        if (sharedResources.tasks.isEmpty()) {
            browseCard.addView(bodyText(copy.none))
        } else {
            sharedResources.tasks.forEach { task ->
                browseCard.addView(taskButton(copy, task))
            }
        }

        browseCard.addView(sectionTitle(copy.nextSurfaces))
        browseCard.addView(bulletView(copy.browseLater))
        browseCard.addView(bulletView(copy.detailLater))
        browseCard.addView(bulletView(copy.pushLater))
    }

    private fun renderDetailCard(copy: AuthCopy) {
        detailCard.removeAllViews()
        detailCard.addView(sectionTitle(copy.detailTitle))

        if (loadingTaskDetail) {
            detailCard.addView(bodyText(copy.detailLoading))
            return
        }

        val detail = selectedTaskDetail
        if (detail == null) {
            detailCard.addView(bodyText(copy.detailEmpty))
            return
        }

        detailCard.addView(
            TextView(this).apply {
                text = detail.title
                textSize = 19f
                setTypeface(typeface, Typeface.BOLD)
                setPadding(0, 12, 0, 0)
            }
        )
        detailCard.addView(bodyText(detail.description.ifBlank { copy.none }))
        detailCard.addView(bodyText("Status: ${detail.status}"))
        detailCard.addView(bodyText("Type: ${detail.type}"))
        detailCard.addView(bodyText("Priority: ${detail.priority}"))
        detailCard.addView(bodyText("Planned: ${detail.plannedTime ?: copy.none}"))
        detailCard.addView(bodyText("Due: ${detail.dueTime ?: copy.none}"))
        detailCard.addView(bodyText("${copy.sharedLabel}: ${yesNo(detail.shared, copy)}"))
        detailCard.addView(bodyText("${copy.archivedLabel}: ${yesNo(detail.archived, copy)}"))
        detailCard.addView(
            bodyText(
                "${copy.tagsTitle}: ${detail.tags.joinToString(separator = ", ") { it.name }.ifBlank { copy.none }}"
            )
        )
        detailCard.addView(bodyText("${copy.recurrenceTitle}: ${recurrenceSummary(detail, copy)}"))
        detailCard.addView(bodyText("${copy.remindersTitle}: ${reminderSummary(detail, copy)}"))
    }

    private fun taskButton(copy: AuthCopy, task: TaskSummary): View {
        val label = buildString {
            append(task.title)
            append(" | ")
            append(task.status)
            append(" | ")
            append(task.priority)
            task.plannedTime?.let {
                append(" | ")
                append(it)
            }
            if (task.shared) {
                append(" | ")
                append(copy.sharedLabel)
            }
        }
        return button(label) { openTaskDetail(task.id) }
    }

    private fun showError(error: Exception) {
        noticeView.text = when (error) {
            is ApiException -> buildString {
                append(error.message)
                if (!error.traceId.isNullOrBlank()) {
                    append("\nTrace ID: ")
                    append(error.traceId)
                }
            }

            else -> error.message ?: "Request failed."
        }
    }

    private fun setBusy(isBusy: Boolean) {
        loadingView.visibility = if (isBusy) View.VISIBLE else View.GONE
        loginButton.isEnabled = !isBusy
        refreshButton.isEnabled = !isBusy
        logoutButton.isEnabled = !isBusy
        registerDeviceButton.isEnabled = !isBusy
        unregisterDeviceButton.isEnabled = !isBusy
    }

    private fun sectionCard(vararg views: View): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 28, 0, 0)
            views.forEach { addView(it) }
        }
    }

    private fun buttonRow(vararg buttons: Button): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.START
            setPadding(0, 16, 0, 0)
            buttons.forEachIndexed { index, button ->
                if (index > 0) {
                    button.setPadding(24, button.paddingTop, 24, button.paddingBottom)
                }
                addView(button)
            }
        }
    }

    private fun button(label: String, onClick: () -> Unit): Button {
        return Button(this).apply {
            text = label
            setOnClickListener { onClick() }
        }
    }

    private fun sectionTitle(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 18f
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, 24, 0, 0)
        }
    }

    private fun subsectionTitle(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 16f
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, 18, 0, 0)
        }
    }

    private fun bodyText(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 15f
            setPadding(0, 8, 0, 0)
        }
    }

    private fun bulletView(text: String): TextView {
        return TextView(this).apply {
            this.text = "- $text"
            textSize = 15f
            setPadding(0, 12, 0, 0)
        }
    }

    private fun defaultDeviceName(): String {
        return listOfNotNull(Build.MANUFACTURER, Build.MODEL)
            .joinToString(separator = " ")
            .trim()
            .ifBlank { "Android companion" }
    }

    private fun yesNo(value: Boolean, copy: AuthCopy): String {
        return if (value) "Yes" else copy.none
    }

    private fun recurrenceSummary(detail: TaskDetail, copy: AuthCopy): String {
        val recurrence = detail.recurrence ?: return copy.none
        val parts = mutableListOf(recurrence.mode)
        recurrence.interval?.let { parts += "interval=$it" }
        if (recurrence.daysOfWeek.isNotEmpty()) {
            parts += recurrence.daysOfWeek.joinToString(separator = ",")
        }
        recurrence.startAt?.let { parts += "start=$it" }
        recurrence.endAt?.let { parts += "end=$it" }
        recurrence.active?.let { parts += "active=$it" }
        return parts.joinToString(separator = " | ")
    }

    private fun reminderSummary(detail: TaskDetail, copy: AuthCopy): String {
        if (detail.reminders.isEmpty()) {
            return copy.none
        }

        return detail.reminders.joinToString(separator = "; ") { reminder ->
            "${reminder.mode}:${reminder.offsetMinutes}m:${reminder.active}"
        }
    }
}
