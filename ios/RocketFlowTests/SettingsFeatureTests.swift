import Foundation
import XCTest
@testable import RocketFlow

final class SettingsFeatureTests: XCTestCase {
    private let accountID = UUID()

    func testRemotePATCHPreservesCompatibilityShadowAndHasNoPriorityUIFieldsOfItsOwn() async throws {
        let settings = settingsDTO(version: 7)
        let sender = SettingsRequestSenderSpy(response: settingsDTO(version: 8))
        let remote = AuthenticatedSettingsRemote(sender: sender)

        _ = try await remote.update(
            language: .en,
            notificationsEnabled: false,
            current: settings
        )

        let requests = await sender.requests()
        let request = try XCTUnwrap(requests.single)
        XCTAssertEqual(request.method, .patch)
        XCTAssertEqual(request.path, ["me", "settings"])
        let body = try json(request.body)
        XCTAssertEqual(body["language"] as? String, "en")
        XCTAssertEqual(body["notificationsEnabled"] as? Bool, false)
        XCTAssertEqual(body["version"] as? Int, 7)
        let green = try XCTUnwrap(body["greenPriorityDecayPolicy"] as? [String: Any])
        XCTAssertEqual(green["enabled"] as? Bool, false)
        XCTAssertEqual(green["thresholdPreset"] as? String, "day")
        XCTAssertEqual(green["decayAmount"] as? Int, 1)
    }

    func testOfflineSaveRemainsOptimisticPendingAndRetryAcknowledges() async throws {
        let initial = settingsDTO(version: 1)
        let applied = settingsDTO(language: .en, notifications: false, version: 2)
        let remote = SettingsRemoteStub(
            current: initial,
            updateOutcomes: [.offline, .value(applied)]
        )
        let cache = InMemorySettingsCache()
        try await cache.save(initial, accountID: accountID)
        let repository = SettingsRepository(remote: remote, cache: cache)

        let offline = try await repository.save(
            accountID: accountID,
            language: .en,
            notificationsEnabled: false
        )
        XCTAssertEqual(offline.source, .optimistic)
        XCTAssertTrue(offline.pending)
        XCTAssertEqual(offline.settings?.language, .en)

        let retried = try await repository.retry(accountID: accountID)
        let pending = try await cache.pending(accountID: accountID)
        XCTAssertEqual(retried.settings?.version, 2)
        XCTAssertFalse(retried.pending)
        XCTAssertNil(pending)
    }

    func testConflictFetchesFreshVersionAndReappliesDesiredVisibleSettings() async throws {
        let initial = settingsDTO(version: 1)
        let fresh = settingsDTO(version: 5)
        let applied = settingsDTO(language: .en, notifications: false, version: 6)
        let remote = SettingsRemoteStub(
            current: initial,
            currentOutcomes: [.value(fresh)],
            updateOutcomes: [
                .api(apiError(409, code: "version_conflict")),
                .value(applied)
            ]
        )
        let cache = InMemorySettingsCache()
        try await cache.save(initial, accountID: accountID)
        let repository = SettingsRepository(remote: remote, cache: cache)

        let result = try await repository.save(
            accountID: accountID,
            language: .en,
            notificationsEnabled: false
        )

        let versions = await remote.versions()
        XCTAssertEqual(result.settings?.version, 6)
        XCTAssertEqual(versions, [1, 5])
    }

