import Foundation

actor DatabaseSyncRepository: SyncRepository, RemoteIDResolving {
    private let database: AppDatabase
    private let store: PendingMutationStore

    init(database: AppDatabase) {
        self.database = database
        store = PendingMutationStore(database: database)
    }

    func pendingCount() async throws -> Int { try await store.pendingCount() }
    func conflictCount() async throws -> Int { try await store.conflictCount() }
    func nextReadyMutation(at date: Date) async throws -> PendingMutation? {
        try await store.nextReady(at: date)
    }

    func returnToQueue(_ mutation: PendingMutation, errorCode: String?, at date: Date) async throws {
        try await store.returnToQueue(mutation, errorCode: errorCode, at: date)
    }

    func acknowledge(_ mutation: PendingMutation, ack: RemoteMutationAck, at date: Date) async throws {
        try await store.acknowledge(mutation, ack: ack, at: date)
    }

    func scheduleRetry(
        _ mutation: PendingMutation,
        at nextRetryAt: Date,
        errorCode: String,
        updatedAt: Date
    ) async throws {
        try await store.scheduleRetry(
            mutation,
            at: nextRetryAt,
            errorCode: errorCode,
            updatedAt: updatedAt
        )
    }

    func recordConflict(
        _ mutation: PendingMutation,
        code: String,
        serverVersion: Int64?,
        serverPayloadJSON: Data?,
        serverDeleted: Bool,
        at date: Date
    ) async throws {
        try await store.recordConflict(
            mutation,
            code: code,
            serverVersion: serverVersion,
            serverPayloadJSON: serverPayloadJSON,
            serverDeleted: serverDeleted,
            at: date
        )
    }

    func applyRemote(_ snapshot: RemotePlanningSnapshot) async throws {
        try database.write { db in
            try PlanningPersistence.applyRemote(snapshot, in: db)
        }
    }

    func conflicts() async throws -> [SyncConflict] { try await store.conflicts() }

    func resolve(_ conflictID: UUID, with resolution: ConflictResolution, at date: Date) async throws {
        try await store.resolve(conflictID, with: resolution, at: date)
    }

    func pullBeforePushRequired() async throws -> Bool {
        try await store.pullBeforePushRequired()
    }

    func didCompleteRequiredPull(_ snapshot: RemotePlanningSnapshot, at date: Date) async throws {
        try await store.didCompleteRequiredPull(snapshot, at: date)
    }

    func remoteID(for entityType: PlanningEntityKind, localID: UUID) async throws -> UUID {
        try await store.remoteID(for: entityType, localID: localID)
    }
}
