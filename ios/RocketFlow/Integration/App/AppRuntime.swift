import Foundation

struct AppRuntimeLease: Equatable, Hashable, Sendable {
    let accountID: UUID
    let runtimeID: UUID
    let sessionGeneration: UInt64

    init(
        accountID: UUID,
        runtimeID: UUID = UUID(),
        sessionGeneration: UInt64
    ) {
        self.accountID = accountID
        self.runtimeID = runtimeID
        self.sessionGeneration = sessionGeneration
    }
}

actor AppRuntimeValidity {
    private var activeLease: AppRuntimeLease?

    init(lease: AppRuntimeLease) {
        activeLease = lease
    }

    func require(_ lease: AppRuntimeLease) throws {
        try Task.checkCancellation()
        guard activeLease == lease else { throw CancellationError() }
    }

    func invalidate(_ lease: AppRuntimeLease) {
        guard activeLease == lease else { return }
        activeLease = nil
    }

    func isValid(_ lease: AppRuntimeLease) -> Bool {
        activeLease == lease
    }
}

actor AppRuntimeOperationGate {
    private struct ActiveOperation {
        let cancel: @Sendable () -> Void
        let completion: Task<Void, Never>
    }

    private let lease: AppRuntimeLease
    private var acceptingOperations = true
    private var activeOperations: [UUID: ActiveOperation] = [:]

    init(lease: AppRuntimeLease) {
        self.lease = lease
    }

    func run<Value: Sendable>(
        for lease: AppRuntimeLease,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        guard acceptingOperations, self.lease == lease else {
            throw CancellationError()
        }

        let operationID = UUID()
        let worker = Task<Value, Error> {
            try Task.checkCancellation()
            let value = try await operation()
            try Task.checkCancellation()
            return value
        }
        let completion = Task<Void, Never> {
            _ = try? await worker.value
        }
        activeOperations[operationID] = ActiveOperation(
            cancel: { worker.cancel() },
            completion: completion
        )

        do {
            let value = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            activeOperations.removeValue(forKey: operationID)
            try Task.checkCancellation()
            guard acceptingOperations, self.lease == lease else {
                throw CancellationError()
            }
            return value
        } catch {
            activeOperations.removeValue(forKey: operationID)
            throw error
        }
    }

    func invalidateCancelAndWait(for lease: AppRuntimeLease) async {
        guard self.lease == lease else { return }
        acceptingOperations = false
        let operations = Array(activeOperations.values)
        activeOperations.removeAll()
        operations.forEach { $0.cancel() }
        for operation in operations {
            await operation.completion.value
        }
    }

    func activeOperationCount() -> Int {
        activeOperations.count
    }
}

struct AppRuntimeTaskReminderWorkflow: TaskReminderWorkflowServing, Sendable {
    let base: TaskReminderWorkflow
    let lease: AppRuntimeLease
    let validity: AppRuntimeValidity
    let operationGate: AppRuntimeOperationGate

    func reminder(taskID: UUID) async throws -> LocalTaskReminder? {
        let validity = self.validity
        let lease = self.lease
        let base = self.base
        return try await operationGate.run(for: lease) {
            try await validity.require(lease)
            let value = try await base.reminder(taskID: taskID)
            try await validity.require(lease)
            return value
        }
    }

    func apply(
        taskID: UUID,
        title: String,
        dueAt: Date?,
        mutation: TaskReminderEditorMutation,
        taskState: ReminderTaskState,
        isNewTask: Bool
    ) async throws {
        let validity = self.validity
        let lease = self.lease
        let base = self.base
        try await operationGate.run(for: lease) {
            try await validity.require(lease)
            try await base.apply(
                taskID: taskID,
                title: title,
                dueAt: dueAt,
                mutation: mutation,
                taskState: taskState,
                isNewTask: isNewTask
            )
            try await validity.require(lease)
        }
    }

    func taskStateDidChange(
        taskID: UUID,
        taskState: ReminderTaskState
    ) async throws {
        let validity = self.validity
        let lease = self.lease
        let base = self.base
        try await operationGate.run(for: lease) {
            try await validity.require(lease)
            try await base.taskStateDidChange(taskID: taskID, taskState: taskState)
            try await validity.require(lease)
        }
    }
}

struct AppRuntimeTaskReminderStore: TaskReminderStoreServing, Sendable {
    let base: any TaskReminderStoreServing
    let accountID: UUID
    let lease: AppRuntimeLease
    let validity: AppRuntimeValidity
    let operationGate: AppRuntimeOperationGate

    func reconciliationItems(accountID: UUID) async throws -> [TaskReminderReconciliationItem] {
        try requireAccount(accountID)
        let base = self.base
        return try await run { try await base.reconciliationItems(accountID: accountID) }
    }

    func reminders(accountID: UUID) async throws -> [LocalTaskReminder] {
        try requireAccount(accountID)
        let base = self.base
        return try await run { try await base.reminders(accountID: accountID) }
    }

    func save(_ reminder: LocalTaskReminder, taskState: ReminderTaskState) async throws {
        try requireAccount(reminder.accountID)
        let base = self.base
        try await run { try await base.save(reminder, taskState: taskState) }
    }

    func remove(accountID: UUID, taskID: UUID, reminderID: UUID) async throws {
        try requireAccount(accountID)
        let base = self.base
        try await run {
            try await base.remove(
                accountID: accountID,
                taskID: taskID,
                reminderID: reminderID
            )
        }
    }

    func defaultReminder(accountID: UUID) async throws -> DefaultTaskReminder? {
        try requireAccount(accountID)
        let base = self.base
        return try await run { try await base.defaultReminder(accountID: accountID) }
    }

    func saveDefault(_ reminder: DefaultTaskReminder) async throws {
        try requireAccount(reminder.accountID)
        let base = self.base
        try await run { try await base.saveDefault(reminder) }
    }

    func clearDefault(accountID: UUID) async throws {
        try requireAccount(accountID)
        let base = self.base
        try await run { try await base.clearDefault(accountID: accountID) }
    }

    func clear(accountID: UUID) async throws {
        try requireAccount(accountID)
        let base = self.base
        try await run { try await base.clear(accountID: accountID) }
    }

    private func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let validity = self.validity
        let lease = self.lease
        return try await operationGate.run(for: lease) {
            try await validity.require(lease)
            let value = try await operation()
            try await validity.require(lease)
            return value
        }
    }

    private func requireAccount(_ accountID: UUID) throws {
        guard accountID == self.accountID else { throw CancellationError() }
    }
}

private enum AppRuntimeStagedDefaultReminder: Equatable, Sendable {
    case save(DefaultTaskReminder)
    case clear
}

private actor AppRuntimeSettingsReminderBuffer {
    struct Snapshot: Equatable, Sendable {
        let revision: UUID
        let mutation: AppRuntimeStagedDefaultReminder
    }

    private var snapshot: Snapshot?

    func stage(_ mutation: AppRuntimeStagedDefaultReminder) {
        snapshot = Snapshot(revision: UUID(), mutation: mutation)
    }

    func value() -> Snapshot? { snapshot }

    func clear(revision: UUID) {
        guard snapshot?.revision == revision else { return }
        snapshot = nil
    }

    func discard() { snapshot = nil }
}

