import Foundation

enum NavigationOrigin: String, Codable, Equatable, Sendable {
    case planner
    case calendar
    case focus
}

enum DeepLinkIntent: Equatable, Sendable {
    case task(taskID: UUID, origin: NavigationOrigin)
    case focus
}

enum DeepLinkParser {
    static func parse(_ url: URL, origin: NavigationOrigin = .planner) -> DeepLinkIntent? {
        guard url.scheme == "rocketflow",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.query == nil,
              url.fragment == nil else {
            return nil
        }
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        switch (url.host, parts) {
        case ("focus", []):
            return .focus
        case let ("task", [rawID]):
            guard let taskID = UUID(uuidString: rawID) else { return nil }
            return .task(taskID: taskID, origin: origin)
        default:
            return nil
        }
    }
}

enum TaskDeepLinkAccess: Equatable, Sendable {
    case accessible
    case inaccessible
    case missing
}

protocol TaskDeepLinkAccessChecking: Sendable {
    func access(taskID: UUID) async throws -> TaskDeepLinkAccess
}

enum DeepLinkDestination: Equatable, Sendable {
    case task(taskID: UUID, origin: NavigationOrigin)
    case focus
    case planner
}

struct DeepLinkResolution: Equatable, Sendable {
    let destination: DeepLinkDestination
    let errorMessage: String?
}

enum DeepLinkReceiveResult: Equatable, Sendable {
    case rejected
    case waitingForAuthentication
    case unauthorized
    case resolved(DeepLinkResolution)
}

protocol DeepLinkUnauthorizedHandling: Sendable {
    func handleDeepLinkUnauthorized() async
}

struct NoopDeepLinkUnauthorizedHandler: DeepLinkUnauthorizedHandling {
    func handleDeepLinkUnauthorized() async {}
}

actor DeepLinkCoordinator {
    private struct PendingIntent: Sendable {
        let id: UUID
        let intent: DeepLinkIntent
    }

    private enum ResolutionAttempt {
        case resolved(DeepLinkResolution)
        case unauthorized
    }

    private let accessChecker: any TaskDeepLinkAccessChecking
    private let unauthorizedHandler: any DeepLinkUnauthorizedHandling
    private var pending: PendingIntent?

    init(
        accessChecker: any TaskDeepLinkAccessChecking,
        unauthorizedHandler: any DeepLinkUnauthorizedHandling = NoopDeepLinkUnauthorizedHandler()
    ) {
        self.accessChecker = accessChecker
        self.unauthorizedHandler = unauthorizedHandler
    }

    func receive(
        _ url: URL,
        authenticated: Bool,
        origin: NavigationOrigin = .planner,
        language: AppLanguage
    ) async -> DeepLinkReceiveResult {
        guard let intent = DeepLinkParser.parse(url, origin: origin) else { return .rejected }
        let candidate = PendingIntent(id: UUID(), intent: intent)
        pending = candidate
        guard authenticated else {
            return .waitingForAuthentication
        }
        switch await resolve(intent, language: language) {
        case let .resolved(resolution):
            consume(candidate)
            return .resolved(resolution)
        case .unauthorized:
            await unauthorizedHandler.handleDeepLinkUnauthorized()
            return .unauthorized
        }
    }

    func authenticationDidSucceed(language: AppLanguage) async -> DeepLinkResolution? {
        guard let candidate = pending else { return nil }
        switch await resolve(candidate.intent, language: language) {
        case let .resolved(resolution):
            consume(candidate)
            return resolution
        case .unauthorized:
            await unauthorizedHandler.handleDeepLinkUnauthorized()
            return nil
        }
    }

    func authenticationDidFail() {
        pending = nil
    }

    func clear() {
        pending = nil
    }

    private func resolve(_ intent: DeepLinkIntent, language: AppLanguage) async -> ResolutionAttempt {
        switch intent {
        case .focus:
            return .resolved(DeepLinkResolution(destination: .focus, errorMessage: nil))
        case let .task(taskID, origin):
            do {
                switch try await accessChecker.access(taskID: taskID) {
                case .accessible:
                    return .resolved(DeepLinkResolution(
                        destination: .task(taskID: taskID, origin: origin),
                        errorMessage: nil
                    ))
                case .inaccessible:
                    return .resolved(fallback(message: language == .ru
                        ? "У вас нет доступа к этой задаче"
                        : "You do not have access to this task"))
                case .missing:
                    return .resolved(fallback(message: language == .ru
                        ? "Задача больше не существует"
                        : "This task no longer exists"))
                }
            } catch let api as APIError where api.isUnauthorized {
                return .unauthorized
            } catch {
                return .resolved(fallback(message: language == .ru
                    ? "Не удалось открыть задачу"
                    : "The task could not be opened"))
            }
        }
    }

    private func consume(_ candidate: PendingIntent) {
        guard pending?.id == candidate.id else { return }
        pending = nil
    }

    private func fallback(message: String) -> DeepLinkResolution {
        DeepLinkResolution(destination: .planner, errorMessage: message)
    }
}
