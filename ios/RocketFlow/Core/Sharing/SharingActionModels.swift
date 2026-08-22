import Foundation

enum ShareableResourceKind: String, CaseIterable, Sendable {
    case folder
    case goal
    case task
    case idea

    var pathSegment: String { "\(rawValue)s" }
}

struct SharingInvitationRequest: Encodable, Equatable, Sendable {
    let email: String?
    let userId: UUID?
    let fullAccess: Bool?

    init(
        email: String? = nil,
        userId: UUID? = nil,
        fullAccess: Bool? = nil
    ) throws {
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasEmail = normalizedEmail?.isEmpty == false
        let hasUserID = userId != nil
        guard hasEmail != hasUserID, email == nil || hasEmail else {
            throw RemoteActionError.validation(
                message: "Share request requires exactly one of email or userId.",
                fieldErrors: ["recipient": "Choose one recipient."]
            )
        }
        self.email = hasEmail ? normalizedEmail : nil
        self.userId = userId
        self.fullAccess = fullAccess
    }
}

struct ActionSharedFolderResourceDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let description: String?
    let displayOrder: Int
    let archived: Bool
    let shared: Bool
    let fullAccess: Bool
    let canAccessFolderContent: Bool
    let version: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct ActionSharedResourcesResponseDTO: Codable, Equatable, Sendable {
    let folders: [ActionSharedFolderResourceDTO]
    let goals: [ActionGoalDTO]
    let tasks: [ActionTaskDTO]
    let ideas: [ActionIdeaDTO]
    let createTaskGoalIds: [UUID]
}

protocol SharingServicing: Sendable {
    func createInvitation(
        resource: ShareableResourceKind,
        id: UUID,
        request: SharingInvitationRequest
    ) async throws -> ShareInvitationDTO
    func listInvitations() async throws -> [ShareInvitationDTO]
    func acceptInvitation(id: UUID) async throws -> ShareInvitationActionResponseDTO
    func declineInvitation(id: UUID) async throws -> ShareInvitationActionResponseDTO
    func revokeInvitation(id: UUID) async throws -> ShareInvitationActionResponseDTO

    func createShareLink(
        resource: ShareableResourceKind,
        id: UUID,
        request: ShareLinkRequestDTO?
    ) async throws -> ShareLinkCreateResponseDTO
    func listShareLinks(resource: ShareableResourceKind, id: UUID) async throws -> [ShareLinkDTO]
    func resolveShareLink(token: String) async throws -> ShareLinkResolveResponseDTO
    func acceptShareLink(token: String) async throws -> ShareLinkAcceptResponseDTO
    func revokeShareLink(id: UUID) async throws -> ShareLinkActionResponseDTO
    func listSharedResources() async throws -> ActionSharedResourcesResponseDTO
}
