import Foundation

struct PendingMutation: Equatable, Sendable, Identifiable {
    let id: UUID
    let entityType: PlanningEntityKind
    let entityID: UUID
    let operation: MutationOperation
    let payloadJSON: Data
    let baseVersion: Int64?
    let attemptCount: Int
    let nextRetryAt: Date?
    let lastErrorCode: String?
    let state: MutationState
    let dependencies: Set<UUID>
    let createdAt: Date
    let updatedAt: Date
}

struct SyncConflict: Equatable, Sendable, Identifiable {
    let id: UUID
    let mutationID: UUID
    let entityType: PlanningEntityKind
    let entityID: UUID
    let operation: MutationOperation
    let localPayloadJSON: Data
    let serverPayloadJSON: Data?
    let baseVersion: Int64?
    let serverVersion: Int64?
    let serverDeleted: Bool
    let errorCode: String
    let createdAt: Date
    let updatedAt: Date
}

enum RemotePlanningCollection: String, CaseIterable, Hashable, Sendable {
    case folders
    case goals
    case tasks
    case ideas
    case ideaNotes
    case notes
    case entityLinks
}

struct RemotePullWarning: Equatable, Sendable, Identifiable {
    let id: String
    let resource: String
    let code: String
}

struct RemotePlanningSnapshot: Equatable, Sendable {
    let folders: [FolderDTO]
    let goals: [GoalDTO]
    let tasks: [TaskDTO]
    let ideas: [IdeaDTO]?
    let ideaNotes: [IdeaNoteDTO]?
    let notes: [NoteDTO]?
    let links: [EntityLinkDTO]?
    let loadedCollections: Set<RemotePlanningCollection>
    let partialWarnings: [RemotePullWarning]

    init(
        folders: [FolderDTO] = [],
        goals: [GoalDTO] = [],
        tasks: [TaskDTO] = [],
        ideas: [IdeaDTO]? = nil,
        ideaNotes: [IdeaNoteDTO]? = nil,
        notes: [NoteDTO]? = nil,
        links: [EntityLinkDTO]? = nil,
        loadedCollections: Set<RemotePlanningCollection>? = nil,
        partialWarnings: [RemotePullWarning] = []
    ) {
        self.folders = folders
        self.goals = goals
        self.tasks = tasks
        self.ideas = ideas
        self.ideaNotes = ideaNotes
        self.notes = notes
        self.links = links
        var inferredCollections: Set<RemotePlanningCollection> = [.folders, .goals, .tasks]
        if ideas != nil { inferredCollections.insert(.ideas) }
        if ideaNotes != nil { inferredCollections.insert(.ideaNotes) }
        if notes != nil { inferredCollections.insert(.notes) }
        if links != nil { inferredCollections.insert(.entityLinks) }
        self.loadedCollections = loadedCollections ?? inferredCollections
        self.partialWarnings = partialWarnings
    }
}

struct RemoteMutationAck: Equatable, Sendable {
    let remoteID: UUID
    let version: Int64
    let serverPayloadJSON: Data?
}

enum SyncRemoteFailure: Error, Equatable, Sendable {
    case unauthorized
    case conflict(
        code: String,
        serverVersion: Int64?,
        serverPayloadJSON: Data?,
        serverDeleted: Bool
    )
    case permanent(code: String, serverPayloadJSON: Data?)
    case transient(code: String)
}

enum SyncTrigger: String, Sendable {
    case foreground
    case manual
    case background
}

enum SyncPhase: String, Sendable {
    case idle
    case syncing
    case waitingForNetwork
    case waitingForRetry
    case conflicted
    case unauthorized
    case cancelled
    case failed
}

struct SyncStatus: Equatable, Sendable {
    let phase: SyncPhase
    let pendingCount: Int
    let conflictCount: Int
    let lastErrorCode: String?
    let updatedAt: Date?

    static let idle = SyncStatus(
        phase: .idle,
        pendingCount: 0,
        conflictCount: 0,
        lastErrorCode: nil,
        updatedAt: nil
    )
}