enum AppRuntimeSettingsTransactionError: Error, Equatable, Sendable {
    case defaultCommitFailed
}

struct AppRuntimeSettingsReminderStore: TaskReminderStoreServing, Sendable {
    let direct: AppRuntimeTaskReminderStore
    private let buffer: AppRuntimeSettingsReminderBuffer

    init(direct: AppRuntimeTaskReminderStore) {
        self.direct = direct
        buffer = AppRuntimeSettingsReminderBuffer()
    }

    func reconciliationItems(accountID: UUID) async throws -> [TaskReminderReconciliationItem] {
        try await direct.reconciliationItems(accountID: accountID)
    }

    func reminders(accountID: UUID) async throws -> [LocalTaskReminder] {
        try await direct.reminders(accountID: accountID)
    }

    func save(_ reminder: LocalTaskReminder, taskState: ReminderTaskState) async throws {
        try await direct.save(reminder, taskState: taskState)
    }

    func remove(accountID: UUID, taskID: UUID, reminderID: UUID) async throws {
        try await direct.remove(
            accountID: accountID,
            taskID: taskID,
            reminderID: reminderID
        )
    }

    func defaultReminder(accountID: UUID) async throws -> DefaultTaskReminder? {
        guard accountID == direct.accountID else { throw CancellationError() }
        if let staged = await buffer.value() {
            switch staged.mutation {
            case let .save(reminder): return reminder
            case .clear: return nil
            }
        }
        return try await direct.defaultReminder(accountID: accountID)
    }

    func saveDefault(_ reminder: DefaultTaskReminder) async throws {
        guard reminder.accountID == direct.accountID else { throw CancellationError() }
        let direct = self.direct
        let buffer = self.buffer
        try await direct.operationGate.run(for: direct.lease) {
            try await direct.validity.require(direct.lease)
            await buffer.stage(.save(reminder))
            try await direct.validity.require(direct.lease)
        }
    }

    func clearDefault(accountID: UUID) async throws {
        guard accountID == direct.accountID else { throw CancellationError() }
        let direct = self.direct
        let buffer = self.buffer
        try await direct.operationGate.run(for: direct.lease) {
            try await direct.validity.require(direct.lease)
            await buffer.stage(.clear)
            try await direct.validity.require(direct.lease)
        }
    }

    func clear(accountID: UUID) async throws {
        await buffer.discard()
        try await direct.clear(accountID: accountID)
    }

    func commitStagedDefaultWithinLease() async throws {
        guard let staged = await buffer.value() else { return }
        do {
            switch staged.mutation {
            case let .save(reminder):
                try await direct.base.saveDefault(reminder)
            case .clear:
                try await direct.base.clearDefault(accountID: direct.accountID)
            }
            await buffer.clear(revision: staged.revision)
        } catch is CancellationError {
            await buffer.clear(revision: staged.revision)
            throw AppRuntimeSettingsTransactionError.defaultCommitFailed
        } catch {
            await buffer.clear(revision: staged.revision)
            throw AppRuntimeSettingsTransactionError.defaultCommitFailed
        }
    }

    func discardStagedDefault() async {
        await buffer.discard()
    }
}

struct AppRuntimeDeviceRegistrationService: DeviceRegistrationServicing, Sendable {
    let base: any DeviceRegistrationServicing
    let accountID: UUID
    let lease: AppRuntimeLease
    let validity: AppRuntimeValidity
    let operationGate: AppRuntimeOperationGate

    func state(accountID: UUID) async -> DeviceRegistrationDisplayState {
        guard accountID == self.accountID else { return .unavailable }
        let base = self.base
        let validity = self.validity
        let lease = self.lease
        do {
            return try await operationGate.run(for: lease) {
                try await validity.require(lease)
                let value = await base.state(accountID: accountID)
                try await validity.require(lease)
                return value
            }
        } catch {
            return .unavailable
        }
    }

    func sync(accountID: UUID, deviceName: String?) async throws -> DeviceRegistrationSyncResult {
        try requireAccount(accountID)
        let base = self.base
        return try await run { try await base.sync(accountID: accountID, deviceName: deviceName) }
    }

    func unregister(accountID: UUID) async throws -> DeviceRegistrationSyncResult {
        try requireAccount(accountID)
        let base = self.base
        return try await run { try await base.unregister(accountID: accountID) }
    }

    private func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let validity = self.validity
        let lease = self.lease
        return try await operationGate.run(for: lease) {
            try await validity.require(lease)
            let value = try await operation()
            try await validity.require(lease)
            return value
        }
    }

    private func requireAccount(_ accountID: UUID) throws {
        guard accountID == self.accountID else { throw CancellationError() }
    }
}

actor AppRuntimeNotificationState {
    private var active = true
    private var runtimeReady = false

    func markRuntimeReady() -> Bool {
        guard active else { return false }
        runtimeReady = true
        return true
    }

    func canResume() -> Bool {
        active && runtimeReady
    }

    func beginDeactivation() -> Bool {
        guard active else { return false }
        active = false
        runtimeReady = false
        return true
    }
}

struct AppRuntimeNotificationLifecycle: Sendable {
    let accountID: UUID
    let timeZone: TimeZone
    let lease: AppRuntimeLease
    let validity: AppRuntimeValidity
    let operationGate: AppRuntimeOperationGate
    let state: AppRuntimeNotificationState
    let settingsRepository: any SettingsRepositoryServing
    let settingsCache: any SettingsCacheServing
    let notificationCenter: any UserNotificationCenterServing
    let scheduler: TaskReminderScheduler

    func suspend() async {
        let accountID = self.accountID
        let lease = self.lease
        let validity = self.validity
        let scheduler = self.scheduler
        try? await operationGate.run(for: lease) {
            try await validity.require(lease)
            await scheduler.suspendNotifications(accountID: accountID)
            try await validity.require(lease)
        }
    }

    func resumeIfEnabled(allowNetwork: Bool) async throws -> Bool {
        let accountID = self.accountID
        let timeZone = self.timeZone
        let lease = self.lease
        let validity = self.validity
        let state = self.state
        let settingsRepository = self.settingsRepository
        let settingsCache = self.settingsCache
        let notificationCenter = self.notificationCenter
        let scheduler = self.scheduler
        return try await operationGate.run(for: lease) {
            try await validity.require(lease)
            guard await state.canResume() else { return false }
            let settings: UserSettingsDTO?
            if allowNetwork {
                settings = try await settingsRepository.load(accountID: accountID).settings
            } else {
                settings = try await settingsCache.settings(accountID: accountID)
            }
            try await validity.require(lease)
            guard await state.canResume() else { throw CancellationError() }
            let authorization = await notificationCenter.authorizationState()
            guard settings?.notificationsEnabled == true,
                  Self.isAuthorized(authorization) else {
                await scheduler.suspendNotifications(accountID: accountID)
                try await validity.require(lease)
                return false
            }
            try await scheduler.resumeNotifications(
                accountID: accountID,
                timeZone: timeZone
            )
            try await validity.require(lease)
            return true
        }
    }

