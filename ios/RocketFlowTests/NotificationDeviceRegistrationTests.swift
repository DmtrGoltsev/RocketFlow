import Foundation
import XCTest
@testable import RocketFlow

final class NotificationDeviceRegistrationTests: XCTestCase {
    func testManualFCMConfigurationUsesAsyncProtocolWitness() async {
        let provider: any FCMRegistrationTokenProviding =
            ManualFCMRegistrationTokenProvider(configured: false)

        let isConfigured = await provider.isConfigured()

        XCTAssertFalse(isConfigured)
    }

    func testEndpointAdapterUsesExactDeviceRoutesAndIOSFCMBody() async throws {
        let registration = deviceRegistration()
        let sender = NotificationRequestSenderSpy(registration: registration)
        let remote = AuthenticatedDeviceRegistrationRemote(sender: sender)

        _ = try await remote.register(RegisterDeviceRequestDTO(
            platform: .ios,
            pushToken: "fcm-token",
            installationId: "installation",
            deviceName: "iPhone"
        ))
        try await remote.delete(registrationID: registration.id)

        let requests = await sender.requests()
        XCTAssertEqual(requests.map(\.method), [.post, .delete])
        XCTAssertEqual(requests[0].path, ["devices"])
        XCTAssertEqual(requests[1].path, ["devices", registration.id.uuidString.lowercased()])
        let body = try json(requests[0].body)
        XCTAssertEqual(body["platform"] as? String, "ios")
        XCTAssertEqual(body["pushToken"] as? String, "fcm-token")
        XCTAssertEqual(body["installationId"] as? String, "installation")
    }