struct SyncPolicy: Equatable, Sendable {
    let maxPushesPerRun: Int
    let maxAttempts: Int
    let baseRetryDelay: TimeInterval
    let maximumRetryDelay: TimeInterval
    let jitterRange: ClosedRange<Double>

    init(
        maxPushesPerRun: Int = 5,
        maxAttempts: Int = 6,
        baseRetryDelay: TimeInterval = 2,
        maximumRetryDelay: TimeInterval = 300,
        jitterRange: ClosedRange<Double> = 0.75...1.25
    ) {
        self.maxPushesPerRun = max(1, maxPushesPerRun)
        self.maxAttempts = max(1, maxAttempts)
        self.baseRetryDelay = max(0, baseRetryDelay)
        self.maximumRetryDelay = max(0, maximumRetryDelay)
        self.jitterRange = jitterRange
    }

    func retryDelay(after attemptCount: Int, randomUnit: Double) -> TimeInterval {
        let exponent = min(max(attemptCount - 1, 0), 16)
        let exponential = min(baseRetryDelay * pow(2, Double(exponent)), maximumRetryDelay)
        let unit = min(max(randomUnit, 0), 1)
        let jitter = jitterRange.lowerBound
            + ((jitterRange.upperBound - jitterRange.lowerBound) * unit)
        return min(exponential * jitter, maximumRetryDelay)
    }
}

enum ConflictResolution: Sendable {
    case keepServer
    case retryLocal
    case discard
    case resetCache
}

protocol PlanningRepository: Sendable {
    func snapshot() async throws -> PlanningSnapshot
    func createFolder(_ draft: FolderDraft) async throws -> FolderDTO
    func updateFolder(id: UUID, name: String, description: String) async throws
    func moveFolder(id: UUID, to parentFolderID: UUID?) async throws
    func createGoal(_ draft: GoalDraft) async throws -> GoalDTO
    func updateGoal(id: UUID, draft: GoalDraft) async throws
    func moveGoal(id: UUID, to folderID: UUID) async throws
    func createTask(_ draft: TaskDraft) async throws -> TaskRecord
    func updateTask(id: UUID, draft: TaskDraft) async throws
    func moveTask(id: UUID, to goalID: UUID) async throws
    func createIdea(_ draft: IdeaDraft) async throws -> IdeaDTO
    func updateIdea(id: UUID, draft: IdeaDraft) async throws
    func moveIdea(id: UUID, to folderID: UUID) async throws
    func createIdeaNote(_ draft: IdeaNoteDraft) async throws -> IdeaNoteDTO
    func updateIdeaNote(id: UUID, draft: IdeaNoteDraft) async throws
    func createNote(_ draft: NoteDraft) async throws -> NoteDTO
    func updateNote(id: UUID, draft: NoteDraft) async throws
    func moveNote(id: UUID, to folderID: UUID) async throws
    func createChecklistItem(_ draft: ChecklistItemDraft) async throws -> ChecklistItemDTO
    func updateChecklistItem(id: UUID, draft: ChecklistItemDraft) async throws
    func deleteChecklistItem(id: UUID, taskID: UUID) async throws
    func reorderChecklist(taskID: UUID, orderedIDs: [UUID]) async throws
    func createTag(_ draft: TagDraft) async throws -> TaskTagDTO
    func updateTag(id: UUID, draft: TagDraft) async throws
    func setTags(_ tagIDs: [UUID], for taskID: UUID) async throws
    func createEntityLink(_ draft: EntityLinkDraft) async throws -> EntityLinkDTO
    func updateEntityLink(id: UUID, relationType: EntityRelationType) async throws
    func reorder(_ entity: PlanningEntityKind, orderedIDs: [UUID]) async throws
    func storeFocusCache(key: String, payloadJSON: Data, version: Int64) async throws
    func focusCache(key: String) async throws -> CachedPayload?
    func removeFocusCache(key: String) async throws
    func storeSettingsCache(key: String, payloadJSON: Data, version: Int64) async throws
    func settingsCache(key: String) async throws -> CachedPayload?
    func removeSettingsCache(key: String) async throws
    func delete(_ entity: PlanningEntityKind, id: UUID) async throws
    func applyRemote(_ snapshot: RemotePlanningSnapshot) async throws
    func resetCachePreservingPending() async throws
}

