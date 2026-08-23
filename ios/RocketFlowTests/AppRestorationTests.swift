import Foundation
import XCTest
@testable import RocketFlow

final class AppRestorationTests: XCTestCase {
    private let accountID = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!
    private let otherAccountID = UUID(uuidString: "70000000-0000-0000-0000-000000000002")!
    private let taskID = UUID(uuidString: "70000000-0000-0000-0000-000000000010")!
    private let newerTaskID = UUID(uuidString: "70000000-0000-0000-0000-000000000011")!

    func testKillAndRecreateRestoresFocusTaskOriginAndCalendarState() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let session = AppRestorationSession(accountID: accountID, persistence: fixture.store)
        var navigation = AppNavigationState()
        navigation.installRestorationMutationHandler(session.navigationMutationHandler())

        navigation.open(
            DetailEntityReference(kind: .task, id: taskID),
            origin: .focus
        )
        let calendar = CalendarRestorationState(
            timezoneIdentifier: "Europe/Moscow",
            visibleMonth: CalendarMonth(year: 2026, month: 11),
            selectedDate: LocalDate(rawValue: "2026-11-17")!
        )
        session.calendarMutationHandler()(calendar)

        let recreated = AppRestorationSession(accountID: accountID, persistence: fixture.store)
        let activation = await recreated.restore(
            accountTimezone: "Europe/Moscow",
            routeValidator: allowingRoutes(for: accountID)
        )

