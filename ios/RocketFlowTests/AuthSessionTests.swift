import Foundation
import XCTest
@testable import RocketFlow

private actor AuthRoutingClient: APIClientProtocol {
    private(set) var refreshCount = 0
    private(set) var protectedCount = 0
    var refreshIsTerminal = false
    var logoutFails = false
    var oldMeIsUnauthorized = false
    var refreshedMeFailsOnce = false

    func configure(
        refreshIsTerminal: Bool? = nil,
        logoutFails: Bool? = nil,
        oldMeIsUnauthorized: Bool? = nil,
        refreshedMeFailsOnce: Bool? = nil
    ) {
        if let refreshIsTerminal { self.refreshIsTerminal = refreshIsTerminal }
        if let logoutFails { self.logoutFails = logoutFails }
        if let oldMeIsUnauthorized { self.oldMeIsUnauthorized = oldMeIsUnauthorized }
        if let refreshedMeFailsOnce { self.refreshedMeFailsOnce = refreshedMeFailsOnce }
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint<Response>,
        bearerToken: String?
    ) async throws -> Response {
        let path = endpoint.pathSegments.joined(separator: "/")
        switch path {
        case "me":
            if bearerToken == "old-access", oldMeIsUnauthorized {
                throw unauthorized()
            }
            if bearerToken == "new-access", refreshedMeFailsOnce {
                refreshedMeFailsOnce = false
                throw URLError(.notConnectedToInternet)
            }
            return try decode(user(), as: Response.self)
        case "auth/refresh":
            refreshCount += 1
            if refreshIsTerminal { throw unauthorized() }
            return try decode(
                RefreshResponseDTO(
                    tokens: TokensDTO(
                        accessToken: "new-access",
                        refreshToken: "new-refresh",
                        expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
                    )
                ),
                as: Response.self
            )
        case "auth/login":
            return try decode(
                AuthResponseDTO(
                    user: user(),
                    tokens: TokensDTO(
                        accessToken: "login-access",
                        refreshToken: "login-refresh",
                        expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
                    )
                ),
                as: Response.self
            )
        case "auth/logout":
            if logoutFails { throw URLError(.notConnectedToInternet) }
            return try decode(EmptyResponse(), as: Response.self)
        case "protected":
            protectedCount += 1
            if bearerToken == "old-access" { throw unauthorized() }
            return try decode(EmptyResponse(), as: Response.self)
        default:
            throw URLError(.unsupportedURL)
        }
    }

    private func decode<Response: Decodable, Value: Encodable>(
        _ value: Value,
        as: Response.Type
    ) throws -> Response {
        try WireJSON.decoder().decode(Response.self, from: WireJSON.encoder().encode(value))
    }

    private func unauthorized() -> APIError {
        APIError(
            statusCode: 401,
            code: "authentication_failed",
            message: "Unauthorized",
            details: [],
            traceID: nil,
            requestID: UUID()
        )
    }

    private func user() -> UserDTO {
        UserDTO(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            email: "user@example.com",
            displayName: "User",
            timezone: "Europe/Moscow",
            language: .ru,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

final class AuthSessionTests: XCTestCase {
    func testConcurrent401RequestsUseSingleRefreshAndRetryOnce() async throws {
        let fixture = makeFixture()
        let restoration = await fixture.session.restore()
        XCTAssertEqual(restoration, .authenticated(fixture.snapshot.user))
        let endpoint = Endpoint<EmptyResponse>(method: .get, path: ["protected"])

        async let first: EmptyResponse = fixture.session.send(endpoint)
        async let second: EmptyResponse = fixture.session.send(endpoint)
        _ = try await (first, second)

        let refreshCount = await fixture.client.refreshCount
        let protectedCount = await fixture.client.protectedCount
        XCTAssertEqual(refreshCount, 1)
        XCTAssertLessThanOrEqual(protectedCount, 4)
        let stored = try await fixture.store.load()
        XCTAssertEqual(stored?.tokens.refreshToken, "new-refresh")
    }

    func testTerminalRefreshClearsMatchingSession() async throws {
        let fixture = makeFixture()
        _ = await fixture.session.restore()
        await fixture.client.configure(refreshIsTerminal: true)

        do {
            let _: EmptyResponse = try await fixture.session.send(
                Endpoint(method: .get, path: ["protected"])
            )
            XCTFail("Expected unauthorized error")
        } catch let error as APIError {
            XCTAssertTrue(error.isUnauthorized)
        }

        let stored = try await fixture.store.load()
        let user = await fixture.session.user()
        XCTAssertNil(stored)
        XCTAssertNil(user)
    }

    func testTerminalRefreshDuringRestoreReturnsSignedOutAndClearsSession() async throws {
        let fixture = makeFixture()
        await fixture.client.configure(refreshIsTerminal: true, oldMeIsUnauthorized: true)

        let restoration = await fixture.session.restore()

        XCTAssertEqual(restoration, .signedOut)
        let stored = try await fixture.store.load()
        let user = await fixture.session.user()
        XCTAssertNil(stored)
        XCTAssertNil(user)
    }

    func testRotatedTokensSurviveTransientCurrentUserFailure() async throws {
        let fixture = makeFixture()
        _ = await fixture.session.restore()
        await fixture.client.configure(refreshedMeFailsOnce: true)

        do {
            let _: EmptyResponse = try await fixture.session.send(
                Endpoint(method: .get, path: ["protected"])
            )
            XCTFail("Expected transient network failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        }

        let storedAfterFailure = try await fixture.store.load()
        XCTAssertEqual(storedAfterFailure?.tokens.refreshToken, "new-refresh")

        let _: EmptyResponse = try await fixture.session.send(
            Endpoint(method: .get, path: ["protected"])
        )
        let refreshCount = await fixture.client.refreshCount
        XCTAssertEqual(refreshCount, 1)
    }

    func testLocalLogoutClearsSessionWhenNetworkFails() async throws {
        let fixture = makeFixture()
        _ = await fixture.session.restore()
        await fixture.client.configure(logoutFails: true)

        await fixture.session.logout()

        let stored = try await fixture.store.load()
        let user = await fixture.session.user()
        XCTAssertNil(stored)
        XCTAssertNil(user)
    }

    private func makeFixture() -> (
        session: AuthSession,
        client: AuthRoutingClient,
        store: InMemorySessionStore,
        snapshot: SessionSnapshot
    ) {
        let user = UserDTO(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            email: "user@example.com",
            displayName: "User",
            timezone: "Europe/Moscow",
            language: .ru,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let snapshot = SessionSnapshot(
            user: user,
            tokens: TokensDTO(
                accessToken: "old-access",
                refreshToken: "old-refresh",
                expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        let client = AuthRoutingClient()
        let store = InMemorySessionStore(session: snapshot)
        let service = AuthService(client: client)
        return (AuthSession(service: service, store: store), client, store, snapshot)
    }
}