    func resumeAcceptedSettings(timeZone: TimeZone) async throws {
        let accountID = self.accountID
        let lease = self.lease
        let validity = self.validity
        let state = self.state
        let notificationCenter = self.notificationCenter
        let scheduler = self.scheduler
        try await operationGate.run(for: lease) {
            try await validity.require(lease)
            guard await state.canResume() else { throw CancellationError() }
            let authorization = await notificationCenter.authorizationState()
            guard Self.isAuthorized(authorization) else {
                await scheduler.suspendNotifications(accountID: accountID)
                return
            }
            try await scheduler.resumeNotifications(
                accountID: accountID,
                timeZone: timeZone
            )
            try await validity.require(lease)
        }
    }

    func clear() async throws {
        let accountID = self.accountID
        let lease = self.lease
        let validity = self.validity
        let scheduler = self.scheduler
        try await operationGate.run(for: lease) {
            try await validity.require(lease)
            try await scheduler.cancelAll(accountID: accountID)
            try await validity.require(lease)
        }
    }

    private static func isAuthorized(_ state: NotificationAuthorizationState) -> Bool {
        switch state {
        case .authorized, .provisional, .ephemeral: true
        case .notDetermined, .denied: false
        }
    }
}

struct AppRuntimeAccountNotificationController: AccountNotificationClearing, Sendable {
    let lifecycle: AppRuntimeNotificationLifecycle
    let settingsReminderStore: AppRuntimeSettingsReminderStore

    func clear(accountID: UUID) async throws {
        guard accountID == lifecycle.accountID else { throw CancellationError() }
        await settingsReminderStore.discardStagedDefault()
        try await lifecycle.clear()
    }

    func suspendNotifications(accountID: UUID) async {
        guard accountID == lifecycle.accountID else { return }
        await lifecycle.suspend()
    }

    func resumeNotifications(accountID: UUID, timeZone: TimeZone) async throws {
        guard accountID == lifecycle.accountID else { throw CancellationError() }
        try await lifecycle.resumeAcceptedSettings(timeZone: timeZone)
    }
}

struct AppCollaboratorResourceScope: Equatable, Sendable {
    let folderRemoteIDs: Set<UUID>
    let goalRemoteIDs: Set<UUID>
}

actor AppSharingScopeRegistry {
    private let lease: AppRuntimeLease
    private var scope: AppCollaboratorResourceScope?

    init(lease: AppRuntimeLease) {
        self.lease = lease
    }

    func update(_ response: ActionSharedResourcesResponseDTO, for lease: AppRuntimeLease) {
        guard self.lease == lease else { return }
        scope = AppCollaboratorResourceScope(
            folderRemoteIDs: Set(response.folders.map(\.id)),
            goalRemoteIDs: Set(response.goals.map(\.id))
        )
    }

    func value(for lease: AppRuntimeLease) -> AppCollaboratorResourceScope? {
        self.lease == lease ? scope : nil
    }

    func invalidate(for lease: AppRuntimeLease) {
        guard self.lease == lease else { return }
        scope = nil
    }
}

struct AppOwnerScopeSharingAccess: PlannerDetailsSharingAccessing, Sendable {
    let service: any SharingServicing
    let scopeRegistry: AppSharingScopeRegistry
    let lease: AppRuntimeLease

    func sharedResources() async throws -> ActionSharedResourcesResponseDTO {
        let response = try await service.listSharedResources()
        try Task.checkCancellation()
        await scopeRegistry.update(response, for: lease)
        return response
    }

    func createInvitation(
        resource: ShareableResourceKind,
        id: UUID,
        request: SharingInvitationRequest
    ) async throws -> ShareInvitationDTO {
        try await service.createInvitation(resource: resource, id: id, request: request)
    }
}

actor AppUnauthorizedRelay {
    typealias Handler = @Sendable (AppRuntimeLease?) async -> Void

    private var handler: Handler?

    func install(_ handler: Handler?) {
        self.handler = handler
    }

    func report(for lease: AppRuntimeLease? = nil) async {
        await handler?(lease)
    }
}

actor AppCoreSyncHookRegistry: CoreSyncHook {
    private var lease: AppRuntimeLease?
    private var hook: (any CoreSyncHook)?

    func activate(lease: AppRuntimeLease, hook: any CoreSyncHook) {
        self.lease = lease
        self.hook = hook
    }

    func deactivate(lease: AppRuntimeLease? = nil) {
        guard lease == nil || self.lease == lease else { return }
        self.lease = nil
        hook = nil
    }

    func synchronize(trigger: CoreSyncTrigger) async throws {
        guard let hook else { return }
        try await hook.synchronize(trigger: trigger)
    }
}

enum AppRuntimeFeatureSyncPipeline {
    static func run(
        checkpoint: @Sendable () async throws -> Void,
        focus: @Sendable () async throws -> Void,
        reminders: @Sendable () async throws -> Void,
        device: @Sendable () async throws -> Void
    ) async throws {
        try await checkpoint()
        try await focus()
        try await checkpoint()
        try await reminders()
        try await checkpoint()
        try await device()
        try await checkpoint()
    }
}

struct AppUserCoreSyncHook: CoreSyncHook {
    let lease: AppRuntimeLease
    let validity: AppRuntimeValidity
    let operationGate: AppRuntimeOperationGate
    let timezone: String
    let planning: SyncEngine
    let focus: any FocusRepositoryServing
    let notifications: AppRuntimeNotificationLifecycle
    let deviceRegistration: any DeviceRegistrationServicing
    let deviceName: String?
    let unauthorizedRelay: AppUnauthorizedRelay

    func synchronize(trigger: CoreSyncTrigger) async throws {
        let operationGate = self.operationGate
        let lease = self.lease
        let focus = self.focus
        do {
            try await withTaskCancellationHandler {
                try await operationGate.run(for: lease) {
                    try await self.synchronizeOperation(trigger: trigger)
                }
            } onCancel: {
                Task {
                    await focus.cancelAndAwaitPendingSync(accountID: lease.accountID)
                }
            }
        } catch let api as APIError where api.isUnauthorized {
            await unauthorizedRelay.report(for: lease)
            throw api
        } catch let integration as PlannerDetailsIntegrationError where integration == .unauthorized {
            await unauthorizedRelay.report(for: lease)
            throw integration
        }
    }

    private func synchronizeOperation(trigger: CoreSyncTrigger) async throws {
            try await checkpoint()
            let status: SyncStatus
            switch trigger {
            case .foreground:
                status = await planning.syncOnForeground()
            case .networkAvailable:
                status = await planning.syncWhenNetworkReturns()
            case .backgroundRefresh:
                status = await planning.syncInBackground()
            }

            try await checkpoint()
            if status.phase == .unauthorized {
                throw PlannerDetailsIntegrationError.unauthorized
            }
            if status.phase == .failed || status.phase == .conflicted {
                throw BackgroundRefreshError.syncFailed(status.lastErrorCode)
            }

            try await AppRuntimeFeatureSyncPipeline.run(
                checkpoint: { try await checkpoint() },
                focus: {
                    _ = try await focus.syncPending(
                        accountID: lease.accountID,
                        timezone: timezone
                    )
                },
                reminders: {
                    _ = try await notifications.resumeIfEnabled(allowNetwork: true)
                },
                device: {
                    _ = try await deviceRegistration.sync(
                        accountID: lease.accountID,
                        deviceName: deviceName
                    )
                }
            )
    }

