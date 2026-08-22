import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject, AuthSubmitting {
    enum State: Equatable {
        case launching
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
    @Published private(set) var planningSnapshot: PlanningSnapshot?
    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published private(set) var remotePullWarnings: [RemotePullWarning] = []
    @Published private(set) var persistenceError: String?
    @Published private(set) var lifecycleState: LifecycleState = .inactive
    private let authSession: AuthSession
    private weak var dependencies: DependencyContainer?
    private var planningRepository: (any PlanningRepository)?
    private var syncEngine: SyncEngine?
    private var planningRemote: APIPlanningRemote?
    private var reachabilityTask: Task<Void, Never>?
    private var didRestore = false
    private var authenticationGeneration = 0
    var isReachabilityMonitoringActive: Bool { reachabilityTask != nil }

    init(authSession: AuthSession, dependencies: DependencyContainer? = nil) {
        self.authSession = authSession
        self.dependencies = dependencies
    }

    func restoreIfNeeded() async {
        guard !didRestore else { return }
        didRestore = true
        switch await authSession.restore() {
        case .signedOut:
            state = .signedOut
        case let .authenticated(user):
            state = .authenticated(user)
            await preparePersistence(for: user.id, sync: true)
        case let .offline(user):
            state = .offline(user)
            await preparePersistence(for: user.id, sync: false)
        }
    }

    func login(email: String, password: String) async throws {
        authenticationGeneration &+= 1
        let previousUserID = dependencies?.activeUserID
        if let previousUserID {
            detachPlanningRuntime()
            try? await dependencies?.deactivatePersistence(
                for: previousUserID,
                eraseUserData: false
            )
        }
        do {
            let user = try await authSession.login(email: email, password: password)
            state = .authenticated(user)
            await preparePersistence(for: user.id, sync: true)
        } catch {
            if let previousUserID {
                await preparePersistence(for: previousUserID, sync: false)
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
        authenticationGeneration &+= 1
        let previousUserID = dependencies?.activeUserID
        if let previousUserID {
            detachPlanningRuntime()
            try? await dependencies?.deactivatePersistence(
                for: previousUserID,
                eraseUserData: false
            )
        }
        do {
            let user = try await authSession.register(
                email: email,
                password: password,
                displayName: displayName,
                timezone: timezone,
                language: language
            )
            state = .authenticated(user)
            await preparePersistence(for: user.id, sync: true)
        } catch {
            if let previousUserID {
                await preparePersistence(for: previousUserID, sync: false)
            }
            throw error
        }
    }

    func logout() async {
        await terminateSession()
    }

    func handleLifecycle(_ lifecycle: LifecycleState) async {
        lifecycleState = lifecycle
        switch lifecycle {
        case .foreground:
            await syncOnForeground()
        case .background:
            prepareForBackgroundSync()
        case .inactive:
            break
        }
    }

    func handleSyncStatus(_ status: SyncStatus) async {
        syncStatus = status
        if status.phase == .unauthorized {
            await terminateSession()
        }
    }

    private func terminateSession() async {
        let terminatingGeneration = authenticationGeneration
        let terminatingUserID = dependencies?.activeUserID ?? stateUserID
        reachabilityTask?.cancel()
        reachabilityTask = nil
        detachPlanningRuntime()
        var clearError: String?
        do {
            if let terminatingUserID {
                try await dependencies?.deactivatePersistence(
                    for: terminatingUserID,
                    eraseUserData: true
                )
            } else {
                await dependencies?.deactivatePersistence()
            }
        } catch {
            clearError = String(describing: error)
        }

        guard authenticationGeneration == terminatingGeneration else { return }
        await authSession.logout()
        guard authenticationGeneration == terminatingGeneration else { return }
        planningSnapshot = nil
        syncStatus = .idle
        remotePullWarnings = []
        persistenceError = clearError
        lifecycleState = .inactive
        state = .signedOut
    }

    private func detachPlanningRuntime() {
        planningRepository = nil
        syncEngine = nil
        planningRemote = nil
    }

    private var stateUserID: UUID? {
        switch state {
        case let .authenticated(user), let .offline(user): user.id
        case .launching, .signedOut: nil
        }
    }

    private func prepareForBackgroundSync() {
        // BGTask scheduling will call the existing serialized syncInBackground entry point later.
    }

    func syncOnForeground() async {
        await runSync { engine in await engine.syncOnForeground() }
    }

    func syncWhenNetworkReturns() async {
        await runSync { engine in await engine.syncWhenNetworkReturns() }
    }

    func manualSync() async {
        await runSync { engine in await engine.syncManually() }
    }

    func retrySync() async {
        await manualSync()
    }

    func retryPersistence() async {
        switch state {
        case let .authenticated(user):
            await preparePersistence(for: user.id, sync: true)
        case let .offline(user):
            await preparePersistence(for: user.id, sync: false)
        case .launching, .signedOut:
            break
        }
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
            if case .resetCache = resolution {
                await manualSync()
            }
        } catch {
            persistenceError = String(describing: error)
        }
    }

    private func preparePersistence(for userID: UUID, sync shouldSync: Bool) async {
        guard let dependencies else { return }
        do {
            try await dependencies.activatePersistence(for: userID)
            planningRepository = dependencies.planningRepository
            syncEngine = dependencies.syncEngine
            planningRemote = dependencies.planningRemote
            planningSnapshot = try await planningRepository?.snapshot()
            persistenceError = nil
            startReachabilityMonitoring(dependencies.networkMonitor)
            if shouldSync {
                await syncOnForeground()
            }
        } catch {
            reachabilityTask?.cancel()
            reachabilityTask = nil
            persistenceError = String(describing: error)
        }
    }

    func startReachabilityMonitoring(_ monitor: any NetworkMonitoring) {
        reachabilityTask?.cancel()
        reachabilityTask = Task { [weak self] in
            var previous = await monitor.isConnected()
            let updates = await monitor.changes()
            for await connected in updates {
                guard !Task.isCancelled else { break }
                if connected, !previous {
                    await self?.syncWhenNetworkReturns()
                }
                previous = connected
            }
        }
    }

    private func runSync(_ operation: (SyncEngine) async -> SyncStatus) async {
        guard let syncEngine else { return }
        let result = await operation(syncEngine)
        guard self.syncEngine === syncEngine else { return }
        await handleSyncStatus(result)
        guard result.phase != .unauthorized else { return }
        do {
            planningSnapshot = try await planningRepository?.snapshot()
            remotePullWarnings = await planningRemote?.latestPullWarnings() ?? []
            persistenceError = nil
        } catch {
            persistenceError = String(describing: error)
        }
    }
}
