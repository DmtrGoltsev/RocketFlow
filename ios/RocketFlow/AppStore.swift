import Combine
import Foundation

@MainActor
final class AppSerialTaskChain {
    private var current: Task<Void, Never>?

    func replace(with operation: @escaping @MainActor () async -> Void) {
        let previous = current
        previous?.cancel()
        current = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    func replaceAndWait(with operation: @escaping @MainActor () async -> Void) async {
        replace(with: operation)
        await current?.value
    }

    func cancelAndWait() async {
        let task = current
        current = nil
        task?.cancel()
        await task?.value
    }
}

private enum AppFeatureSyncOutcome: Equatable {
    case completed
    case unauthorized
    case cancelled
    case failed
}

@MainActor
final class AppStore: ObservableObject, AuthSubmitting {
    enum State: Equatable {
        case launching
        case configurationError(String)
        case cleanupRequired(String)
        case signedOut
        case authenticated(UserDTO)
        case offline(UserDTO)
    }

    enum LifecycleState: Equatable {
        case inactive
        case foreground
        case background
    }

    @Published private(set) var state: State = .launching
    @Published private(set) var runtimeReady = false
    @Published private(set) var planningSnapshot: PlanningSnapshot?
    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published private(set) var remotePullWarnings: [RemotePullWarning] = []
    @Published private(set) var persistenceError: String?
    @Published private(set) var pushConfigurationDiagnostic: String?
    @Published private(set) var lifecycleState: LifecycleState = .inactive
    @Published var navigation = AppNavigationState()

    let plannerScrollState = PlannerScrollStateController()

    private let authSession: AuthSession
    private weak var dependencies: DependencyContainer?
    private let launchUser: UserDTO?
    private var planningRepository: (any PlanningRepository)?
    private var syncEngine: SyncEngine?
    private var planningRemote: APIPlanningRemote?
    private var reachabilityTask: Task<Void, Never>?
    private let lifecycleTasks = AppSerialTaskChain()
    private var featureSyncTask: Task<AppFeatureSyncOutcome, Never>?
    private var featureSyncID: UUID?
    private var didRestore = false
    private var didBindExternalEvents = false
    private var authenticationGeneration: UInt64 = 0
    private var pendingCleanupUserID: UUID?
    private var pendingDeepLinks: [(URL, NavigationOrigin)] = []
    private var pendingRemoteNotifications: [([String: String], Bool)] = []

    var isReachabilityMonitoringActive: Bool { reachabilityTask != nil }
    var activeUser: UserDTO? { stateUser }
    var activeRuntime: AppUserRuntime? { dependencies?.activeRuntime }
    var currentRuntimeLease: AppRuntimeLease? { dependencies?.activeRuntime?.lease }
    var pendingDeepLinkCount: Int { pendingDeepLinks.count }
    var shouldShowPersistenceRecovery: Bool {
        guard persistenceError != nil else { return false }
        switch state {
        case .authenticated, .offline, .launching:
            return true
        case .configurationError, .cleanupRequired, .signedOut:
            return false
        }
    }

    init(
        authSession: AuthSession,
        dependencies: DependencyContainer? = nil,
        launchUser: UserDTO? = nil
    ) {
        self.authSession = authSession
        self.dependencies = dependencies
        self.launchUser = launchUser
        planningRepository = dependencies?.planningRepository
        syncEngine = dependencies?.syncEngine
        planningRemote = dependencies?.planningRemote
    }

    func restoreIfNeeded() async {
        guard !didRestore else { return }
        didRestore = true
        await bindExternalEventsIfNeeded()
        await installUnauthorizedHandler()

        if let configurationError = dependencies?.startupConfigurationError {
            state = .configurationError(configurationError.localizedDescription)
            return
        }

        let generation = authenticationGeneration
        if let launchUser {
            state = .authenticated(launchUser)
            await prepareApplication(for: launchUser, sync: false, generation: generation)
            return
        }

        let restored = await authSession.restore()
        guard generation == authenticationGeneration else { return }
        switch restored {
        case .signedOut:
            state = .signedOut
        case let .authenticated(user):
            state = .authenticated(user)
            await prepareApplication(for: user, sync: true, generation: generation)
        case let .offline(user):
            state = .offline(user)
            await prepareApplication(for: user, sync: false, generation: generation)
        }
    }