    private func checkpoint() async throws {
        try await validity.require(lease)
    }
}

struct AppTaskIDMapper: Sendable {
    let persistence: any PlannerDetailsPersistenceAccessing
    let repository: any PlanningRepository

    func localID(for serverOrLocalID: UUID) async throws -> UUID? {
        if let mapped = try await persistence.localID(for: .task, remoteID: serverOrLocalID) {
            return mapped
        }
        let snapshot = try await repository.snapshot()
        return snapshot.tasks.contains(where: { $0.id == serverOrLocalID })
            ? serverOrLocalID
            : nil
    }

    func serverID(for localOrServerID: UUID) async throws -> UUID? {
        if let task = (try await repository.snapshot()).tasks.first(where: { $0.id == localOrServerID }) {
            if let mapped = try? await persistence.remoteID(for: .task, localID: task.id) {
                return mapped
            }
            return task.id
        }
        return localOrServerID
    }
}

actor AppTaskDeepLinkAccessRegistry: TaskDeepLinkAccessChecking {
    private var lease: AppRuntimeLease?
    private var mapper: AppTaskIDMapper?

    func activate(_ mapper: AppTaskIDMapper, lease: AppRuntimeLease) {
        self.lease = lease
        self.mapper = mapper
    }

    func deactivate(lease: AppRuntimeLease? = nil) {
        guard lease == nil || self.lease == lease else { return }
        self.lease = nil
        mapper = nil
    }

    func isReady(for lease: AppRuntimeLease) -> Bool {
        self.lease == lease && mapper != nil
    }

    func access(taskID: UUID) async throws -> TaskDeepLinkAccess {
        guard let mapper else { return .missing }
        let localID = try await mapper.localID(for: taskID)
        return localID == nil ? .missing : .accessible
    }

    func localID(for taskID: UUID) async throws -> UUID? {
        guard let mapper else { return nil }
        return try await mapper.localID(for: taskID)
    }
}

enum AppTeardownStage: String, CaseIterable, Equatable, Sendable {
    case deviceUnregister
    case reminders
    case deviceRetry
    case featureCache
    case coreDatabase
}

struct AppTeardownFailure: Equatable, Sendable {
    let stage: AppTeardownStage
    let requiredForPrivacy: Bool
    let message: String
}

struct AppRuntimeTeardownError: Error, Equatable, Sendable, LocalizedError {
    let accountID: UUID
    let failures: [AppTeardownFailure]

    var hasRequiredPrivacyFailure: Bool {
        failures.contains { $0.requiredForPrivacy }
    }

    var errorDescription: String? {
        failures
            .map { "\($0.stage.rawValue): \($0.message)" }
            .joined(separator: "; ")
    }
}

@MainActor
struct AppTeardownOperation {
    let stage: AppTeardownStage
    let requiredForPrivacy: Bool
    let run: () async throws -> Void
}

@MainActor
enum AppTeardownExecutor {
    static func run(_ operations: [AppTeardownOperation]) async -> [AppTeardownFailure] {
        var failures: [AppTeardownFailure] = []
        for operation in operations {
            do {
                try await operation.run()
            } catch {
                failures.append(
                    AppTeardownFailure(
                        stage: operation.stage,
                        requiredForPrivacy: operation.requiredForPrivacy,
                        message: error.localizedDescription
                    )
                )
            }
        }
        return failures
    }
}

struct AppUnauthorizedPlannerDetailsAdapter: PlannerLoading, PlannerActionPerforming,
    DetailLoading, DetailMutationPerforming, EditorSaving, EditorTagCreating,
    EditorFocusUpdating, PlannerDetailsCommandServing, PlannerDetailsEditorSeedLoading,
    PlannerDetailsResourceIDResolving, Sendable {

    let base: PlannerDetailsAdapter
    let lease: AppRuntimeLease
    let relay: AppUnauthorizedRelay
    let operationGate: AppRuntimeOperationGate

    init(
        base: PlannerDetailsAdapter,
        lease: AppRuntimeLease,
        relay: AppUnauthorizedRelay,
        operationGate: AppRuntimeOperationGate? = nil
    ) {
        self.base = base
        self.lease = lease
        self.relay = relay
        self.operationGate = operationGate ?? AppRuntimeOperationGate(lease: lease)
    }

    func loadPlanner() async throws -> PlannerLoadResult {
        try await reporting { try await self.base.loadPlanner() }
    }

    func perform(_ action: PlannerMutationAction) async throws -> PlannerMutationResult {
        try await reporting { try await self.base.perform(action) }
    }

    func loadDetail(_ reference: DetailEntityReference) async throws -> DetailLoadResult {
        try await reporting { try await self.base.loadDetail(reference) }
    }

    func performDetailMutation(_ mutation: DetailMutation) async throws -> DetailMutationResult {
        try await reporting { try await self.base.performDetailMutation(mutation) }
    }

    func saveEditor(_ request: EditorSaveRequest) async throws -> EditorSaveResult {
        try await reporting { try await self.base.saveEditor(request) }
    }

    func createTag(_ payload: TagEditorPayload) async throws -> TagEditorItemDraft {
        try await reporting { try await self.base.createTag(payload) }
    }

    func setTaskFocus(taskID: UUID, focused: Bool) async throws {
        try await reporting { try await self.base.setTaskFocus(taskID: taskID, focused: focused) }
    }

    func move(
        _ reference: DetailEntityReference,
        toParentID: UUID?
    ) async throws -> DetailEntityReference {
        try await reporting { try await self.base.move(reference, toParentID: toParentID) }
    }

    func clone(
        _ reference: DetailEntityReference,
        toParentID: UUID?
    ) async throws -> DetailEntityReference {
        try await reporting { try await self.base.clone(reference, toParentID: toParentID) }
    }

    func invite(
        _ reference: DetailEntityReference,
        request: SharingInvitationRequest
    ) async throws -> ShareInvitationDTO {
        try await reporting { try await self.base.invite(reference, request: request) }
    }

    func rescheduleTask(localID: UUID, plannedAt: Date) async throws {
        try await reporting {
            try await self.base.rescheduleTask(localID: localID, plannedAt: plannedAt)
        }
    }

    func editorSeed(for route: DetailEditorRoute) async throws -> PlannerDetailsEditorSeed {
        try await reporting { try await self.base.editorSeed(for: route) }
    }

    func localID(kind: DetailEntityKind, serverID: UUID) async throws -> UUID {
        try await reporting { try await self.base.localID(kind: kind, serverID: serverID) }
    }

    func serverID(kind: DetailEntityKind, localID: UUID) async throws -> UUID {
        try await reporting { try await self.base.serverID(kind: kind, localID: localID) }
    }

    private func reporting<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            return try await operationGate.run(for: lease, operation: operation)
        } catch {
            if AppUnauthorizedErrorClassifier.isUnauthorized(error) {
                await relay.report(for: lease)
            }
            throw error
        }
    }
}