    func testMatchingAccountTokenInstallationAndNameDoesNotReregister() async throws {
        let accountID = UUID()
        let registration = deviceRegistration()
        let tokenProvider = ManualFCMRegistrationTokenProvider(token: "same-token")
        let store = InMemoryDeviceRegistrationStateStore(value: DeviceRegistrationSnapshot(
            accountID: accountID,
            fcmToken: "same-token",
            installationID: "installation",
            deviceName: "iPhone",
            registration: registration
        ))
        let remote = DeviceRegistrationRemoteSpy(registration: registration)
        let service = DeviceRegistrationService(
            remote: remote,
            tokenProvider: tokenProvider,
            installation: FixedInstallationIdentity("installation"),
            store: store,
            retryStore: InMemoryDeviceRegistrationRetryStore()
        )

        let result = try await service.sync(accountID: accountID, deviceName: "iPhone")

        XCTAssertEqual(result, .unchanged(registration))
        let calls = await remote.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testTokenChangeRegistersReplacementBeforeDeletingOldRegistration() async throws {
        let accountID = UUID()
        let old = deviceRegistration(id: UUID())
        let replacement = deviceRegistration(id: UUID())
        let tokenProvider = ManualFCMRegistrationTokenProvider(token: "new-token")
        let store = InMemoryDeviceRegistrationStateStore(value: DeviceRegistrationSnapshot(
            accountID: accountID,
            fcmToken: "old-token",
            installationID: "installation",
            deviceName: nil,
            registration: old
        ))
        let remote = DeviceRegistrationRemoteSpy(registration: replacement)
        let service = DeviceRegistrationService(
            remote: remote,
            tokenProvider: tokenProvider,
            installation: FixedInstallationIdentity("installation"),
            store: store,
            retryStore: InMemoryDeviceRegistrationRetryStore()
        )

        let result = try await service.sync(accountID: accountID, deviceName: nil)

        XCTAssertEqual(result, .registered(replacement))
        let calls = await remote.calls()
        XCTAssertEqual(calls, [.register, .delete(old.id)])
        let stored = try await store.snapshot()
        XCTAssertEqual(stored?.fcmToken, "new-token")
    }

    func testAccountSwitchNeverDeletesRegistrationUsingNewAccountSession() async throws {
        let oldAccount = UUID()
        let newAccount = UUID()
        let old = deviceRegistration(id: UUID())
        let replacement = deviceRegistration(id: UUID())
        let store = InMemoryDeviceRegistrationStateStore(value: DeviceRegistrationSnapshot(
            accountID: oldAccount,
            fcmToken: "token",
            installationID: "installation",
            deviceName: nil,
            registration: old
        ))
        let remote = DeviceRegistrationRemoteSpy(registration: replacement)
        let service = DeviceRegistrationService(
            remote: remote,
            tokenProvider: ManualFCMRegistrationTokenProvider(token: "token"),
            installation: FixedInstallationIdentity("installation"),
            store: store,
            retryStore: InMemoryDeviceRegistrationRetryStore()
        )

        _ = try await service.sync(accountID: newAccount, deviceName: nil)

        let calls = await remote.calls()
        let stored = try await store.snapshot()
        XCTAssertEqual(calls, [.register])
        XCTAssertEqual(stored?.accountID, newAccount)
    }

    func testMissingFCMTokenDoesNotCallBackend() async throws {
        let remote = DeviceRegistrationRemoteSpy(registration: deviceRegistration())
        let service = DeviceRegistrationService(
            remote: remote,
            tokenProvider: ManualFCMRegistrationTokenProvider(token: nil),
            installation: FixedInstallationIdentity("installation"),
            store: InMemoryDeviceRegistrationStateStore(),
            retryStore: InMemoryDeviceRegistrationRetryStore()
        )

        let result = try await service.sync(accountID: UUID(), deviceName: nil)

        XCTAssertEqual(result, .tokenUnavailable)
        let calls = await remote.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testMissingFirebaseConfigurationSurfacesUnavailableWithoutBackendCall() async throws {
        let accountID = UUID()
        let remote = DeviceRegistrationRemoteSpy(registration: deviceRegistration())
        let service = DeviceRegistrationService(
            remote: remote,
            tokenProvider: ManualFCMRegistrationTokenProvider(token: nil, configured: false),
            installation: FixedInstallationIdentity("installation"),
            store: InMemoryDeviceRegistrationStateStore(),
            retryStore: InMemoryDeviceRegistrationRetryStore()
        )

        let state = await service.state(accountID: accountID)
        let result = try await service.sync(accountID: accountID, deviceName: nil)
        let calls = await remote.calls()

        XCTAssertEqual(state, .unavailable)
        XCTAssertEqual(result, .tokenUnavailable)
        XCTAssertTrue(calls.isEmpty)
    }

    func testUnregisterTreats404AsAlreadyRemovedAndClearsLocalState() async throws {
        let accountID = UUID()
        let registration = deviceRegistration()
        let store = InMemoryDeviceRegistrationStateStore(value: DeviceRegistrationSnapshot(
            accountID: accountID,
            fcmToken: "token",
            installationID: "installation",
            deviceName: nil,
            registration: registration
        ))
        let remote = DeviceRegistrationRemoteSpy(
            registration: registration,
            deleteError: APIError(
                statusCode: 404, code: "not_found", message: "not found",
                details: [], traceID: nil, requestID: UUID()
            )
        )
        let service = DeviceRegistrationService(
            remote: remote,
            tokenProvider: ManualFCMRegistrationTokenProvider(token: "token"),
            installation: FixedInstallationIdentity("installation"),
            store: store,
            retryStore: InMemoryDeviceRegistrationRetryStore()
        )

        let result = try await service.unregister(accountID: accountID)
        let stored = try await store.snapshot()
        XCTAssertEqual(result, .unregistered)
        XCTAssertNil(stored)
    }

    func testRegistrationFailurePreservesOldSnapshotAndSchedulesDurableRetry() async throws {
        let accountID = UUID()
        let old = deviceRegistration(id: UUID())
        let store = InMemoryDeviceRegistrationStateStore(value: DeviceRegistrationSnapshot(
            accountID: accountID,
            fcmToken: "old-token",
            installationID: "installation",
            deviceName: nil,
            registration: old
        ))
        let retryStore = InMemoryDeviceRegistrationRetryStore()
        let retryScheduler = DeviceRetrySchedulerSpy()
        let remote = DeviceRegistrationRemoteSpy(
            registration: deviceRegistration(),
            registerError: apiError(status: 503)
        )
        let service = DeviceRegistrationService(
            remote: remote,
            tokenProvider: ManualFCMRegistrationTokenProvider(token: "new-token"),
            installation: FixedInstallationIdentity("installation"),
            store: store,
            retryStore: retryStore,
            retryScheduler: retryScheduler
        )

        do {
            _ = try await service.sync(accountID: accountID, deviceName: nil)
            XCTFail("Expected registration failure")
        } catch {
            XCTAssertEqual((error as? APIError)?.statusCode, 503)
        }

        let retained = try await store.snapshot()
        let pending = try await retryStore.pending(accountID: accountID)
        let scheduled = await retryScheduler.accounts()
        XCTAssertEqual(retained?.registration.id, old.id)
        XCTAssertEqual(retained?.fcmToken, "old-token")
        XCTAssertEqual(pending?.fcmToken, "new-token")
        XCTAssertEqual(scheduled, [accountID])
        let calls = await remote.calls()
        XCTAssertEqual(calls, [.register])
    }

    func testConcurrentSyncCallsShareSingleFlight() async throws {
        let accountID = UUID()
        let registration = deviceRegistration()
        let remote = DeviceRegistrationRemoteSpy(
            registration: registration,
            registerDelayNanoseconds: 50_000_000
        )
        let service = DeviceRegistrationService(
            remote: remote,
            tokenProvider: ManualFCMRegistrationTokenProvider(token: "token"),
            installation: FixedInstallationIdentity("installation"),
            store: InMemoryDeviceRegistrationStateStore(),
            retryStore: InMemoryDeviceRegistrationRetryStore()
        )

        async let first = service.sync(accountID: accountID, deviceName: "iPhone")
        async let second = service.sync(accountID: accountID, deviceName: "iPhone")
        let firstResult = try await first
        let secondResult = try await second
        let results = [firstResult, secondResult]
        let calls = await remote.calls()

        XCTAssertEqual(results, [.registered(registration), .registered(registration)])
        XCTAssertEqual(calls, [.register])
    }

    func testUnauthorizedUnregisterClearsLocalStateRetryAndAccountNotifications() async throws {
        let accountID = UUID()
        let registration = deviceRegistration()
        let store = InMemoryDeviceRegistrationStateStore(value: DeviceRegistrationSnapshot(
            accountID: accountID,
            fcmToken: "token",
            installationID: "installation",
            deviceName: nil,
            registration: registration
        ))
        let retryStore = InMemoryDeviceRegistrationRetryStore()
        try await retryStore.save(PendingDeviceRegistrationRetry(
            accountID: accountID,
            fcmToken: "token",
            installationID: "installation",
            deviceName: nil,
            obsoleteRegistrationID: nil,
            requestedAt: Date()
        ))
        let cleaner = AccountNotificationCleanerSpy()
        let service = DeviceRegistrationService(
            remote: DeviceRegistrationRemoteSpy(
                registration: registration,
                deleteError: apiError(status: 401)
            ),
            tokenProvider: ManualFCMRegistrationTokenProvider(token: "token"),
            installation: FixedInstallationIdentity("installation"),
            store: store,
            retryStore: retryStore,
            terminalCleaner: cleaner
        )

        do {
            _ = try await service.unregister(accountID: accountID)
            XCTFail("Expected unauthorized")
        } catch {
            XCTAssertEqual((error as? APIError)?.statusCode, 401)
        }

        let stored = try await store.snapshot()
        let pending = try await retryStore.pending(accountID: accountID)
        let clearedAccounts = await cleaner.accounts()
        XCTAssertNil(stored)
        XCTAssertNil(pending)
        XCTAssertEqual(clearedAccounts, [accountID])
    }

    func testPersistedRetryCanResumeAfterServiceRecreationBeforeTokenProviderIsReady() async throws {
        let accountID = UUID()
        let retryStore = InMemoryDeviceRegistrationRetryStore()
        try await retryStore.save(PendingDeviceRegistrationRetry(
            accountID: accountID,
            fcmToken: "persisted-token",
            installationID: "installation",
            deviceName: "iPhone",
            obsoleteRegistrationID: nil,
            requestedAt: Date(timeIntervalSince1970: 1_787_001_200)
        ))
        let registration = deviceRegistration()
        let remote = DeviceRegistrationRemoteSpy(registration: registration)
        let recreated = DeviceRegistrationService(
            remote: remote,
            tokenProvider: ManualFCMRegistrationTokenProvider(token: nil),
            installation: FixedInstallationIdentity("installation"),
            store: InMemoryDeviceRegistrationStateStore(),
            retryStore: retryStore
        )

        let result = try await recreated.sync(accountID: accountID, deviceName: "iPhone")

        let pending = try await retryStore.pending(accountID: accountID)
        XCTAssertEqual(result, .registered(registration))
        XCTAssertNil(pending)
        let calls = await remote.calls()
        XCTAssertEqual(calls, [.register])
    }

    private func json(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(data)) as? [String: Any])
    }
}

