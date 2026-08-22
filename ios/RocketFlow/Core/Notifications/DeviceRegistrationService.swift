import Foundation

protocol NotificationRequestSending: Sendable {
    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response
}

extension AuthSession: NotificationRequestSending {}

protocol DeviceRegistrationRemoteServing: Sendable {
    func register(_ request: RegisterDeviceRequestDTO) async throws -> DeviceRegistrationDTO
    func delete(registrationID: UUID) async throws
}

struct AuthenticatedDeviceRegistrationRemote: DeviceRegistrationRemoteServing {
    private let sender: any NotificationRequestSending

    init(sender: any NotificationRequestSending) {
        self.sender = sender
    }

    func register(_ request: RegisterDeviceRequestDTO) async throws -> DeviceRegistrationDTO {
        try await sender.send(
            Endpoint(method: .post, path: ["devices"], body: request)
        )
    }

    func delete(registrationID: UUID) async throws {
        let _: EmptyResponse = try await sender.send(
            Endpoint(
                method: .delete,
                path: ["devices", registrationID.uuidString.lowercased()]
            )
        )
    }
}

protocol FCMRegistrationTokenProviding: Sendable {
    func isConfigured() async -> Bool
    func currentToken() async throws -> String?
    func tokenChanges() async -> AsyncStream<String>
}

extension FCMRegistrationTokenProviding {
    func isConfigured() async -> Bool { true }
}