    func login(email: String, password: String) async throws {
        let generation = await beginSessionTransition()
        let previousUser = stateUser
        await deactivateCurrentApplication(eraseUserData: false)
        try requireCurrent(generation)
        do {
            let user = try await authSession.login(email: email, password: password)
            try requireCurrent(generation)
            navigation.resetForAccountTransition()
            state = .authenticated(user)
            await prepareApplication(for: user, sync: true, generation: generation)
            try requireCurrent(generation)
        } catch {
            guard generation == authenticationGeneration else { throw CancellationError() }
            if let previousUser {
                state = .offline(previousUser)
                await prepareApplication(for: previousUser, sync: false, generation: generation)
            } else {
                state = .signedOut
            }
            throw error
        }
    }

    func register(
        email: String,
        password: String,
        displayName: String,
        timezone: String,
        language: AppLanguage
    ) async throws {
        let generation = await beginSessionTransition()
        let previousUser = stateUser
        await deactivateCurrentApplication(eraseUserData: false)
        try requireCurrent(generation)
        do {
            let user = try await authSession.register(
                email: email,
                password: password,
                displayName: displayName,
                timezone: timezone,
                language: language
            )
            try requireCurrent(generation)
            navigation.resetForAccountTransition()
            state = .authenticated(user)
            await prepareApplication(for: user, sync: true, generation: generation)
            try requireCurrent(generation)
        } catch {
            guard generation == authenticationGeneration else { throw CancellationError() }
            if let previousUser {
                state = .offline(previousUser)
                await prepareApplication(for: previousUser, sync: false, generation: generation)
            } else {
                state = .signedOut
            }
            throw error
        }
    }

    func logout() async {
        await terminateSession(expectedLease: currentRuntimeLease)
    }

    func handleUnauthorized(for lease: AppRuntimeLease? = nil) async {
        if let lease, currentRuntimeLease != lease { return }
        await terminateSession(expectedLease: lease ?? currentRuntimeLease)
    }

    func retryPrivacyCleanup() async {
        guard let userID = pendingCleanupUserID else { return }
        do {
            try await dependencies?.retryPrivacyCleanup(for: userID)
            pendingCleanupUserID = nil
            persistenceError = nil
            state = .signedOut
        } catch {
            let teardown = error as? AppRuntimeTeardownError
            persistenceError = nil
            state = .cleanupRequired(teardown?.localizedDescription ?? error.localizedDescription)
        }
    }

    func scheduleLifecycle(_ lifecycle: LifecycleState) {
        let lease = currentRuntimeLease
        lifecycleTasks.replace { [weak self] in
            guard let self else { return }
            await self.performLifecycle(lifecycle, expectedLease: lease)
        }
    }

    func handleLifecycle(_ lifecycle: LifecycleState) async {
        let lease = currentRuntimeLease
        await lifecycleTasks.replaceAndWait { [weak self] in
            await self?.performLifecycle(lifecycle, expectedLease: lease)
        }
    }

    func handleSyncStatus(_ status: SyncStatus, lease: AppRuntimeLease? = nil) async {
        if let lease, currentRuntimeLease != lease { return }
        syncStatus = status
        if status.phase == .unauthorized {
            await handleUnauthorized(for: lease ?? currentRuntimeLease)
        }
    }

    func syncOnForeground() async {
        let lease = currentRuntimeLease
        _ = await runSync({ engine in await engine.syncOnForeground() }, expectedLease: lease)
    }

