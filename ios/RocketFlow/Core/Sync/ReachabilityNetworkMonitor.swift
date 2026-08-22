import Foundation
import Network

final class ReachabilityNetworkMonitor: NetworkMonitoring, @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var connected = false
    private var started = false
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init(monitor: NWPathMonitor = NWPathMonitor(), startImmediately: Bool = true) {
        self.monitor = monitor
        queue = DispatchQueue(label: "com.rocketflow.companion.ios.reachability")
        monitor.pathUpdateHandler = { [weak self] path in
            self?.publish(path.status == .satisfied)
        }
        if startImmediately {
            start()
        }
    }

    deinit {
        cancel()
    }

    func start() {
        let shouldStart = lock.synchronized { () -> Bool in
            guard !started else { return false }
            started = true
            return true
        }
        if shouldStart {
            monitor.start(queue: queue)
        }
    }

    func cancel() {
        let activeContinuations = lock.synchronized { () -> [AsyncStream<Bool>.Continuation] in
            guard started || !continuations.isEmpty else { return [] }
            started = false
            let values = Array(continuations.values)
            continuations.removeAll()
            return values
        }
        monitor.cancel()
        activeContinuations.forEach { $0.finish() }
    }

    func isConnected() async -> Bool {
        lock.synchronized { connected }
    }

    func changes() -> AsyncStream<Bool> {
        let id = UUID()
        let stream = AsyncStream<Bool>.makeStream()
        let initial = lock.synchronized { () -> Bool in
            continuations[id] = stream.continuation
            return connected
        }
        stream.continuation.yield(initial)
        stream.continuation.onTermination = { [weak self] _ in
            self?.removeContinuation(id)
        }
        return stream.stream
    }

    private func publish(_ value: Bool) {
        let values = lock.synchronized { () -> [AsyncStream<Bool>.Continuation] in
            guard connected != value else { return [] }
            connected = value
            return Array(continuations.values)
        }
        values.forEach { $0.yield(value) }
    }

    private func removeContinuation(_ id: UUID) {
        _ = lock.synchronized { continuations.removeValue(forKey: id) }
    }
}

actor ManualNetworkMonitor: NetworkMonitoring {
    private var connected: Bool
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init(connected: Bool) {
        self.connected = connected
    }

    func isConnected() -> Bool { connected }

    func changes() -> AsyncStream<Bool> {
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

    func setConnected(_ value: Bool) {
        guard connected != value else { return }
        connected = value
        continuations.values.forEach { $0.yield(value) }
    }

    func finish() {
        continuations.values.forEach { $0.finish() }
        continuations.removeAll()
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

private extension NSLock {
    func synchronized<Value>(_ operation: () throws -> Value) rethrows -> Value {
        lock()
        defer { unlock() }
        return try operation()
    }
}