struct AppUnauthorizedSharingService: SharingFeatureServing, Sendable {
    let base: any SharingFeatureServing
    let lease: AppRuntimeLease
    let relay: AppUnauthorizedRelay
    let operationGate: AppRuntimeOperationGate

    init(
        base: any SharingFeatureServing,
        lease: AppRuntimeLease,
        relay: AppUnauthorizedRelay,
        operationGate: AppRuntimeOperationGate? = nil
    ) {
        self.base = base
        self.lease = lease
        self.relay = relay
        self.operationGate = operationGate ?? AppRuntimeOperationGate(lease: lease)
    }

    func createInvitation(
        resource: ShareableResourceKind,
        id: UUID,
        request: SharingInvitationRequest
    ) async throws -> ShareInvitationDTO {
        try await reporting {
            try await self.base.createInvitation(resource: resource, id: id, request: request)
        }
    }

    func listInvitations() async throws -> [ShareInvitationDTO] {
        try await reporting { try await self.base.listInvitations() }
    }

    func revokeInvitation(id: UUID) async throws -> ShareInvitationActionResponseDTO {
        try await reporting { try await self.base.revokeInvitation(id: id) }
    }

    func createShareLink(
        resource: ShareableResourceKind,
        id: UUID,
        request: ShareLinkRequestDTO?
    ) async throws -> ShareLinkCreateResponseDTO {
        try await reporting {
            try await self.base.createShareLink(resource: resource, id: id, request: request)
        }
    }

    func listShareLinks(resource: ShareableResourceKind, id: UUID) async throws -> [ShareLinkDTO] {
        try await reporting { try await self.base.listShareLinks(resource: resource, id: id) }
    }

    func revokeShareLink(id: UUID) async throws -> ShareLinkActionResponseDTO {
        try await reporting { try await self.base.revokeShareLink(id: id) }
    }

    func resolveShareLink(token: String) async throws -> ShareLinkResolveResponseDTO {
        try await reporting { try await self.base.resolveShareLink(token: token) }
    }

    func acceptShareLink(token: String) async throws -> ShareLinkAcceptResponseDTO {
        try await reporting { try await self.base.acceptShareLink(token: token) }
    }

    private func reporting<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            return try await operationGate.run(for: lease, operation: operation)
        } catch {
            if AppUnauthorizedErrorClassifier.isUnauthorized(error) {
                await relay.report(for: lease)
            }
            throw error
        }
    }
}

struct AppUnauthorizedEntityLinkService: EntityLinkFeatureServing, Sendable {
    let base: any EntityLinkFeatureServing
    let lease: AppRuntimeLease
    let relay: AppUnauthorizedRelay
    let operationGate: AppRuntimeOperationGate

    init(
        base: any EntityLinkFeatureServing,
        lease: AppRuntimeLease,
        relay: AppUnauthorizedRelay,
        operationGate: AppRuntimeOperationGate? = nil
    ) {
        self.base = base
        self.lease = lease
        self.relay = relay
        self.operationGate = operationGate ?? AppRuntimeOperationGate(lease: lease)
    }

    func listEntityLinks(type: LinkedEntityType, id: UUID) async throws -> [ActionEntityLinkDTO] {
        try await reporting { try await self.base.listEntityLinks(type: type, id: id) }
    }

    func createEntityLink(_ request: CreateEntityLinkRequestDTO) async throws -> ActionEntityLinkDTO {
        try await reporting { try await self.base.createEntityLink(request) }
    }

    func updateEntityLink(
        id: UUID,
        request: UpdateEntityLinkRequestDTO
    ) async throws -> ActionEntityLinkDTO {
        try await reporting { try await self.base.updateEntityLink(id: id, request: request) }
    }

    func deleteEntityLink(id: UUID) async throws {
        try await reporting { try await self.base.deleteEntityLink(id: id) }
    }

    private func reporting<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            return try await operationGate.run(for: lease, operation: operation)
        } catch {
            if AppUnauthorizedErrorClassifier.isUnauthorized(error) {
                await relay.report(for: lease)
            }
            throw error
        }
    }
}

enum AppUnauthorizedErrorClassifier {
    static func isUnauthorized(_ error: Error) -> Bool {
        if let api = error as? APIError { return api.isUnauthorized }
        if let integration = error as? PlannerDetailsIntegrationError {
            return integration == .unauthorized
        }
        if let detail = error as? DetailServiceFailure {
            return detail.statusCode == 401 || detail.code == "unauthorized"
        }
        if let remote = error as? RemoteActionError, case .unauthorized = remote {
            return true
        }
        return false
    }
}

struct AppRuntimeCalendarLoader: CalendarLoading, Sendable {
    let base: any CalendarLoading
    let lease: AppRuntimeLease
    let relay: AppUnauthorizedRelay
    let operationGate: AppRuntimeOperationGate

    func load(
        accountID: UUID,
        accountTimezone: String,
        from: LocalDate,
        toExclusive: LocalDate
    ) async throws -> CalendarLoadResult {
        try requireAccount(accountID)
        return try await reporting {
            try await self.base.load(
                accountID: accountID,
                accountTimezone: accountTimezone,
                from: from,
                toExclusive: toExclusive
            )
        }
    }

    private func requireAccount(_ accountID: UUID) throws {
        guard accountID == lease.accountID else { throw CancellationError() }
    }

    private func reporting<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            return try await operationGate.run(for: lease, operation: operation)
        } catch {
            if AppUnauthorizedErrorClassifier.isUnauthorized(error) {
                await relay.report(for: lease)
            }
            throw error
        }
    }
}

struct AppRuntimeFocusRepository: FocusRepositoryServing, Sendable {
    let base: any FocusRepositoryServing
    let lease: AppRuntimeLease
    let relay: AppUnauthorizedRelay
    let operationGate: AppRuntimeOperationGate

    func loadCurrent(accountID: UUID, timezone: String) async throws -> FocusCurrentResult {
        return try await run(accountID: accountID) {
            try await self.base.loadCurrent(accountID: accountID, timezone: timezone)
        }
    }

    func loadCandidates(
        accountID: UUID,
        query: String?,
        folderID: UUID?,
        goalID: UUID?,
        cursor: String?,
        limit: Int
    ) async throws -> FocusCandidateListResponseDTO {
        try await run(accountID: accountID) {
            try await self.base.loadCandidates(
                accountID: accountID,
                query: query,
                folderID: folderID,
                goalID: goalID,
                cursor: cursor,
                limit: limit
            )
        }
    }

    func add(accountID: UUID, candidate: FocusCandidateDTO) async throws -> FocusCurrentResult {
        try await run(accountID: accountID) {
            try await self.base.add(accountID: accountID, candidate: candidate)
        }
    }

    func remove(accountID: UUID, taskID: UUID) async throws -> FocusCurrentResult {
        try await run(accountID: accountID) {
            try await self.base.remove(accountID: accountID, taskID: taskID)
        }
    }

    func reorder(accountID: UUID, taskIDs: [UUID]) async throws -> FocusCurrentResult {
        try await run(accountID: accountID) {
            try await self.base.reorder(accountID: accountID, taskIDs: taskIDs)
        }
    }