protocol SyncRepository: Sendable {
    func pendingCount() async throws -> Int
    func conflictCount() async throws -> Int
    func nextReadyMutation(at date: Date) async throws -> PendingMutation?
    func returnToQueue(_ mutation: PendingMutation, errorCode: String?, at date: Date) async throws
    func acknowledge(_ mutation: PendingMutation, ack: RemoteMutationAck, at date: Date) async throws
    func scheduleRetry(
        _ mutation: PendingMutation,
        at nextRetryAt: Date,
        errorCode: String,
        updatedAt: Date
    ) async throws
    func recordConflict(
        _ mutation: PendingMutation,
        code: String,
        serverVersion: Int64?,
        serverPayloadJSON: Data?,
        serverDeleted: Bool,
        at date: Date
    ) async throws
    func applyRemote(_ snapshot: RemotePlanningSnapshot) async throws
    func conflicts() async throws -> [SyncConflict]
    func resolve(_ conflictID: UUID, with resolution: ConflictResolution, at date: Date) async throws
    func pullBeforePushRequired() async throws -> Bool
    func didCompleteRequiredPull(_ snapshot: RemotePlanningSnapshot, at date: Date) async throws
}

extension SyncRepository {
    func pullBeforePushRequired() async throws -> Bool { false }
    func didCompleteRequiredPull(_ snapshot: RemotePlanningSnapshot, at date: Date) async throws {}
}

protocol RemoteIDResolving: Sendable {
    func remoteID(for entityType: PlanningEntityKind, localID: UUID) async throws -> UUID
}

protocol SyncRemote: Sendable {
    func push(_ mutation: PendingMutation) async throws -> RemoteMutationAck
    func pull() async throws -> RemotePlanningSnapshot
}

protocol NetworkMonitoring: Sendable {
    func isConnected() async -> Bool
    func changes() async -> AsyncStream<Bool>
}

protocol SyncClock: Sendable {
    func now() async -> Date
}

protocol SyncRandom: Sendable {
    func unitInterval() async -> Double
}

struct SystemSyncClock: SyncClock {
    func now() -> Date { Date() }
}

actor SystemSyncRandom: SyncRandom {
    func unitInterval() -> Double { Double.random(in: 0...1) }
}

