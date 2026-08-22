import Combine
import Foundation

protocol PlannerScrollStatePersisting {
    func load(accountID: UUID) -> PlannerScrollRestorableState?
    func save(_ state: PlannerScrollRestorableState)
    func remove(accountID: UUID)
}

struct PlannerScrollUserDefaultsStore: PlannerScrollStatePersisting {
    private let defaults: UserDefaults
    private let keyPrefix: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "rocketflow.planner.scroll"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func load(accountID: UUID) -> PlannerScrollRestorableState? {
        guard
            let data = defaults.data(forKey: key(for: accountID)),
            let state = try? decoder.decode(PlannerScrollRestorableState.self, from: data),
            state.schemaVersion == PlannerScrollRestorableState.currentSchemaVersion,
            state.accountID == accountID
        else {
            return nil
        }
        return state
    }

    func save(_ state: PlannerScrollRestorableState) {
        guard
            state.schemaVersion == PlannerScrollRestorableState.currentSchemaVersion,
            let data = try? encoder.encode(state)
        else {
            return
        }
        defaults.set(data, forKey: key(for: state.accountID))
    }

    func remove(accountID: UUID) {
        defaults.removeObject(forKey: key(for: accountID))
    }

    private func key(for accountID: UUID) -> String {
        "\(keyPrefix).\(accountID.uuidString.lowercased())"
    }
}

@MainActor
final class PlannerScrollStateController: ObservableObject {
    @Published private(set) var position: PlannerScrollPosition?
    @Published private(set) var activeAccountID: UUID?
    @Published private(set) var lastCaptureReason: PlannerScrollCaptureReason?

    private let persistence: any PlannerScrollStatePersisting

    init(persistence: any PlannerScrollStatePersisting = PlannerScrollUserDefaultsStore()) {
        self.persistence = persistence
    }

    @discardableResult
    func activate(
        accountID: UUID,
        processState: PlannerScrollRestorableState? = nil
    ) -> PlannerScrollPosition? {
        activeAccountID = accountID
        lastCaptureReason = nil

        if
            let processState,
            processState.schemaVersion == PlannerScrollRestorableState.currentSchemaVersion,
            processState.accountID == accountID
        {
            position = processState.position
            persistence.save(processState)
        } else {
            position = persistence.load(accountID: accountID)?.position
        }
        return position
    }

    @discardableResult
    func captureBefore(
        _ reason: PlannerScrollCaptureReason,
        rows: [PlannerScrollRowGeometry],
        viewport: PlannerScrollViewport,
        expandedFolderIDs: Set<UUID>,
        expandedGoalIDs: Set<UUID>
    ) -> PlannerScrollPosition? {
        guard activeAccountID != nil else { return nil }

        let captured = PlannerScrollAnchorResolver.capture(
            rows: rows,
            absoluteY: min(viewport.absoluteY, viewport.maximumOffsetY),
            expandedFolderIDs: expandedFolderIDs,
            expandedGoalIDs: expandedGoalIDs
        )
        position = captured
        lastCaptureReason = reason
        persistCurrentPosition()
        return captured
    }

    func updateExpandedState(
        folderIDs: Set<UUID>,
        goalIDs: Set<UUID>
    ) {
        guard activeAccountID != nil else { return }
        guard let current = position else {
            position = PlannerScrollPosition(
                expandedFolderIDs: folderIDs,
                expandedGoalIDs: goalIDs
            )
            persistCurrentPosition()
            return
        }

        position = PlannerScrollPosition(
            anchor: current.anchor,
            ancestorChain: current.ancestorChain,
            pixelOffset: current.pixelOffset,
            absoluteY: current.absoluteY,
            expandedFolderIDs: folderIDs,
            expandedGoalIDs: goalIDs
        )
        persistCurrentPosition()
    }

    func restoration(
        rows: [PlannerScrollRowGeometry],
        viewport: PlannerScrollViewport
    ) -> PlannerScrollRestoration {
        PlannerScrollAnchorResolver.restore(
            position,
            rows: rows,
            maximumOffsetY: viewport.maximumOffsetY
        )
    }

    func makeRestorationRequest(
        rows: [PlannerScrollRowGeometry],
        viewport _: PlannerScrollViewport
    ) -> PlannerScrollRestorationRequest {
        let resolved = PlannerScrollAnchorResolver.desiredRestoration(position, rows: rows)
        return PlannerScrollRestorationRequest(absoluteY: resolved.absoluteY)
    }

    func processRestorableState() -> PlannerScrollRestorableState? {
        guard let accountID = activeAccountID, let position else { return nil }
        return PlannerScrollRestorableState(accountID: accountID, position: position)
    }

    func reset(_ reason: PlannerScrollResetReason) {
        guard let accountID = activeAccountID else {
            position = nil
            lastCaptureReason = nil
            return
        }

        persistence.remove(accountID: accountID)
        position = nil
        lastCaptureReason = nil
        switch reason {
        case .explicitTopLevelTabSwitch:
            break
        case .logout, .userDataClear:
            activeAccountID = nil
        }
    }

    private func persistCurrentPosition() {
        guard let accountID = activeAccountID, let position else { return }
        persistence.save(PlannerScrollRestorableState(accountID: accountID, position: position))
    }
}
