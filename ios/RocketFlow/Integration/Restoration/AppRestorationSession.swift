import Foundation

final class AppRestorationSession: @unchecked Sendable {
    private let accountID: UUID
    private let leaseID: UUID
    private let persistence: any AppRestorationPersisting
    private let lock = NSLock()

    private var navigation = AppNavigationRestorationState(navigation: AppNavigationState())
    private var runtimeNavigation = AppNavigationState()
    private var calendar: CalendarRestorationState?
    private var isActive = true
    private var hasLease = false
    private var revision: UInt64 = 0

    init(
        accountID: UUID,
        persistence: any AppRestorationPersisting = AppRestorationUserDefaultsStore(),
        leaseID: UUID = UUID()
    ) {
        self.accountID = accountID
        self.persistence = persistence
        self.leaseID = leaseID
    }

    func navigationMutationHandler() -> @Sendable (AppNavigationState) -> Void {
        { [weak self] state in
            self?.capture(navigation: state)
        }
    }

    func calendarMutationHandler() -> @Sendable (CalendarRestorationState) -> Void {
        { [weak self] state in
            self?.capture(calendar: state)
        }
    }

    func canApply(_ activation: AppRestorationActivation) -> Bool {
        withLock {
            guard
                activation.shouldApplyToRuntime,
                isActive,
                hasLease,
                activation.generation == revision
            else {
                return false
            }
            return persistence.isLeaseOwner(accountID: accountID, leaseID: leaseID)
        }
    }

    func restore(
        accountTimezone: String,
        routeValidator: AppRestorationRouteValidator
    ) async -> AppRestorationActivation {
        let restorationStart = withLock { () -> (AppRestorationStoredSnapshot, UInt64)? in
            guard isActive else { return nil }
            let stored = persistence.acquireLease(accountID: accountID, leaseID: leaseID)
            hasLease = true
            revision &+= 1
            return (stored, revision)
        }
        guard let (stored, startingRevision) = restorationStart else {
            return emptyActivation(source: .superseded)
        }

        switch stored {
        case .missing:
            return finishWithoutSnapshot(
                source: .missing,
                startingRevision: startingRevision
            )
        case let .discarded(reason):
            return finishWithoutSnapshot(
                source: .discarded(reason),
                startingRevision: startingRevision
            )
        case let .loaded(snapshot):
            let restoredNavigation = await restoreNavigation(
                snapshot.navigation,
                routeValidator: routeValidator
            )
            let restoredCalendar = snapshot.calendar.flatMap { state in
                state.validatedVisibleMonth(accountTimezone: accountTimezone) == nil ? nil : state
            }

            let sanitizedSnapshot = AppRestorationSnapshot(
                accountID: accountID,
                navigation: AppNavigationRestorationState(navigation: restoredNavigation),
                calendar: restoredCalendar
            )
            return withLock {
                guard isActive else { return emptyActivation(source: .superseded) }
                guard revision == startingRevision else {
                    return currentActivation(source: .superseded)
                }
                guard persistence.save(sanitizedSnapshot, leaseID: leaseID) else {
                    isActive = false
                    return currentActivation(source: .superseded)
                }
                navigation = sanitizedSnapshot.navigation
                runtimeNavigation = restoredNavigation
                calendar = sanitizedSnapshot.calendar
                return AppRestorationActivation(
                    source: .restored,
                    navigation: restoredNavigation,
                    calendar: restoredCalendar,
                    generation: revision
                )
            }
        }
    }

    func clear() {
        invalidate(clearPersisted: true)
    }

    func detachPreservingSnapshot() {
        invalidate(clearPersisted: false)
    }

    private func invalidate(clearPersisted: Bool) {
        withLock {
            guard isActive else { return }
            isActive = false
            revision &+= 1
            navigation = AppNavigationRestorationState(navigation: AppNavigationState())
            runtimeNavigation = AppNavigationState()
            calendar = nil
            if clearPersisted, hasLease {
                persistence.clear(accountID: accountID, leaseID: leaseID)
            }
            hasLease = false
        }
    }

    private func capture(navigation state: AppNavigationState) {
        withLock {
            guard isActive else { return }
            revision &+= 1
            runtimeNavigation = state
            runtimeNavigation.removeRestorationMutationHandler()
            navigation = AppNavigationRestorationState(navigation: runtimeNavigation)
            persistCurrentSnapshotOrInvalidate()
        }
    }

    private func capture(calendar state: CalendarRestorationState) {
        withLock {
            guard isActive else { return }
            revision &+= 1
            calendar = state
            persistCurrentSnapshotOrInvalidate()
        }
    }

    private func persistCurrentSnapshotOrInvalidate() {
        if !hasLease {
            _ = persistence.acquireLease(accountID: accountID, leaseID: leaseID)
            hasLease = true
        }
        guard persistence.save(currentSnapshot(), leaseID: leaseID) else {
            isActive = false
            hasLease = false
            return
        }
    }

    private func currentSnapshot() -> AppRestorationSnapshot {
        AppRestorationSnapshot(
            accountID: accountID,
            navigation: navigation,
            calendar: calendar
        )
    }

    private func restoreNavigation(
        _ state: AppNavigationRestorationState,
        routeValidator: AppRestorationRouteValidator
    ) async -> AppNavigationState {
        let selectedPath = state.path(for: state.selectedTab)
        guard let destination = selectedPath.last else {
            var navigation = AppNavigationState()
            navigation.select(state.selectedTab)
            return navigation
        }

        guard case let .detail(reference, origin) = destination else {
            return topLevelFallback(for: destination, selectedTab: state.selectedTab)
        }
        guard reference.kind == .task else {
            return topLevelFallback(for: destination, selectedTab: state.selectedTab)
        }
        guard AppTab(origin: origin) == state.selectedTab else {
            return navigationAtRoot(state.selectedTab)
        }

        guard await routeValidator.isAvailable(destination, accountID) else {
            var navigation = AppNavigationState()
            navigation.select(AppTab(origin: origin))
            return navigation
        }

        var navigation = AppNavigationState()
        navigation.open(reference, origin: origin)
        return navigation
    }

    private func topLevelFallback(
        for route: AppRestorableRoute,
        selectedTab: AppTab
    ) -> AppNavigationState {
        switch route {
        case let .detail(_, origin), let .links(_, origin):
            return navigationAtRoot(AppTab(origin: origin))
        case .settings:
            return navigationAtRoot(selectedTab)
        }
    }

    private func navigationAtRoot(_ tab: AppTab) -> AppNavigationState {
        var navigation = AppNavigationState()
        navigation.select(tab)
        return navigation
    }

    private func finishWithoutSnapshot(
        source: AppRestorationSource,
        startingRevision: UInt64
    ) -> AppRestorationActivation {
        withLock {
            guard isActive else { return emptyActivation(source: .superseded) }
            guard revision == startingRevision else {
                return currentActivation(source: .superseded)
            }
            navigation = AppNavigationRestorationState(navigation: AppNavigationState())
            runtimeNavigation = AppNavigationState()
            calendar = nil
            return emptyActivation(source: source)
        }
    }

    private func currentActivation(source: AppRestorationSource) -> AppRestorationActivation {
        AppRestorationActivation(
            source: source,
            navigation: runtimeNavigation,
            calendar: calendar,
            generation: revision
        )
    }

    private func emptyActivation(source: AppRestorationSource) -> AppRestorationActivation {
        AppRestorationActivation(
            source: source,
            navigation: AppNavigationState(),
            calendar: nil,
            generation: revision
        )
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
