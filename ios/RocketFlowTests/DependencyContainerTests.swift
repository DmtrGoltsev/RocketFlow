import Foundation
import XCTest
@testable import RocketFlow

private struct SuccessfulLogoutTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> HTTPResult {
        HTTPResult(
            data: Data(),
            response: HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.test")!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private struct AuthRestoreTransport: HTTPTransport {
    let user: UserDTO

    func data(for request: URLRequest) async throws -> HTTPResult {
        HTTPResult(
            data: try WireJSON.encoder().encode(user),
            response: HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private actor ReloginDuringLogoutTransport: HTTPTransport {
    private let loginResponse: AuthResponseDTO
    private var logoutStarted = false
    private var logoutContinuation: CheckedContinuation<HTTPResult, Never>?

    init(loginResponse: AuthResponseDTO) {
        self.loginResponse = loginResponse
    }

    func data(for request: URLRequest) async throws -> HTTPResult {
        let path = request.url?.path ?? ""
        if path.hasSuffix("/auth/logout") {
            logoutStarted = true
            return await withCheckedContinuation { continuation in
                logoutContinuation = continuation
            }
        }
        if path.hasSuffix("/auth/login") {
            return response(for: request, statusCode: 200, body: try WireJSON.encoder().encode(loginResponse))
        }
        return response(for: request, statusCode: 200, body: Data("{\"items\":[]}".utf8))
    }

    func waitUntilLogoutStarts() async {
        while !logoutStarted { await Task.yield() }
    }

    func finishLogout() {
        let continuation = logoutContinuation
        logoutContinuation = nil
        continuation?.resume(
            returning: response(
                for: URLRequest(url: URL(string: "https://example.test/rocket-api/auth/logout")!),
                statusCode: 204,
                body: Data()
            )
        )
    }

    private func response(for request: URLRequest, statusCode: Int, body: Data) -> HTTPResult {
        HTTPResult(
            data: body,
            response: HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.test")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private actor AccountSwitchTransport: HTTPTransport {
    private let restoredUser: UserDTO
    private let loginResponse: AuthResponseDTO
    private var planningRequestStarted = false
    private var planningAuthorizationHeaders: [String] = []

    init(restoredUser: UserDTO, loginResponse: AuthResponseDTO) {
        self.restoredUser = restoredUser
        self.loginResponse = loginResponse
    }

    func data(for request: URLRequest) async throws -> HTTPResult {
        let path = request.url?.path ?? ""
        if path.hasSuffix("/me") {
            return try response(for: request, body: WireJSON.encoder().encode(restoredUser))
        }
        if path.hasSuffix("/auth/login") {
            return try response(for: request, body: WireJSON.encoder().encode(loginResponse))
        }
        if request.httpMethod == "POST", path.hasSuffix("/folders") {
            planningAuthorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            planningRequestStarted = true
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }
        return response(for: request, body: Data("{\"items\":[]}".utf8))
    }

    func waitUntilPlanningRequestStarts() async {
        while !planningRequestStarted { await Task.yield() }
    }

    func planningHeaders() -> [String] { planningAuthorizationHeaders }

    private func response(for request: URLRequest, body: Data) -> HTTPResult {
        HTTPResult(
            data: body,
            response: HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private enum PersistenceOpenFailure: Error, Equatable {
    case unavailable
}

@MainActor
final class DependencyContainerTests: XCTestCase {
    func testValidExplicitAPIBaseURLIsUsedWithoutStartupConfigurationError() {
        let expectedURL = URL(string: "https://example.test/rocket-api")!

        let container = DependencyContainer(apiBaseURL: expectedURL)

        XCTAssertEqual(container.apiBaseURL, expectedURL)
        XCTAssertNil(container.startupConfigurationError)
        XCTAssertNotNil(container.databaseQueue)
    }

    func testCurrentHTTPAPIBaseURLIsAcceptedOnlyWhenExplicitlyConfigured() {
        let expectedURL = URL(string: "http://45.10.110.42/rocket-api")!

        let container = DependencyContainer(apiBaseURL: expectedURL)

        XCTAssertEqual(container.apiBaseURL, expectedURL)
        XCTAssertNil(container.startupConfigurationError)
    }

    func testMissingOrInvalidConfiguredAPIBaseURLUsesNonRoutableSentinelWithoutProductionFallback() {
        let values: [String?] = [nil, "", "$(ROCKETFLOW_API_BASE_URL)", "not a URL"]
        let resolved = values.map { DependencyContainer.configuredAPIBaseURL(from: $0) }

        XCTAssertTrue(resolved.allSatisfy {
            $0.absoluteString == "https://configuration.invalid/rocket-api"
        })
        XCTAssertFalse(resolved.contains {
            $0.absoluteString == "http://45.10.110.42/rocket-api"
        })
    }

    func testInvalidExplicitAPIBaseURLReturnsStartupErrorAndBlocksActivation() async {
        let invalidValue = "ftp://example.test/rocket-api"
        let container = DependencyContainer(apiBaseURL: URL(string: invalidValue)!)

        XCTAssertEqual(container.apiBaseURL.absoluteString, "https://configuration.invalid/rocket-api")
        XCTAssertEqual(
            container.startupConfigurationError,
            .invalidAPIBaseURL(invalidValue)
        )

        do {
            _ = try await container.activateApplication(for: user(email: "config@example.test"))
            XCTFail("Expected invalid API configuration to block startup")
        } catch {
            XCTAssertEqual(
                error as? AppStartupConfigurationError,
                .invalidAPIBaseURL(invalidValue)
            )
        }
    }

    func testDatabaseSyncRepositoryPersistsPullBeforePushFlag() async throws {
        let database = try AppDatabase.inMemory()
        let local = LocalPlanningRepository(database: database)
        let store = PendingMutationStore(database: database)
        let repository = DatabaseSyncRepository(database: database)
        let folder = try await local.createFolder(FolderDraft(name: "Folder"))
        let ready = try await store.nextReady(at: Date())
        let mutation = try XCTUnwrap(ready)
        try await store.recordConflict(
            mutation,
            code: "version",
            serverVersion: nil,
            serverPayloadJSON: nil,
            serverDeleted: false,
            at: Date()
        )
        let conflicts = try await store.conflicts()
        let conflict = try XCTUnwrap(conflicts.first)
        try await repository.resolve(conflict.id, with: .resetCache, at: Date())

        let requiredBefore = try await repository.pullBeforePushRequired()
        XCTAssertTrue(requiredBefore)
        try await repository.didCompleteRequiredPull(RemotePlanningSnapshot(), at: Date())
        let requiredAfter = try await repository.pullBeforePushRequired()
        XCTAssertFalse(requiredAfter)
        XCTAssertEqual(folder.id, mutation.entityID)
    }

    func testReachabilityStreamEmitsInitialAndChangedValues() async {
        let concreteMonitor = FixedNetworkMonitor(connected: true)
        let monitor: any NetworkMonitoring = concreteMonitor
        let stream = await monitor.changes()
        var iterator = stream.makeAsyncIterator()
        let initial = await iterator.next()
        await concreteMonitor.setConnected(false)
        let changed = await iterator.next()
        await concreteMonitor.finish()
        let finished = await iterator.next()

        XCTAssertEqual(initial, true)
        XCTAssertEqual(changed, false)
        XCTAssertNil(finished)
    }

    func testManualReachabilityStreamUsesAsyncProtocolWitness() async {
        let concreteMonitor = ManualNetworkMonitor(connected: false)
        let monitor: any NetworkMonitoring = concreteMonitor
        let stream = await monitor.changes()
        var iterator = stream.makeAsyncIterator()

        let initial = await iterator.next()
        await concreteMonitor.setConnected(true)
        let changed = await iterator.next()
        await concreteMonitor.finish()
        let finished = await iterator.next()

        XCTAssertEqual(initial, false)
        XCTAssertEqual(changed, true)
        XCTAssertNil(finished)
    }

    func testUnauthorizedStatusClearsSessionDatabaseAndReachability() async throws {
        let user = UserDTO(
            id: UUID(), email: "user@example.com", displayName: "User",
            timezone: "Europe/Moscow", language: .ru,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let session = SessionSnapshot(
            user: user,
            tokens: TokensDTO(
                accessToken: "access", refreshToken: "refresh",
                expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
            )
        )
        let sessionStore = InMemorySessionStore(session: session)
        let database = try AppDatabase.inMemory()
        let monitor = FixedNetworkMonitor()
        let container = DependencyContainer(
            apiBaseURL: URL(string: "https://example.test/rocket-api")!,
            transport: SuccessfulLogoutTransport(),
            sessionStore: sessionStore,
            databaseOpener: { _ in database },
            networkMonitor: monitor
        )
        try await container.activatePersistence(for: user.id)
        _ = try await container.planningRepository?.createFolder(FolderDraft(name: "Private"))
        let store = container.makeAppStore()
        store.startReachabilityMonitoring(monitor)
        XCTAssertTrue(store.isReachabilityMonitoringActive)

        await store.handleSyncStatus(
            SyncStatus(
                phase: .unauthorized,
                pendingCount: 1,
                conflictCount: 0,
                lastErrorCode: "unauthorized",
                updatedAt: Date()
            )
        )

        let sessionAfter = try await sessionStore.load()
        let counts = try database.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM folders") ?? -1,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pending_mutations") ?? -1
            )
        }
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(sessionAfter)
        XCTAssertEqual(counts.0, 0)
        XCTAssertEqual(counts.1, 0)
        XCTAssertFalse(store.isReachabilityMonitoringActive)
        XCTAssertNil(container.activeUserID)
    }

    func testLifecycleForegroundTriggersSyncAndBackgroundExposesHook() async throws {
        let database = try AppDatabase.inMemory()
        let container = DependencyContainer(
            apiBaseURL: URL(string: "https://example.test/rocket-api")!,
            transport: SuccessfulLogoutTransport(),
            sessionStore: InMemorySessionStore(),
            databaseOpener: { _ in database },
            networkMonitor: FixedNetworkMonitor(connected: false)
        )
        try await container.activatePersistence(for: UUID())
        let store = container.makeAppStore()

        await store.handleLifecycle(.foreground)
        XCTAssertEqual(store.lifecycleState, .foreground)
        XCTAssertEqual(store.syncStatus.phase, .waitingForNetwork)
        await store.handleLifecycle(.background)
        XCTAssertEqual(store.lifecycleState, .background)
    }

    func testPersistenceActivationFailureLeavesContainerInactive() async {
        let container = DependencyContainer(
            apiBaseURL: URL(string: "https://example.test/rocket-api")!,
            databaseOpener: { _ in throw PersistenceOpenFailure.unavailable }
        )

        do {
            try await container.activatePersistence(for: UUID())
            XCTFail("Expected persistence activation failure")
        } catch {
            XCTAssertEqual(error as? PersistenceOpenFailure, .unavailable)
        }
        XCTAssertNil(container.activeUserID)
        XCTAssertNil(container.appDatabase)
        XCTAssertNil(container.syncEngine)
    }

    func testReloginDuringUnauthorizedCleanupPreservesNewSessionAndDatabase() async throws {
        let oldUser = user(email: "old@example.com")
        let newUser = user(email: "new@example.com")
        let oldSession = session(user: oldUser, accessToken: "old-access")
        let newTokens = tokens(accessToken: "new-access")
        let sessionStore = InMemorySessionStore(session: oldSession)
        let transport = ReloginDuringLogoutTransport(
            loginResponse: AuthResponseDTO(user: newUser, tokens: newTokens)
        )
        let oldDatabase = try AppDatabase.inMemory()
        let newDatabase = try AppDatabase.inMemory()
        let databases = [oldUser.id: oldDatabase, newUser.id: newDatabase]
        let container = DependencyContainer(
            apiBaseURL: URL(string: "https://example.test/rocket-api")!,
            transport: transport,
            sessionStore: sessionStore,
            databaseOpener: { userID in
                guard let database = databases[userID] else { throw PersistenceOpenFailure.unavailable }
                return database
            },
            networkMonitor: FixedNetworkMonitor(connected: false)
        )
        try await container.activatePersistence(for: oldUser.id)
        _ = try await container.planningRepository?.createFolder(FolderDraft(name: "Old private"))
        let store = container.makeAppStore()

        let cleanup = Task {
            await store.handleSyncStatus(
                SyncStatus(
                    phase: .unauthorized,
                    pendingCount: 1,
                    conflictCount: 0,
                    lastErrorCode: "unauthorized",
                    updatedAt: Date()
                )
            )
        }
        await transport.waitUntilLogoutStarts()
        try await store.login(email: newUser.email, password: "password")
        _ = try await container.planningRepository?.createFolder(FolderDraft(name: "New private"))
        await transport.finishLogout()
        await cleanup.value

        let persisted = try await sessionStore.load()
        let oldCount = try oldDatabase.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM folders") ?? -1
        }
        let newCount = try newDatabase.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM folders") ?? -1
        }
        XCTAssertEqual(persisted?.user.id, newUser.id)
        XCTAssertEqual(persisted?.tokens.accessToken, "new-access")
        XCTAssertEqual(store.state, .authenticated(newUser))
        XCTAssertEqual(container.activeUserID, newUser.id)
        XCTAssertTrue(container.appDatabase === newDatabase)
        XCTAssertEqual(oldCount, 0)
        XCTAssertEqual(newCount, 1)
    }

    func testAccountSwitchCancelsOldFlightBeforeNewDatabaseActivation() async throws {
        let oldUser = user(email: "old@example.com")
        let newUser = user(email: "new@example.com")
        let sessionStore = InMemorySessionStore(session: session(user: oldUser, accessToken: "old-access"))
        let transport = AccountSwitchTransport(
            restoredUser: oldUser,
            loginResponse: AuthResponseDTO(user: newUser, tokens: tokens(accessToken: "new-access"))
        )
        let oldDatabase = try AppDatabase.inMemory()
        let newDatabase = try AppDatabase.inMemory()
        let databases = [oldUser.id: oldDatabase, newUser.id: newDatabase]
        let container = DependencyContainer(
            apiBaseURL: URL(string: "https://example.test/rocket-api")!,
            transport: transport,
            sessionStore: sessionStore,
            databaseOpener: { userID in
                guard let database = databases[userID] else { throw PersistenceOpenFailure.unavailable }
                return database
            },
            networkMonitor: FixedNetworkMonitor(connected: true)
        )
        let restoration = await container.authSession.restore()
        XCTAssertEqual(restoration, .authenticated(oldUser))
        try await container.activatePersistence(for: oldUser.id)
        _ = try await container.planningRepository?.createFolder(FolderDraft(name: "First"))
        _ = try await container.planningRepository?.createFolder(FolderDraft(name: "Second"))
        let oldEngine = try XCTUnwrap(container.syncEngine)
        let oldSync = Task { await oldEngine.syncManually() }
        await transport.waitUntilPlanningRequestStarts()

        _ = try await container.authSession.login(email: newUser.email, password: "password")
        try await container.activatePersistence(for: newUser.id)
        let oldStatus = await oldSync.value

        let headers = await transport.planningHeaders()
        let pending = try await PendingMutationStore(database: oldDatabase).all()
        XCTAssertEqual(oldStatus.phase, .cancelled)
        XCTAssertEqual(headers, ["Bearer old-access"])
        XCTAssertEqual(pending.count, 2)
        XCTAssertTrue(pending.allSatisfy { $0.state == .queued })
        XCTAssertEqual(container.activeUserID, newUser.id)
        XCTAssertTrue(container.appDatabase === newDatabase)
    }

    func testAppStoreExposesRecoverablePersistenceFailureAfterAuthRestore() async {
        let user = UserDTO(
            id: UUID(), email: "user@example.com", displayName: "User",
            timezone: "Europe/Moscow", language: .ru,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let sessionStore = InMemorySessionStore(
            session: SessionSnapshot(
                user: user,
                tokens: TokensDTO(
                    accessToken: "access", refreshToken: "refresh",
                    expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
                )
            )
        )
        let container = DependencyContainer(
            apiBaseURL: URL(string: "https://example.test/rocket-api")!,
            transport: AuthRestoreTransport(user: user),
            sessionStore: sessionStore,
            databaseOpener: { _ in throw PersistenceOpenFailure.unavailable }
        )
        let store = container.makeAppStore()

        await store.restoreIfNeeded()

        XCTAssertEqual(store.state, .authenticated(user))
        XCTAssertNotNil(store.persistenceError)
        XCTAssertNil(container.appDatabase)
    }

    private func user(email: String) -> UserDTO {
        UserDTO(
            id: UUID(),
            email: email,
            displayName: email,
            timezone: "Europe/Moscow",
            language: .ru,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func tokens(accessToken: String) -> TokensDTO {
        TokensDTO(
            accessToken: accessToken,
            refreshToken: "refresh-\(accessToken)",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
        )
    }

    private func session(user: UserDTO, accessToken: String) -> SessionSnapshot {
        SessionSnapshot(user: user, tokens: tokens(accessToken: accessToken))
    }
}