    func syncWhenNetworkReturns() async {
        let lease = currentRuntimeLease
        guard await runSync(
            { engine in await engine.syncWhenNetworkReturns() },
            expectedLease: lease
        ) else { return }
        await synchronizeFeatureServices(reason: .foreground, expectedLease: lease)
    }

    func manualSync() async {
        let lease = currentRuntimeLease
        guard await runSync(
            { engine in await engine.syncManually() },
            expectedLease: lease
        ) else { return }
        await synchronizeFeatureServices(reason: .foreground, expectedLease: lease)
    }

    func retrySync() async {
        await manualSync()
    }

    func retryPersistence() async {
        guard let user = stateUser else { return }
        let shouldSync: Bool
        if case .authenticated = state { shouldSync = true } else { shouldSync = false }
        await prepareApplication(
            for: user,
            sync: shouldSync,
            generation: authenticationGeneration
        )
    }

    func resetCache() async {
        guard let planningRepository else { return }
        do {
            try await planningRepository.resetCachePreservingPending()
            planningSnapshot = try await planningRepository.snapshot()
            await manualSync()
        } catch {
            persistenceError = String(describing: error)
        }
    }

    func resolveConflict(_ id: UUID, with resolution: ConflictResolution) async {
        guard let repository = dependencies?.syncRepository else { return }
        do {
            try await repository.resolve(id, with: resolution, at: Date())
            planningSnapshot = try await planningRepository?.snapshot()
            syncStatus = await syncEngine?.status ?? .idle
            if case .resetCache = resolution { await manualSync() }
        } catch {
            persistenceError = String(describing: error)
        }
    }

    func selectTab(_ tab: AppTab, userInitiated: Bool = true) {
        if userInitiated, navigation.selectedTab != tab {
            plannerScrollState.reset(.explicitTopLevelTabSwitch)
        }
        navigation.select(tab)
    }

    func setPath(_ path: [AppRoute], for tab: AppTab) {
        navigation.setPath(path, for: tab)
    }

    func handlePlannerNavigation(_ intent: PlannerNavigationIntent) {
        switch intent {
        case let .openDetail(reference):
            navigation.open(detailReference(reference), origin: .home)
        case .openSettings:
            navigation.openSettings()
        case let .create(intent):
            let afterSave: DetailAfterSaveRoute
            switch intent.afterSuccessfulSave {
            case .stayInPlanner: afterSave = .stayOnCurrentDetail
            case .openCreatedItem: afterSave = .openCreated
            case let .openDetail(reference):
                afterSave = reference.kind == .goal
                    ? .goalDetail(reference.id)
                    : .stayOnCurrentDetail
            }
            navigation.present(
                .editor(
                    .create(
                        kind: DetailCreateKind(intent.kind),
                        parent: intent.parent.map(detailReference),
                        afterSave: afterSave
                    ),
                    origin: .home
                )
            )
        case let .edit(reference):
            navigation.present(.editor(.edit(detailReference(reference)), origin: .home))
        case let .move(reference):
            navigation.present(.command(.move, detailReference(reference), origin: .home))
        case let .clone(reference):
            navigation.present(.command(.clone, detailReference(reference), origin: .home))
        case let .share(reference):
            navigation.present(.sharing(detailReference(reference), origin: .home))
        }
    }

    func handleDetailNavigation(_ result: DetailNavigationResult) {
        if case let .present(.links(reference), origin) = result {
            navigation.dismissPresentation()
            navigation.openLinks(reference, origin: origin)
        } else {
            navigation.handle(result)
        }
    }

    func openTask(_ taskID: UUID, origin: DetailOriginTab) {
        navigation.open(
            DetailEntityReference(kind: .task, id: taskID),
            origin: origin
        )
    }

    func dismissPresentation() {
        navigation.dismissPresentation()
    }

