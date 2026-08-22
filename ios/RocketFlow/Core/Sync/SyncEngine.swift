import Foundation

actor SyncEngine {
    private struct Flight: Sendable {
        let id: UUID
        let task: Task<SyncStatus, Never>
    }

    private let repository: any SyncRepository
    private let remote: any SyncRemote
    private let network: any NetworkMonitoring
    private let clock: any SyncClock
    private let random: any SyncRandom
    private let policy: SyncPolicy
    private var flight: Flight?
    private(set) var status: SyncStatus = .idle

    init(
        repository: any SyncRepository,
        remote: any SyncRemote,
        network: any NetworkMonitoring,
        clock: any SyncClock = SystemSyncClock(),
        random: any SyncRandom = SystemSyncRandom(),
        policy: SyncPolicy = SyncPolicy()
    ) {
        self.repository = repository
        self.remote = remote
        self.network = network
        self.clock = clock
        self.random = random
        self.policy = policy
    }

    func syncOnForeground() async -> SyncStatus { await sync(trigger: .foreground) }
    func syncManually() async -> SyncStatus { await sync(trigger: .manual) }
    func syncInBackground() async -> SyncStatus { await sync(trigger: .background) }
    func syncWhenNetworkReturns() async -> SyncStatus { await sync(trigger: .foreground) }

    func sync(trigger: SyncTrigger) async -> SyncStatus {
        if let flight {
            return await flight.task.value
        }
        let startedAt = await clock.now()
        status = await makeStatus(phase: .syncing, errorCode: nil, at: startedAt)
        let id = UUID()
        let repository = self.repository
        let remote = self.remote
        let network = self.network
        let clock = self.clock
        let random = self.random
        let policy = self.policy
        let task = Task {
            await Self.perform(
                repository: repository,
                remote: remote,
                network: network,
                clock: clock,
                random: random,
                policy: policy
            )
        }
        flight = Flight(id: id, task: task)
        let result = await task.value
        if flight?.id == id {
            flight = nil
            status = result
        }
        return result
    }

    func cancel() async {
        guard let task = flight?.task else { return }
        task.cancel()
        _ = await task.value
    }

    private func makeStatus(
        phase: SyncPhase,
        errorCode: String?,
        at date: Date
    ) async -> SyncStatus {
        SyncStatus(
            phase: phase,
            pendingCount: (try? await repository.pendingCount()) ?? 0,
            conflictCount: (try? await repository.conflictCount()) ?? 0,
            lastErrorCode: errorCode,
            updatedAt: date
        )
    }

    private static func perform(
        repository: any SyncRepository,
        remote: any SyncRemote,
        network: any NetworkMonitoring,
        clock: any SyncClock,
        random: any SyncRandom,
        policy: SyncPolicy
    ) async -> SyncStatus {
        guard await network.isConnected() else {
            return await makeStatus(
                repository: repository,
                phase: .waitingForNetwork,
                errorCode: nil,
                clock: clock
            )
        }

        var currentMutation: PendingMutation?
        do {
            if try await repository.pullBeforePushRequired() {
                try Task.checkCancellation()
                let recoverySnapshot = try await remote.pull()
                try Task.checkCancellation()
                try await repository.applyRemote(recoverySnapshot)
                try await repository.didCompleteRequiredPull(recoverySnapshot, at: await clock.now())
            }

            for _ in 0..<policy.maxPushesPerRun {
                try Task.checkCancellation()
                let now = await clock.now()
                guard let mutation = try await repository.nextReadyMutation(at: now) else { break }
                currentMutation = mutation
                do {
                    let ack = try await remote.push(mutation)
                    try Task.checkCancellation()
                    try await repository.acknowledge(mutation, ack: ack, at: await clock.now())
                } catch is CancellationError {
                    try? await repository.returnToQueue(mutation, errorCode: "cancelled", at: await clock.now())
                    throw CancellationError()
                } catch let failure as SyncRemoteFailure {
                    switch failure {
                    case .unauthorized:
                        try await repository.returnToQueue(
                            mutation,
                            errorCode: "unauthorized",
                            at: await clock.now()
                        )
                        return await makeStatus(
                            repository: repository,
                            phase: .unauthorized,
                            errorCode: "unauthorized",
                            clock: clock
                        )
                    case let .conflict(code, serverVersion, payload, serverDeleted):
                        try await repository.recordConflict(
                            mutation,
                            code: code,
                            serverVersion: serverVersion,
                            serverPayloadJSON: payload,
                            serverDeleted: serverDeleted,
                            at: await clock.now()
                        )
                    case let .permanent(code, payload):
                        try await repository.recordConflict(
                            mutation,
                            code: code,
                            serverVersion: nil,
                            serverPayloadJSON: payload,
                            serverDeleted: false,
                            at: await clock.now()
                        )
                    case let .transient(code):
                        if mutation.attemptCount + 1 >= policy.maxAttempts {
                            try await repository.recordConflict(
                                mutation,
                                code: "retry_exhausted:\(code)",
                                serverVersion: nil,
                                serverPayloadJSON: nil,
                                serverDeleted: false,
                                at: await clock.now()
                            )
                        } else {
                            let retryBase = await clock.now()
                            let delay = policy.retryDelay(
                                after: mutation.attemptCount + 1,
                                randomUnit: await random.unitInterval()
                            )
                            try await repository.scheduleRetry(
                                mutation,
                                at: retryBase.addingTimeInterval(delay),
                                errorCode: code,
                                updatedAt: retryBase
                            )
                        }
                    }
                }
                currentMutation = nil
            }

            try Task.checkCancellation()
            let remoteSnapshot = try await remote.pull()
            try Task.checkCancellation()
            try await repository.applyRemote(remoteSnapshot)
            let conflicts = try await repository.conflictCount()
            let pending = try await repository.pendingCount()
            let phase: SyncPhase = conflicts > 0 ? .conflicted : (pending > 0 ? .waitingForRetry : .idle)
            return SyncStatus(
                phase: phase,
                pendingCount: pending,
                conflictCount: conflicts,
                lastErrorCode: nil,
                updatedAt: await clock.now()
            )
        } catch is CancellationError {
            if let currentMutation {
                try? await repository.returnToQueue(
                    currentMutation,
                    errorCode: "cancelled",
                    at: await clock.now()
                )
            }
            return await makeStatus(
                repository: repository,
                phase: .cancelled,
                errorCode: "cancelled",
                clock: clock
            )
        } catch let failure as SyncRemoteFailure {
            let phase: SyncPhase = failure == .unauthorized ? .unauthorized : .failed
            return await makeStatus(
                repository: repository,
                phase: phase,
                errorCode: failure.code,
                clock: clock
            )
        } catch {
            if let currentMutation {
                try? await repository.returnToQueue(
                    currentMutation,
                    errorCode: "sync_failed",
                    at: await clock.now()
                )
            }
            return await makeStatus(
                repository: repository,
                phase: .failed,
                errorCode: "sync_failed",
                clock: clock
            )
        }
    }

    private static func makeStatus(
        repository: any SyncRepository,
        phase: SyncPhase,
        errorCode: String?,
        clock: any SyncClock
    ) async -> SyncStatus {
        SyncStatus(
            phase: phase,
            pendingCount: (try? await repository.pendingCount()) ?? 0,
            conflictCount: (try? await repository.conflictCount()) ?? 0,
            lastErrorCode: errorCode,
            updatedAt: await clock.now()
        )
    }
}

private extension SyncRemoteFailure {
    var code: String {
        switch self {
        case .unauthorized: "unauthorized"
        case let .conflict(code, _, _, _), let .permanent(code, _), let .transient(code): code
        }
    }
}
