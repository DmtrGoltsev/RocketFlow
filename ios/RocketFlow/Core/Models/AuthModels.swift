import Foundation

enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case ru
    case en
}

struct UserDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let email: String
    let displayName: String
    let timezone: String
    let language: AppLanguage
    let createdAt: Date
}

struct TokensDTO: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

struct AuthResponseDTO: Codable, Equatable, Sendable {
    let user: UserDTO
    let tokens: TokensDTO
}

struct RefreshResponseDTO: Codable, Equatable, Sendable {
    let tokens: TokensDTO
}

struct LoginRequestDTO: Codable, Equatable, Sendable {
    let email: String
    let password: String
}

struct RegisterRequestDTO: Codable, Equatable, Sendable {
    let email: String
    let password: String
    let displayName: String
    let timezone: String
    let language: AppLanguage
}

struct RefreshRequestDTO: Codable, Equatable, Sendable {
    let refreshToken: String
}

struct LogoutRequestDTO: Codable, Equatable, Sendable {
    let refreshToken: String
}

struct SessionSnapshot: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let user: UserDTO
    let tokens: TokensDTO
    let storedAt: Date

    init(
        id: UUID = UUID(),
        user: UserDTO,
        tokens: TokensDTO,
        storedAt: Date = Date()
    ) {
        self.id = id
        self.user = user
        self.tokens = tokens
        self.storedAt = storedAt
    }
}
