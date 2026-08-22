import BackgroundTasks
import Foundation

enum CoreSyncTrigger: String, Sendable {
    case foreground
    case networkAvailable
    case backgroundRefresh
}

protocol CoreSyncHook: Sendable {
    func synchronize(trigger: CoreSyncTrigger) async throws
}

struct SyncEngineCoreSyncHook: CoreSyncHook {
    let engine: SyncEngine

    func synchronize(trigger: CoreSyncTrigger) async throws {
        let status = await withTaskCancellationHandler {
            switch trigger {
            case .foreground:
                return await engine.syncOnForeground()
            case .networkAvailable:
                return await engine.syncWhenNetworkReturns()
            case .backgroundRefresh:
                return await engine.syncInBackground()
            }
        } onCancel: {
            Task { await engine.cancel() }
        }
        try Task.checkCancellation()
        switch status.phase {
        case .idle, .waitingForNetwork, .waitingForRetry:
            return
        case .syncing:
            return
        case .cancelled:
            throw CancellationError()
        case .unauthorized, .conflicted, .failed:
            throw BackgroundRefreshError.syncFailed(status.lastErrorCode)
        }
    }
}

enum BackgroundRefreshError: Error, Equatable, Sendable {
    case syncFailed(String?)
}

protocol BackgroundRefreshScheduling: Sendable {
    func submit(identifier: String, earliestBeginDate: Date) async throws
    func cancel(identifier: String) async
}

final class SystemBackgroundRefreshScheduler: BackgroundRefreshScheduling, @unchecked Sendable {
    private let scheduler: BGTaskScheduler

    init(scheduler: BGTaskScheduler = .shared) {
        self.scheduler = scheduler
    }

    func submit(identifier: String, earliestBeginDate: Date) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        try scheduler.submit(request)
    }

    func cancel(identifier: String) {
        scheduler.cancel(taskRequestWithIdentifier: identifier)
    }
}

protocol BackgroundRefreshTaskHandling: Sendable {
    func setExpirationHandler(_ handler: (@Sendable () -> Void)?)
    func complete(success: Bool)
}

final class SystemBackgroundRefreshTaskHandle: BackgroundRefreshTaskHandling, @unchecked Sendable {
    private let task: BGAppRefreshTask

    init(task: BGAppRefreshTask) {
        self.task = task
    }

    func setExpirationHandler(_ handler: (@Sendable () -> Void)?) {
        task.expirationHandler = handler
    }

    func complete(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}

actor BackgroundRefreshCoordinator {
    static let defaultIdentifier = "com.rocketflow.companion.ios.refresh"

    private let identifier: String
    private let scheduler: any BackgroundRefreshScheduling
    private let sync: any CoreSyncHook
    private let now: @Sendable () -> Date
    private let minimumDelay: TimeInterval

    init(
        identifier: String = BackgroundRefreshCoordinator.defaultIdentifier,
        scheduler: any BackgroundRefreshScheduling,
        sync: any CoreSyncHook,
        now: @escaping @Sendable () -> Date = Date.init,
        minimumDelay: TimeInterval = 15 * 60
    ) {
        self.identifier = identifier
        self.scheduler = scheduler
        self.sync = sync
        self.now = now
        self.minimumDelay = max(minimumDelay, 15 * 60)
    }

    func scheduleNext() async throws {
        await scheduler.cancel(identifier: identifier)
        try await scheduler.submit(
            identifier: identifier,
            earliestBeginDate: now().addingTimeInterval(minimumDelay)
        )
    }

    @discardableResult
    func handle(_ task: any BackgroundRefreshTaskHandling) async -> Bool {
        let sync = self.sync
        let work = Task {
            try await sync.synchronize(trigger: .backgroundRefresh)
            try Task.checkCancellation()
        }
        task.setExpirationHandler { work.cancel() }

        let synchronized = await withTaskCancellationHandler {
            do {
                try await work.value
                return true
            } catch {
                return false
            }
        } onCancel: {
            work.cancel()
        }
        task.setExpirationHandler(nil)

        let rescheduled: Bool
        do {
            try await scheduleNext()
            rescheduled = true
        } catch {
            rescheduled = false
        }
        let success = synchronized && rescheduled
        task.complete(success: success)
        return success
    }
}

@MainActor
final class SystemBackgroundRefreshRegistrar {
    private let scheduler: BGTaskScheduler

    init(scheduler: BGTaskScheduler = .shared) {
        self.scheduler = scheduler
    }

    @discardableResult
    func register(
        identifier: String = BackgroundRefreshCoordinator.defaultIdentifier,
        coordinator: BackgroundRefreshCoordinator
    ) -> Bool {
        scheduler.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let handle = SystemBackgroundRefreshTaskHandle(task: refreshTask)
            Task { await coordinator.handle(handle) }
        }
    }
}

actor ApplicationSyncTriggerCoordinator {
    private let sync: any CoreSyncHook
    private var networkObservation: Task<Void, Never>?

    init(sync: any CoreSyncHook) {
        self.sync = sync
    }

    func foreground() async {
        _ = try? await sync.synchronize(trigger: .foreground)
    }

    func networkBecameAvailable() async {
        _ = try? await sync.synchronize(trigger: .networkAvailable)
    }

    func startNetworkObservation(_ monitor: any NetworkMonitoring) {
        networkObservation?.cancel()
        let sync = self.sync
        networkObservation = Task {
            let changes = await monitor.changes()
            var wasConnected = false
            for await connected in changes {
                guard !Task.isCancelled else { return }
                if connected && !wasConnected {
                    _ = try? await sync.synchronize(trigger: .networkAvailable)
                }
                wasConnected = connected
            }
        }
    }

    func stopNetworkObservation() {
        networkObservation?.cancel()
        networkObservation = nil
    }
}