actor FixedNetworkMonitor: NetworkMonitoring {
    private var connected: Bool
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init(connected: Bool = true) {
        self.connected = connected
    }

    func isConnected() -> Bool { connected }

    func changes() async -> AsyncStream<Bool> {
        let id = UUID()
        let initial = connected
        let stream = AsyncStream<Bool>.makeStream()
        continuations[id] = stream.continuation
        stream.continuation.yield(initial)
        stream.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream.stream
    }

    func setConnected(_ connected: Bool) {
        guard self.connected != connected else { return }
        self.connected = connected
        continuations.values.forEach { $0.yield(connected) }
    }

    func finish() {
        continuations.values.forEach { $0.finish() }
        continuations.removeAll()
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

struct FolderDraft: Equatable, Sendable {
    let id: UUID
    let parentFolderID: UUID?
    let name: String
    let description: String
    let displayOrder: Int

    init(
        id: UUID = UUID(),
        parentFolderID: UUID? = nil,
        name: String,
        description: String = "",
        displayOrder: Int = 0
    ) {
        self.id = id
        self.parentFolderID = parentFolderID
        self.name = name
        self.description = description
        self.displayOrder = displayOrder
    }
}

struct GoalDraft: Equatable, Sendable {
    let id: UUID
    let folderID: UUID
    let name: String
    let description: String
    let status: PlanningStatus

    init(
        id: UUID = UUID(),
        folderID: UUID,
        name: String,
        description: String = "",
        status: PlanningStatus = .todo
    ) {
        self.id = id
        self.folderID = folderID
        self.name = name
        self.description = description
        self.status = status
    }
}

struct TaskDraft: Equatable, Sendable {
    let id: UUID
    let goalID: UUID
    let title: String
    let description: String
    let type: TaskType
    let effort: Int
    let status: PlanningStatus
    let plannedTime: Date?
    let dueTime: Date?

    init(
        id: UUID = UUID(),
        goalID: UUID,
        title: String,
        description: String = "",
        type: TaskType = .green,
        effort: Int = 0,
        status: PlanningStatus = .todo,
        plannedTime: Date? = nil,
        dueTime: Date? = nil
    ) {
        self.id = id
        self.goalID = goalID
        self.title = title
        self.description = description
        self.type = type
        self.effort = effort
        self.status = status
        self.plannedTime = plannedTime
        self.dueTime = dueTime
    }
}

struct NoteDraft: Equatable, Sendable {
    let id: UUID
    let folderID: UUID
    let title: String
    let body: String
    let displayOrder: Int

    init(
        id: UUID = UUID(),
        folderID: UUID,
        title: String,
        body: String = "",
        displayOrder: Int = 0
    ) {
        self.id = id
        self.folderID = folderID
        self.title = title
        self.body = body
        self.displayOrder = displayOrder
    }
}

struct IdeaDraft: Equatable, Sendable {
    let id: UUID
    let folderID: UUID
    let title: String
    let body: String
    let status: String
    let displayOrder: Int
    let allowAuthorNoteEdits: Bool

    init(
        id: UUID = UUID(),
        folderID: UUID,
        title: String,
        body: String = "",
        status: String = "ACTIVE",
        displayOrder: Int = 0,
        allowAuthorNoteEdits: Bool = false
    ) {
        self.id = id
        self.folderID = folderID
        self.title = title
        self.body = body
        self.status = status
        self.displayOrder = displayOrder
        self.allowAuthorNoteEdits = allowAuthorNoteEdits
    }
}

struct IdeaNoteDraft: Equatable, Sendable {
    let id: UUID
    let ideaID: UUID
    let eventType: String
    let body: String
    let metadata: [String: JSONValue]

    init(
        id: UUID = UUID(),
        ideaID: UUID,
        eventType: String,
        body: String = "",
        metadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.ideaID = ideaID
        self.eventType = eventType
        self.body = body
        self.metadata = metadata
    }
}

struct ChecklistItemDraft: Equatable, Sendable {
    let id: UUID
    let taskID: UUID
    let text: String
    let checked: Bool
    let displayOrder: Int

    init(
        id: UUID = UUID(),
        taskID: UUID,
        text: String,
        checked: Bool = false,
        displayOrder: Int = 0
    ) {
        self.id = id
        self.taskID = taskID
        self.text = text
        self.checked = checked
        self.displayOrder = displayOrder
    }
}

struct TagDraft: Equatable, Sendable {
    let id: UUID
    let name: String
    let color: String?

    init(id: UUID = UUID(), name: String, color: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
    }
}

struct EntityLinkDraft: Equatable, Sendable {
    let id: UUID
    let source: EntityReferenceDTO
    let target: EntityReferenceDTO
    let relationType: EntityRelationType

    init(
        id: UUID = UUID(),
        source: EntityReferenceDTO,
        target: EntityReferenceDTO,
        relationType: EntityRelationType
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.relationType = relationType
    }
}

struct CachedPayload: Equatable, Sendable {
    let payloadJSON: Data
    let version: Int64
    let updatedAt: Date
}

struct PlanningSnapshot: Equatable, Sendable {
    let folders: [FolderDTO]
    let goals: [GoalDTO]
    let tasks: [TaskDTO]
    let ideas: [IdeaDTO]
    let notes: [NoteDTO]
    let pendingCount: Int
    let conflictCount: Int
}

struct DeleteMutationPayload: Codable, Equatable, Sendable {
    let remoteID: UUID?
    let version: Int64
}

struct MoveMutationPayload: Codable, Equatable, Sendable {
    let targetParentID: UUID?
    let version: Int64
}
