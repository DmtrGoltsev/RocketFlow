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
    let reminders: TaskReminderScheduler
    let deviceRegistration: any DeviceRegistrationServicing
    let deviceName: String?
    let unauthorizedRelay: AppUnauthorizedRelay

    func synchronize(trigger: CoreSyncTrigger) async throws {
        do {
            try await withTaskCancellationHandler {
                try await operationGate.run(for: lease) {
                    try await synchronizeOperation(trigger: trigger)
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
                    _ = try await reminders.reconcile(
                        accountID: lease.accountID,
                        timeZone: TimeZone(identifier: timezone)
                            ?? TimeZone(secondsFromGMT: 0)!,
                        reason: trigger == .foreground ? .foreground : .launch
                    )
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
        try await reporting { try await base.loadPlanner() }
    }

    func perform(_ action: PlannerMutationAction) async throws -> PlannerMutationResult {
        try await reporting { try await base.perform(action) }
    }

    func loadDetail(_ reference: DetailEntityReference) async throws -> DetailLoadResult {
        try await reporting { try await base.loadDetail(reference) }
    }

    func performDetailMutation(_ mutation: DetailMutation) async throws -> DetailMutationResult {
        try await reporting { try await base.performDetailMutation(mutation) }
    }

    func saveEditor(_ request: EditorSaveRequest) async throws -> EditorSaveResult {
        try await reporting { try await base.saveEditor(request) }
    }

    func createTag(_ payload: TagEditorPayload) async throws -> TagEditorItemDraft {
        try await reporting { try await base.createTag(payload) }
    }

    func setTaskFocus(taskID: UUID, focused: Bool) async throws {
        try await reporting { try await base.setTaskFocus(taskID: taskID, focused: focused) }
    }

    func move(
        _ reference: DetailEntityReference,
        toParentID: UUID?
    ) async throws -> DetailEntityReference {
        try await reporting { try await base.move(reference, toParentID: toParentID) }
    }

    func clone(
        _ reference: DetailEntityReference,
        toParentID: UUID?
    ) async throws -> DetailEntityReference {
        try await reporting { try await base.clone(reference, toParentID: toParentID) }
    }

    func invite(
        _ reference: DetailEntityReference,
        request: SharingInvitationRequest
    ) async throws -> ShareInvitationDTO {
        try await reporting { try await base.invite(reference, request: request) }
    }

    func rescheduleTask(localID: UUID, plannedAt: Date) async throws {
        try await reporting {
            try await base.rescheduleTask(localID: localID, plannedAt: plannedAt)
        }
    }

    func editorSeed(for route: DetailEditorRoute) async throws -> PlannerDetailsEditorSeed {
        try await reporting { try await base.editorSeed(for: route) }
    }

    func localID(kind: DetailEntityKind, serverID: UUID) async throws -> UUID {
        try await reporting { try await base.localID(kind: kind, serverID: serverID) }
    }

    func serverID(kind: DetailEntityKind, localID: UUID) async throws -> UUID {
        try await reporting { try await base.serverID(kind: kind, localID: localID) }
    }

    private func reporting<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
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
        try await reporting { try await base.createInvitation(resource: resource, id: id, request: request) }
    }

    func listInvitations() async throws -> [ShareInvitationDTO] {
        try await reporting { try await base.listInvitations() }
    }

    func revokeInvitation(id: UUID) async throws -> ShareInvitationActionResponseDTO {
        try await reporting { try await base.revokeInvitation(id: id) }
    }

    func createShareLink(
        resource: ShareableResourceKind,
        id: UUID,
        request: ShareLinkRequestDTO?
    ) async throws -> ShareLinkCreateResponseDTO {
        try await reporting { try await base.createShareLink(resource: resource, id: id, request: request) }
    }

    func listShareLinks(resource: ShareableResourceKind, id: UUID) async throws -> [ShareLinkDTO] {
        try await reporting { try await base.listShareLinks(resource: resource, id: id) }
    }

    func revokeShareLink(id: UUID) async throws -> ShareLinkActionResponseDTO {
        try await reporting { try await base.revokeShareLink(id: id) }
    }

    func resolveShareLink(token: String) async throws -> ShareLinkResolveResponseDTO {
        try await reporting { try await base.resolveShareLink(token: token) }
    }

    func acceptShareLink(token: String) async throws -> ShareLinkAcceptResponseDTO {
        try await reporting { try await base.acceptShareLink(token: token) }
    }

    private func reporting<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
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
        try await reporting { try await base.listEntityLinks(type: type, id: id) }
    }

    func createEntityLink(_ request: CreateEntityLinkRequestDTO) async throws -> ActionEntityLinkDTO {
        try await reporting { try await base.createEntityLink(request) }
    }

    func updateEntityLink(
        id: UUID,
        request: UpdateEntityLinkRequestDTO
    ) async throws -> ActionEntityLinkDTO {
        try await reporting { try await base.updateEntityLink(id: id, request: request) }
    }

    func deleteEntityLink(id: UUID) async throws {
        try await reporting { try await base.deleteEntityLink(id: id) }
    }

    private func reporting<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
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
        try await run(accountID: accountID) {
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
        try await run(accountID: accountID) {
            try await self.base.save(
                accountID: accountID,
                language: language,
                notificationsEnabled: notificationsEnabled
            )
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
        try await operationGate.run(for: lease) {
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
                let localScope = try await localScope(remoteScope, snapshot: snapshot)
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

    private func localScope(
        _ remoteScope: AppCollaboratorResourceScope,
        snapshot: PlanningSnapshot
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
    let settingsActions: AppRuntimeSettingsRepository
    let reminderStore: GRDBTaskReminderStore
    let reminderScheduler: TaskReminderScheduler
    let deviceRegistration: DeviceRegistrationService
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
        reminderStore: GRDBTaskReminderStore,
        reminderScheduler: TaskReminderScheduler,
        deviceRegistration: DeviceRegistrationService,
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
        plannerDetailsActions = AppUnauthorizedPlannerDetailsAdapter(
            base: plannerDetails,
            lease: lease,
            relay: unauthorizedRelay,
            operationGate: operationGate
        )
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
        settingsActions = AppRuntimeSettingsRepository(
            base: settingsRepository,
            lease: lease,
            relay: unauthorizedRelay,
            operationGate: operationGate
        )
        self.reminderStore = reminderStore
        self.reminderScheduler = reminderScheduler
        self.deviceRegistration = deviceRegistration
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

    func invalidate() async {
        async let operationDrain: Void = operationGate.invalidateCancelAndWait(for: lease)
        async let focusDrain: Void = focusRepository.cancelAndAwaitPendingSync(accountID: user.id)
        async let settingsDrain: Void = settingsRepository.cancelAndAwaitAllOperations(accountID: user.id)
        _ = await (operationDrain, focusDrain, settingsDrain)
        await sharingScopeRegistry.invalidate(for: lease)
        await validity.invalidate(lease)
    }

    func synchronizeFocusPending() async throws {
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
        let reminders = reminderScheduler
        let accountID = user.id
        let timezone = user.timezone
        try await operationGate.run(for: lease) {
            try await validity.require(lease)
            _ = try await reminders.reconcile(
                accountID: accountID,
                timeZone: TimeZone(identifier: timezone) ?? TimeZone(secondsFromGMT: 0)!,
                reason: reason
            )
            try await validity.require(lease)
        }
    }

    func synchronizeDevice(deviceName: String?) async throws {
        let registration = deviceRegistration
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
        let focus = focusRepository
        let reminders = reminderScheduler
        let registration = deviceRegistration
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
                        _ = try await reminders.reconcile(
                            accountID: accountID,
                            timeZone: TimeZone(identifier: timezone)
                                ?? TimeZone(secondsFromGMT: 0)!,
                            reason: reason
                        )
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
                _ = try await self.deviceRegistration.unregister(accountID: self.user.id)
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