    func resolveRollover(
        accountID: UUID,
        selectedTaskIDs: [UUID]
    ) async throws -> FocusCurrentResult {
        try await run(accountID: accountID) {
            try await self.base.resolveRollover(
                accountID: accountID,
                selectedTaskIDs: selectedTaskIDs
            )
        }
    }

    func loadHistory(accountID: UUID) async throws -> FocusHistoryResult {
        try await run(accountID: accountID) {
            try await self.base.loadHistory(accountID: accountID)
        }
    }

    func loadHistoryDetail(
        accountID: UUID,
        periodID: UUID
    ) async throws -> FocusHistoryDetailResult {
        try await run(accountID: accountID) {
            try await self.base.loadHistoryDetail(accountID: accountID, periodID: periodID)
        }
    }

    func loadSettings(accountID: UUID) async throws -> FocusSettingsResult {
        try await run(accountID: accountID) {
            try await self.base.loadSettings(accountID: accountID)
        }
    }

    func updateSettings(
        accountID: UUID,
        values: FocusCadenceValues
    ) async throws -> FocusSettingsResult {
        try await run(accountID: accountID) {
            try await self.base.updateSettings(accountID: accountID, values: values)
        }
    }

    func syncPending(accountID: UUID, timezone: String) async throws -> FocusSyncResult {
        try await run(accountID: accountID) {
            try await self.base.syncPending(accountID: accountID, timezone: timezone)
        }
    }

    func cancelAndAwaitPendingSync(accountID: UUID) async {
        guard accountID == lease.accountID else { return }
        await base.cancelAndAwaitPendingSync(accountID: accountID)
    }

    private func run<Value: Sendable>(
        accountID: UUID,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        guard accountID == lease.accountID else { throw CancellationError() }
        do {
            return try await operationGate.run(for: lease, operation: operation)
        } catch {
            if AppUnauthorizedErrorClassifier.isUnauthorized(error) {
                await relay.report(for: lease)
            }
            throw error
        }
    }
}

struct AppRuntimeSettingsRepository: SettingsRepositoryServing, Sendable {
    let base: any SettingsRepositoryServing
    let lease: AppRuntimeLease
    let relay: AppUnauthorizedRelay
    let operationGate: AppRuntimeOperationGate
    let acceptedSaveCommit: @Sendable () async throws -> Void

    init(
        base: any SettingsRepositoryServing,
        lease: AppRuntimeLease,
        relay: AppUnauthorizedRelay,
        operationGate: AppRuntimeOperationGate,
        acceptedSaveCommit: @escaping @Sendable () async throws -> Void = {}
    ) {
        self.base = base
        self.lease = lease
        self.relay = relay
        self.operationGate = operationGate
        self.acceptedSaveCommit = acceptedSaveCommit
    }

    func load(accountID: UUID) async throws -> SettingsRepositorySnapshot {
        try await run(accountID: accountID) {
            try await self.base.load(accountID: accountID)
        }
    }

    func save(
        accountID: UUID,
        language: AppLanguage,
        notificationsEnabled: Bool
    ) async throws -> SettingsRepositorySnapshot {
        let base = self.base
        let acceptedSaveCommit = self.acceptedSaveCommit
        return try await run(accountID: accountID) {
            let snapshot = try await base.save(
                accountID: accountID,
                language: language,
                notificationsEnabled: notificationsEnabled
            )
            try await acceptedSaveCommit()
            return snapshot
        }
    }

    func retry(accountID: UUID) async throws -> SettingsRepositorySnapshot {
        try await run(accountID: accountID) {
            try await self.base.retry(accountID: accountID)
        }
    }

    func cancelAndAwaitAllOperations(accountID: UUID) async {
        guard accountID == lease.accountID else { return }
        await base.cancelAndAwaitAllOperations(accountID: accountID)
    }

    private func run<Value: Sendable>(
        accountID: UUID,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        guard accountID == lease.accountID else { throw CancellationError() }
        do {
            return try await operationGate.run(for: lease, operation: operation)
        } catch {
            if AppUnauthorizedErrorClassifier.isUnauthorized(error) {
                await relay.report(for: lease)
            }
            throw error
        }
    }
}

struct AppSharingOwnershipResolver: Sendable {
    let currentUserID: UUID
    let repository: any PlanningRepository
    let persistence: any PlannerDetailsPersistenceAccessing
    let scopeRegistry: AppSharingScopeRegistry
    let lease: AppRuntimeLease
    let operationGate: AppRuntimeOperationGate

    func isOwner(of reference: DetailEntityReference) async throws -> Bool {
        let currentUserID = self.currentUserID
        let repository = self.repository
        let persistence = self.persistence
        let scopeRegistry = self.scopeRegistry
        let lease = self.lease
        let operationGate = self.operationGate
        return try await operationGate.run(for: lease) {
            let snapshot = try await repository.snapshot()
            switch reference.kind {
            case .task:
                return Self.isOwner(
                    currentUserID: currentUserID,
                    ownerUserID: snapshot.tasks.first(where: { $0.id == reference.id })?.creatorUserId
                )
            case .idea:
                return Self.isOwner(
                    currentUserID: currentUserID,
                    ownerUserID: snapshot.ideas.first(where: { $0.id == reference.id })?.creatorUserId
                )
            case .folder, .goal:
                guard let remoteScope = await scopeRegistry.value(for: lease) else {
                    return false
                }
                let localScope = try await Self.localScope(
                    remoteScope,
                    snapshot: snapshot,
                    persistence: persistence
                )
                return Self.isOwnedFolderOrGoal(
                    reference: reference,
                    snapshot: snapshot,
                    collaboratorFolderIDs: localScope.folderIDs,
                    collaboratorGoalIDs: localScope.goalIDs
                )
            case .note:
                return false
            }
        }
    }

    static func isOwner(
        currentUserID: UUID,
        ownerUserID: UUID?,
        explicitOwnerCapability: Bool = false
    ) -> Bool {
        explicitOwnerCapability || ownerUserID == currentUserID
    }

    static func isOwnedFolderOrGoal(
        reference: DetailEntityReference,
        snapshot: PlanningSnapshot,
        collaboratorFolderIDs: Set<UUID>,
        collaboratorGoalIDs: Set<UUID>
    ) -> Bool {
        let startingFolderID: UUID
        switch reference.kind {
        case .folder:
            startingFolderID = reference.id
        case .goal:
            guard
                !collaboratorGoalIDs.contains(reference.id),
                let goal = snapshot.goals.first(where: { $0.id == reference.id })
            else {
                return false
            }
            startingFolderID = goal.folderId
        case .task, .idea, .note:
            return false
        }

        var folderID: UUID? = startingFolderID
        var visited: Set<UUID> = []
        while let currentID = folderID {
            guard visited.insert(currentID).inserted,
                  !collaboratorFolderIDs.contains(currentID),
                  let folder = snapshot.folders.first(where: { $0.id == currentID }) else {
                return false
            }
            folderID = folder.parentFolderId
        }
        return true
    }