        XCTAssertEqual(activation.source, .restored)
        XCTAssertTrue(activation.shouldApplyToRuntime)
        XCTAssertTrue(recreated.canApply(activation))
        XCTAssertEqual(activation.navigation.selectedTab, .focus)
        XCTAssertEqual(
            activation.navigation.focusPath,
            [.detail(DetailEntityReference(kind: .task, id: taskID), origin: .focus)]
        )
        XCTAssertEqual(activation.calendar, calendar)
        XCTAssertNil(activation.navigation.presentation)
        XCTAssertNil(activation.navigation.notice)
    }

    func testEveryTopLevelRootRestoresWithoutRouteLookup() async {
        for tab in AppTab.allCases {
            let fixture = makeFixture()
            defer { fixture.cleanUp() }
            let session = AppRestorationSession(accountID: accountID, persistence: fixture.store)
            var navigation = AppNavigationState()
            navigation.installRestorationMutationHandler(session.navigationMutationHandler())
            navigation.select(tab)

            let activation = await AppRestorationSession(
                accountID: accountID,
                persistence: fixture.store
            ).restore(
                accountTimezone: "Europe/Moscow",
                routeValidator: AppRestorationRouteValidator { _, _ in
                    XCTFail("Top-level restoration must not perform an entity lookup")
                    return false
                }
            )

            XCTAssertEqual(activation.navigation.selectedTab, tab)
            XCTAssertTrue(activation.navigation.path(for: tab).isEmpty)
        }
    }

    func testUnavailableTaskFallsBackToRecordedCalendarOrigin() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let session = AppRestorationSession(accountID: accountID, persistence: fixture.store)
        var navigation = AppNavigationState()
        navigation.installRestorationMutationHandler(session.navigationMutationHandler())
        navigation.open(
            DetailEntityReference(kind: .task, id: taskID),
            origin: .calendar
        )

        let activation = await AppRestorationSession(
            accountID: accountID,
            persistence: fixture.store
        ).restore(
            accountTimezone: "Europe/Moscow",
            routeValidator: AppRestorationRouteValidator { _, _ in false }
        )

        XCTAssertEqual(activation.navigation.selectedTab, .calendar)
        XCTAssertTrue(activation.navigation.calendarPath.isEmpty)
        XCTAssertEqual(
            fixture.store.load(accountID: accountID),
            .loaded(
                AppRestorationSnapshot(
                    accountID: accountID,
                    navigation: AppNavigationRestorationState(navigation: activation.navigation),
                    calendar: nil
                )
            )
        )
    }

    func testSnapshotKeepsTypedPathsAndEveryTaskOrigin() {
        var navigation = AppNavigationState()
        navigation.setPath(
            [.detail(DetailEntityReference(kind: .goal, id: UUID()), origin: .home)],
            for: .planner
        )
        navigation.setPath(
            [.detail(DetailEntityReference(kind: .task, id: taskID), origin: .calendar)],
            for: .calendar
        )
        navigation.setPath(
            [.detail(DetailEntityReference(kind: .task, id: taskID), origin: .focus)],
            for: .focus
        )
        navigation.select(.focus)

        let snapshot = AppNavigationRestorationState(navigation: navigation)

        XCTAssertEqual(snapshot.selectedTab, .focus)
        XCTAssertEqual(
            snapshot.calendarPath,
            [.detail(DetailEntityReference(kind: .task, id: taskID), origin: .calendar)]
        )
        XCTAssertEqual(
            snapshot.focusPath,
            [.detail(DetailEntityReference(kind: .task, id: taskID), origin: .focus)]
        )
        XCTAssertEqual(snapshot.plannerPath.first?.appRoute, navigation.plannerPath.first)
    }

    func testUnsupportedDestinationsRestoreTheirRecordedSafeRoot() async {
        let cases: [(AppRestorableRoute, AppTab)] = [
            (
                .detail(
                    DetailEntityReference(kind: .goal, id: taskID),
                    origin: .focus
                ),
                .focus
            ),
            (.settings, .planner),
            (
                .links(
                    DetailEntityReference(kind: .task, id: taskID),
                    origin: .calendar
                ),
                .calendar
            )
        ]
        for (destination, expectedTab) in cases {
            let fixture = makeFixture()
            defer { fixture.cleanUp() }
            var navigation = AppNavigationState()
            switch destination {
            case let .detail(reference, origin): navigation.open(reference, origin: origin)
            case .settings: navigation.openSettings()
            case let .links(reference, origin): navigation.openLinks(reference, origin: origin)
            }
            fixture.seed(
                AppRestorationSnapshot(
                    accountID: accountID,
                    navigation: AppNavigationRestorationState(navigation: navigation),
                    calendar: nil
                )
            )

            let activation = await AppRestorationSession(
                accountID: accountID,
                persistence: fixture.store
            ).restore(
                accountTimezone: "Europe/Moscow",
                routeValidator: AppRestorationRouteValidator { _, _ in
                    XCTFail("Unsupported destinations must fall back without a lookup")
                    return false
                }
            )

            XCTAssertEqual(
                activation.navigation,
                AppNavigationState(selectedTab: expectedTab)
            )
        }
    }

    func testDeepLinkedTaskSurvivesRecreateWithRequestedOrigin() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let session = AppRestorationSession(accountID: accountID, persistence: fixture.store)
        var navigation = AppNavigationState()
        navigation.installRestorationMutationHandler(session.navigationMutationHandler())
        navigation.applyDeepLink(
            DeepLinkResolution(
                destination: .task(taskID: UUID(), origin: .focus),
                errorMessage: nil
            ),
            localTaskID: taskID
        )

        let activation = await AppRestorationSession(
            accountID: accountID,
            persistence: fixture.store
        ).restore(
            accountTimezone: "Europe/Moscow",
            routeValidator: allowingRoutes(for: accountID)
        )

        XCTAssertEqual(activation.navigation.selectedTab, .focus)
        XCTAssertEqual(
            activation.navigation.focusPath,
            [.detail(DetailEntityReference(kind: .task, id: taskID), origin: .focus)]
        )
    }

    func testWarmDeepLinkSupersedesSlowColdRestoreAndBecomesDurable() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        var coldNavigation = AppNavigationState()
        coldNavigation.open(
            DetailEntityReference(kind: .task, id: taskID),
            origin: .focus
        )
        fixture.seed(
            AppRestorationSnapshot(
                accountID: accountID,
                navigation: AppNavigationRestorationState(navigation: coldNavigation),
                calendar: nil
            )
        )
        let session = AppRestorationSession(accountID: accountID, persistence: fixture.store)
        let gate = AppRestorationValidationGate()
        let coldRestore = Task {
            await session.restore(
                accountTimezone: "Europe/Moscow",
                routeValidator: AppRestorationRouteValidator { _, _ in
                    await gate.wait()
                    return true
                }
            )
        }
        await gate.waitUntilEntered()

        var warmNavigation = AppNavigationState()
        warmNavigation.installRestorationMutationHandler(session.navigationMutationHandler())
        warmNavigation.applyDeepLink(
            DeepLinkResolution(
                destination: .task(taskID: UUID(), origin: .calendar),
                errorMessage: nil
            ),
            localTaskID: newerTaskID
        )
        await gate.release()

        let activation = await coldRestore.value
        XCTAssertEqual(activation.source, .superseded)
        XCTAssertFalse(activation.shouldApplyToRuntime)
        XCTAssertFalse(session.canApply(activation))
        XCTAssertEqual(activation.navigation.selectedTab, .calendar)
        XCTAssertEqual(
            activation.navigation.calendarPath,
            [.detail(DetailEntityReference(kind: .task, id: newerTaskID), origin: .calendar)]
        )

        let recreated = await AppRestorationSession(
            accountID: accountID,
            persistence: fixture.store
        ).restore(
            accountTimezone: "Europe/Moscow",
            routeValidator: allowingRoutes(for: accountID)
        )
        XCTAssertEqual(recreated.navigation, activation.navigation)
    }

    func testCalendarMutationDuringSlowRestoreWinsRevisionRace() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        var coldNavigation = AppNavigationState()
        coldNavigation.open(
            DetailEntityReference(kind: .task, id: taskID),
            origin: .focus
        )
        fixture.seed(
            AppRestorationSnapshot(
                accountID: accountID,
                navigation: AppNavigationRestorationState(navigation: coldNavigation),
                calendar: nil
            )
        )
        let session = AppRestorationSession(accountID: accountID, persistence: fixture.store)
        let gate = AppRestorationValidationGate()
        let coldRestore = Task {
            await session.restore(
                accountTimezone: "UTC",
                routeValidator: AppRestorationRouteValidator { _, _ in
                    await gate.wait()
                    return true
                }
            )
        }
        await gate.waitUntilEntered()
        let warmCalendar = CalendarRestorationState(
            timezoneIdentifier: "Etc/UTC",
            visibleMonth: CalendarMonth(year: 2026, month: 12),
            selectedDate: LocalDate(rawValue: "2026-12-09")!
        )
        session.calendarMutationHandler()(warmCalendar)
        await gate.release()

        let activation = await coldRestore.value
        XCTAssertEqual(activation.source, .superseded)
        XCTAssertEqual(activation.calendar, warmCalendar)
        guard case let .loaded(snapshot) = fixture.store.load(accountID: accountID) else {
            XCTFail("Expected warm Calendar mutation to be durable")
            return
        }
        XCTAssertEqual(snapshot.calendar, warmCalendar)
    }

    func testChangedAccountTimezoneDropsAndSanitizesCalendarSnapshot() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let calendar = CalendarRestorationState(
            timezoneIdentifier: "Asia/Tokyo",
            visibleMonth: CalendarMonth(year: 2026, month: 8),
            selectedDate: LocalDate(rawValue: "2026-08-11")!
        )
        fixture.seed(
            AppRestorationSnapshot(
                accountID: accountID,
                navigation: AppNavigationRestorationState(navigation: AppNavigationState()),
                calendar: calendar
            )
        )

        let activation = await AppRestorationSession(
            accountID: accountID,
            persistence: fixture.store
        ).restore(
            accountTimezone: "Europe/Moscow",
            routeValidator: allowingRoutes(for: accountID)
        )

        XCTAssertNil(activation.calendar)
        guard case let .loaded(snapshot) = fixture.store.load(accountID: accountID) else {
            XCTFail("Expected sanitized snapshot")
            return
        }
        XCTAssertNil(snapshot.calendar)
    }

    func testStorageIsAccountScopedAndRejectsSnapshotUnderWrongAccountKey() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let first = AppRestorationSession(accountID: accountID, persistence: fixture.store)
        var navigation = AppNavigationState()
        navigation.installRestorationMutationHandler(first.navigationMutationHandler())
        navigation.select(.focus)

        let otherActivation = await AppRestorationSession(
            accountID: otherAccountID,
            persistence: fixture.store
        ).restore(
            accountTimezone: "Europe/Moscow",
            routeValidator: allowingRoutes(for: otherAccountID)
        )
        XCTAssertEqual(otherActivation.source, .missing)

        let wrongAccountSnapshot = AppRestorationSnapshot(
            accountID: otherAccountID,
            navigation: AppNavigationRestorationState(navigation: navigation),
            calendar: nil
        )
        fixture.defaults.set(
            try JSONEncoder().encode(wrongAccountSnapshot),
            forKey: fixture.key(accountID)
        )
        XCTAssertEqual(fixture.store.load(accountID: accountID), .discarded(.accountMismatch))
        XCTAssertEqual(fixture.store.load(accountID: accountID), .missing)
    }

    func testEnvelopeReadsUnsupportedVersionBeforeMalformedHistoricalPayload() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let unsupportedFixture = """
        {
          "schemaVersion": 0,
          "legacyAccount": "not-a-current-envelope",
          "payload": "historical-v0-shape-not-known-to-v1"
        }
        """
        fixture.defaults.set(
            Data(unsupportedFixture.utf8),
            forKey: fixture.key(accountID)
        )

        XCTAssertEqual(fixture.store.load(accountID: accountID), .discarded(.versionMismatch))
        XCTAssertEqual(fixture.store.load(accountID: accountID), .missing)
    }

    func testHistoricalV1EnvelopeFixtureDecodesThroughVersionBranch() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let versionOneFixture = """
        {
          "schemaVersion": 1,
          "accountID": "\(accountID.uuidString)",
          "payload": {
            "navigation": {
              "selectedTab": "focus",
              "plannerPath": [],
              "calendarPath": [],
              "focusPath": []
            },
            "calendar": null
          }
        }
        """
        fixture.defaults.set(Data(versionOneFixture.utf8), forKey: fixture.key(accountID))

        guard case let .loaded(snapshot) = fixture.store.load(accountID: accountID) else {
            XCTFail("Expected the historical V1 fixture to decode")
            return
        }
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.navigation.selectedTab, .focus)
    }

    func testCorruptHeaderAndCurrentVersionPayloadAreDiscardedAndCleared() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(Data("not-json".utf8), forKey: fixture.key(accountID))

        XCTAssertEqual(fixture.store.load(accountID: accountID), .discarded(.corrupt))
        XCTAssertEqual(fixture.store.load(accountID: accountID), .missing)

        let malformedV1 = """
        {
          "schemaVersion": 1,
          "accountID": "\(accountID.uuidString)",
          "payload": "malformed-current-payload"
        }
        """
        fixture.defaults.set(
            Data(malformedV1.utf8),
            forKey: fixture.key(accountID)
        )

        XCTAssertEqual(fixture.store.load(accountID: accountID), .discarded(.corrupt))
        XCTAssertEqual(fixture.store.load(accountID: accountID), .missing)
    }

    func testLogoutClearInvalidatesOldMutationHooks() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let session = AppRestorationSession(accountID: accountID, persistence: fixture.store)
        var navigation = AppNavigationState()
        navigation.installRestorationMutationHandler(session.navigationMutationHandler())
        navigation.select(.calendar)

        session.clear()
        navigation.select(.focus)

        let activation = await AppRestorationSession(
            accountID: accountID,
            persistence: fixture.store
        ).restore(
            accountTimezone: "Europe/Moscow",
            routeValidator: allowingRoutes(for: accountID)
        )
        XCTAssertEqual(activation.source, .missing)
        XCTAssertEqual(activation.navigation, AppNavigationState())
    }

    func testLateLogoutCannotClearReloginSnapshotForSameAccount() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let oldSession = AppRestorationSession(accountID: accountID, persistence: fixture.store)
        var oldNavigation = AppNavigationState()
        oldNavigation.installRestorationMutationHandler(oldSession.navigationMutationHandler())
        oldNavigation.select(.focus)

        let reloginSession = AppRestorationSession(accountID: accountID, persistence: fixture.store)
        let reloginActivation = await reloginSession.restore(
            accountTimezone: "Europe/Moscow",
            routeValidator: allowingRoutes(for: accountID)
        )
        XCTAssertTrue(reloginSession.canApply(reloginActivation))
        var reloginNavigation = reloginActivation.navigation
        reloginNavigation.installRestorationMutationHandler(
            reloginSession.navigationMutationHandler()
        )
        reloginNavigation.select(.calendar)
        XCTAssertFalse(reloginSession.canApply(reloginActivation))

        oldSession.clear()
        oldNavigation.select(.planner)

        let recreated = await AppRestorationSession(
            accountID: accountID,
            persistence: fixture.store
        ).restore(
            accountTimezone: "Europe/Moscow",
            routeValidator: allowingRoutes(for: accountID)
        )
        XCTAssertEqual(recreated.source, .restored)
        XCTAssertEqual(recreated.navigation.selectedTab, .calendar)
    }

    func testClearDuringRouteValidationCannotResurrectSnapshot() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        var navigation = AppNavigationState()
        navigation.open(
            DetailEntityReference(kind: .task, id: taskID),
            origin: .focus
        )
        fixture.seed(
            AppRestorationSnapshot(
                accountID: accountID,
                navigation: AppNavigationRestorationState(navigation: navigation),
                calendar: nil
            )
        )
        let session = AppRestorationSession(accountID: accountID, persistence: fixture.store)
        let gate = AppRestorationValidationGate()

        let restoration = Task {
            await session.restore(
                accountTimezone: "Europe/Moscow",
                routeValidator: AppRestorationRouteValidator { _, _ in
                    await gate.wait()
                    return true
                }
            )
        }
        await gate.waitUntilEntered()
        session.clear()
        await gate.release()

        let activation = await restoration.value
        XCTAssertEqual(activation.source, .superseded)
        XCTAssertFalse(activation.shouldApplyToRuntime)
        XCTAssertFalse(session.canApply(activation))
        XCTAssertEqual(fixture.store.load(accountID: accountID), .missing)
    }

    func testSnapshotContainsIDsButNotNoticeOrPresentationPayload() throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let session = AppRestorationSession(accountID: accountID, persistence: fixture.store)
        var navigation = AppNavigationState()
        navigation.notice = "PRIVATE-NOTICE"
        navigation.presentation = AppPresentation(route: .focusCadence)
        navigation.installRestorationMutationHandler(session.navigationMutationHandler())
        navigation.open(
            DetailEntityReference(kind: .task, id: taskID),
            origin: .focus
        )

        let data = try XCTUnwrap(fixture.defaults.data(forKey: fixture.key(accountID)))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.localizedCaseInsensitiveContains(taskID.uuidString))
        XCTAssertFalse(json.contains("PRIVATE-NOTICE"))
        XCTAssertFalse(json.contains("focusCadence"))
    }

    func testTransientRuntimeDetachPreservesSnapshotForRetry() async {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        let session = AppRestorationSession(accountID: accountID, persistence: fixture.store)
        var navigation = AppNavigationState()
        navigation.installRestorationMutationHandler(session.navigationMutationHandler())
        navigation.select(.calendar)

        session.detachPreservingSnapshot()

        let retrySession = AppRestorationSession(accountID: accountID, persistence: fixture.store)
        let activation = await retrySession.restore(
            accountTimezone: "Europe/Moscow",
            routeValidator: allowingRoutes(for: accountID)
        )
        XCTAssertEqual(activation.source, .restored)
        XCTAssertEqual(activation.navigation.selectedTab, .calendar)
    }

    private func allowingRoutes(for accountID: UUID) -> AppRestorationRouteValidator {
        AppRestorationRouteValidator { route, candidateAccountID in
            guard candidateAccountID == accountID else { return false }
            guard case let .detail(reference, _) = route else { return false }
            return reference.kind == .task
        }
    }

    private func makeFixture() -> AppRestorationDefaultsFixture {
        AppRestorationDefaultsFixture()
    }
}