    func receiveDeepLink(_ url: URL, origin: NavigationOrigin = .planner) async {
        guard let lease = currentRuntimeLease,
              runtimeReady,
              await dependencies?.taskDeepLinkRegistry.isReady(for: lease) == true else {
            enqueueDeepLink(url, origin: origin)
            return
        }
        await processDeepLink(url, origin: origin, lease: lease)
    }

    func handleRemoteNotification(
        data: [String: String],
        hasNotificationPayload: Bool
    ) async -> AppRemoteNotificationFetchResult {
        guard let runtime = dependencies?.activeRuntime,
              runtimeReady,
              currentRuntimeLease == runtime.lease else {
            enqueueRemoteNotification(data, hasNotificationPayload: hasNotificationPayload)
            return .noData
        }
        do {
            let result = try await runtime.remoteNotificationHandler.handle(
                data: data,
                hasNotificationPayload: hasNotificationPayload
            )
            guard currentRuntimeLease == runtime.lease else { return .noData }
            switch result {
            case .presented: return .newData
            case .duplicate, .rejected: return .noData
            }
        } catch let api as APIError where api.isUnauthorized {
            await handleUnauthorized(for: runtime.lease)
            return .failed
        } catch is CancellationError {
            return .noData
        } catch {
            persistenceError = String(describing: error)
            return .failed
        }
    }

    private func terminateSession(expectedLease: AppRuntimeLease?) async {
        if let expectedLease, currentRuntimeLease != expectedLease { return }
        let generation = await beginSessionTransition()
        let terminatingLease = expectedLease ?? currentRuntimeLease
        let terminatingUserID = terminatingLease?.accountID
            ?? dependencies?.activeUserID
            ?? stateUser?.id
        detachPlanningRuntime()
        runtimeReady = false
        plannerScrollState.reset(.logout)

        var teardownError: AppRuntimeTeardownError?
        if let terminatingUserID {
            do {
                try await dependencies?.deactivateApplication(
                    for: terminatingUserID,
                    expectedLease: terminatingLease,
                    eraseUserData: true
                )
            } catch let error as AppRuntimeTeardownError {
                teardownError = error
            } catch {
                teardownError = AppRuntimeTeardownError(
                    accountID: terminatingUserID,
                    failures: [
                        AppTeardownFailure(
                            stage: .coreDatabase,
                            requiredForPrivacy: true,
                            message: error.localizedDescription
                        )
                    ]
                )
            }
        } else {
            await dependencies?.deactivateApplication()
        }

        guard generation == authenticationGeneration else { return }
        await authSession.logout()
        guard generation == authenticationGeneration else { return }
        await dependencies?.deepLinkCoordinator.clear()
        planningSnapshot = nil
        syncStatus = .idle
        remotePullWarnings = []
        pendingRemoteNotifications = []
        pendingDeepLinks = []
        pushConfigurationDiagnostic = nil
        lifecycleState = .inactive
        navigation.resetForAccountTransition()

        if let teardownError, teardownError.hasRequiredPrivacyFailure,
           let terminatingUserID {
            pendingCleanupUserID = terminatingUserID
            persistenceError = nil
            state = .cleanupRequired(teardownError.localizedDescription)
        } else {
            pendingCleanupUserID = nil
            persistenceError = teardownError?.localizedDescription
            state = .signedOut
        }
    }