    private static func localScope(
        _ remoteScope: AppCollaboratorResourceScope,
        snapshot: PlanningSnapshot,
        persistence: any PlannerDetailsPersistenceAccessing
    ) async throws -> (folderIDs: Set<UUID>, goalIDs: Set<UUID>) {
        var folders: Set<UUID> = []
        for remoteID in remoteScope.folderRemoteIDs {
            if let localID = try await persistence.localID(for: .folder, remoteID: remoteID) {
                folders.insert(localID)
            } else if snapshot.folders.contains(where: { $0.id == remoteID }) {
                folders.insert(remoteID)
            }
        }
        var goals: Set<UUID> = []
        for remoteID in remoteScope.goalRemoteIDs {
            if let localID = try await persistence.localID(for: .goal, remoteID: remoteID) {
                goals.insert(localID)
            } else if snapshot.goals.contains(where: { $0.id == remoteID }) {
                goals.insert(remoteID)
            }
        }
        return (folders, goals)
    }
}

@MainActor
final class AppUserRuntime {
    let lease: AppRuntimeLease
    let validity: AppRuntimeValidity
    let operationGate: AppRuntimeOperationGate
    let sharingScopeRegistry: AppSharingScopeRegistry
    let user: UserDTO
    let database: AppDatabase
    let planningRepository: LocalPlanningRepository
    let syncEngine: SyncEngine
    let plannerDetails: PlannerDetailsAdapter
    let plannerDetailsActions: AppUnauthorizedPlannerDetailsAdapter
    let taskIDMapper: AppTaskIDMapper
    let calendarRepository: CalendarRepository
    let calendarActions: AppRuntimeCalendarLoader
    let focusRepository: FocusRepository
    let focusActions: AppRuntimeFocusRepository
    let settingsRepository: SettingsRepository
    let settingsCache: any SettingsCacheServing
    let settingsActions: AppRuntimeSettingsRepository
    let reminderStore: AppRuntimeTaskReminderStore
    let settingsReminderStore: AppRuntimeSettingsReminderStore
    let reminderScheduler: TaskReminderScheduler
    let notificationState: AppRuntimeNotificationState
    let notificationLifecycle: AppRuntimeNotificationLifecycle
    let notificationActions: AppRuntimeAccountNotificationController
    let reminderWorkflow: AppRuntimeTaskReminderWorkflow
    let reminderEditorActions: TaskReminderEditorSavingAdapter
    let reminderDetailActions: TaskReminderDetailMutationAdapter
    let reminderEditorSeedLoader: TaskReminderEditorSeedLoader
    private let deviceRegistrationBackend: any DeviceRegistrationServicing
    let deviceRegistration: AppRuntimeDeviceRegistrationService
    let deviceTokenCoordinator: DeviceRegistrationTokenCoordinator
    let remoteNotificationHandler: RemoteNotificationHandler
    let planningActions: PlanningActionService
    let entityLinkActions: AppUnauthorizedEntityLinkService
    let sharingService: SharingService
    let sharingActions: AppUnauthorizedSharingService
    let sharingOwnership: AppSharingOwnershipResolver
    let notificationCenter: any UserNotificationCenterServing
    let featureCleaner: GRDBFeaturePersistenceCleaner
    let deviceRetryStore: AppDeviceRegistrationRetryStore

    init(
        lease: AppRuntimeLease,
        validity: AppRuntimeValidity,
        operationGate: AppRuntimeOperationGate,
        sharingScopeRegistry: AppSharingScopeRegistry,
        user: UserDTO,
        database: AppDatabase,
        planningRepository: LocalPlanningRepository,
        syncEngine: SyncEngine,
        plannerDetails: PlannerDetailsAdapter,
        plannerDetailsPersistence: any PlannerDetailsPersistenceAccessing,
        taskIDMapper: AppTaskIDMapper,
        calendarRepository: CalendarRepository,
        focusRepository: FocusRepository,
        settingsRepository: SettingsRepository,
        settingsCache: any SettingsCacheServing,
        reminderStore: GRDBTaskReminderStore,
        reminderScheduler: TaskReminderScheduler,
        deviceRegistration: any DeviceRegistrationServicing,
        deviceTokenCoordinator: DeviceRegistrationTokenCoordinator,
        remoteNotificationHandler: RemoteNotificationHandler,
        planningActions: PlanningActionService,
        sharingService: SharingService,
        unauthorizedRelay: AppUnauthorizedRelay,
        notificationCenter: any UserNotificationCenterServing,
        featureCleaner: GRDBFeaturePersistenceCleaner,
        deviceRetryStore: AppDeviceRegistrationRetryStore
    ) {
        self.lease = lease
        self.validity = validity
        self.operationGate = operationGate
        self.sharingScopeRegistry = sharingScopeRegistry
        self.user = user
        self.database = database
        self.planningRepository = planningRepository
        self.syncEngine = syncEngine
        self.plannerDetails = plannerDetails
        let guardedPlannerDetails = AppUnauthorizedPlannerDetailsAdapter(
            base: plannerDetails,
            lease: lease,
            relay: unauthorizedRelay,
            operationGate: operationGate
        )
        plannerDetailsActions = guardedPlannerDetails
        self.taskIDMapper = taskIDMapper
        self.calendarRepository = calendarRepository
        calendarActions = AppRuntimeCalendarLoader(
            base: calendarRepository,
            lease: lease,
            relay: unauthorizedRelay,
            operationGate: operationGate
        )
        self.focusRepository = focusRepository
        focusActions = AppRuntimeFocusRepository(
            base: focusRepository,
            lease: lease,
            relay: unauthorizedRelay,
            operationGate: operationGate
        )
        self.settingsRepository = settingsRepository
        self.settingsCache = settingsCache
        let guardedReminderStore = AppRuntimeTaskReminderStore(
            base: reminderStore,
            accountID: user.id,
            lease: lease,
            validity: validity,
            operationGate: operationGate
        )
        self.reminderStore = guardedReminderStore
        let settingsReminderStore = AppRuntimeSettingsReminderStore(
            direct: guardedReminderStore
        )
        self.settingsReminderStore = settingsReminderStore
        settingsActions = AppRuntimeSettingsRepository(
            base: settingsRepository,
            lease: lease,
            relay: unauthorizedRelay,
            operationGate: operationGate,
            acceptedSaveCommit: {
                try await settingsReminderStore.commitStagedDefaultWithinLease()
            }
        )
        self.reminderScheduler = reminderScheduler
        let notificationState = AppRuntimeNotificationState()
        self.notificationState = notificationState
        let notificationLifecycle = AppRuntimeNotificationLifecycle(
            accountID: user.id,
            timeZone: TimeZone(identifier: user.timezone) ?? TimeZone(secondsFromGMT: 0)!,
            lease: lease,
            validity: validity,
            operationGate: operationGate,
            state: notificationState,
            settingsRepository: settingsRepository,
            settingsCache: settingsCache,
            notificationCenter: notificationCenter,
            scheduler: reminderScheduler
        )
        self.notificationLifecycle = notificationLifecycle
        notificationActions = AppRuntimeAccountNotificationController(
            lifecycle: notificationLifecycle,
            settingsReminderStore: settingsReminderStore
        )
        let rawReminderWorkflow = TaskReminderWorkflow(
            accountID: user.id,
            timeZone: TimeZone(identifier: user.timezone) ?? TimeZone(secondsFromGMT: 0)!,
            store: reminderStore,
            scheduler: reminderScheduler
        )
        let guardedReminderWorkflow = AppRuntimeTaskReminderWorkflow(
            base: rawReminderWorkflow,
            lease: lease,
            validity: validity,
            operationGate: operationGate
        )
        reminderWorkflow = guardedReminderWorkflow
        reminderEditorActions = TaskReminderEditorSavingAdapter(
            base: guardedPlannerDetails,
            reminders: guardedReminderWorkflow
        )
        reminderDetailActions = TaskReminderDetailMutationAdapter(
            base: guardedPlannerDetails,
            reminders: guardedReminderWorkflow
        )
        reminderEditorSeedLoader = TaskReminderEditorSeedLoader(
            base: guardedPlannerDetails,
            reminders: guardedReminderWorkflow
        )
        deviceRegistrationBackend = deviceRegistration
        self.deviceRegistration = AppRuntimeDeviceRegistrationService(
            base: deviceRegistration,
            accountID: user.id,
            lease: lease,
            validity: validity,
            operationGate: operationGate
        )
        self.deviceTokenCoordinator = deviceTokenCoordinator
        self.remoteNotificationHandler = remoteNotificationHandler
        self.planningActions = planningActions
        entityLinkActions = AppUnauthorizedEntityLinkService(
            base: planningActions,
            lease: lease,
            relay: unauthorizedRelay,
            operationGate: operationGate
        )
        self.sharingService = sharingService
        sharingActions = AppUnauthorizedSharingService(
            base: sharingService,
            lease: lease,
            relay: unauthorizedRelay,
            operationGate: operationGate
        )
        sharingOwnership = AppSharingOwnershipResolver(
            currentUserID: user.id,
            repository: planningRepository,
            persistence: plannerDetailsPersistence,
            scopeRegistry: sharingScopeRegistry,
            lease: lease,
            operationGate: operationGate
        )
        self.notificationCenter = notificationCenter
        self.featureCleaner = featureCleaner
        self.deviceRetryStore = deviceRetryStore
    }