private actor NotificationRequestSenderSpy: NotificationRequestSending {
    struct Request: Sendable {
        let method: HTTPMethod
        let path: [String]
        let body: Data?
    }

    private let registration: DeviceRegistrationDTO
    private var values: [Request] = []

    init(registration: DeviceRegistrationDTO) { self.registration = registration }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) throws -> Response {
        values.append(Request(method: endpoint.method, path: endpoint.pathSegments, body: endpoint.body))
        let response: Any = Response.self == DeviceRegistrationDTO.self
            ? registration
            : EmptyResponse()
        guard let typed = response as? Response else { throw DeviceRegistrationTestError.unexpectedResponse }
        return typed
    }

    func requests() -> [Request] { values }
}

private actor DeviceRegistrationRemoteSpy: DeviceRegistrationRemoteServing {
    enum Call: Equatable, Sendable {
        case delete(UUID)
        case register
    }

    private let registration: DeviceRegistrationDTO
    private let registerError: APIError?
    private let deleteError: APIError?
    private let registerDelayNanoseconds: UInt64
    private var values: [Call] = []
    private var requests: [RegisterDeviceRequestDTO] = []

    init(
        registration: DeviceRegistrationDTO,
        registerError: APIError? = nil,
        deleteError: APIError? = nil,
        registerDelayNanoseconds: UInt64 = 0
    ) {
        self.registration = registration
        self.registerError = registerError
        self.deleteError = deleteError
        self.registerDelayNanoseconds = registerDelayNanoseconds
    }

    func register(_ request: RegisterDeviceRequestDTO) async throws -> DeviceRegistrationDTO {
        values.append(.register)
        requests.append(request)
        if registerDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: registerDelayNanoseconds)
        }
        if let registerError { throw registerError }
        return registration
    }

    func delete(registrationID: UUID) throws {
        values.append(.delete(registrationID))
        if let deleteError { throw deleteError }
    }

    func calls() -> [Call] { values }
}

private struct FixedInstallationIdentity: InstallationIdentityProviding {
    let value: String
    init(_ value: String) { self.value = value }
    func installationID() -> String { value }
}

private actor DeviceRetrySchedulerSpy: DeviceRegistrationRetryScheduling {
    private var values: [UUID] = []
    func scheduleDeviceRegistrationRetry(accountID: UUID) { values.append(accountID) }
    func accounts() -> [UUID] { values }
}

private actor AccountNotificationCleanerSpy: AccountNotificationClearing {
    private var values: [UUID] = []
    func clear(accountID: UUID) { values.append(accountID) }
    func accounts() -> [UUID] { values }
}

private enum DeviceRegistrationTestError: Error {
    case unexpectedResponse
}

private func apiError(status: Int) -> APIError {
    APIError(
        statusCode: status,
        code: status == 401 ? "unauthorized" : "unavailable",
        message: "test",
        details: [],
        traceID: nil,
        requestID: UUID()
    )
}

private func deviceRegistration(id: UUID = UUID()) -> DeviceRegistrationDTO {
    DeviceRegistrationDTO(
        id: id,
        platform: .ios,
        deviceName: "iPhone",
        active: true,
        createdAt: Date(timeIntervalSince1970: 1_787_001_200)
    )
}
