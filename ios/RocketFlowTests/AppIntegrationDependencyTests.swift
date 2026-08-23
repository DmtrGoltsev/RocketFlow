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

    func testProductionCompositionAdoptsAuthenticatedLanguageInInjectedStore() async {
        let persistence = AppIntegrationLanguagePersistence(initial: .en)
        let languageStore = AppLanguageStore(persistence: persistence)
        let container = DependencyContainer(
            apiBaseURL: appIntegrationAPIURL,
            languageStore: languageStore,
            sessionStore: InMemorySessionStore(),
            databaseOpener: { _ in try AppDatabase.inMemory() },
            networkMonitor: FixedNetworkMonitor(connected: false),
            notificationCenter: AppUITestNotificationCenter(),
            fcmTokenProvider: ManualFCMRegistrationTokenProvider(configured: false),
            backgroundScheduler: AppIntegrationBackgroundScheduler(),
            registerBackgroundTasks: false
        )
        let user = appIntegrationUser(id: UUID())
        let store = container.makeAppStore(launchUser: user)

        await store.restoreIfNeeded()

        XCTAssertTrue(container.languageStore === languageStore)
        XCTAssertTrue(store.languageStore === languageStore)
        XCTAssertEqual(languageStore.language, .ru)
        XCTAssertEqual(persistence.saved.last, .ru)
        XCTAssertEqual(store.activeRuntime?.lease.accountID, user.id)
    }

    func testRuntimeReminderCompositionUsesSharedStoreAndCurrentLanguageCopy() async throws {
        let languageStore = AppLanguageStore(
            persistence: AppIntegrationLanguagePersistence(initial: .en)
        )
        let notifications = AppIntegrationAuthorizedNotificationCenter()
        let container = DependencyContainer(
            apiBaseURL: appIntegrationAPIURL,
            languageStore: languageStore,
            sessionStore: InMemorySessionStore(),
            databaseOpener: { _ in try AppDatabase.inMemory() },
            networkMonitor: FixedNetworkMonitor(connected: false),
            notificationCenter: notifications,
            fcmTokenProvider: ManualFCMRegistrationTokenProvider(configured: false),
            backgroundScheduler: AppIntegrationBackgroundScheduler(),
            registerBackgroundTasks: false
        )
        let user = appIntegrationUser(id: UUID())
        _ = try await container.activateApplication(for: user, sessionGeneration: 1)
        let runtime = try XCTUnwrap(container.activeRuntime)
        try await seedReminderSettings(runtime: runtime, enabled: true)
        let taskID = try await seedPlanningTask(runtime: runtime, title: "Language task")
        let dueAt = Date().addingTimeInterval(7_200)
        try await runtime.reminderStore.saveDefault(
            DefaultTaskReminder(
                accountID: user.id,
                offsetMinutes: 30,
                repeatRule: .none,
                enabled: true
            )
        )
        _ = try await runtime.resumeNotificationsAfterRuntimeReady(allowNetwork: false)

        try await runtime.reminderWorkflow.apply(
            taskID: taskID,
            title: "Language task",
            dueAt: dueAt,
            mutation: .preserveOrDefault,
            taskState: .active,
            isNewTask: true
        )

        let storedReminders = try await runtime.reminderStore.reminders(accountID: user.id)
        let englishBody = await notifications.solePendingBody()
        XCTAssertEqual(storedReminders.count, 1)
        XCTAssertEqual(englishBody, TaskReminderCopy(language: .en).openTaskBody)

        languageStore.setLanguage(.ru)
        try await runtime.reconcileReminders(reason: .settingsChange)

        let russianBody = await notifications.solePendingBody()
        XCTAssertEqual(russianBody, TaskReminderCopy(language: .ru).openTaskBody)
    }

    func testProductionReminderLifecycleSwitchesAtoBtoAWithoutLeaksOrDuplicates() async throws {
        let notifications = AppIntegrationAuthorizedNotificationCenter()
        let fixture = makePersistentReminderContainer(notifications: notifications)
        let first = appIntegrationUser(id: UUID())
        let second = appIntegrationUser(id: UUID())

        _ = try await fixture.container.activateApplication(for: first, sessionGeneration: 1)
        let firstRuntime = try XCTUnwrap(fixture.container.activeRuntime)
        try await seedReminder(runtime: firstRuntime, title: "Account A")
        let firstResumed = try await firstRuntime.resumeNotificationsAfterRuntimeReady(
            allowNetwork: false
        )
        let firstTitles = await notifications.requestTitles()
        XCTAssertTrue(firstResumed)
        XCTAssertEqual(firstTitles, ["Account A"])

        _ = try await fixture.container.activateApplication(for: second, sessionGeneration: 2)
        let afterFirstSuspension = await notifications.requestTitles()
        XCTAssertEqual(afterFirstSuspension, [])
        let secondRuntime = try XCTUnwrap(fixture.container.activeRuntime)
        try await seedReminder(runtime: secondRuntime, title: "Account B")
        let secondResumed = try await secondRuntime.resumeNotificationsAfterRuntimeReady(
            allowNetwork: false
        )
        let secondTitles = await notifications.requestTitles()
        XCTAssertTrue(secondResumed)
        XCTAssertEqual(secondTitles, ["Account B"])

        _ = try await fixture.container.activateApplication(for: first, sessionGeneration: 3)
        let afterSecondSuspension = await notifications.requestTitles()
        XCTAssertEqual(afterSecondSuspension, [])
        let restoredFirstRuntime = try XCTUnwrap(fixture.container.activeRuntime)
        let restored = try await restoredFirstRuntime.resumeNotificationsAfterRuntimeReady(
            allowNetwork: false
        )
        let restoredTitles = await notifications.requestTitles()
        let restoredDefault = try await restoredFirstRuntime.reminderStore.defaultReminder(
            accountID: first.id
        )
        let restoredRows = try await restoredFirstRuntime.reminderStore.reminders(
            accountID: first.id
        )

        XCTAssertTrue(restored)
        XCTAssertEqual(restoredTitles, ["Account A"])
        XCTAssertEqual(restoredRows.count, 1)
        XCTAssertNotNil(restoredDefault)

        await fixture.container.deactivateApplication()
        try? FileManager.default.removeItem(at: fixture.rootURL)
    }

    func testProductionReminderLogoutErasesRequestsRowsAndDefault() async throws {
        let notifications = AppIntegrationAuthorizedNotificationCenter()
        let fixture = makePersistentReminderContainer(notifications: notifications)
        let user = appIntegrationUser(id: UUID())

        _ = try await fixture.container.activateApplication(for: user, sessionGeneration: 1)
        let runtime = try XCTUnwrap(fixture.container.activeRuntime)
        try await seedReminder(runtime: runtime, title: "Private task")
        _ = try await runtime.resumeNotificationsAfterRuntimeReady(allowNetwork: false)

        try await fixture.container.deactivateApplication(
            for: user.id,
            expectedLease: runtime.lease,
            eraseUserData: true
        )
        let pendingTitles = await notifications.requestTitles()
        let reopened = try fixture.factory.open(userID: user.id)
        let reopenedStore = try GRDBTaskReminderStore(database: reopened, accountID: user.id)
        let rows = try await reopenedStore.reminders(accountID: user.id)
        let defaultReminder = try await reopenedStore.defaultReminder(accountID: user.id)

        XCTAssertEqual(pendingTitles, [])
        XCTAssertEqual(rows, [])
        XCTAssertNil(defaultReminder)

        try? FileManager.default.removeItem(at: fixture.rootURL)
    }

    func testPrivacyEraseSuspendsPrivateTitlesBeforeBlockedDeviceUnregister() async throws {
        let notifications = AppIntegrationAuthorizedNotificationCenter()
        let registration = AppIntegrationBlockingUnregisterService()
        let fixture = makePersistentReminderContainer(
            notifications: notifications,
            deviceRegistrationOverride: registration
        )
        let user = appIntegrationUser(id: UUID())

        _ = try await fixture.container.activateApplication(for: user, sessionGeneration: 1)
        let runtime = try XCTUnwrap(fixture.container.activeRuntime)
        try await seedReminder(runtime: runtime, title: "Private account title")
        _ = try await runtime.resumeNotificationsAfterRuntimeReady(allowNetwork: false)

        let teardown = Task {
            try await fixture.container.deactivateApplication(
                for: user.id,
                expectedLease: runtime.lease,
                eraseUserData: true
            )
        }
        await registration.waitUntilUnregisterStarted()
        let titlesWhileUnregisterBlocked = await notifications.requestTitles()
        let finishedWhileBlocked = await registration.unregisterFinished()

        XCTAssertEqual(titlesWhileUnregisterBlocked, [])
        XCTAssertFalse(finishedWhileBlocked)

        await registration.releaseUnregister()
        try await teardown.value
        let finishedAfterRelease = await registration.unregisterFinished()
        XCTAssertTrue(finishedAfterRelease)

        try? FileManager.default.removeItem(at: fixture.rootURL)
    }

    func testStaleSameAccountRuntimeCannotSuspendNewSessionNotifications() async throws {
        let notifications = AppIntegrationAuthorizedNotificationCenter()
        let fixture = makePersistentReminderContainer(notifications: notifications)
        let user = appIntegrationUser(id: UUID())

        _ = try await fixture.container.activateApplication(for: user, sessionGeneration: 1)
        let staleRuntime = try XCTUnwrap(fixture.container.activeRuntime)
        try await seedReminder(runtime: staleRuntime, title: "Current session")
        _ = try await staleRuntime.resumeNotificationsAfterRuntimeReady(allowNetwork: false)

        _ = try await fixture.container.activateApplication(for: user, sessionGeneration: 2)
        let currentRuntime = try XCTUnwrap(fixture.container.activeRuntime)
        _ = try await currentRuntime.resumeNotificationsAfterRuntimeReady(allowNetwork: false)
        await staleRuntime.suspendNotificationsForDeactivation()

        let titles = await notifications.requestTitles()
        XCTAssertEqual(titles, ["Current session"])
        XCTAssertNotEqual(staleRuntime.lease, currentRuntime.lease)

        await fixture.container.deactivateApplication()
        try? FileManager.default.removeItem(at: fixture.rootURL)
    }

    func testStaleSettingsSaveCannotCommitDefaultAfterSameAccountRelogin() async throws {
        let notifications = AppIntegrationAuthorizedNotificationCenter()
        let fixture = makePersistentReminderContainer(notifications: notifications)
        let user = appIntegrationUser(id: UUID())

        _ = try await fixture.container.activateApplication(for: user, sessionGeneration: 1)
        let staleRuntime = try XCTUnwrap(fixture.container.activeRuntime)
        let delayedRepository = AppIntegrationDelayedSettingsSaveRepository()
        let guardedRepository = AppRuntimeSettingsRepository(
            base: delayedRepository,
            lease: staleRuntime.lease,
            relay: AppUnauthorizedRelay(),
            operationGate: staleRuntime.operationGate,
            acceptedSaveCommit: {
                try await staleRuntime.settingsReminderStore.commitStagedDefaultWithinLease()
            }
        )
        let model = makeRuntimeSettingsViewModel(
            runtime: staleRuntime,
            repository: guardedRepository,
            notificationCenter: notifications
        )
        model.defaultReminderEnabled = true
        model.defaultOffsetMinutes = 45

        let staleSave = Task { await model.save() }
        await delayedRepository.waitUntilSaveStarted()
        _ = try await fixture.container.activateApplication(for: user, sessionGeneration: 2)
        let didSave = await staleSave.value
        let currentRuntime = try XCTUnwrap(fixture.container.activeRuntime)
        let durableDefault = try await currentRuntime.reminderStore.defaultReminder(
            accountID: user.id
        )
        let delayedState = await delayedRepository.state()

        XCTAssertFalse(didSave)
        XCTAssertNil(durableDefault)
        XCTAssertTrue(delayedState.cancelled)
        XCTAssertFalse(delayedState.completed)

        await fixture.container.deactivateApplication()
        try? FileManager.default.removeItem(at: fixture.rootURL)
    }

    func testAcceptedSettingsDefaultCommitBlocksLeaseDeactivationUntilDurableWriteFinishes() async throws {
        let accountID = UUID()
        let lease = AppRuntimeLease(accountID: accountID, sessionGeneration: 21)
        let validity = AppRuntimeValidity(lease: lease)
        let gate = AppRuntimeOperationGate(lease: lease)
        let baseStore = AppIntegrationControlledDefaultStore(mode: .blocking)
        let guardedStore = AppRuntimeTaskReminderStore(
            base: baseStore,
            accountID: accountID,
            lease: lease,
            validity: validity,
            operationGate: gate
        )
        let settingsStore = AppRuntimeSettingsReminderStore(direct: guardedStore)
        let desiredDefault = DefaultTaskReminder(
            accountID: accountID,
            offsetMinutes: 75,
            repeatRule: .weekly,
            enabled: true
        )
        try await settingsStore.saveDefault(desiredDefault)
        let repository = AppRuntimeSettingsRepository(
            base: AppIntegrationAcceptedSettingsRepository(),
            lease: lease,
            relay: AppUnauthorizedRelay(),
            operationGate: gate,
            acceptedSaveCommit: {
                try await settingsStore.commitStagedDefaultWithinLease()
            }
        )

        let save = Task {
            try await repository.save(
                accountID: accountID,
                language: .en,
                notificationsEnabled: true
            )
        }
        await baseStore.waitUntilDefaultCommitStarted()
        let teardownRecorder = AppIntegrationStringRecorder()
        let teardown = Task {
            await gate.invalidateCancelAndWait(for: lease)
            await teardownRecorder.record("finished")
        }
        await baseStore.waitUntilCommitCancellationObserved()

        let stagesWhileCommitBlocked = await teardownRecorder.values()
        XCTAssertTrue(stagesWhileCommitBlocked.isEmpty)

        await baseStore.releaseDefaultCommit()
        await teardown.value
        await assertCancelled(save)
        let durableDefault = try await baseStore.defaultReminder(accountID: accountID)
        let completedStages = await teardownRecorder.values()

        XCTAssertEqual(completedStages, ["finished"])
        XCTAssertEqual(durableDefault, desiredDefault)
    }

    func testAcceptedSettingsDefaultCommitFailureIsVisibleAndDoesNotSuspendNotifications() async throws {
        let accountID = UUID()
        let lease = AppRuntimeLease(accountID: accountID, sessionGeneration: 22)
        let validity = AppRuntimeValidity(lease: lease)
        let gate = AppRuntimeOperationGate(lease: lease)
        let baseStore = AppIntegrationControlledDefaultStore(mode: .failing)
        let guardedStore = AppRuntimeTaskReminderStore(
            base: baseStore,
            accountID: accountID,
            lease: lease,
            validity: validity,
            operationGate: gate
        )
        let settingsStore = AppRuntimeSettingsReminderStore(direct: guardedStore)
        let acceptedRepository = AppIntegrationAcceptedSettingsRepository()
        let repository = AppRuntimeSettingsRepository(
            base: acceptedRepository,
            lease: lease,
            relay: AppUnauthorizedRelay(),
            operationGate: gate,
            acceptedSaveCommit: {
                try await settingsStore.commitStagedDefaultWithinLease()
            }
        )
        try await settingsStore.saveDefault(DefaultTaskReminder(
            accountID: accountID,
            offsetMinutes: 30,
            repeatRule: .none,
            enabled: true
        ))
        do {
            _ = try await repository.save(
                accountID: accountID,
                language: .en,
                notificationsEnabled: false
            )
            XCTFail("Expected typed default commit failure")
        } catch let error as AppRuntimeSettingsTransactionError {
            XCTAssertEqual(error, .defaultCommitFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let cleaner = AppIntegrationNotificationCleanerRecorder()
        let model = SettingsViewModel(
            accountID: accountID,
            initialLanguage: .en,
            repository: repository,
            notificationCenter: AppIntegrationAuthorizedNotificationCenter(),
            reminderStore: settingsStore,
            registration: AppIntegrationDelayedDeviceRegistrationService(),
            notificationCleaner: cleaner,
            deviceName: "Test iPhone",
            onOpenFocusCadence: {}
        )
        model.defaultReminderEnabled = true
        model.defaultOffsetMinutes = 45
        model.notificationsEnabled = false

        let saved = await model.save()
        let durableDefault = try await baseStore.defaultReminder(accountID: accountID)
        let acceptedSaveCount = await acceptedRepository.saveCount()
        let suspendedAccounts = await cleaner.suspendedAccounts()

        XCTAssertFalse(saved)
        XCTAssertEqual(model.phase, .error)
        XCTAssertEqual(model.failure?.code, "settings_unavailable")
        XCTAssertEqual(acceptedSaveCount, 2)
        XCTAssertNil(durableDefault)
        XCTAssertTrue(suspendedAccounts.isEmpty)
    }

    func testStaleSettingsDeviceSyncIsCancelledBeforeSameAccountRuntimeReplacement() async throws {
        let notifications = AppIntegrationAuthorizedNotificationCenter()
        let registration = AppIntegrationDelayedDeviceRegistrationService()
        let fixture = makePersistentReminderContainer(
            notifications: notifications,
            deviceRegistrationOverride: registration
        )
        let user = appIntegrationUser(id: UUID())

        _ = try await fixture.container.activateApplication(for: user, sessionGeneration: 1)
        let staleRuntime = try XCTUnwrap(fixture.container.activeRuntime)
        let model = makeRuntimeSettingsViewModel(
            runtime: staleRuntime,
            repository: staleRuntime.settingsActions,
            notificationCenter: notifications
        )

        let staleSync = Task { await model.syncDeviceRegistration() }
        await registration.waitUntilSyncStarted()
        _ = try await fixture.container.activateApplication(for: user, sessionGeneration: 2)
        await staleSync.value
        let state = await registration.stateSnapshot()

        XCTAssertTrue(state.cancelled)
        XCTAssertFalse(state.completed)
        XCTAssertEqual(state.unregisterCount, 0)

        await fixture.container.deactivateApplication()
        try? FileManager.default.removeItem(at: fixture.rootURL)
    }

    func testDelayedStaleNotificationToggleCannotRemoveNewSameAccountRequest() async throws {
        let notifications = AppIntegrationAuthorizedNotificationCenter()
        let fixture = makePersistentReminderContainer(notifications: notifications)
        let user = appIntegrationUser(id: UUID())

        _ = try await fixture.container.activateApplication(for: user, sessionGeneration: 1)
        let staleRuntime = try XCTUnwrap(fixture.container.activeRuntime)
        try await seedReminder(runtime: staleRuntime, title: "Same account task")
        _ = try await staleRuntime.resumeNotificationsAfterRuntimeReady(allowNetwork: false)
        await notifications.delayNextRemoval()

        let staleToggle = Task {
            await staleRuntime.notificationActions.suspendNotifications(accountID: user.id)
        }
        await notifications.waitUntilDelayedRemovalStarted()
        _ = try await fixture.container.activateApplication(for: user, sessionGeneration: 2)
        let currentRuntime = try XCTUnwrap(fixture.container.activeRuntime)
        _ = try await currentRuntime.resumeNotificationsAfterRuntimeReady(allowNetwork: false)
        await staleToggle.value

        let titles = await notifications.requestTitles()
        let cancelledRemovals = await notifications.cancelledDelayedRemovalCount()
        XCTAssertEqual(titles, ["Same account task"])
        XCTAssertEqual(cancelledRemovals, 1)

        await fixture.container.deactivateApplication()
        try? FileManager.default.removeItem(at: fixture.rootURL)
    }

    func testProductionSettingsNotificationControllerPreservesDefaultAcrossToggle() async throws {
        let notifications = AppIntegrationAuthorizedNotificationCenter()
        let fixture = makePersistentReminderContainer(notifications: notifications)
        let user = appIntegrationUser(id: UUID())

        _ = try await fixture.container.activateApplication(for: user, sessionGeneration: 1)
        let runtime = try XCTUnwrap(fixture.container.activeRuntime)
        try await seedReminder(runtime: runtime, title: "Settings task")
        _ = try await runtime.resumeNotificationsAfterRuntimeReady(allowNetwork: false)
        let acceptedDefault = DefaultTaskReminder(
            accountID: user.id,
            offsetMinutes: 75,
            repeatRule: .daily,
            enabled: true
        )
        try await runtime.settingsReminderStore.saveDefault(acceptedDefault)
        let acceptedRepository = AppRuntimeSettingsRepository(
            base: AppIntegrationAcceptedSettingsRepository(),
            lease: runtime.lease,
            relay: AppUnauthorizedRelay(),
            operationGate: runtime.operationGate,
            acceptedSaveCommit: {
                try await runtime.settingsReminderStore.commitStagedDefaultWithinLease()
            }
        )
        _ = try await acceptedRepository.save(
            accountID: user.id,
            language: .en,
            notificationsEnabled: false
        )

        try await seedReminderSettings(runtime: runtime, enabled: false)
        await runtime.notificationActions.suspendNotifications(accountID: user.id)
        let disabledResume = try await runtime.resumeNotificationsAfterRuntimeReady(
            allowNetwork: false
        )
        let suspendedTitles = await notifications.requestTitles()
        let suspendedRows = try await runtime.reminderStore.reminders(accountID: user.id)
        let suspendedDefault = try await runtime.reminderStore.defaultReminder(accountID: user.id)

        try await seedReminderSettings(runtime: runtime, enabled: true)
        try await runtime.notificationActions.resumeNotifications(
            accountID: user.id,
            timeZone: TimeZone(identifier: user.timezone)!
        )
        let resumedTitles = await notifications.requestTitles()
        let resumedRows = try await runtime.reminderStore.reminders(accountID: user.id)
        let resumedDefault = try await runtime.reminderStore.defaultReminder(accountID: user.id)

        XCTAssertFalse(disabledResume)
        XCTAssertEqual(suspendedTitles, [])
        XCTAssertEqual(suspendedRows.count, 1)
        XCTAssertEqual(suspendedDefault, acceptedDefault)
        XCTAssertEqual(resumedTitles, ["Settings task"])
        XCTAssertEqual(resumedRows, suspendedRows)
        XCTAssertEqual(resumedDefault, suspendedDefault)

        await fixture.container.deactivateApplication()
        try? FileManager.default.removeItem(at: fixture.rootURL)
    }

    func testAppStoreRestoresTabAndCalendarThenLogoutClearsScopedSession() async throws {
        let accountID = UUID()
        let suiteName = "AppStoreRestoration-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let restoration = AppRestorationUserDefaultsStore(
            defaults: defaults,
            keyPrefix: "app-store-composition"
        )
        let seedLease = UUID()
        _ = restoration.acquireLease(accountID: accountID, leaseID: seedLease)
        var navigation = AppNavigationState()
        navigation.select(.calendar)
        let calendar = CalendarRestorationState(
            timezoneIdentifier: "Europe/Moscow",
            visibleMonth: CalendarMonth(year: 2026, month: 8),
            selectedDate: LocalDate(rawValue: "2026-08-23")!
        )
        XCTAssertTrue(
            restoration.save(
                AppRestorationSnapshot(
                    accountID: accountID,
                    navigation: AppNavigationRestorationState(navigation: navigation),
                    calendar: calendar
                ),
                leaseID: seedLease
            )
        )
        let container = makeContainer()
        let store = container.makeAppStore(
            launchUser: appIntegrationUser(id: accountID),
            restorationPersistence: restoration
        )

        await store.restoreIfNeeded()

        XCTAssertEqual(store.navigation.selectedTab, .calendar)
        XCTAssertEqual(store.restoredCalendarState, calendar)
        await store.logout()
        XCTAssertEqual(restoration.load(accountID: accountID), .missing)
        XCTAssertNil(store.restoredCalendarState)
    }

    func testNewestWarmDeepLinkWinsAfterRuntimeRestoration() async {
        let container = makeContainer()
        let store = container.makeAppStore(launchUser: appIntegrationUser(id: UUID()))
        await store.restoreIfNeeded()
        let missingTaskID = UUID()

        await store.receiveDeepLink(URL(string: "rocketflow://focus")!)
        XCTAssertEqual(store.navigation.selectedTab, .focus)

        await store.receiveDeepLink(
            URL(string: "rocketflow://task/\(missingTaskID.uuidString)")!
        )

        XCTAssertEqual(store.navigation.selectedTab, .planner)
        XCTAssertEqual(store.navigation.plannerPath, [])
    }

    func testBlockedOldTaskMappingCannotOverwriteNewerWarmFocusLink() async throws {
        let container = makeContainer()
        let resolver = AppIntegrationBlockingDeepLinkLocalIDResolver()
        let user = appIntegrationUser(id: UUID())
        let store = AppStore(
            authSession: container.authSession,
            dependencies: container,
            launchUser: user,
            languageStore: container.languageStore,
            deepLinkLocalIDResolver: { taskID in
                await resolver.resolve(taskID)
            }
        )
        await store.restoreIfNeeded()
        let runtime = try XCTUnwrap(store.activeRuntime)
        let taskID = try await seedPlanningTask(runtime: runtime, title: "Older task link")
        let oldTaskLink = Task {
            await store.receiveDeepLink(
                URL(string: "rocketflow://task/\(taskID.uuidString)")!
            )
        }
        await resolver.waitUntilResolutionStarted()

        await store.receiveDeepLink(URL(string: "rocketflow://focus")!)
        XCTAssertEqual(store.navigation.selectedTab, .focus)

        await resolver.release()
        await oldTaskLink.value

        XCTAssertEqual(store.navigation.selectedTab, .focus)
        XCTAssertEqual(store.navigation.focusPath, [])
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
            languageStore: AppLanguageStore(
                persistence: AppIntegrationLanguagePersistence(initial: .en)
            ),
            sessionStore: InMemorySessionStore(),
            databaseOpener: { _ in try AppDatabase.inMemory() },
            networkMonitor: FixedNetworkMonitor(connected: false),
            notificationCenter: AppUITestNotificationCenter(),
            fcmTokenProvider: ManualFCMRegistrationTokenProvider(configured: false),
            backgroundScheduler: AppIntegrationBackgroundScheduler(),
            registerBackgroundTasks: false
        )
    }

    private func makePersistentReminderContainer(
        notifications: AppIntegrationAuthorizedNotificationCenter,
        deviceRegistrationOverride: (any DeviceRegistrationServicing)? = nil
    ) -> (container: DependencyContainer, factory: AppDatabaseFactory, rootURL: URL) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RocketFlowReminderLifecycle-\(UUID())", isDirectory: true)
        let factory = AppDatabaseFactory(rootURL: rootURL)
        let container = DependencyContainer(
            apiBaseURL: appIntegrationAPIURL,
            languageStore: AppLanguageStore(
                persistence: AppIntegrationLanguagePersistence(initial: .en)
            ),
            sessionStore: InMemorySessionStore(),
            databaseFactory: factory,
            networkMonitor: FixedNetworkMonitor(connected: false),
            notificationCenter: notifications,
            fcmTokenProvider: ManualFCMRegistrationTokenProvider(configured: false),
            deviceRegistrationOverride: deviceRegistrationOverride,
            backgroundScheduler: AppIntegrationBackgroundScheduler(),
            registerBackgroundTasks: false
        )
        return (container, factory, rootURL)
    }

    private func makeRuntimeSettingsViewModel(
        runtime: AppUserRuntime,
        repository: any SettingsRepositoryServing,
        notificationCenter: any UserNotificationCenterServing
    ) -> SettingsViewModel {
        SettingsViewModel(
            accountID: runtime.user.id,
            initialLanguage: .en,
            repository: repository,
            notificationCenter: notificationCenter,
            reminderStore: runtime.settingsReminderStore,
            registration: runtime.deviceRegistration,
            notificationCleaner: runtime.notificationActions,
            deviceName: "Test iPhone",
            reminderTimeZone: TimeZone(identifier: runtime.user.timezone)!,
            onOpenFocusCadence: {}
        )
    }

    private func seedReminder(
        runtime: AppUserRuntime,
        title: String
    ) async throws {
        try await seedReminderSettings(runtime: runtime, enabled: true)
        let taskID = try await seedPlanningTask(runtime: runtime, title: title)
        try await runtime.reminderStore.saveDefault(
            DefaultTaskReminder(
                accountID: runtime.user.id,
                offsetMinutes: 30,
                repeatRule: .none,
                enabled: true
            )
        )
        try await runtime.reminderStore.save(
            LocalTaskReminder(
                id: UUID(),
                accountID: runtime.user.id,
                taskID: taskID,
                taskTitle: title,
                triggerAt: Date().addingTimeInterval(7_200),
                repeatRule: .none
            ),
            taskState: .active
        )
    }

    private func seedReminderSettings(
        runtime: AppUserRuntime,
        enabled: Bool
    ) async throws {
        try await runtime.settingsCache.save(
            UserSettingsDTO(
                language: .en,
                greenPriorityDecayPolicy: nil,
                redPriorityDecayPolicy: nil,
                notificationsEnabled: enabled,
                version: 1
            ),
            accountID: runtime.user.id
        )
    }

    private func seedPlanningTask(
        runtime: AppUserRuntime,
        title: String
    ) async throws -> UUID {
        let folder = try await runtime.planningRepository.createFolder(
            FolderDraft(name: "Reminder folder \(UUID())")
        )
        let goal = try await runtime.planningRepository.createGoal(
            GoalDraft(folderID: folder.id, name: "Reminder goal")
        )
        let taskID = UUID()
        _ = try await runtime.planningRepository.createTask(
            TaskDraft(id: taskID, goalID: goal.id, title: title)
        )
        return taskID
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

private final class AppIntegrationLanguagePersistence: AppLanguagePersisting {
    private(set) var saved: [AppLanguage] = []
    private var value: AppLanguage?

    init(initial: AppLanguage?) {
        value = initial
    }

    func loadLanguage() -> AppLanguage? { value }

    func saveLanguage(_ language: AppLanguage) {
        value = language
        saved.append(language)
    }
}

private actor AppIntegrationAuthorizedNotificationCenter: UserNotificationCenterServing {
    private var requests: [String: UserNotificationRequestValue] = [:]
    private var shouldDelayNextRemoval = false
    private var delayedRemovalStarted = false
    private var delayedRemovalWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelledDelayedRemovals = 0

    func authorizationState() async -> NotificationAuthorizationState { .authorized }
    func requestAuthorization() async -> Bool { true }
    func pendingIdentifiers() async -> Set<String> { Set(requests.keys) }
    func add(_ request: UserNotificationRequestValue) async {
        requests[request.identifier] = request
    }
    func remove(identifiers: [String]) async {
        if shouldDelayNextRemoval {
            shouldDelayNextRemoval = false
            delayedRemovalStarted = true
            let waiters = delayedRemovalWaiters
            delayedRemovalWaiters.removeAll()
            waiters.forEach { $0.resume() }
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                cancelledDelayedRemovals += 1
                return
            }
        }
        identifiers.forEach { requests.removeValue(forKey: $0) }
    }
    func solePendingBody() -> String? {
        guard requests.count == 1 else { return nil }
        return requests.values.first?.body
    }
    func requestTitles() -> [String] {
        requests.values.map(\.title).sorted()
    }

    func delayNextRemoval() {
        shouldDelayNextRemoval = true
        delayedRemovalStarted = false
    }

    func waitUntilDelayedRemovalStarted() async {
        guard !delayedRemovalStarted else { return }
        await withCheckedContinuation { continuation in
            delayedRemovalWaiters.append(continuation)
        }
    }

    func cancelledDelayedRemovalCount() -> Int { cancelledDelayedRemovals }
}