private struct AppRestorationDefaultsFixture {
    let suiteName = "AppRestorationTests.\(UUID().uuidString)"
    let keyPrefix = "tests.app-restoration"
    let defaults: UserDefaults
    let store: AppRestorationUserDefaultsStore

    init() {
        let configuredDefaults = UserDefaults(suiteName: suiteName)!
        configuredDefaults.removePersistentDomain(forName: suiteName)
        defaults = configuredDefaults
        store = AppRestorationUserDefaultsStore(
            defaults: configuredDefaults,
            keyPrefix: keyPrefix
        )
    }

    func key(_ accountID: UUID) -> String {
        "\(keyPrefix).\(accountID.uuidString.lowercased())"
    }

    func seed(_ snapshot: AppRestorationSnapshot) {
        let leaseID = UUID()
        _ = store.acquireLease(accountID: snapshot.accountID, leaseID: leaseID)
        precondition(store.save(snapshot, leaseID: leaseID))
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private actor AppRestorationValidationGate {
    private var entered = false
    private var released = false
    private var validationContinuation: CheckedContinuation<Void, Never>?
    private var enteredContinuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        enteredContinuations.forEach { $0.resume() }
        enteredContinuations = []
        guard !released else { return }
        await withCheckedContinuation { validationContinuation = $0 }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredContinuations.append($0) }
    }

    func release() {
        released = true
        validationContinuation?.resume()
        validationContinuation = nil
    }
}