actor ManualFCMRegistrationTokenProvider: FCMRegistrationTokenProviding {
    private var token: String?
    private let configured: Bool
    private var continuations: [UUID: AsyncStream<String>.Continuation] = [:]

    init(token: String? = nil, configured: Bool = true) {
        self.token = token
        self.configured = configured
    }

    func isConfigured() -> Bool { configured }
    func currentToken() -> String? { token }

    func tokenChanges() -> AsyncStream<String> {
        let id = UUID()
        let stream = AsyncStream<String>.makeStream()
        continuations[id] = stream.continuation
        stream.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream.stream
    }

    func update(_ value: String) {
        token = value
        continuations.values.forEach { $0.yield(value) }
    }

    func finish() {
        continuations.values.forEach { $0.finish() }
        continuations.removeAll()
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

protocol InstallationIdentityProviding: Sendable {
    func installationID() async throws -> String
}

actor UserDefaultsInstallationIdentity: InstallationIdentityProviding {
    private let suiteName: String?
    private let key: String

    init(
        suiteName: String? = nil,
        key: String = "rocketflow.installation-id.v1"
    ) {
        self.suiteName = suiteName
        self.key = key
    }

    func installationID() -> String {
        let defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        if let stored = defaults.string(forKey: key), !stored.isEmpty { return stored }
        let created = UUID().uuidString.lowercased()
        defaults.set(created, forKey: key)
        return created
    }
}

struct DeviceRegistrationSnapshot: Codable, Equatable, Sendable {
    let accountID: UUID
    let fcmToken: String
    let installationID: String
    let deviceName: String?
    let registration: DeviceRegistrationDTO
}

protocol DeviceRegistrationStateStoring: Sendable {
    func snapshot() async throws -> DeviceRegistrationSnapshot?
    func save(_ snapshot: DeviceRegistrationSnapshot) async throws
    func clear() async throws
}

struct PendingDeviceRegistrationRetry: Codable, Equatable, Sendable {
    let accountID: UUID
    let fcmToken: String
    let installationID: String
    let deviceName: String?
    let obsoleteRegistrationID: UUID?
    let requestedAt: Date
}

protocol DeviceRegistrationRetryStoring: Sendable {
    func pending(accountID: UUID) async throws -> PendingDeviceRegistrationRetry?
    func save(_ pending: PendingDeviceRegistrationRetry) async throws
    func clear(accountID: UUID) async throws
}

actor InMemoryDeviceRegistrationRetryStore: DeviceRegistrationRetryStoring {
    private var values: [UUID: PendingDeviceRegistrationRetry] = [:]

    func pending(accountID: UUID) -> PendingDeviceRegistrationRetry? { values[accountID] }
    func save(_ pending: PendingDeviceRegistrationRetry) { values[pending.accountID] = pending }
    func clear(accountID: UUID) { values.removeValue(forKey: accountID) }
}

protocol DeviceRegistrationRetryScheduling: Sendable {
    func scheduleDeviceRegistrationRetry(accountID: UUID) async
}

struct NoopDeviceRegistrationRetryScheduler: DeviceRegistrationRetryScheduling {
    func scheduleDeviceRegistrationRetry(accountID: UUID) async {}
}

actor InMemoryDeviceRegistrationStateStore: DeviceRegistrationStateStoring {
    private var value: DeviceRegistrationSnapshot?

    init(value: DeviceRegistrationSnapshot? = nil) { self.value = value }
    func snapshot() -> DeviceRegistrationSnapshot? { value }
    func save(_ snapshot: DeviceRegistrationSnapshot) { value = snapshot }
    func clear() { value = nil }
}

enum DeviceRegistrationSyncResult: Equatable, Sendable {
    case tokenUnavailable
    case unchanged(DeviceRegistrationDTO)
    case registered(DeviceRegistrationDTO)
    case unregistered
}

enum DeviceRegistrationDisplayState: Equatable, Sendable {
    case unavailable
    case unregistered
    case registered(DeviceRegistrationDTO)
    case syncing
    case failed(String)
}

protocol DeviceRegistrationServicing: Sendable {
    func state(accountID: UUID) async -> DeviceRegistrationDisplayState
    func sync(accountID: UUID, deviceName: String?) async throws -> DeviceRegistrationSyncResult
    func unregister(accountID: UUID) async throws -> DeviceRegistrationSyncResult
}

actor DeviceRegistrationService: DeviceRegistrationServicing {
    private struct SyncFlight {
        let id: UUID
        let task: Task<DeviceRegistrationSyncResult, Error>
    }

    private let remote: any DeviceRegistrationRemoteServing
    private let tokenProvider: any FCMRegistrationTokenProviding
    private let installation: any InstallationIdentityProviding
    private let store: any DeviceRegistrationStateStoring
    private let retryStore: any DeviceRegistrationRetryStoring
    private let retryScheduler: any DeviceRegistrationRetryScheduling
    private let terminalCleaner: any AccountNotificationClearing
    private let now: @Sendable () -> Date
    private var syncFlights: [UUID: SyncFlight] = [:]

    init(
        remote: any DeviceRegistrationRemoteServing,
        tokenProvider: any FCMRegistrationTokenProviding,
        installation: any InstallationIdentityProviding,
        store: any DeviceRegistrationStateStoring,
        retryStore: any DeviceRegistrationRetryStoring,
        retryScheduler: any DeviceRegistrationRetryScheduling = NoopDeviceRegistrationRetryScheduler(),
        terminalCleaner: any AccountNotificationClearing = NoopAccountNotificationCleaner(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.remote = remote
        self.tokenProvider = tokenProvider
        self.installation = installation
        self.store = store
        self.retryStore = retryStore
        self.retryScheduler = retryScheduler
        self.terminalCleaner = terminalCleaner
        self.now = now
    }

    func state(accountID: UUID) async -> DeviceRegistrationDisplayState {
        guard await tokenProvider.isConfigured() else { return .unavailable }
        if syncFlights[accountID] != nil { return .syncing }
        guard let snapshot = try? await store.snapshot(), snapshot.accountID == accountID else {
            return .unregistered
        }
        return snapshot.registration.active ? .registered(snapshot.registration) : .unregistered
    }

    func sync(accountID: UUID, deviceName: String?) async throws -> DeviceRegistrationSyncResult {
        if let existing = syncFlights[accountID] {
            return try await existing.task.value
        }
        let id = UUID()
        let task = Task {
            try await self.performSync(accountID: accountID, deviceName: deviceName)
        }
        syncFlights[accountID] = SyncFlight(id: id, task: task)
        do {
            let result = try await task.value
            removeFlight(id: id, accountID: accountID)
            return result
        } catch {
            removeFlight(id: id, accountID: accountID)
            throw error
        }
    }

    private func performSync(accountID: UUID, deviceName: String?) async throws -> DeviceRegistrationSyncResult {
        try Task.checkCancellation()

        guard await tokenProvider.isConfigured() else { return .tokenUnavailable }
        let retry = try await retryStore.pending(accountID: accountID)
        let providedToken = try await tokenProvider.currentToken()
        let currentToken = providedToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        guard let rawToken = currentToken ?? retry?.fcmToken else {
            return .tokenUnavailable
        }
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return .tokenUnavailable }
        let usingPersistedRetry = currentToken == nil
        let installationID: String
        if usingPersistedRetry, let persistedInstallationID = retry?.installationID {
            installationID = persistedInstallationID
        } else {
            installationID = try await installation.installationID()
        }
        let requestedName = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let normalizedName = requestedName ?? (usingPersistedRetry ? retry?.deviceName : nil)
        let existing = try await store.snapshot()

        if let existing,
           existing.accountID == accountID,
           existing.fcmToken == token,
           existing.installationID == installationID,
           existing.deviceName == normalizedName,
           existing.registration.active {
            if let retry,
               let obsoleteID = retry.obsoleteRegistrationID,
               obsoleteID != existing.registration.id {
                _ = try await removeObsoleteRegistration(
                    obsoleteID,
                    accountID: accountID,
                    retry: retry
                )
            } else {
                try await retryStore.clear(accountID: accountID)
            }
            return .unchanged(existing.registration)
        }

        let pending = PendingDeviceRegistrationRetry(
            accountID: accountID,
            fcmToken: token,
            installationID: installationID,
            deviceName: normalizedName,
            obsoleteRegistrationID: nil,
            requestedAt: now()
        )
        let registration: DeviceRegistrationDTO
        do {
            registration = try await remote.register(
                RegisterDeviceRequestDTO(
                    platform: .ios,
                    pushToken: token,
                    installationId: installationID,
                    deviceName: normalizedName
                )
            )
        } catch let api as APIError where api.isUnauthorized {
            await clearForTerminalUnauthorized(accountID: accountID)
            throw api
        } catch {
            try await recordRetry(pending)
            throw error
        }
        try Task.checkCancellation()
        do {
            try await store.save(
                DeviceRegistrationSnapshot(
                    accountID: accountID,
                    fcmToken: token,
                    installationID: installationID,
                    deviceName: normalizedName,
                    registration: registration
                )
            )
        } catch {
            try await recordRetry(pending)
            throw error
        }
        if let existing,
           existing.accountID == accountID,
           existing.registration.id != registration.id {
            let cleanupRetry = PendingDeviceRegistrationRetry(
                accountID: accountID,
                fcmToken: token,
                installationID: installationID,
                deviceName: normalizedName,
                obsoleteRegistrationID: existing.registration.id,
                requestedAt: now()
            )
            _ = try await removeObsoleteRegistration(
                existing.registration.id,
                accountID: accountID,
                retry: cleanupRetry
            )
        } else {
            try await retryStore.clear(accountID: accountID)
        }
        return .registered(registration)
    }

    func unregister(accountID: UUID) async throws -> DeviceRegistrationSyncResult {
        if let flight = syncFlights[accountID] {
            _ = try? await flight.task.value
            removeFlight(id: flight.id, accountID: accountID)
        }
        guard let existing = try await store.snapshot(), existing.accountID == accountID else {
            try? await retryStore.clear(accountID: accountID)
            try? await terminalCleaner.clear(accountID: accountID)
            return .unregistered
        }
        do {
            try await remote.delete(registrationID: existing.registration.id)
        } catch let api as APIError where api.statusCode == 404 {
            // A missing server registration is already the requested state.
        } catch let api as APIError where api.isUnauthorized {
            await clearForTerminalUnauthorized(accountID: accountID)
            throw api
        }
        try await store.clear()
        try await retryStore.clear(accountID: accountID)
        try await terminalCleaner.clear(accountID: accountID)
        return .unregistered
    }

    private func removeObsoleteRegistration(
        _ registrationID: UUID,
        accountID: UUID,
        retry: PendingDeviceRegistrationRetry
    ) async throws -> Bool {
        do {
            try await remote.delete(registrationID: registrationID)
            try await retryStore.clear(accountID: accountID)
            return true
        } catch let api as APIError where api.statusCode == 404 {
            try await retryStore.clear(accountID: accountID)
            return true
        } catch let api as APIError where api.isUnauthorized {
            await clearForTerminalUnauthorized(accountID: accountID)
            throw api
        } catch {
            try await recordRetry(retry)
            return false
        }
    }

    private func recordRetry(_ pending: PendingDeviceRegistrationRetry) async throws {
        try await retryStore.save(pending)
        await retryScheduler.scheduleDeviceRegistrationRetry(accountID: pending.accountID)
    }

    private func clearForTerminalUnauthorized(accountID: UUID) async {
        try? await store.clear()
        try? await retryStore.clear(accountID: accountID)
        try? await terminalCleaner.clear(accountID: accountID)
    }

    private func removeFlight(id: UUID, accountID: UUID) {
        guard syncFlights[accountID]?.id == id else { return }
        syncFlights.removeValue(forKey: accountID)
    }
}

actor DeviceRegistrationTokenCoordinator {
    private let service: any DeviceRegistrationServicing
    private var observation: Task<Void, Never>?

    init(service: any DeviceRegistrationServicing) {
        self.service = service
    }

    func start(
        accountID: UUID,
        deviceName: String?,
        provider: any FCMRegistrationTokenProviding
    ) {
        observation?.cancel()
        let service = self.service
        observation = Task {
            let changes = await provider.tokenChanges()
            for await _ in changes {
                guard !Task.isCancelled else { return }
                _ = try? await service.sync(accountID: accountID, deviceName: deviceName)
            }
        }
    }

    func stop() {
        observation?.cancel()
        observation = nil
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
