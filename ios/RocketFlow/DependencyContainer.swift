import Combine
import Foundation
import GRDB

private actor PersistenceTransitionGate {
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        if !occupied {
            occupied = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func leave() {
        if waiters.isEmpty {
            occupied = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

@MainActor
final class DependencyContainer: ObservableObject {
    typealias DatabaseOpener = @Sendable (UUID) throws -> AppDatabase

    static let apiBaseURLInfoKey = "RocketFlowAPIBaseURL"

    let apiBaseURL: URL
    let languageStore: AppLanguageStore
    let databaseQueue: DatabaseQueue?
    let databaseFactory: AppDatabaseFactory
    let apiClient: APIClient
    let sessionStore: any SessionStore
    let authService: AuthService
    let authSession: AuthSession
    let networkMonitor: any NetworkMonitoring
    let notificationCenter: any UserNotificationCenterServing
    let fcmTokenProvider: any FCMRegistrationTokenProviding
    let unauthorizedRelay: AppUnauthorizedRelay
    let taskDeepLinkRegistry: AppTaskDeepLinkAccessRegistry
    let deepLinkCoordinator: DeepLinkCoordinator
    let backgroundSyncRegistry: AppCoreSyncHookRegistry
    let backgroundCoordinator: BackgroundRefreshCoordinator
    let backgroundScheduler: any BackgroundRefreshScheduling
    let backgroundTaskRegistered: Bool
    let startupConfigurationError: AppStartupConfigurationError?
    private let databaseOpener: DatabaseOpener
    private let deviceRegistrationOverride: (any DeviceRegistrationServicing)?
    private let applicationTransitionGate = PersistenceTransitionGate()
    private let persistenceTransitionGate = PersistenceTransitionGate()

    private(set) var activeUserID: UUID?
    private(set) var appDatabase: AppDatabase?
    private(set) var planningRepository: LocalPlanningRepository?
    private(set) var pendingMutationStore: PendingMutationStore?
    private(set) var syncRepository: DatabaseSyncRepository?
    private(set) var planningRemote: APIPlanningRemote?
    private(set) var syncEngine: SyncEngine?
    private(set) var activeRuntime: AppUserRuntime?

    init(
        apiBaseURL: URL? = nil,
        languageStore: AppLanguageStore = .shared,
        databasePath: String = ":memory:",
        transport: (any HTTPTransport)? = nil,
        sessionStore: (any SessionStore)? = nil,
        databaseFactory: AppDatabaseFactory? = nil,
        databaseOpener: DatabaseOpener? = nil,
        networkMonitor: (any NetworkMonitoring)? = nil,
        notificationCenter: (any UserNotificationCenterServing)? = nil,
        fcmTokenProvider: (any FCMRegistrationTokenProviding)? = nil,
        deviceRegistrationOverride: (any DeviceRegistrationServicing)? = nil,
        backgroundScheduler: (any BackgroundRefreshScheduling)? = nil,
        registerBackgroundTasks: Bool = false
    ) {
        let configuredValue = Bundle.main.object(forInfoDictionaryKey: Self.apiBaseURLInfoKey) as? String
        let resolution = Self.resolveAPIBaseURL(
            explicit: apiBaseURL,
            configuredValue: configuredValue
        )
        let resolvedURL = resolution.url
        let resolvedStore = sessionStore ?? KeychainSessionStore()
        let client = APIClient(
            baseURL: resolvedURL,
            transport: transport ?? URLSessionTransport()
        )
        let service = AuthService(client: client)
        let resolvedFactory = databaseFactory ?? AppDatabaseFactory()
        let resolvedNotificationCenter = notificationCenter ?? SystemUserNotificationCenter()
        let resolvedTokenProvider = fcmTokenProvider ?? AppFirebaseMessagingRuntime.tokenProvider
        let unauthorizedRelay = AppUnauthorizedRelay()
        let taskRegistry = AppTaskDeepLinkAccessRegistry()
        let syncRegistry = AppCoreSyncHookRegistry()
        let resolvedBackgroundScheduler = backgroundScheduler ?? SystemBackgroundRefreshScheduler()
        let backgroundCoordinator = BackgroundRefreshCoordinator(
            scheduler: resolvedBackgroundScheduler,
            sync: syncRegistry
        )

        self.apiBaseURL = resolvedURL
        self.languageStore = languageStore
        databaseQueue = try? DatabaseQueue(path: databasePath)
        self.databaseFactory = resolvedFactory
        apiClient = client
        self.sessionStore = resolvedStore
        authService = service
        authSession = AuthSession(service: service, store: resolvedStore)
        self.databaseOpener = databaseOpener ?? { userID in
            try resolvedFactory.open(userID: userID)
        }
        self.networkMonitor = networkMonitor ?? ReachabilityNetworkMonitor()
        self.notificationCenter = resolvedNotificationCenter
        self.fcmTokenProvider = resolvedTokenProvider
        self.deviceRegistrationOverride = deviceRegistrationOverride
        self.unauthorizedRelay = unauthorizedRelay
        taskDeepLinkRegistry = taskRegistry
        deepLinkCoordinator = DeepLinkCoordinator(accessChecker: taskRegistry)
        backgroundSyncRegistry = syncRegistry
        self.backgroundCoordinator = backgroundCoordinator
        self.backgroundScheduler = resolvedBackgroundScheduler
        startupConfigurationError = resolution.error
        backgroundTaskRegistered = registerBackgroundTasks
            ? SystemBackgroundRefreshRegistrar().register(coordinator: backgroundCoordinator)
            : false
    }

    @discardableResult
    func activateApplication(
        for user: UserDTO,
        sessionGeneration: UInt64 = 0
    ) async throws -> AppRuntimeLease {
        if let startupConfigurationError { throw startupConfigurationError }
        await applicationTransitionGate.enter()
        do {
            if let current = activeRuntime,
               current.user.id == user.id,
               current.lease.sessionGeneration == sessionGeneration {
                await applicationTransitionGate.leave()
                return current.lease
            }
            if let current = activeRuntime {
                _ = await deactivateApplicationLocked(
                    runtime: current,
                    userID: current.user.id,
                    eraseUserData: false
                )
            }

            let lease = AppRuntimeLease(
                accountID: user.id,
                sessionGeneration: sessionGeneration
            )
            let validity = AppRuntimeValidity(lease: lease)
            let operationGate = AppRuntimeOperationGate(lease: lease)
            let sharingScopeRegistry = AppSharingScopeRegistry(lease: lease)
            try await activatePersistence(for: user.id)
            guard
                let database = appDatabase,
                let local = planningRepository,
                let engine = syncEngine
            else {
                throw AppRuntimeConstructionError.persistenceUnavailable
            }

            let persistence = GRDBPlannerDetailsPersistence(database: database)
            let taskMapper = AppTaskIDMapper(
                persistence: persistence,
                repository: local
            )
            let calendarMapping = PersistedCalendarTaskIDMappingAdapter(
                mappedLocalID: { serverID in
                    try await persistence.localID(for: .task, remoteID: serverID)
                },
                isKnownLocalID: { localID in
                    (try await local.snapshot()).tasks.contains { $0.id == localID }
                }
            )
            let focusMapping = PersistedFocusTaskIDMappingAdapter(
                mappedLocalID: { serverID in
                    try await persistence.localID(for: .task, remoteID: serverID)
                },
                isKnownLocalID: { localID in
                    (try await local.snapshot()).tasks.contains { $0.id == localID }
                }
            )
            let focus = FocusRepository(
                sender: authSession,
                cache: try GRDBFocusCache(database: database, accountID: user.id),
                queue: try GRDBFocusActionQueue(database: database, accountID: user.id),
                taskIDMapping: focusMapping
            )
            let actions = PlanningActionService(sender: authSession)
            let sharing = SharingService(sender: authSession)
            let ownerScopeSharing = AppOwnerScopeSharingAccess(
                service: sharing,
                scopeRegistry: sharingScopeRegistry,
                lease: lease
            )
            let plannerDetails = PlannerDetailsAdapter(
                repository: local,
                persistence: persistence,
                account: PlannerDetailsAccountContext(
                    accountID: user.id,
                    currentUserID: user.id,
                    timezone: user.timezone
                ),
                network: networkMonitor,
                refresher: SyncEnginePlannerDetailsRefresher(engine: engine),
                remote: PlanningActionPlannerDetailsRemote(service: actions),
                sharing: ownerScopeSharing,
                focus: focus
            )
            let calendar = CalendarRepository(
                sender: authSession,
                cache: try GRDBCalendarRangeCache(database: database, accountID: user.id),
                taskIDMapping: calendarMapping
            )
            let settingsCache = try GRDBSettingsCache(
                database: database,
                accountID: user.id
            )
            let settings = SettingsRepository(
                remote: AuthenticatedSettingsRemote(sender: authSession),
                cache: settingsCache
            )
            let reminderStore = try GRDBTaskReminderStore(
                database: database,
                accountID: user.id
            )
            let reminderScheduler = TaskReminderScheduler(
                center: notificationCenter,
                store: reminderStore,
                notificationBody: { [weak languageStore] in
                    await MainActor.run {
                        TaskReminderCopy(language: languageStore?.language ?? .en).openTaskBody
                    }
                }
            )
            let registrationStore = try GRDBAccountDeviceRegistrationStateStore(
                database: database,
                accountID: user.id
            )
            let installation = try GRDBInstallationIdentityStore(
                database: database,
                accountID: user.id
            )
            let retryStore = AppDeviceRegistrationRetryStore()
            let registration: any DeviceRegistrationServicing
            if let deviceRegistrationOverride {
                registration = deviceRegistrationOverride
            } else {
                registration = DeviceRegistrationService(
                    remote: AuthenticatedDeviceRegistrationRemote(sender: authSession),
                    tokenProvider: fcmTokenProvider,
                    installation: installation,
                    store: registrationStore,
                    retryStore: retryStore,
                    retryScheduler: AppDeviceRegistrationRetryScheduler(
                        background: backgroundCoordinator
                    ),
                    terminalCleaner: reminderScheduler
                )
            }
            let runtime = AppUserRuntime(
                lease: lease,
                validity: validity,
                operationGate: operationGate,
                sharingScopeRegistry: sharingScopeRegistry,
                user: user,
                database: database,
                planningRepository: local,
                syncEngine: engine,
                plannerDetails: plannerDetails,
                plannerDetailsPersistence: persistence,
                taskIDMapper: taskMapper,
                calendarRepository: calendar,
                focusRepository: focus,
                settingsRepository: settings,
                settingsCache: settingsCache,
                reminderStore: reminderStore,
                reminderScheduler: reminderScheduler,
                deviceRegistration: registration,
                deviceTokenCoordinator: DeviceRegistrationTokenCoordinator(service: registration),
                remoteNotificationHandler: RemoteNotificationHandler(
                    center: notificationCenter,
                    dedupe: try GRDBFocusNotificationEventStore(
                        database: database,
                        accountID: user.id
                    )
                ),
                planningActions: actions,
                sharingService: sharing,
                unauthorizedRelay: unauthorizedRelay,
                notificationCenter: notificationCenter,
                featureCleaner: GRDBFeaturePersistenceCleaner(database: database),
                deviceRetryStore: retryStore
            )
            activeRuntime = runtime
            await taskDeepLinkRegistry.activate(taskMapper, lease: lease)
            await backgroundSyncRegistry.activate(
                lease: lease,
                hook: AppUserCoreSyncHook(
                    lease: lease,
                    validity: validity,
                    operationGate: operationGate,
                    timezone: user.timezone,
                    planning: engine,
                    focus: focus,
                    notifications: runtime.notificationLifecycle,
                    deviceRegistration: registration,
                    deviceName: AppDeviceInfo.name,
                    unauthorizedRelay: unauthorizedRelay
                )
            )
            await applicationTransitionGate.leave()
            return lease
        } catch {
            if activeRuntime?.user.id == user.id {
                await activeRuntime?.invalidate()
                activeRuntime = nil
            }
            await taskDeepLinkRegistry.deactivate()
            await backgroundSyncRegistry.deactivate()
            await deactivatePersistence()
            await applicationTransitionGate.leave()
            throw error
        }
    }

    func deactivateApplication(
        for userID: UUID,
        expectedLease: AppRuntimeLease? = nil,
        eraseUserData: Bool
    ) async throws {
        await applicationTransitionGate.enter()
        if let expectedLease,
           let currentLease = activeRuntime?.lease,
           currentLease != expectedLease {
            await applicationTransitionGate.leave()
            return
        }
        if let expectedLease,
           activeRuntime == nil,
           activeUserID != expectedLease.accountID {
            await applicationTransitionGate.leave()
            return
        }

        let runtime = activeRuntime?.user.id == userID ? activeRuntime : nil
        let failures = await deactivateApplicationLocked(
            runtime: runtime,
            userID: userID,
            eraseUserData: eraseUserData
        )
        await applicationTransitionGate.leave()
        if !failures.isEmpty {
            throw AppRuntimeTeardownError(accountID: userID, failures: failures)
        }
    }

    func deactivateApplication() async {
        await applicationTransitionGate.enter()
        let userID = activeRuntime?.user.id ?? activeUserID
        _ = await deactivateApplicationLocked(
            runtime: activeRuntime,
            userID: userID,
            eraseUserData: false
        )
        await applicationTransitionGate.leave()
    }

    func retryPrivacyCleanup(for userID: UUID) async throws {
        await applicationTransitionGate.enter()
        guard activeRuntime?.user.id != userID, activeUserID != userID else {
            await applicationTransitionGate.leave()
            throw AppRuntimeConstructionError.cleanupWouldAffectActiveRuntime
        }
        let failures = await detachedPrivacyCleanup(for: userID)
        await applicationTransitionGate.leave()
        if !failures.isEmpty {
            throw AppRuntimeTeardownError(accountID: userID, failures: failures)
        }
    }

    private func deactivateApplicationLocked(
        runtime: AppUserRuntime?,
        userID: UUID?,
        eraseUserData: Bool
    ) async -> [AppTeardownFailure] {
        if let runtime {
            await runtime.suspendNotificationsForDeactivation()
            await runtime.invalidate()
            await runtime.stopDeviceTokenObservation()
            await runtime.syncEngine.cancel()
        } else if let userID, activeUserID == userID {
            await syncEngine?.cancel()
        }

        if activeRuntime?.lease == runtime?.lease {
            activeRuntime = nil
            await taskDeepLinkRegistry.deactivate(lease: runtime?.lease)
            await backgroundSyncRegistry.deactivate(lease: runtime?.lease)
        }
        await backgroundCoordinatorCancel()

        if let userID, activeUserID == userID {
            await deactivatePersistence()
        }
        guard eraseUserData, let userID else { return [] }
        if let runtime {
            return await AppTeardownExecutor.run(runtime.privacyCleanupOperations())
        }
        return await detachedPrivacyCleanup(for: userID)
    }

    private func detachedPrivacyCleanup(for userID: UUID) async -> [AppTeardownFailure] {
        var operations: [AppTeardownOperation] = [
            AppTeardownOperation(stage: .deviceRetry, requiredForPrivacy: true) {
                try await AppDeviceRegistrationRetryStore().clear(accountID: userID)
            }
        ]
        var failures: [AppTeardownFailure] = []
        let database: AppDatabase
        do {
            database = try databaseOpener(userID)
        } catch {
            failures.append(
                AppTeardownFailure(
                    stage: .coreDatabase,
                    requiredForPrivacy: true,
                    message: error.localizedDescription
                )
            )
            return failures + (await AppTeardownExecutor.run(operations))
        }

        do {
            let store = try GRDBTaskReminderStore(database: database, accountID: userID)
            let scheduler = TaskReminderScheduler(center: notificationCenter, store: store)
            operations.append(
                AppTeardownOperation(stage: .reminders, requiredForPrivacy: true) {
                    try await scheduler.cancelAll(accountID: userID)
                }
            )
        } catch {
            failures.append(
                AppTeardownFailure(
                    stage: .reminders,
                    requiredForPrivacy: true,
                    message: error.localizedDescription
                )
            )
        }
        let cleaner = GRDBFeaturePersistenceCleaner(database: database)
        operations.append(
            AppTeardownOperation(stage: .featureCache, requiredForPrivacy: true) {
                try await cleaner.clear(accountID: userID)
            }
        )
        operations.append(
            AppTeardownOperation(stage: .coreDatabase, requiredForPrivacy: true) {
                try database.eraseUserData()
            }
        )
        return failures + (await AppTeardownExecutor.run(operations))
    }

    func activatePersistence(for userID: UUID) async throws {
        if activeUserID == userID, syncEngine != nil { return }
        await persistenceTransitionGate.enter()
        do {
            if activeUserID == userID, syncEngine != nil {
                await persistenceTransitionGate.leave()
                return
            }
            let previousEngine = detachPersistence()
            await previousEngine?.cancel()

            let database = try databaseOpener(userID)
            let local = LocalPlanningRepository(database: database)
            let pending = PendingMutationStore(database: database)
            let sync = DatabaseSyncRepository(database: database)
            let remote = APIPlanningRemote(sender: authSession, idResolver: sync)
            let engine = SyncEngine(
                repository: sync,
                remote: remote,
                network: networkMonitor
            )
            activeUserID = userID
            appDatabase = database
            planningRepository = local
            pendingMutationStore = pending
            syncRepository = sync
            planningRemote = remote
            syncEngine = engine
            await persistenceTransitionGate.leave()
        } catch {
            await persistenceTransitionGate.leave()
            throw error
        }
    }

    func deactivatePersistence() async {
        await persistenceTransitionGate.enter()
        let previousEngine = detachPersistence()
        await previousEngine?.cancel()
        await persistenceTransitionGate.leave()
    }

    func deactivatePersistence(for userID: UUID, eraseUserData: Bool) async throws {
        let scopedDatabase = activeUserID == userID ? appDatabase : nil
        let scopedEngine = activeUserID == userID ? syncEngine : nil
        await persistenceTransitionGate.enter()
        let previousEngine = activeUserID == userID ? detachPersistence() : scopedEngine
        await previousEngine?.cancel()
        do {
            if eraseUserData {
                let database: AppDatabase
                if let scopedDatabase {
                    database = scopedDatabase
                } else {
                    database = try databaseOpener(userID)
                }
                try database.eraseUserData()
            }
            await persistenceTransitionGate.leave()
        } catch {
            await persistenceTransitionGate.leave()
            throw error
        }
    }

    @discardableResult
    private func detachPersistence() -> SyncEngine? {
        let previousEngine = syncEngine
        activeUserID = nil
        appDatabase = nil
        planningRepository = nil
        pendingMutationStore = nil
        syncRepository = nil
        planningRemote = nil
        syncEngine = nil
        return previousEngine
    }

    func makeAppStore(
        launchUser: UserDTO? = nil,
        restorationPersistence: any AppRestorationPersisting = AppRestorationUserDefaultsStore()
    ) -> AppStore {
        AppStore(
            authSession: authSession,
            dependencies: self,
            launchUser: launchUser,
            languageStore: languageStore,
            restorationPersistence: restorationPersistence
        )
    }

    func pushConfigurationDiagnostic() async -> String? {
        if let provider = fcmTokenProvider as? AppFCMRegistrationTokenProvider {
            if let diagnostic = await provider.diagnostic() { return diagnostic }
            if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") == nil {
                return AppFirebaseMessagingRuntime.missingConfigurationDiagnostic
            }
            return nil
        }
        return await fcmTokenProvider.isConfigured()
            ? nil
            : "Push notifications are unavailable on this build."
    }

    private func backgroundCoordinatorCancel() async {
        await backgroundScheduler.cancel(
            identifier: BackgroundRefreshCoordinator.defaultIdentifier
        )
    }

    nonisolated static func configuredAPIBaseURL(from value: String?) -> URL {
        validatedAPIBaseURL(value)
            ?? URL(string: "https://configuration.invalid/rocket-api")!
    }

    private nonisolated static func resolveAPIBaseURL(
        explicit: URL?,
        configuredValue: String?
    ) -> (url: URL, error: AppStartupConfigurationError?) {
        if let explicit {
            guard validatedAPIBaseURL(explicit.absoluteString) != nil else {
                return (
                    configuredAPIBaseURL(from: nil),
                    .invalidAPIBaseURL(explicit.absoluteString)
                )
            }
            return (explicit, nil)
        }
        guard let configuredValue,
              !configuredValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !configuredValue.contains("$(") else {
            return (configuredAPIBaseURL(from: nil), .missingAPIBaseURL)
        }
        guard let url = validatedAPIBaseURL(configuredValue) else {
            return (
                configuredAPIBaseURL(from: nil),
                .invalidAPIBaseURL(configuredValue)
            )
        }
        return (url, nil)
    }

    private nonisolated static func validatedAPIBaseURL(_ value: String?) -> URL? {
        guard
            let value,
            let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host != nil
        else {
            return nil
        }
        return url
    }
}

enum AppRuntimeConstructionError: Error, Equatable {
    case persistenceUnavailable
    case cleanupWouldAffectActiveRuntime
}

enum AppStartupConfigurationError: Error, Equatable, Sendable, LocalizedError {
    case missingAPIBaseURL
    case invalidAPIBaseURL(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIBaseURL:
            "RocketFlowAPIBaseURL is missing from the active build configuration."
        case let .invalidAPIBaseURL(value):
            "RocketFlowAPIBaseURL is invalid: \(value)"
        }
    }
}
