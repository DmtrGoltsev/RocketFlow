import Foundation

actor AuthService {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func login(email: String, password: String) async throws -> AuthResponseDTO {
        try await client.send(
            AuthEndpoints.login(.init(email: email, password: password)),
            bearerToken: nil
        )
    }

    func register(
        email: String,
        password: String,
        displayName: String,
        timezone: String,
        language: AppLanguage
    ) async throws -> AuthResponseDTO {
        try await client.send(
            AuthEndpoints.register(
                .init(
                    email: email,
                    password: password,
                    displayName: displayName,
                    timezone: timezone,
                    language: language
                )
            ),
            bearerToken: nil
        )
    }

    func refresh(refreshToken: String) async throws -> TokensDTO {
        let response: RefreshResponseDTO = try await client.send(
            AuthEndpoints.refresh(.init(refreshToken: refreshToken)),
            bearerToken: nil
        )
        return response.tokens
    }

    func currentUser(accessToken: String) async throws -> UserDTO {
        try await client.send(AuthEndpoints.me, bearerToken: accessToken)
    }

    func logout(accessToken: String, refreshToken: String) async throws {
        let _: EmptyResponse = try await client.send(
            AuthEndpoints.logout(.init(refreshToken: refreshToken)),
            bearerToken: accessToken
        )
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint<Response>,
        accessToken: String
    ) async throws -> Response {
        try await client.send(endpoint, bearerToken: accessToken)
    }
}
