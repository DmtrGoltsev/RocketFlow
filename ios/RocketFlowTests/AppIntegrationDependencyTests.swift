import XCTest
@testable import RocketFlow

@MainActor
final class AppIntegrationDependencyTests: XCTestCase {
    func testConstructsUserScopedRuntimeWithoutFirebaseConfiguration() async throws {
        let scheduler = AppIntegrationBackgroundScheduler()
        let tokenProvider = ManualFCMRegistrationTokenProvider(configured: false)
        let container = DependencyContainer(
            apiBaseURL: appIntegrationAPIURL,
            sessionStore: InMemorySessionStore(),
            databaseOpener: { _ in try AppDatabase.inMemory() },
            networkMonitor: FixedNetworkMonitor(connected: false),
            notificationCenter: AppUITestNotificationCenter(),
            fcmTokenProvider: tokenProvider,
            backgroundScheduler: scheduler,
            registerBackgroundTasks: false
        )
        let user = appIntegrationUser(id: UUID())

        try await container.activateApplication(for: user)

        XCTAssertEqual(container.activeUserID, user.id)
        XCTAssertEqual(container.activeRuntime?.user.id, user.id)
        XCTAssertNotNil(container.activeRuntime?.plannerDetails)
        XCTAssertNotNil(container.activeRuntime?.calendarRepository)
        XCTAssertNotNil(container.activeRuntime?.focusRepository)
        let isConfigured = await tokenProvider.isConfigured()
        XCTAssertFalse(isConfigured)

        try await container.deactivateApplication(for: user.id, eraseUserData: true)
        XCTAssertNil(container.activeRuntime)
        XCTAssertNil(container.activeUserID)
    }

    func testAccountSwitchReplacesAllScopedDependencies() async throws {
        let container = DependencyContainer(
            apiBaseURL: appIntegrationAPIURL,
            sessionStore: InMemorySessionStore(),
            databaseOpener: { _ in try AppDatabase.inMemory() },
            networkMonitor: FixedNetworkMonitor(connected: false),
            notificationCenter: AppUITestNotificationCenter(),
            fcmTokenProvider: ManualFCMRegistrationTokenProvider(configured: false),
            backgroundScheduler: AppIntegrationBackgroundScheduler(),
            registerBackgroundTasks: false
        )
        let first = appIntegrationUser(id: UUID())
        let second = appIntegrationUser(id: UUID())

        try await container.activateApplication(for: first)
        try await container.deactivateApplication(for: first.id, eraseUserData: false)
        try await container.activateApplication(for: second)

        XCTAssertEqual(container.activeRuntime?.user.id, second.id)
        XCTAssertEqual(container.activeUserID, second.id)
    }

    func testStaleLeaseCannotDeactivateNewerRuntimeForSameAccount() async throws {
        let container = makeContainer()
        let user = appIntegrationUser(id: UUID())
        let stale = try await container.activateApplication(for: user, sessionGeneration: 1)
        let current = try await container.activateApplication(for: user, sessionGeneration: 2)

        try await container.deactivateApplication(
            for: user.id,
            expectedLease: stale,
            eraseUserData: false
        )

        XCTAssertNotEqual(stale.runtimeID, current.runtimeID)
        XCTAssertEqual(container.activeRuntime?.lease, current)
        XCTAssertEqual(container.activeUserID, user.id)
    }

    func testTeardownExecutorAttemptsEveryOperationAndAggregatesFailures() async {
        let recorder = AppIntegrationStageRecorder()
        let operations = AppTeardownStage.allCases.map { stage in
            AppTeardownOperation(
                stage: stage,
                requiredForPrivacy: stage != .deviceUnregister
            ) {
                await recorder.record(stage)
                if stage == .reminders || stage == .featureCache {
                    throw AppIntegrationExpectedError.failure
                }
            }
        }

        let failures = await AppTeardownExecutor.run(operations)
        let attemptedStages = await recorder.values()

        XCTAssertEqual(attemptedStages, AppTeardownStage.allCases)
        XCTAssertEqual(failures.map(\.stage), [.reminders, .featureCache])
        XCTAssertTrue(
            AppRuntimeTeardownError(accountID: UUID(), failures: failures)
                .hasRequiredPrivacyFailure
        )
    }

    func testFeaturePipelineRunsDeviceAfterFocusAndReminders() async throws {
        let lease = AppRuntimeLease(accountID: UUID(), sessionGeneration: 4)
        let validity = AppRuntimeValidity(lease: lease)
        let recorder = AppIntegrationStringRecorder()

        try await AppRuntimeFeatureSyncPipeline.run(
            checkpoint: { try await validity.require(lease) },
            focus: { await recorder.record("focus") },
            reminders: { await recorder.record("reminders") },
            device: { await recorder.record("device") }
        )

        let values = await recorder.values()
        XCTAssertEqual(values, ["focus", "reminders", "device"])
    }