    func testConcurrentSaveOldResponseCannotClearNewPendingMutation() async throws {
        let initial = settingsDTO(version: 1)
        let cache = InMemorySettingsCache()
        try await cache.save(initial, accountID: accountID)
        let remote = ControlledSettingsRemote(
            firstResponse: settingsDTO(language: .en, notifications: true, version: 2)
        )
        let repository = SettingsRepository(remote: remote, cache: cache)
        let expectedAccountID = accountID

        let first = Task {
            try await repository.save(
                accountID: expectedAccountID,
                language: .en,
                notificationsEnabled: true
            )
        }
        let firstStarted = await remote.waitUntilFirstUpdateStarted()
        XCTAssertTrue(firstStarted)
        let second = Task {
            try await repository.save(
                accountID: expectedAccountID,
                language: .ru,
                notificationsEnabled: false
            )
        }
        let latestWasPersisted = await waitUntil {
            guard let value = try? await cache.pending(accountID: expectedAccountID) else { return false }
            return value.language == .ru && !value.notificationsEnabled
        }
        XCTAssertTrue(latestWasPersisted)
        await remote.releaseFirstUpdate()

        let firstResult = try await first.value
        let secondResult = try await second.value
        let pending = try await cache.pending(accountID: accountID)
        let cached = try await cache.settings(accountID: accountID)
        let updateCount = await remote.updateCount()

        XCTAssertEqual(firstResult.settings?.language, .ru)
        XCTAssertEqual(secondResult.settings?.language, .ru)
        XCTAssertTrue(firstResult.pending)
        XCTAssertTrue(secondResult.pending)
        XCTAssertEqual(pending?.language, .ru)
        XCTAssertEqual(pending?.notificationsEnabled, false)
        XCTAssertEqual(cached?.notificationsEnabled, false)
        XCTAssertEqual(updateCount, 2)
    }

