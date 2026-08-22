import Foundation

enum SessionRestoration: Equatable, Sendable {
    case signedOut
    case authenticated(UserDTO)
    case offline(UserDTO)
}

enum AuthSessionError: Error, Equatable, Sendable, LocalizedError {
    case sessionMissing
    case sessionReplaced
    case sessionPersistenceFailed

    var errorDescription: String? {
        switch self {
        case .sessionMissing: "The authenticated session is missing."
        case .sessionReplaced: "The authenticated session changed while the request was running."
        case .sessionPersistenceFailed: "The refreshed session could not be stored securely."
        }
    }
}

actor AuthSession {
    private struct RefreshFlight: Sendable {
        let id: UUID
        let sessionID: UUID
        let task: Task<SessionSnapshot, Error>
    }

    private let service: AuthService
    private let store: any SessionStore
    private var current: SessionSnapshot?
    private var refreshFlight: RefreshFlight?

    init(service: AuthService, store: any SessionStore) {
        self.service = service
        self.store = store
    }

    func restore() async -> SessionRestoration {
        let stored: SessionSnapshot
        do {
            guard let value = try await store.load() else {
                current = nil
                return .signedOut
            }
            stored = value
            current = value
        } catch {
            current = nil
            return .signedOut
        }

        do {
            let user = try await service.currentUser(accessToken: stored.tokens.accessToken)
            let updated = SessionSnapshot(
                id: stored.id,
                user: user,
                tokens: stored.tokens,
                storedAt: Date()
            )
            if try await store.replace(updated, matching: stored.id) {
                current = updated
                return .authenticated(user)
            }
            return .signedOut
        } catch let error as APIError where error.isUnauthorized {
            do {
                let refreshed = try await refreshedSession(expected: stored)
                return .authenticated(refreshed.user)
            } catch let refreshError as APIError {
                return refreshError.isUnauthorized ? .signedOut : .offline(stored.user)
            } catch is AuthSessionError {
                return .signedOut
            } catch {
                return .offline(stored.user)
            }
        } catch {
            return .offline(stored.user)
        }
    }

    @discardableResult
    func login(email: String, password: String) async throws -> UserDTO {
        let response = try await service.login(email: email, password: password)
        let session = SessionSnapshot(user: response.user, tokens: response.tokens)
        try await store.save(session)
        current = session
        refreshFlight = nil
        return response.user
    }

    @discardableResult
    func register(
        email: String,
        password: String,
        displayName: String,
        timezone: String,
        language: AppLanguage
    ) async throws -> UserDTO {
        let response = try await service.register(
            email: email,
            password: password,
            displayName: displayName,
            timezone: timezone,
            language: language
        )
        let session = SessionSnapshot(user: response.user, tokens: response.tokens)
        try await store.save(session)
        current = session
        refreshFlight = nil
        return response.user
    }

    func logout() async {
        let session = current ?? (try? await store.load())
        if let session {
            do {
                try await service.logout(
                    accessToken: session.tokens.accessToken,
                    refreshToken: session.tokens.refreshToken
                )
            } catch {
                // Local logout is authoritative even when the server is unavailable.
            }
            _ = try? await store.clear(matching: session.id)
            if current?.id == session.id {
                current = nil
            }
        } else {
            _ = try? await store.clear(matching: nil)
            current = nil
        }
        refreshFlight = nil
    }

    func user() -> UserDTO? {
        current?.user
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint<Response>
    ) async throws -> Response {
        guard endpoint.requiresAuthorization else {
            throw APIClientFailure.missingAuthorization
        }
        guard let initial = current else {
            throw AuthSessionError.sessionMissing
        }

        do {
            return try await service.send(endpoint, accessToken: initial.tokens.accessToken)
        } catch let error as APIError where error.isUnauthorized {
            let refreshed = try await refreshedSession(expected: initial)
            do {
                return try await service.send(endpoint, accessToken: refreshed.tokens.accessToken)
            } catch let retryError as APIError where retryError.isUnauthorized {
                await clearIfCurrent(refreshed)
                throw retryError
            }
        }
    }

    private func refreshedSession(expected: SessionSnapshot) async throws -> SessionSnapshot {
        guard let current else {
            throw AuthSessionError.sessionMissing
        }
        guard current.id == expected.id else {
            throw AuthSessionError.sessionReplaced
        }
        if current.tokens.refreshToken != expected.tokens.refreshToken {
            return current
        }

        let flight: RefreshFlight
        if let active = refreshFlight, active.sessionID == expected.id {
            flight = active
        } else {
            let service = self.service
            let store = self.store
            let refreshToken = expected.tokens.refreshToken
            let task = Task {
                let tokens = try await service.refresh(refreshToken: refreshToken)
                let provisional = SessionSnapshot(
                    id: expected.id,
                    user: expected.user,
                    tokens: tokens,
                    storedAt: Date()
                )
                do {
                    guard try await store.replace(provisional, matching: expected.id) else {
                        throw AuthSessionError.sessionReplaced
                    }
                } catch let error as AuthSessionError {
                    throw error
                } catch {
                    throw AuthSessionError.sessionPersistenceFailed
                }

                let user = try await service.currentUser(accessToken: tokens.accessToken)
                let refreshed = SessionSnapshot(
                    id: expected.id,
                    user: user,
                    tokens: tokens,
                    storedAt: Date()
                )
                do {
                    guard try await store.replace(refreshed, matching: expected.id) else {
                        throw AuthSessionError.sessionReplaced
                    }
                } catch let error as AuthSessionError {
                    throw error
                } catch {
                    throw AuthSessionError.sessionPersistenceFailed
                }
                return refreshed
            }
            flight = RefreshFlight(id: UUID(), sessionID: expected.id, task: task)
            refreshFlight = flight
        }

        let refreshed: SessionSnapshot
        do {
            refreshed = try await flight.task.value
        } catch {
            if refreshFlight?.id == flight.id {
                refreshFlight = nil
            }
            if let apiError = error as? APIError, apiError.isUnauthorized {
                await clearIfCurrent(expected)
            } else if error as? AuthSessionError == .sessionPersistenceFailed {
                await clearIfCurrent(expected)
            } else {
                await reconcileCurrentSession(expectedID: expected.id)
            }
            throw error
        }

        if refreshFlight?.id == flight.id {
            refreshFlight = nil
        }
        guard let active = current, active.id == expected.id else {
            throw AuthSessionError.sessionReplaced
        }
        if active.tokens.refreshToken == refreshed.tokens.refreshToken {
            return active
        }
        guard
            active.tokens.refreshToken == expected.tokens.refreshToken,
            refreshed.id == active.id
        else {
            throw AuthSessionError.sessionReplaced
        }
        current = refreshed
        return refreshed
    }

    private func reconcileCurrentSession(expectedID: UUID) async {
        do {
            let stored = try await store.load()
            guard current?.id == expectedID else { return }
            current = stored?.id == expectedID ? stored : nil
        } catch {
            // Keep the in-memory session when secure storage cannot be inspected.
        }
    }

    private func clearIfCurrent(_ failed: SessionSnapshot) async {
        _ = try? await store.clear(matching: failed.id)
        if current?.id == failed.id {
            current = nil
        }
        if refreshFlight?.sessionID == failed.id {
            refreshFlight?.task.cancel()
            refreshFlight = nil
        }
    }
}