    private func deactivateCurrentApplication(eraseUserData: Bool) async {
        let lease = currentRuntimeLease
        let userID = lease?.accountID
            ?? dependencies?.activeUserID
            ?? stateUser?.id
        await cancelRuntimeTasksAndWait()
        detachPlanningRuntime()
        runtimeReady = false
        guard let userID else {
            await dependencies?.deactivateApplication()
            return
        }
        do {
            try await dependencies?.deactivateApplication(
                for: userID,
                expectedLease: lease,
                eraseUserData: eraseUserData
            )
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private func detachPlanningRuntime() {
        planningRepository = nil
        syncEngine = nil
        planningRemote = nil
    }

    private var stateUser: UserDTO? {
        switch state {
        case let .authenticated(user), let .offline(user): user
        case .launching, .configurationError, .cleanupRequired, .signedOut: nil
        }
    }

    private func prepareApplication(
        for user: UserDTO,
        sync shouldSync: Bool,
        generation: UInt64
    ) async {
        guard let dependencies, generation == authenticationGeneration else { return }
        runtimeReady = false
        do {
            let lease = try await dependencies.activateApplication(
                for: user,
                sessionGeneration: generation
            )
            guard isCurrent(generation: generation, lease: lease) else {
                try? await dependencies.deactivateApplication(
                    for: user.id,
                    expectedLease: lease,
                    eraseUserData: false
                )
                return
            }
            planningRepository = dependencies.planningRepository
            syncEngine = dependencies.syncEngine
            planningRemote = dependencies.planningRemote
            planningSnapshot = try await planningRepository?.snapshot()
            try requireCurrent(generation, lease: lease)
            persistenceError = nil
            plannerScrollState.activate(accountID: user.id)
            startReachabilityMonitoring(dependencies.networkMonitor, lease: lease)

            guard let runtime = dependencies.activeRuntime, runtime.lease == lease else {
                throw CancellationError()
            }
            await runtime.startDeviceTokenObservation(
                provider: dependencies.fcmTokenProvider,
                deviceName: AppDeviceInfo.name
            )
            try requireCurrent(generation, lease: lease)
            try? await runtime.reconcileReminders(reason: .launch)
            try requireCurrent(generation, lease: lease)

            if shouldSync {
                guard await runSync(
                    { engine in await engine.syncOnForeground() },
                    expectedLease: lease
                ) else { throw CancellationError() }
                try requireCurrent(generation, lease: lease)
                await synchronizeFeatureServices(reason: .launch, expectedLease: lease)
                try requireCurrent(generation, lease: lease)
            }

            pushConfigurationDiagnostic = await dependencies.pushConfigurationDiagnostic()
            runtimeReady = true
            await drainPendingExternalEvents(lease: lease)
            try requireCurrent(generation, lease: lease)

            if let resolution = await dependencies.deepLinkCoordinator
                .authenticationDidSucceed(language: user.language) {
                try requireCurrent(generation, lease: lease)
                await applyDeepLinkResolution(resolution, lease: lease)
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == authenticationGeneration else { return }
            await cancelRuntimeTasksAndWait()
            runtimeReady = false
            persistenceError = String(describing: error)
        }
    }

    func startReachabilityMonitoring(
        _ monitor: any NetworkMonitoring,
        lease: AppRuntimeLease? = nil
    ) {
        reachabilityTask?.cancel()
        let expectedLease = lease ?? currentRuntimeLease
        reachabilityTask = Task { [weak self] in
            var previous = await monitor.isConnected()
            let updates = await monitor.changes()
            for await connected in updates {
                guard !Task.isCancelled else { break }
                if let expectedLease,
                   self?.currentRuntimeLease != expectedLease {
                    break
                }
                if connected, !previous {
                    await self?.syncWhenNetworkReturns()
                }
                previous = connected
            }
        }
    }

    private func runSync(
        _ operation: @escaping @Sendable (SyncEngine) async -> SyncStatus,
        expectedLease: AppRuntimeLease?
    ) async -> Bool {
        guard !Task.isCancelled, let syncEngine else { return false }
        if let expectedLease, currentRuntimeLease != expectedLease { return false }
        let result = await withTaskCancellationHandler {
            await operation(syncEngine)
        } onCancel: {
            Task { await syncEngine.cancel() }
        }
        guard !Task.isCancelled, self.syncEngine === syncEngine else { return false }
        if let expectedLease, currentRuntimeLease != expectedLease { return false }
        syncStatus = result
        if result.phase == .unauthorized {
            requestUnauthorizedSignout(for: expectedLease ?? currentRuntimeLease)
            return false
        }
        do {
            guard !Task.isCancelled else { return false }
            planningSnapshot = try await planningRepository?.snapshot()
            guard !Task.isCancelled else { return false }
            if let expectedLease, currentRuntimeLease != expectedLease { return false }
            remotePullWarnings = await planningRemote?.latestPullWarnings() ?? []
            guard !Task.isCancelled else { return false }
            persistenceError = nil
        } catch {
            guard !(error is CancellationError), !Task.isCancelled else { return false }
            persistenceError = String(describing: error)
        }
        return true
    }

    private func synchronizeFeatureServices(
        reason: ReminderReconcileReason,
        expectedLease: AppRuntimeLease?
    ) async {
        guard let runtime = dependencies?.activeRuntime else { return }
        if let expectedLease, runtime.lease != expectedLease { return }
        let previous = featureSyncTask
        previous?.cancel()
        _ = await previous?.value
        let operationID = UUID()
        featureSyncID = operationID
        let task = Task<AppFeatureSyncOutcome, Never> {
            do {
                try await runtime.synchronizeFeatures(
                    reason: reason,
                    deviceName: AppDeviceInfo.name
                )
                return .completed
            } catch is CancellationError {
                return .cancelled
            } catch {
                return AppUnauthorizedErrorClassifier.isUnauthorized(error)
                    ? .unauthorized
                    : .failed
            }
        }
        featureSyncTask = task
        let outcome = await task.value
        if featureSyncID == operationID {
            featureSyncTask = nil
            featureSyncID = nil
        }
        if outcome == .unauthorized {
            requestUnauthorizedSignout(for: runtime.lease)
        }
    }

    private func bindExternalEventsIfNeeded() async {
        guard !didBindExternalEvents else { return }
        didBindExternalEvents = true
        await AppExternalEventHub.shared.bind(
            deepLinks: { [weak self] url in await self?.receiveDeepLink(url) },
            remoteData: { [weak self] data, hasNotificationPayload in
                guard let self else { return .noData }
                return await self.handleRemoteNotification(
                    data: data,
                    hasNotificationPayload: hasNotificationPayload
                )
            }
        )
    }

    private func installUnauthorizedHandler() async {
        await dependencies?.unauthorizedRelay.install { [weak self] lease in
            await self?.handleUnauthorized(for: lease)
        }
    }

    private func processDeepLink(
        _ url: URL,
        origin: NavigationOrigin,
        lease: AppRuntimeLease
    ) async {
        guard currentRuntimeLease == lease, runtimeReady, let dependencies else {
            enqueueDeepLink(url, origin: origin)
            return
        }
        let result = await dependencies.deepLinkCoordinator.receive(
            url,
            authenticated: true,
            origin: origin,
            language: stateUser?.language ?? .ru
        )
        guard currentRuntimeLease == lease else {
            enqueueDeepLink(url, origin: origin)
            return
        }
        if case let .resolved(resolution) = result {
            await applyDeepLinkResolution(resolution, lease: lease)
        }
    }

    private func drainPendingExternalEvents(lease: AppRuntimeLease) async {
        guard currentRuntimeLease == lease, runtimeReady else { return }
        let remoteNotifications = pendingRemoteNotifications
        pendingRemoteNotifications.removeAll()
        for (data, hasNotificationPayload) in remoteNotifications {
            guard currentRuntimeLease == lease else {
                enqueueRemoteNotification(data, hasNotificationPayload: hasNotificationPayload)
                return
            }
            _ = await handleRemoteNotification(
                data: data,
                hasNotificationPayload: hasNotificationPayload
            )
        }

        let deepLinks = pendingDeepLinks
        pendingDeepLinks.removeAll()
        for (url, origin) in deepLinks {
            guard currentRuntimeLease == lease else {
                enqueueDeepLink(url, origin: origin)
                return
            }
            await processDeepLink(url, origin: origin, lease: lease)
        }
    }

    private func applyDeepLinkResolution(
        _ resolution: DeepLinkResolution,
        lease: AppRuntimeLease
    ) async {
        guard currentRuntimeLease == lease else { return }
        let localID: UUID?
        if case let .task(taskID, _) = resolution.destination {
            localID = try? await dependencies?.taskDeepLinkRegistry.localID(for: taskID)
        } else {
            localID = nil
        }
        guard currentRuntimeLease == lease else { return }
        navigation.applyDeepLink(resolution, localTaskID: localID)
    }

    private func performLifecycle(
        _ lifecycle: LifecycleState,
        expectedLease: AppRuntimeLease?
    ) async {
        guard !Task.isCancelled else { return }
        if let expectedLease, currentRuntimeLease != expectedLease { return }
        lifecycleState = lifecycle
        switch lifecycle {
        case .foreground:
            guard await runSync(
                { engine in await engine.syncOnForeground() },
                expectedLease: expectedLease
            ) else { return }
            guard !Task.isCancelled else { return }
            await synchronizeFeatureServices(reason: .foreground, expectedLease: expectedLease)
            guard !Task.isCancelled else { return }
            try? await dependencies?.backgroundCoordinator.scheduleNext()
        case .background:
            try? await dependencies?.backgroundCoordinator.scheduleNext()
        case .inactive:
            break
        }
    }

    private func beginSessionTransition() async -> UInt64 {
        authenticationGeneration &+= 1
        await cancelRuntimeTasksAndWait()
        return authenticationGeneration
    }

    private func cancelRuntimeTasksAndWait() async {
        let reachability = reachabilityTask
        reachabilityTask = nil
        let feature = featureSyncTask
        featureSyncTask = nil
        featureSyncID = nil
        reachability?.cancel()
        feature?.cancel()
        await lifecycleTasks.cancelAndWait()
        await reachability?.value
        _ = await feature?.value
    }

    private func requestUnauthorizedSignout(for lease: AppRuntimeLease?) {
        Task { @MainActor [weak self] in
            await Task.yield()
            await self?.handleUnauthorized(for: lease)
        }
    }

    private func requireCurrent(
        _ generation: UInt64,
        lease: AppRuntimeLease? = nil
    ) throws {
        guard generation == authenticationGeneration else { throw CancellationError() }
        if let lease, currentRuntimeLease != lease { throw CancellationError() }
        try Task.checkCancellation()
    }

    private func isCurrent(generation: UInt64, lease: AppRuntimeLease) -> Bool {
        generation == authenticationGeneration && currentRuntimeLease == lease
    }

    private func enqueueDeepLink(_ url: URL, origin: NavigationOrigin) {
        pendingDeepLinks.append((url, origin))
        if pendingDeepLinks.count > 32 {
            pendingDeepLinks.removeFirst(pendingDeepLinks.count - 32)
        }
    }

    private func enqueueRemoteNotification(
        _ data: [String: String],
        hasNotificationPayload: Bool
    ) {
        pendingRemoteNotifications.append((data, hasNotificationPayload))
        if pendingRemoteNotifications.count > 64 {
            pendingRemoteNotifications.removeFirst(pendingRemoteNotifications.count - 64)
        }
    }

    private func detailReference(_ value: PlannerItemReference) -> DetailEntityReference {
        DetailEntityReference(kind: DetailEntityKind(value.kind), id: value.id)
    }
}

private extension DetailEntityKind {
    init(_ value: PlannerItemKind) {
        switch value {
        case .folder: self = .folder
        case .goal: self = .goal
        case .task: self = .task
        case .idea: self = .idea
        case .note: self = .note
        }
    }
}

private extension DetailCreateKind {
    init(_ value: PlannerCreateKind) {
        switch value {
        case .folder: self = .folder
        case .goal: self = .goal
        case .task: self = .task
        case .idea: self = .idea
        case .note: self = .note
        }
    }
}