    func testCancelAndAwaitAllOperationsStopsFlushBeforeSessionReplacement() async throws {
        let initial = settingsDTO(version: 1)
        let cache = InMemorySettingsCache()
        try await cache.save(initial, accountID: accountID)
        let remote = ControlledSettingsRemote(
            firstResponse: settingsDTO(language: .en, notifications: false, version: 2)
        )
        let repository = SettingsRepository(remote: remote, cache: cache)
        let expectedAccountID = accountID
        let save = Task {
            try await repository.save(
                accountID: expectedAccountID,
                language: .en,
                notificationsEnabled: false
            )
        }
        let updateStarted = await remote.waitUntilFirstUpdateStarted()
        XCTAssertTrue(updateStarted)

        await repository.cancelAndAwaitAllOperations(accountID: expectedAccountID)

        do {
            _ = try await save.value
            XCTFail("Expected the settings flush to be cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let pending = try await cache.pending(accountID: expectedAccountID)
        let cached = try await cache.settings(accountID: expectedAccountID)
        let remoteWasCancelled = await remote.wasCancelled()
        XCTAssertTrue(remoteWasCancelled)
        XCTAssertNotNil(pending)
        XCTAssertEqual(cached?.version, initial.version)
    }

    func testDefaultReminderValidationRejectsNegativeAndUnboundedOffsets() {
        XCTAssertNoThrow(try SettingsValidation.validateDefaultReminder(enabled: true, offsetMinutes: 0))
        XCTAssertThrowsError(
            try SettingsValidation.validateDefaultReminder(enabled: true, offsetMinutes: -1)
        ) { XCTAssertEqual($0 as? SettingsValidationError, .invalidDefaultOffset) }
        XCTAssertThrowsError(
            try SettingsValidation.validateDefaultReminder(
                enabled: true,
                offsetMinutes: SettingsValidation.maximumDefaultOffsetMinutes + 1
            )
        ) { XCTAssertEqual($0 as? SettingsValidationError, .invalidDefaultOffset) }
        XCTAssertNoThrow(
            try SettingsValidation.validateDefaultReminder(enabled: false, offsetMinutes: -1)
        )
    }

    @MainActor
    func testDeniedSystemAuthorizationPreventsEnablingNotifications() async {
        let center = SettingsNotificationCenterStub(state: .denied)
        let model = makeViewModel(center: center)

        await model.setNotificationsEnabled(true)

        XCTAssertFalse(model.notificationsEnabled)
        XCTAssertEqual(model.authorization, .denied)
        XCTAssertEqual(model.validationMessage, SettingsCopy(language: .en).permissionRequired)
    }

    @MainActor
    func testSettingsViewModelLoadsOfflinePendingAndExposesFocusHook() async {
        let repository = SettingsRepositoryViewStub(snapshot: SettingsRepositorySnapshot(
            settings: settingsDTO(),
            source: .cache,
            pending: true,
            failure: SettingsFeatureFailure(SettingsTestError.offline)
        ))
        var opened = 0
        let model = makeViewModel(repository: repository) { opened += 1 }

        await model.load()
        model.openFocusCadence()

        XCTAssertEqual(model.phase, .pending)
        XCTAssertTrue(model.hasPendingChanges)
        XCTAssertEqual(opened, 1)
    }

    @MainActor
    func testSavePersistsDefaultReminderAndCurrentSettings() async {
        let reminderStore = InMemoryTaskReminderStore()
        let repository = SettingsRepositoryViewStub(snapshot: SettingsRepositorySnapshot(
            settings: settingsDTO(), source: .network, pending: false, failure: nil
        ))
        let model = makeViewModel(repository: repository, reminderStore: reminderStore)
        model.defaultReminderEnabled = true
        model.defaultOffsetMinutes = 30
        model.defaultRepeatRule = .weekly

        let savedSuccessfully = await model.save()
        XCTAssertTrue(savedSuccessfully)

        let saved = try? await reminderStore.defaultReminder(accountID: accountID)
        let repositoryValues = await repository.savedValues()
        XCTAssertEqual(saved?.offsetMinutes, 30)
        XCTAssertEqual(saved?.repeatRule, .weekly)
        XCTAssertEqual(repositoryValues.single?.notificationsEnabled, false)
    }

    @MainActor
    func testUnauthorizedSettingsLoadTransitionsAndInvokesAuthHook() async {
        let repository = SettingsRepositoryViewStub(
            snapshot: SettingsRepositorySnapshot(
                settings: nil, source: .cache, pending: false, failure: nil
            ),
            error: apiError(401, code: "unauthorized")
        )
        var unauthorizedCount = 0
        let cleaner = SettingsNotificationCleanerSpy()
        let model = SettingsViewModel(
            accountID: accountID,
            initialLanguage: .en,
            repository: repository,
            notificationCenter: SettingsNotificationCenterStub(state: .authorized),
            reminderStore: InMemoryTaskReminderStore(),
            registration: SettingsRegistrationStub(),
            notificationCleaner: cleaner,
            deviceName: nil,
            onOpenFocusCadence: {},
            onUnauthorized: { unauthorizedCount += 1 }
        )

        await model.load()

        XCTAssertEqual(model.phase, .unauthorized)
        XCTAssertEqual(unauthorizedCount, 1)
        let clearedAccounts = await cleaner.clearedAccounts()
        XCTAssertEqual(clearedAccounts, [accountID])
    }

    @MainActor
    func testSavingNotificationsOffSuspendsOnlyCurrentAccountNotifications() async {
        let cleaner = SettingsNotificationCleanerSpy()
        let repository = SettingsRepositoryViewStub(snapshot: SettingsRepositorySnapshot(
            settings: settingsDTO(notifications: false),
            source: .network,
            pending: false,
            failure: nil
        ))
        let model = makeViewModel(repository: repository, notificationCleaner: cleaner)
        model.notificationsEnabled = false

        let saved = await model.save()

        let suspended = await cleaner.suspendedAccounts()
        let erased = await cleaner.clearedAccounts()
        XCTAssertTrue(saved)
        XCTAssertEqual(suspended, [accountID])
        XCTAssertTrue(erased.isEmpty)
    }

    @MainActor
    func testTurningNotificationsOffWaitsForSaveBeforeSuspending() async {
        let cleaner = SettingsNotificationCleanerSpy()
        let model = makeViewModel(notificationCleaner: cleaner)
        model.notificationsEnabled = true

        await model.setNotificationsEnabled(false)

        let suspended = await cleaner.suspendedAccounts()
        let erased = await cleaner.clearedAccounts()
        XCTAssertFalse(model.notificationsEnabled)
        XCTAssertTrue(suspended.isEmpty)
        XCTAssertTrue(erased.isEmpty)
    }

    @MainActor
    func testSavingNotificationsOffPreservesDurableReminderAndDefault() async throws {
        let now = Date(timeIntervalSince1970: 1_787_001_200)
        let reminderStore = InMemoryTaskReminderStore()
        let center = SettingsNotificationCenterStub(state: .authorized)
        let scheduler = TaskReminderScheduler(center: center, store: reminderStore, now: { now })
        let reminder = LocalTaskReminder(
            id: UUID(),
            accountID: accountID,
            taskID: UUID(),
            taskTitle: "Private title",
            triggerAt: now.addingTimeInterval(60 * 60),
            repeatRule: .daily
        )
        let defaultReminder = DefaultTaskReminder(
            accountID: accountID,
            offsetMinutes: 45,
            repeatRule: .weekly,
            enabled: true
        )
        try await reminderStore.saveDefault(defaultReminder)
        _ = try await scheduler.schedule(reminder, taskState: .active, timeZone: .current)
        let repository = SettingsRepositoryViewStub(snapshot: SettingsRepositorySnapshot(
            settings: settingsDTO(notifications: false),
            source: .network,
            pending: false,
            failure: nil
        ))
        let model = makeViewModel(
            repository: repository,
            center: center,
            reminderStore: reminderStore,
            notificationCleaner: scheduler
        )
        await model.load()
        await model.setNotificationsEnabled(false)

        let saved = await model.save()

        let reminders = try await reminderStore.reminders(accountID: accountID)
        let storedDefault = try await reminderStore.defaultReminder(accountID: accountID)
        let pending = await center.pendingIdentifiers()
        XCTAssertTrue(saved)
        XCTAssertEqual(reminders, [reminder])
        XCTAssertEqual(storedDefault, defaultReminder)
        XCTAssertTrue(pending.isEmpty)
    }

    @MainActor
    func testFailedSettingsSaveRestoresPreviousDurableDefault() async throws {
        let reminderStore = InMemoryTaskReminderStore()
        let previous = DefaultTaskReminder(
            accountID: accountID,
            offsetMinutes: 30,
            repeatRule: .weekly,
            enabled: true
        )
        try await reminderStore.saveDefault(previous)
        let repository = SettingsRepositoryViewStub(
            snapshot: SettingsRepositorySnapshot(
                settings: nil,
                source: .cache,
                pending: false,
                failure: nil
            ),
            error: apiError(503, code: "service_unavailable")
        )
        let model = makeViewModel(repository: repository, reminderStore: reminderStore)
        model.defaultReminderEnabled = true
        model.defaultOffsetMinutes = 90
        model.defaultRepeatRule = .daily

        let saved = await model.save()

        let restored = try await reminderStore.defaultReminder(accountID: accountID)
        XCTAssertFalse(saved)
        XCTAssertEqual(restored, previous)
    }

    @MainActor
    func testSavingNotificationsOnRequestsScopedReconciliation() async {
        let cleaner = SettingsNotificationCleanerSpy()
        let repository = SettingsRepositoryViewStub(snapshot: SettingsRepositorySnapshot(
            settings: settingsDTO(notifications: true),
            source: .network,
            pending: false,
            failure: nil
        ))
        let model = makeViewModel(repository: repository, notificationCleaner: cleaner)
        model.notificationsEnabled = true

        let saved = await model.save()

        let resumed = await cleaner.resumedAccounts()
        XCTAssertTrue(saved)
        XCTAssertEqual(resumed, [accountID])
    }

    @MainActor
    func testUnavailablePushServiceDisablesRegistrationActionAndExplainsState() async {
        let model = makeViewModel(
            registration: SettingsRegistrationStub(displayState: .unavailable)
        )

        await model.load()

        XCTAssertEqual(model.registrationState, .unavailable)
        XCTAssertFalse(model.canChangeDeviceRegistration)
        XCTAssertEqual(model.deviceRegistrationExplanation, model.copy.pushUnavailableHint)
    }

    @MainActor
    func testAcceptedLanguageInvokesCallbackAfterPublishedStateChanges() async {
        let repository = SettingsRepositoryViewStub(snapshot: SettingsRepositorySnapshot(
            settings: settingsDTO(language: .ru), source: .network, pending: false, failure: nil
        ))
        var observedModel: SettingsViewModel?
        var callbackLanguages: [AppLanguage] = []
        var languageObservedDuringCallback: AppLanguage?
        let model = makeViewModel(
            repository: repository,
            onLanguageChanged: { language in
                callbackLanguages.append(language)
                languageObservedDuringCallback = observedModel?.language
            }
        )
        observedModel = model
        XCTAssertEqual(model.language, .en)

        let saved = await model.save()
        let savedValues = await repository.savedValues()

        XCTAssertTrue(saved)
        XCTAssertEqual(savedValues.single?.language, .en)
        XCTAssertEqual(model.language, .ru)
        XCTAssertEqual(callbackLanguages, [.ru])
        XCTAssertEqual(languageObservedDuringCallback, .ru)
        observedModel = nil
    }

    @MainActor
    func testAcceptedSameLanguageReconcilesExternallyStaleStore() async {
        let repository = SettingsRepositoryViewStub(snapshot: SettingsRepositorySnapshot(
            settings: settingsDTO(language: .en), source: .network, pending: false, failure: nil
        ))
        var externalLanguage: AppLanguage = .ru
        var callbackLanguages: [AppLanguage] = []
        let model = makeViewModel(
            repository: repository,
            onLanguageChanged: { language in
                callbackLanguages.append(language)
                externalLanguage = language
            }
        )

        let saved = await model.save()

        XCTAssertTrue(saved)
        XCTAssertEqual(model.language, .en)
        XCTAssertEqual(callbackLanguages, [.en])
        XCTAssertEqual(externalLanguage, .en)
    }

    @MainActor
    func testAcceptedSameLanguagePendingSnapshotAlsoReconcilesExternalStore() async {
        let repository = SettingsRepositoryViewStub(snapshot: SettingsRepositorySnapshot(
            settings: settingsDTO(language: .en),
            source: .optimistic,
            pending: true,
            failure: SettingsFeatureFailure(SettingsTestError.offline)
        ))
        var externalLanguage: AppLanguage = .ru
        var callbackLanguages: [AppLanguage] = []
        let model = makeViewModel(
            repository: repository,
            onLanguageChanged: { language in
                callbackLanguages.append(language)
                externalLanguage = language
            }
        )

        let saved = await model.save()

        XCTAssertTrue(saved)
        XCTAssertEqual(model.phase, .pending)
        XCTAssertEqual(callbackLanguages, [.en])
        XCTAssertEqual(externalLanguage, .en)
    }

    @MainActor
    func testOfflinePendingLanguageIsAcceptedAndPropagated() async {
        let repository = SettingsRepositoryViewStub(snapshot: SettingsRepositorySnapshot(
            settings: settingsDTO(language: .ru),
            source: .optimistic,
            pending: true,
            failure: SettingsFeatureFailure(SettingsTestError.offline)
        ))
        var callbackLanguages: [AppLanguage] = []
        let model = makeViewModel(
            repository: repository,
            onLanguageChanged: { callbackLanguages.append($0) }
        )
        model.language = .ru

        let saved = await model.save()

        XCTAssertTrue(saved)
        XCTAssertEqual(model.phase, .pending)
        XCTAssertTrue(model.hasPendingChanges)
        XCTAssertEqual(callbackLanguages, [.ru])
    }

    @MainActor
    func testFailedLanguageSaveRollsBackWithoutPropagation() async {
        let repository = SettingsRepositoryViewStub(
            snapshot: SettingsRepositorySnapshot(
                settings: nil, source: .cache, pending: false, failure: nil
            ),
            error: apiError(503, code: "service_unavailable")
        )
        var callbackLanguages: [AppLanguage] = []
        let model = makeViewModel(
            repository: repository,
            onLanguageChanged: { callbackLanguages.append($0) }
        )
        model.language = .ru

        let saved = await model.save()

        XCTAssertFalse(saved)
        XCTAssertEqual(model.language, .en)
        XCTAssertEqual(model.phase, .error)
        XCTAssertTrue(callbackLanguages.isEmpty)
    }

    @MainActor
    private func makeViewModel(
        repository: SettingsRepositoryViewStub? = nil,
        center: SettingsNotificationCenterStub = SettingsNotificationCenterStub(state: .authorized),
        reminderStore: InMemoryTaskReminderStore = InMemoryTaskReminderStore(),
        registration: SettingsRegistrationStub = SettingsRegistrationStub(),
        notificationCleaner: any AccountNotificationClearing = NoopAccountNotificationCleaner(),
        onFocus: @escaping () -> Void = {},
        onLanguageChanged: @escaping (AppLanguage) -> Void = { _ in }
    ) -> SettingsViewModel {
        let repository = repository ?? SettingsRepositoryViewStub(snapshot: SettingsRepositorySnapshot(
            settings: settingsDTO(), source: .network, pending: false, failure: nil
        ))
        return SettingsViewModel(
            accountID: accountID,
            initialLanguage: .en,
            repository: repository,
            notificationCenter: center,
            reminderStore: reminderStore,
            registration: registration,
            notificationCleaner: notificationCleaner,
            deviceName: "iPhone",
            onOpenFocusCadence: onFocus,
            onLanguageChanged: onLanguageChanged
        )
    }

    private func json(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(data)) as? [String: Any])
    }

