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
    let databaseQueue: DatabaseQueue?
    let databaseFactory: AppDatabaseFactory
    let apiClient: APIClient
    let sessionStore: any SessionStore
    let authService: AuthService
    let authSession: AuthSession
    let networkMonitor: any NetworkMonitoring
    private let databaseOpener: DatabaseOpener
    private let persistenceTransitionGate = PersistenceTransitionGate()

    private(set) var activeUserID: UUID?
    private(set) var appDatabase: AppDatabase?
    private(set) var planningRepository: LocalPlanningRepository?
    private(set) var pendingMutationStore: PendingMutationStore?
    private(set) var syncRepository: DatabaseSyncRepository?
    private(set) var planningRemote: APIPlanningRemote?
    private(set) var syncEngine: SyncEngine?

    init(
        apiBaseURL: URL? = nil,
        databasePath: String = ":memory:",
        transport: (any HTTPTransport)? = nil,
        sessionStore: (any SessionStore)? = nil,
        databaseFactory: AppDatabaseFactory? = nil,
        databaseOpener: DatabaseOpener? = nil,
        networkMonitor: (any NetworkMonitoring)? = nil
    ) {
        let configuredValue = Bundle.main.object(forInfoDictionaryKey: Self.apiBaseURLInfoKey) as? String
        let resolvedURL = apiBaseURL ?? Self.configuredAPIBaseURL(from: configuredValue)
        let resolvedStore = sessionStore ?? KeychainSessionStore()
        let client = APIClient(
            baseURL: resolvedURL,
            transport: transport ?? URLSessionTransport()
        )
        let service = AuthService(client: client)
        let resolvedFactory = databaseFactory ?? AppDatabaseFactory()

        self.apiBaseURL = resolvedURL
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

    func makeAppStore() -> AppStore {
        AppStore(authSession: authSession, dependencies: self)
    }

    nonisolated static func configuredAPIBaseURL(from value: String?) -> URL {
        guard
            let value,
            let url = URL(string: value),
            let scheme = url.scheme,
            ["http", "https"].contains(scheme.lowercased()),
            url.host != nil
        else {
            return URL(string: "http://45.10.110.42/rocket-api")!
        }

        return url
    }
}