    func requireActive() async throws {
        try await validity.require(lease)
    }

    func suspendNotificationsForDeactivation() async {
        guard await notificationState.beginDeactivation() else { return }
        async let settingsDrain: Void = settingsRepository.cancelAndAwaitAllOperations(
            accountID: user.id
        )
        await operationGate.invalidateCancelAndWait(for: lease)
        _ = await settingsDrain
        await settingsReminderStore.discardStagedDefault()
        await reminderScheduler.suspendNotifications(accountID: user.id)
        await reminderEditorActions.clearReminderRecoveries()
        await reminderDetailActions.clearReminderRecoveries()
    }

    @discardableResult
    func resumeNotificationsAfterRuntimeReady(allowNetwork: Bool) async throws -> Bool {
        guard await notificationState.markRuntimeReady() else {
            throw CancellationError()
        }
        return try await notificationLifecycle.resumeIfEnabled(allowNetwork: allowNetwork)
    }

    func invalidate() async {
        _ = await notificationState.beginDeactivation()
        async let focusDrain: Void = focusRepository.cancelAndAwaitPendingSync(accountID: user.id)
        async let settingsDrain: Void = settingsRepository.cancelAndAwaitAllOperations(accountID: user.id)
        await operationGate.invalidateCancelAndWait(for: lease)
        await settingsReminderStore.discardStagedDefault()
        await reminderEditorActions.clearReminderRecoveries()
        await reminderDetailActions.clearReminderRecoveries()
        _ = await (focusDrain, settingsDrain)
        await sharingScopeRegistry.invalidate(for: lease)
        await validity.invalidate(lease)
    }

    func synchronizeFocusPending() async throws {
        let validity = self.validity
        let lease = self.lease
        let operationGate = self.operationGate
        let focus = focusRepository
        let accountID = user.id
        let timezone = user.timezone
        try await withTaskCancellationHandler {
            try await operationGate.run(for: lease) {
                try await validity.require(lease)
                _ = try await focus.syncPending(accountID: accountID, timezone: timezone)
                try await validity.require(lease)
            }
        } onCancel: {
            Task { await focus.cancelAndAwaitPendingSync(accountID: accountID) }
        }
    }

    func reconcileReminders(reason: ReminderReconcileReason) async throws {
        _ = reason
        _ = try await resumeNotificationsAfterRuntimeReady(allowNetwork: false)
    }

    func synchronizeDevice(deviceName: String?) async throws {
        let validity = self.validity
        let lease = self.lease
        let operationGate = self.operationGate
        let registration = deviceRegistrationBackend
        let accountID = user.id
        try await operationGate.run(for: lease) {
            try await validity.require(lease)
            _ = try await registration.sync(accountID: accountID, deviceName: deviceName)
            try await validity.require(lease)
        }
    }

    func synchronizeFeatures(
        reason: ReminderReconcileReason,
        deviceName: String?
    ) async throws {
        let validity = self.validity
        let lease = self.lease
        let operationGate = self.operationGate
        let focus = focusRepository
        let notifications = notificationLifecycle
        let registration = deviceRegistrationBackend
        let accountID = user.id
        let timezone = user.timezone
        try await withTaskCancellationHandler {
            try await operationGate.run(for: lease) {
                try await AppRuntimeFeatureSyncPipeline.run(
                    checkpoint: { try await validity.require(lease) },
                    focus: {
                        _ = try await focus.syncPending(accountID: accountID, timezone: timezone)
                    },
                    reminders: {
                        guard reason != .launch else { return }
                        _ = try await notifications.resumeIfEnabled(allowNetwork: true)
                    },
                    device: {
                        _ = try await registration.sync(
                            accountID: accountID,
                            deviceName: deviceName
                        )
                    }
                )
            }
        } onCancel: {
            Task { await focus.cancelAndAwaitPendingSync(accountID: accountID) }
        }
    }

    func startDeviceTokenObservation(
        provider: any FCMRegistrationTokenProviding,
        deviceName: String?
    ) async {
        do {
            try await requireActive()
        } catch {
            return
        }
        await deviceTokenCoordinator.start(
            accountID: user.id,
            deviceName: deviceName,
            provider: provider
        )
    }

    func stopDeviceTokenObservation() async {
        await deviceTokenCoordinator.stop()
    }

    func privacyCleanupOperations() -> [AppTeardownOperation] {
        [
            AppTeardownOperation(stage: .deviceUnregister, requiredForPrivacy: false) {
                _ = try await self.deviceRegistrationBackend.unregister(accountID: self.user.id)
            },
            AppTeardownOperation(stage: .reminders, requiredForPrivacy: true) {
                try await self.reminderScheduler.cancelAll(accountID: self.user.id)
            },
            AppTeardownOperation(stage: .deviceRetry, requiredForPrivacy: true) {
                try await self.deviceRetryStore.clear(accountID: self.user.id)
            },
            AppTeardownOperation(stage: .featureCache, requiredForPrivacy: true) {
                try await self.featureCleaner.clear(accountID: self.user.id)
            },
            AppTeardownOperation(stage: .coreDatabase, requiredForPrivacy: true) {
                try self.database.eraseUserData()
            }
        ]
    }
}