    private func waitUntil(
        _ predicate: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<500 {
            if await predicate() { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }
}

private enum SettingsOutcome<Value: Sendable>: Sendable {
    case value(Value)
    case api(APIError)
    case offline

    func get() throws -> Value {
        switch self {
        case let .value(value): return value
        case let .api(error): throw error
        case .offline: throw SettingsTestError.offline
        }
    }
}

private actor SettingsRemoteStub: SettingsRemoteServing {
    private var currentValue: UserSettingsDTO
    private var currentOutcomes: [SettingsOutcome<UserSettingsDTO>]
    private var updateOutcomes: [SettingsOutcome<UserSettingsDTO>]
    private var capturedVersions: [Int64] = []

    init(
        current: UserSettingsDTO,
        currentOutcomes: [SettingsOutcome<UserSettingsDTO>] = [],
        updateOutcomes: [SettingsOutcome<UserSettingsDTO>] = []
    ) {
        currentValue = current
        self.currentOutcomes = currentOutcomes
        self.updateOutcomes = updateOutcomes
    }

    func current() throws -> UserSettingsDTO {
        guard !currentOutcomes.isEmpty else { return currentValue }
        let value = try currentOutcomes.removeFirst().get()
        currentValue = value
        return value
    }

    func update(
        language: AppLanguage,
        notificationsEnabled: Bool,
        current: UserSettingsDTO
    ) throws -> UserSettingsDTO {
        capturedVersions.append(current.version)
        guard !updateOutcomes.isEmpty else { throw SettingsTestError.missingStub }
        let value = try updateOutcomes.removeFirst().get()
        currentValue = value
        return value
    }

    func versions() -> [Int64] { capturedVersions }
}

private actor ControlledSettingsRemote: SettingsRemoteServing {
    private let firstResponse: UserSettingsDTO
    private var firstStarted = false
    private var firstReleased = false
    private var updates = 0
    private var cancelled = false

    init(firstResponse: UserSettingsDTO) {
        self.firstResponse = firstResponse
    }

    func current() -> UserSettingsDTO { firstResponse }

    func update(
        language: AppLanguage,
        notificationsEnabled: Bool,
        current: UserSettingsDTO
    ) async throws -> UserSettingsDTO {
        updates += 1
        if updates == 1 {
            firstStarted = true
            do {
                while !firstReleased {
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
            } catch {
                cancelled = true
                throw error
            }
            return firstResponse
        }
        throw SettingsTestError.offline
    }

    func waitUntilFirstUpdateStarted() async -> Bool {
        for _ in 0..<500 {
            if firstStarted { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    func releaseFirstUpdate() { firstReleased = true }
    func updateCount() -> Int { updates }
    func wasCancelled() -> Bool { cancelled }
}

private actor SettingsRequestSenderSpy: SettingsRequestSending {
    struct Request: Sendable {
        let method: HTTPMethod
        let path: [String]
        let body: Data?
    }

    private let response: UserSettingsDTO
    private var values: [Request] = []

    init(response: UserSettingsDTO) { self.response = response }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) throws -> Response {
        values.append(Request(method: endpoint.method, path: endpoint.pathSegments, body: endpoint.body))
        guard let typed = response as? Response else { throw SettingsTestError.missingStub }
        return typed
    }

    func requests() -> [Request] { values }
}

private actor SettingsRepositoryViewStub: SettingsRepositoryServing {
    struct Saved: Equatable, Sendable {
        let language: AppLanguage
        let notificationsEnabled: Bool
    }

    private let snapshot: SettingsRepositorySnapshot
    private let error: APIError?
    private var saved: [Saved] = []

    init(snapshot: SettingsRepositorySnapshot, error: APIError? = nil) {
        self.snapshot = snapshot
        self.error = error
    }
    func load(accountID: UUID) throws -> SettingsRepositorySnapshot {
        if let error { throw error }
        return snapshot
    }
    func save(
        accountID: UUID,
        language: AppLanguage,
        notificationsEnabled: Bool
    ) throws -> SettingsRepositorySnapshot {
        if let error { throw error }
        saved.append(Saved(language: language, notificationsEnabled: notificationsEnabled))
        return snapshot
    }
    func retry(accountID: UUID) throws -> SettingsRepositorySnapshot {
        if let error { throw error }
        return snapshot
    }
    func savedValues() -> [Saved] { saved }
}

private actor SettingsNotificationCenterStub: UserNotificationCenterServing {
    private var state: NotificationAuthorizationState
    private var values: [String: UserNotificationRequestValue] = [:]
    init(state: NotificationAuthorizationState) { self.state = state }
    func authorizationState() -> NotificationAuthorizationState { state }
    func requestAuthorization() -> Bool { state != .denied }
    func pendingIdentifiers() -> Set<String> { Set(values.keys) }
    func add(_ request: UserNotificationRequestValue) { values[request.identifier] = request }
    func remove(identifiers: [String]) {
        for identifier in identifiers { values.removeValue(forKey: identifier) }
    }
}

private actor SettingsRegistrationStub: DeviceRegistrationServicing {
    private let displayState: DeviceRegistrationDisplayState

    init(displayState: DeviceRegistrationDisplayState = .unregistered) {
        self.displayState = displayState
    }

    func state(accountID: UUID) -> DeviceRegistrationDisplayState { displayState }
    func sync(accountID: UUID, deviceName: String?) -> DeviceRegistrationSyncResult { .tokenUnavailable }
    func unregister(accountID: UUID) -> DeviceRegistrationSyncResult { .unregistered }
}

private actor SettingsNotificationCleanerSpy: AccountNotificationClearing {
    private var cleared: [UUID] = []
    private var suspended: [UUID] = []
    private var resumed: [UUID] = []
    func clear(accountID: UUID) { cleared.append(accountID) }
    func suspendNotifications(accountID: UUID) { suspended.append(accountID) }
    func resumeNotifications(accountID: UUID, timeZone: TimeZone) {
        _ = timeZone
        resumed.append(accountID)
    }
    func clearedAccounts() -> [UUID] { cleared }
    func suspendedAccounts() -> [UUID] { suspended }
    func resumedAccounts() -> [UUID] { resumed }
}

private enum SettingsTestError: Error {
    case offline
    case missingStub
}

private func settingsDTO(
    language: AppLanguage = .ru,
    notifications: Bool = true,
    version: Int64 = 7
) -> UserSettingsDTO {
    UserSettingsDTO(
        language: language,
        greenPriorityDecayPolicy: PriorityDecayPolicyDTO(
            taskType: "green", enabled: false, thresholdPreset: "day", decayAmount: 1
        ),
        redPriorityDecayPolicy: nil,
        notificationsEnabled: notifications,
        version: version
    )
}

private func apiError(_ status: Int, code: String) -> APIError {
    APIError(
        statusCode: status, code: code, message: code,
        details: [], traceID: nil, requestID: UUID()
    )
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