private actor AppIntegrationBlockingUnregisterService: DeviceRegistrationServicing {
    private var unregisterContinuation: CheckedContinuation<DeviceRegistrationSyncResult, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var started = false
    private var finished = false

    func state(accountID: UUID) async -> DeviceRegistrationDisplayState { .unregistered }

    func sync(accountID: UUID, deviceName: String?) async throws -> DeviceRegistrationSyncResult {
        .tokenUnavailable
    }

    func unregister(accountID: UUID) async throws -> DeviceRegistrationSyncResult {
        let result: DeviceRegistrationSyncResult = await withCheckedContinuation {
            (continuation: CheckedContinuation<DeviceRegistrationSyncResult, Never>) in
            unregisterContinuation = continuation
            started = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        finished = true
        return result
    }

    func waitUntilUnregisterStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseUnregister() {
        let continuation = unregisterContinuation
        unregisterContinuation = nil
        continuation?.resume(returning: .unregistered)
    }

    func unregisterFinished() -> Bool { finished }
}

private actor AppIntegrationDelayedDeviceRegistrationService: DeviceRegistrationServicing {
    struct State: Sendable {
        let completed: Bool
        let cancelled: Bool
        let unregisterCount: Int
    }

    private var syncStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completed = false
    private var cancelled = false
    private var unregisterCount = 0

    func state(accountID: UUID) async -> DeviceRegistrationDisplayState { .unregistered }

    func sync(accountID: UUID, deviceName: String?) async throws -> DeviceRegistrationSyncResult {
        syncStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            try Task.checkCancellation()
            completed = true
            return .tokenUnavailable
        } catch {
            cancelled = true
            throw error
        }
    }

    func unregister(accountID: UUID) async throws -> DeviceRegistrationSyncResult {
        unregisterCount += 1
        return .unregistered
    }

    func waitUntilSyncStarted() async {
        guard !syncStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func stateSnapshot() -> State {
        State(
            completed: completed,
            cancelled: cancelled,
            unregisterCount: unregisterCount
        )
    }
}

private actor AppIntegrationDelayedSettingsSaveRepository: SettingsRepositoryServing {
    struct State: Sendable {
        let completed: Bool
        let cancelled: Bool
    }

    private var saveStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completed = false
    private var cancelled = false

    func load(accountID: UUID) async throws -> SettingsRepositorySnapshot {
        snapshot(notificationsEnabled: false)
    }

    func save(
        accountID: UUID,
        language: AppLanguage,
        notificationsEnabled: Bool
    ) async throws -> SettingsRepositorySnapshot {
        saveStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            try Task.checkCancellation()
            completed = true
            return snapshot(notificationsEnabled: notificationsEnabled)
        } catch {
            cancelled = true
            throw error
        }
    }

    func retry(accountID: UUID) async throws -> SettingsRepositorySnapshot {
        snapshot(notificationsEnabled: false)
    }

    func waitUntilSaveStarted() async {
        guard !saveStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func state() -> State { State(completed: completed, cancelled: cancelled) }

    private func snapshot(notificationsEnabled: Bool) -> SettingsRepositorySnapshot {
        SettingsRepositorySnapshot(
            settings: UserSettingsDTO(
                language: .en,
                greenPriorityDecayPolicy: nil,
                redPriorityDecayPolicy: nil,
                notificationsEnabled: notificationsEnabled,
                version: 1
            ),
            source: .network,
            pending: false,
            failure: nil
        )
    }
}

private actor AppIntegrationAcceptedSettingsRepository: SettingsRepositoryServing {
    private var saves = 0

    func load(accountID: UUID) async throws -> SettingsRepositorySnapshot {
        snapshot(language: .en, notificationsEnabled: true)
    }

    func save(
        accountID: UUID,
        language: AppLanguage,
        notificationsEnabled: Bool
    ) async throws -> SettingsRepositorySnapshot {
        saves += 1
        return snapshot(language: language, notificationsEnabled: notificationsEnabled)
    }

    func retry(accountID: UUID) async throws -> SettingsRepositorySnapshot {
        snapshot(language: .en, notificationsEnabled: true)
    }

    func saveCount() -> Int { saves }

    private func snapshot(
        language: AppLanguage,
        notificationsEnabled: Bool
    ) -> SettingsRepositorySnapshot {
        SettingsRepositorySnapshot(
            settings: UserSettingsDTO(
                language: language,
                greenPriorityDecayPolicy: nil,
                redPriorityDecayPolicy: nil,
                notificationsEnabled: notificationsEnabled,
                version: 1
            ),
            source: .network,
            pending: false,
            failure: nil
        )
    }
}

private actor AppIntegrationControlledDefaultStore: TaskReminderStoreServing {
    enum Mode: Sendable {
        case immediate
        case blocking
        case failing
    }

    private let mode: Mode
    private let backing = InMemoryTaskReminderStore()
    private let cancellationEvents: AsyncStream<Void>
    private let cancellationContinuation: AsyncStream<Void>.Continuation
    private var commitStarted = false
    private var commitStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var commitRelease: CheckedContinuation<Void, Never>?

    init(mode: Mode) {
        self.mode = mode
        let channel = AsyncStream<Void>.makeStream()
        cancellationEvents = channel.stream
        cancellationContinuation = channel.continuation
    }

    func reconciliationItems(accountID: UUID) async throws -> [TaskReminderReconciliationItem] {
        await backing.reconciliationItems(accountID: accountID)
    }

    func reminders(accountID: UUID) async throws -> [LocalTaskReminder] {
        await backing.reminders(accountID: accountID)
    }

    func save(_ reminder: LocalTaskReminder, taskState: ReminderTaskState) async throws {
        await backing.save(reminder, taskState: taskState)
    }

    func remove(accountID: UUID, taskID: UUID, reminderID: UUID) async throws {
        await backing.remove(accountID: accountID, taskID: taskID, reminderID: reminderID)
    }

    func defaultReminder(accountID: UUID) async throws -> DefaultTaskReminder? {
        await backing.defaultReminder(accountID: accountID)
    }

    func saveDefault(_ reminder: DefaultTaskReminder) async throws {
        switch mode {
        case .immediate:
            break
        case .failing:
            throw AppIntegrationExpectedError.failure
        case .blocking:
            commitStarted = true
            let waiters = commitStartWaiters
            commitStartWaiters.removeAll()
            waiters.forEach { $0.resume() }
            let cancellationContinuation = self.cancellationContinuation
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    commitRelease = continuation
                }
            } onCancel: {
                cancellationContinuation.yield(())
            }
        }
        await backing.saveDefault(reminder)
    }

    func clearDefault(accountID: UUID) async throws {
        await backing.clearDefault(accountID: accountID)
    }

    func clear(accountID: UUID) async throws {
        try await backing.clear(accountID: accountID)
    }

    func waitUntilDefaultCommitStarted() async {
        guard !commitStarted else { return }
        await withCheckedContinuation { continuation in
            commitStartWaiters.append(continuation)
        }
    }

    func waitUntilCommitCancellationObserved() async {
        for await _ in cancellationEvents { return }
    }

    func releaseDefaultCommit() {
        let continuation = commitRelease
        commitRelease = nil
        continuation?.resume()
    }
}

private actor AppIntegrationNotificationCleanerRecorder: AccountNotificationClearing {
    private var suspended: [UUID] = []

    func clear(accountID: UUID) async throws {}

    func suspendNotifications(accountID: UUID) async {
        suspended.append(accountID)
    }

    func resumeNotifications(accountID: UUID, timeZone: TimeZone) async throws {}

    func suspendedAccounts() -> [UUID] { suspended }
}

private actor AppIntegrationBlockingDeepLinkLocalIDResolver {
    private var resolutionStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func resolve(_ taskID: UUID) async -> UUID? {
        resolutionStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return taskID
    }

    func waitUntilResolutionStarted() async {
        guard !resolutionStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        let continuation = releaseContinuation
        releaseContinuation = nil
        continuation?.resume()
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