    func testFeaturePipelineStopsAfterLeaseInvalidation() async {
        let lease = AppRuntimeLease(accountID: UUID(), sessionGeneration: 5)
        let validity = AppRuntimeValidity(lease: lease)
        let recorder = AppIntegrationStringRecorder()

        do {
            try await AppRuntimeFeatureSyncPipeline.run(
                checkpoint: { try await validity.require(lease) },
                focus: {
                    await recorder.record("focus")
                    await validity.invalidate(lease)
                },
                reminders: { await recorder.record("reminders") },
                device: { await recorder.record("device") }
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            let values = await recorder.values()
            XCTAssertEqual(values, ["focus"])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnauthorizedSharingActionReportsExactRuntimeLease() async {
        let lease = AppRuntimeLease(accountID: UUID(), sessionGeneration: 7)
        let recorder = AppIntegrationLeaseRecorder()
        let relay = AppUnauthorizedRelay()
        await relay.install { reported in await recorder.record(reported) }
        let service = AppUnauthorizedSharingService(
            base: AppIntegrationUnauthorizedSharingStub(),
            lease: lease,
            relay: relay
        )

        do {
            _ = try await service.listInvitations()
            XCTFail("Expected unauthorized")
        } catch {
            XCTAssertTrue(AppUnauthorizedErrorClassifier.isUnauthorized(error))
        }
        let reportedLease = await recorder.value()
        XCTAssertEqual(reportedLease, lease)
    }

    func testOwnerResolverRequiresMatchingOwnerOrExplicitCapability() {
        let current = UUID()

        XCTAssertTrue(
            AppSharingOwnershipResolver.isOwner(
                currentUserID: current,
                ownerUserID: current
            )
        )
        XCTAssertFalse(
            AppSharingOwnershipResolver.isOwner(
                currentUserID: current,
                ownerUserID: nil
            )
        )
        XCTAssertTrue(
            AppSharingOwnershipResolver.isOwner(
                currentUserID: current,
                ownerUserID: nil,
                explicitOwnerCapability: true
            )
        )
    }

    func testOwnedFolderAndGoalRemainShareableWhenSharedFlagIsTrue() {
        let fixture = sharingOwnershipFixture()

        XCTAssertTrue(
            AppSharingOwnershipResolver.isOwnedFolderOrGoal(
                reference: .init(kind: .folder, id: fixture.folderID),
                snapshot: fixture.snapshot,
                collaboratorFolderIDs: [],
                collaboratorGoalIDs: []
            )
        )
        XCTAssertTrue(
            AppSharingOwnershipResolver.isOwnedFolderOrGoal(
                reference: .init(kind: .goal, id: fixture.goalID),
                snapshot: fixture.snapshot,
                collaboratorFolderIDs: [],
                collaboratorGoalIDs: []
            )
        )
    }

    func testCollaboratorFolderAndGoalAreNotTreatedAsOwner() {
        let fixture = sharingOwnershipFixture()

        XCTAssertFalse(
            AppSharingOwnershipResolver.isOwnedFolderOrGoal(
                reference: .init(kind: .folder, id: fixture.folderID),
                snapshot: fixture.snapshot,
                collaboratorFolderIDs: [fixture.folderID],
                collaboratorGoalIDs: []
            )
        )
        XCTAssertFalse(
            AppSharingOwnershipResolver.isOwnedFolderOrGoal(
                reference: .init(kind: .goal, id: fixture.goalID),
                snapshot: fixture.snapshot,
                collaboratorFolderIDs: [fixture.folderID],
                collaboratorGoalIDs: []
            )
        )
    }

    func testOperationGateCancelsAndAwaitsDelayedRuntimeRequest() async {
        let lease = AppRuntimeLease(accountID: UUID(), sessionGeneration: 9)
        let gate = AppRuntimeOperationGate(lease: lease)
        let delayed = AppIntegrationDelayedOperation()
        let request = Task {
            try await gate.run(for: lease) {
                try await delayed.run()
            }
        }
        for _ in 0..<200 {
            if await gate.activeOperationCount() > 0 { break }
            await Task.yield()
        }

        await gate.invalidateCancelAndWait(for: lease)

        do {
            try await request.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let state = await delayed.state()
        let activeCount = await gate.activeOperationCount()
        XCTAssertTrue(state.cancelled)
        XCTAssertFalse(state.completed)
        XCTAssertEqual(activeCount, 0)
    }

    func testCalendarAdapterDrainsOldSessionBeforeAccountSwitch() async {
        let lease = AppRuntimeLease(accountID: UUID(), sessionGeneration: 10)
        let gate = AppRuntimeOperationGate(lease: lease)
        let operation = AppIntegrationDelayedSessionOperation(token: "calendar-old")
        let adapter = AppRuntimeCalendarLoader(
            base: AppIntegrationDelayedCalendarLoader(operation: operation),
            lease: lease,
            relay: AppUnauthorizedRelay(),
            operationGate: gate
        )
        let request = Task {
            try await adapter.load(
                accountID: lease.accountID,
                accountTimezone: "UTC",
                from: LocalDate(rawValue: "2026-08-01")!,
                toExclusive: LocalDate(rawValue: "2026-09-01")!
            )
        }
        await operation.waitUntilStarted()

        await gate.invalidateCancelAndWait(for: lease)
        await operation.replaceToken("calendar-new")

        await assertCancelled(request)
        let state = await operation.state()
        XCTAssertEqual(state.startedTokens, ["calendar-old"])
        XCTAssertTrue(state.cancelled)
        XCTAssertFalse(state.completed)
    }

    func testFocusAdapterDrainsOldSessionBeforeRelogin() async {
        let lease = AppRuntimeLease(accountID: UUID(), sessionGeneration: 11)
        let gate = AppRuntimeOperationGate(lease: lease)
        let operation = AppIntegrationDelayedSessionOperation(token: "focus-old")
        let adapter = AppRuntimeFocusRepository(
            base: AppIntegrationDelayedFocusRepository(operation: operation),
            lease: lease,
            relay: AppUnauthorizedRelay(),
            operationGate: gate
        )
        let request = Task {
            try await adapter.loadCurrent(accountID: lease.accountID, timezone: "UTC")
        }
        await operation.waitUntilStarted()

        await gate.invalidateCancelAndWait(for: lease)
        await operation.replaceToken("focus-new")

        await assertCancelled(request)
        let state = await operation.state()
        XCTAssertEqual(state.startedTokens, ["focus-old"])
        XCTAssertTrue(state.cancelled)
        XCTAssertFalse(state.completed)
    }

    func testSettingsAdapterDrainsOldSessionBeforeRelogin() async {
        let lease = AppRuntimeLease(accountID: UUID(), sessionGeneration: 12)
        let gate = AppRuntimeOperationGate(lease: lease)
        let operation = AppIntegrationDelayedSessionOperation(token: "settings-old")
        let adapter = AppRuntimeSettingsRepository(
            base: AppIntegrationDelayedSettingsRepository(operation: operation),
            lease: lease,
            relay: AppUnauthorizedRelay(),
            operationGate: gate
        )
        let request = Task {
            try await adapter.load(accountID: lease.accountID)
        }
        await operation.waitUntilStarted()

        await gate.invalidateCancelAndWait(for: lease)
        await operation.replaceToken("settings-new")

        await assertCancelled(request)
        let state = await operation.state()
        XCTAssertEqual(state.startedTokens, ["settings-old"])
        XCTAssertTrue(state.cancelled)
        XCTAssertFalse(state.completed)
    }

    func testSerialLifecycleChainAwaitsCancelledWorkBeforeReplacement() async {
        let chain = AppSerialTaskChain()
        let recorder = AppIntegrationStringRecorder()
        chain.replace {
            await recorder.record("first-start")
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                await recorder.record("first-completed")
            } catch {
                await recorder.record("first-cancelled")
            }
        }
        for _ in 0..<200 {
            if await recorder.values() == ["first-start"] { break }
            await Task.yield()
        }

        await chain.replaceAndWait {
            await recorder.record("second-start")
        }

        let values = await recorder.values()
        XCTAssertEqual(
            values,
            ["first-start", "first-cancelled", "second-start"]
        )
    }

    func testInvalidExplicitAPIURLSurfacesConfigurationErrorWithoutProductionFallback() {
        let invalid = URL(string: "relative/rocket-api")!
        let container = DependencyContainer(
            apiBaseURL: invalid,
            registerBackgroundTasks: false
        )

        XCTAssertEqual(
            container.startupConfigurationError,
            .invalidAPIBaseURL(invalid.absoluteString)
        )
        XCTAssertEqual(
            container.apiBaseURL.absoluteString,
            "https://configuration.invalid/rocket-api"
        )
    }

    func testDeepLinkWaitsWhileRuntimeMapperIsUnavailable() async {
        let container = makeContainer()
        let store = container.makeAppStore()

        await store.receiveDeepLink(URL(string: "rocketflow://focus")!)

        XCTAssertEqual(store.pendingDeepLinkCount, 1)
        XCTAssertNil(store.currentRuntimeLease)
    }

    private var appIntegrationAPIURL: URL {
        URL(string: "https://app-integration.test/rocket-api")!
    }

    private func assertCancelled<Value: Sendable>(_ task: Task<Value, Error>) async {
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func makeContainer() -> DependencyContainer {
        DependencyContainer(
            apiBaseURL: appIntegrationAPIURL,
            sessionStore: InMemorySessionStore(),
            databaseOpener: { _ in try AppDatabase.inMemory() },
            networkMonitor: FixedNetworkMonitor(connected: false),
            notificationCenter: AppUITestNotificationCenter(),
            fcmTokenProvider: ManualFCMRegistrationTokenProvider(configured: false),
            backgroundScheduler: AppIntegrationBackgroundScheduler(),
            registerBackgroundTasks: false
        )
    }

    private func appIntegrationUser(id: UUID) -> UserDTO {
        UserDTO(
            id: id,
            email: "test@rocketflow.local",
            displayName: "Test",
            timezone: "Europe/Moscow",
            language: .ru,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func sharingOwnershipFixture() -> (
        snapshot: PlanningSnapshot,
        folderID: UUID,
        goalID: UUID
    ) {
        let folderID = UUID()
        let goalID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return (
            PlanningSnapshot(
                folders: [
                    FolderDTO(
                        id: folderID,
                        parentFolderId: nil,
                        name: "Owned shared folder",
                        description: "",
                        displayOrder: 0,
                        archived: false,
                        shared: true,
                        fullAccess: true,
                        version: 1,
                        createdAt: date,
                        updatedAt: date
                    )
                ],
                goals: [
                    GoalDTO(
                        id: goalID,
                        folderId: folderID,
                        name: "Owned shared goal",
                        description: "",
                        status: .todo,
                        archived: false,
                        shared: true,
                        fullAccess: true,
                        version: 1,
                        createdAt: date,
                        updatedAt: date
                    )
                ],
                tasks: [],
                ideas: [],
                notes: [],
                pendingCount: 0,
                conflictCount: 0
            ),
            folderID,
            goalID
        )
    }
}

private actor AppIntegrationBackgroundScheduler: BackgroundRefreshScheduling {
    func submit(identifier: String, earliestBeginDate: Date) {}
    func cancel(identifier: String) {}
}

private enum AppIntegrationExpectedError: Error {
    case failure
}

private actor AppIntegrationStageRecorder {
    private var stages: [AppTeardownStage] = []
    func record(_ stage: AppTeardownStage) { stages.append(stage) }
    func values() -> [AppTeardownStage] { stages }
}

private actor AppIntegrationStringRecorder {
    private var items: [String] = []
    func record(_ value: String) { items.append(value) }
    func values() -> [String] { items }
}

private actor AppIntegrationLeaseRecorder {
    private var lease: AppRuntimeLease?
    func record(_ value: AppRuntimeLease?) { lease = value }
    func value() -> AppRuntimeLease? { lease }
}

private actor AppIntegrationDelayedOperation {
    private var completed = false
    private var cancelled = false

    func run() async throws {
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            completed = true
        } catch {
            cancelled = true
            throw error
        }
    }

    func state() -> (completed: Bool, cancelled: Bool) {
        (completed, cancelled)
    }
}

private actor AppIntegrationDelayedSessionOperation {
    struct State: Sendable {
        let startedTokens: [String]
        let completed: Bool
        let cancelled: Bool
    }

    private var token: String
    private var startedTokens: [String] = []
    private var completed = false
    private var cancelled = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(token: String) {
        self.token = token
    }

    func run() async throws {
        startedTokens.append(token)
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            try Task.checkCancellation()
            completed = true
        } catch {
            cancelled = true
            throw error
        }
    }

    func waitUntilStarted() async {
        guard startedTokens.isEmpty else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func replaceToken(_ token: String) {
        self.token = token
    }

    func state() -> State {
        State(startedTokens: startedTokens, completed: completed, cancelled: cancelled)
    }
}

private enum AppIntegrationDelayedFeatureError: Error {
    case unused
}

private actor AppIntegrationDelayedCalendarLoader: CalendarLoading {
    let operation: AppIntegrationDelayedSessionOperation

    init(operation: AppIntegrationDelayedSessionOperation) {
        self.operation = operation
    }

    func load(
        accountID: UUID,
        accountTimezone: String,
        from: LocalDate,
        toExclusive: LocalDate
    ) async throws -> CalendarLoadResult {
        try await operation.run()
        throw AppIntegrationDelayedFeatureError.unused
    }
}

private actor AppIntegrationDelayedFocusRepository: FocusRepositoryServing {
    let operation: AppIntegrationDelayedSessionOperation

    init(operation: AppIntegrationDelayedSessionOperation) {
        self.operation = operation
    }

    func loadCurrent(accountID: UUID, timezone: String) async throws -> FocusCurrentResult {
        try await operation.run()
        throw AppIntegrationDelayedFeatureError.unused
    }

    func loadCandidates(
        accountID: UUID,
        query: String?,
        folderID: UUID?,
        goalID: UUID?,
        cursor: String?,
        limit: Int
    ) async throws -> FocusCandidateListResponseDTO {
        throw AppIntegrationDelayedFeatureError.unused
    }

    func add(accountID: UUID, candidate: FocusCandidateDTO) async throws -> FocusCurrentResult {
        throw AppIntegrationDelayedFeatureError.unused
    }

    func remove(accountID: UUID, taskID: UUID) async throws -> FocusCurrentResult {
        throw AppIntegrationDelayedFeatureError.unused
    }

    func reorder(accountID: UUID, taskIDs: [UUID]) async throws -> FocusCurrentResult {
        throw AppIntegrationDelayedFeatureError.unused
    }

    func resolveRollover(
        accountID: UUID,
        selectedTaskIDs: [UUID]
    ) async throws -> FocusCurrentResult {
        throw AppIntegrationDelayedFeatureError.unused
    }

    func loadHistory(accountID: UUID) async throws -> FocusHistoryResult {
        throw AppIntegrationDelayedFeatureError.unused
    }

    func loadHistoryDetail(
        accountID: UUID,
        periodID: UUID
    ) async throws -> FocusHistoryDetailResult {
        throw AppIntegrationDelayedFeatureError.unused
    }

    func loadSettings(accountID: UUID) async throws -> FocusSettingsResult {
        throw AppIntegrationDelayedFeatureError.unused
    }

    func updateSettings(
        accountID: UUID,
        values: FocusCadenceValues
    ) async throws -> FocusSettingsResult {
        throw AppIntegrationDelayedFeatureError.unused
    }

    func syncPending(accountID: UUID, timezone: String) async throws -> FocusSyncResult {
        throw AppIntegrationDelayedFeatureError.unused
    }
}

private actor AppIntegrationDelayedSettingsRepository: SettingsRepositoryServing {
    let operation: AppIntegrationDelayedSessionOperation

    init(operation: AppIntegrationDelayedSessionOperation) {
        self.operation = operation
    }

    func load(accountID: UUID) async throws -> SettingsRepositorySnapshot {
        try await operation.run()
        throw AppIntegrationDelayedFeatureError.unused
    }

    func save(
        accountID: UUID,
        language: AppLanguage,
        notificationsEnabled: Bool
    ) async throws -> SettingsRepositorySnapshot {
        throw AppIntegrationDelayedFeatureError.unused
    }

    func retry(accountID: UUID) async throws -> SettingsRepositorySnapshot {
        throw AppIntegrationDelayedFeatureError.unused
    }
}

private actor AppIntegrationUnauthorizedSharingStub: SharingFeatureServing {
    func createInvitation(
        resource: ShareableResourceKind,
        id: UUID,
        request: SharingInvitationRequest
    ) async throws -> ShareInvitationDTO { throw unauthorized }

    func listInvitations() async throws -> [ShareInvitationDTO] { throw unauthorized }
    func revokeInvitation(id: UUID) async throws -> ShareInvitationActionResponseDTO {
        throw unauthorized
    }
    func createShareLink(
        resource: ShareableResourceKind,
        id: UUID,
        request: ShareLinkRequestDTO?
    ) async throws -> ShareLinkCreateResponseDTO { throw unauthorized }
    func listShareLinks(resource: ShareableResourceKind, id: UUID) async throws -> [ShareLinkDTO] {
        throw unauthorized
    }
    func revokeShareLink(id: UUID) async throws -> ShareLinkActionResponseDTO {
        throw unauthorized
    }
    func resolveShareLink(token: String) async throws -> ShareLinkResolveResponseDTO {
        throw unauthorized
    }
    func acceptShareLink(token: String) async throws -> ShareLinkAcceptResponseDTO {
        throw unauthorized
    }

    private var unauthorized: APIError {
        APIError(
            statusCode: 401,
            code: "unauthorized",
            message: "Unauthorized",
            details: [],
            traceID: nil,
            requestID: UUID()
        )
    }
}
