import Foundation

protocol SessionStore: Sendable {
    func load() async throws -> SessionSnapshot?
    func save(_ session: SessionSnapshot) async throws
    func replace(_ session: SessionSnapshot, matching sessionID: UUID) async throws -> Bool
    func clear(matching sessionID: UUID?) async throws -> Bool
}

actor InMemorySessionStore: SessionStore {
    private var session: SessionSnapshot?

    init(session: SessionSnapshot? = nil) {
        self.session = session
    }

    func load() -> SessionSnapshot? {
        session
    }

    func save(_ session: SessionSnapshot) {
        self.session = session
    }

    func replace(_ session: SessionSnapshot, matching sessionID: UUID) -> Bool {
        guard self.session?.id == sessionID else { return false }
        self.session = session
        return true
    }

    func clear(matching sessionID: UUID?) -> Bool {
        guard sessionID == nil || session?.id == sessionID else { return false }
        let containedSession = session != nil
        session = nil
        return containedSession
    }
}
