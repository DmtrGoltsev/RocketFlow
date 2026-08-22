import Foundation

enum PlannerResourceType: String, Codable, CaseIterable, Sendable {
    case folder
    case goal
    case task
    case idea
    case note
}

struct PlannerScrollAnchor: Codable, Equatable, Hashable, Sendable {
    let resourceType: PlannerResourceType
    let resourceID: UUID
}

struct PlannerScrollRowGeometry: Codable, Equatable, Sendable {
    let anchor: PlannerScrollAnchor
    let parentAnchor: PlannerScrollAnchor?
    let minY: Double
    let maxY: Double

    init(
        anchor: PlannerScrollAnchor,
        parentAnchor: PlannerScrollAnchor? = nil,
        minY: Double,
        maxY: Double
    ) {
        self.anchor = anchor
        self.parentAnchor = parentAnchor
        self.minY = min(minY, maxY)
        self.maxY = max(minY, maxY)
    }
}

struct PlannerScrollPosition: Codable, Equatable, Sendable {
    let anchor: PlannerScrollAnchor?
    let ancestorChain: [PlannerScrollAnchor]
    let pixelOffset: Double
    let absoluteY: Double
    let expandedFolderIDs: Set<UUID>
    let expandedGoalIDs: Set<UUID>

    init(
        anchor: PlannerScrollAnchor? = nil,
        ancestorChain: [PlannerScrollAnchor] = [],
        pixelOffset: Double = 0,
        absoluteY: Double = 0,
        expandedFolderIDs: Set<UUID> = [],
        expandedGoalIDs: Set<UUID> = []
    ) {
        self.anchor = anchor
        self.ancestorChain = ancestorChain
        self.pixelOffset = pixelOffset
        self.absoluteY = max(0, absoluteY)
        self.expandedFolderIDs = expandedFolderIDs
        self.expandedGoalIDs = expandedGoalIDs
    }
}

struct PlannerScrollRestorableState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let accountID: UUID
    let position: PlannerScrollPosition

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        accountID: UUID,
        position: PlannerScrollPosition
    ) {
        self.schemaVersion = schemaVersion
        self.accountID = accountID
        self.position = position
    }
}

enum PlannerScrollRestoreSource: Equatable, Sendable {
    case exact(PlannerScrollAnchor)
    case ancestor(PlannerScrollAnchor)
    case absoluteY
    case top
}

struct PlannerScrollRestoration: Equatable, Sendable {
    let absoluteY: Double
    let source: PlannerScrollRestoreSource
}

struct PlannerScrollRestorationRequest: Equatable, Identifiable, Sendable {
    let id: UUID
    let absoluteY: Double
    let readinessPolicy: PlannerScrollRestorationReadinessPolicy

    init(
        id: UUID = UUID(),
        absoluteY: Double,
        readinessPolicy: PlannerScrollRestorationReadinessPolicy = .default
    ) {
        self.id = id
        self.absoluteY = max(0, absoluteY)
        self.readinessPolicy = readinessPolicy
    }
}

struct PlannerScrollRestorationReadinessPolicy: Equatable, Sendable {
    static let `default` = PlannerScrollRestorationReadinessPolicy()

    let requiredStablePasses: Int
    let minimumFallbackPasses: Int
    let maximumWaitPasses: Int
    let geometryTolerance: Double

    init(
        requiredStablePasses: Int = 3,
        minimumFallbackPasses: Int = 20,
        maximumWaitPasses: Int = 60,
        geometryTolerance: Double = 0.5
    ) {
        self.requiredStablePasses = max(1, requiredStablePasses)
        self.minimumFallbackPasses = max(1, minimumFallbackPasses)
        self.maximumWaitPasses = max(self.minimumFallbackPasses, maximumWaitPasses)
        self.geometryTolerance = max(0, geometryTolerance)
    }
}

enum PlannerScrollRestorationReadinessDecision: Equatable, Sendable {
    case wait
    case applyTarget(Double)
    case applyBoundedFallback(Double)
}

protocol PlannerScrollRestorationReadinessEvaluating {
    mutating func evaluate(
        viewport: PlannerScrollViewport
    ) -> PlannerScrollRestorationReadinessDecision
}

struct PlannerScrollRestorationReadinessTracker: PlannerScrollRestorationReadinessEvaluating {
    private let targetAbsoluteY: Double
    private let policy: PlannerScrollRestorationReadinessPolicy
    private var observedPasses = 0
    private var stablePasses = 0
    private var previousViewport: PlannerScrollViewport?

    init(request: PlannerScrollRestorationRequest) {
        targetAbsoluteY = request.absoluteY
        policy = request.readinessPolicy
    }

    mutating func evaluate(
        viewport: PlannerScrollViewport
    ) -> PlannerScrollRestorationReadinessDecision {
        observedPasses += 1
        if targetAbsoluteY <= viewport.maximumOffsetY {
            return .applyTarget(targetAbsoluteY)
        }

        if let previousViewport, isStable(previousViewport, viewport) {
            stablePasses += 1
        } else {
            stablePasses = 1
        }
        previousViewport = viewport

        let reachedStableFallback = observedPasses >= policy.minimumFallbackPasses
            && stablePasses >= policy.requiredStablePasses
        if reachedStableFallback || observedPasses >= policy.maximumWaitPasses {
            return .applyBoundedFallback(viewport.maximumOffsetY)
        }
        return .wait
    }

    private func isStable(
        _ lhs: PlannerScrollViewport,
        _ rhs: PlannerScrollViewport
    ) -> Bool {
        abs(lhs.maximumOffsetY - rhs.maximumOffsetY) <= policy.geometryTolerance
            && abs(lhs.contentHeight - rhs.contentHeight) <= policy.geometryTolerance
            && abs(lhs.viewportHeight - rhs.viewportHeight) <= policy.geometryTolerance
    }
}

struct PlannerScrollViewport: Equatable, Sendable {
    let absoluteY: Double
    let maximumOffsetY: Double
    let contentHeight: Double
    let viewportHeight: Double

    init(
        absoluteY: Double,
        maximumOffsetY: Double,
        contentHeight: Double,
        viewportHeight: Double
    ) {
        self.absoluteY = max(0, absoluteY)
        self.maximumOffsetY = max(0, maximumOffsetY)
        self.contentHeight = max(0, contentHeight)
        self.viewportHeight = max(0, viewportHeight)
    }
}

enum PlannerScrollCaptureReason: String, Codable, CaseIterable, Sendable {
    case openDetail
    case openEditor
    case expandCollapse
    case snapshotRefresh
    case insertionAbove
    case mutation
    case background
    case rotation
}

enum PlannerScrollResetReason: String, Codable, CaseIterable, Sendable {
    case explicitTopLevelTabSwitch
    case logout
    case userDataClear
}
