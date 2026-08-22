import Foundation

enum LinkedEntityType: String, Codable, CaseIterable, Sendable {
    case goal
    case task
    case idea
    case note
}

enum EntityRelationType: String, Codable, CaseIterable, Sendable {
    case related
    case dependency
}

struct EntityReferenceDTO: Codable, Equatable, Sendable, Identifiable {
    let type: LinkedEntityType
    let id: UUID
    let title: String
    let subtitle: String?
    let status: String?
    let path: String?
    let archived: Bool?
    let accessible: Bool
    let redacted: Bool
}

struct EntityLinkDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let source: EntityReferenceDTO
    let target: EntityReferenceDTO
    let relationType: EntityRelationType
    let createdByUserId: UUID?
    let createdByName: String?
    let createdAt: Date
    let updatedAt: Date
    let version: Int64
}

struct EntityLinkListResponseDTO: Codable, Equatable, Sendable {
    let items: [EntityLinkDTO]
}

struct CreateEntityLinkRequestDTO: Codable, Equatable, Sendable {
    let sourceType: LinkedEntityType
    let sourceId: UUID
    let targetType: LinkedEntityType
    let targetId: UUID
    let relationType: EntityRelationType
}

struct UpdateEntityLinkRequestDTO: Codable, Equatable, Sendable {
    let relationType: EntityRelationType
    let version: Int64
}

struct ShareInvitationDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let targetType: String
    let targetId: UUID
    let targetEmail: String?
    let targetUserId: UUID?
    let fullAccess: Bool
    let status: String
    let createdAt: Date
    let expiresAt: Date?
}

struct ShareInvitationListResponseDTO: Codable, Equatable, Sendable {
    let items: [ShareInvitationDTO]
}

struct ShareInvitationActionResponseDTO: Codable, Equatable, Sendable {
    let id: UUID
    let status: String
}

struct ShareLinkDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let targetType: String
    let targetId: UUID
    let fullAccess: Bool
    let status: String
    let createdAt: Date
    let expiresAt: Date?
    let revokedAt: Date?
}

struct ShareLinkCreateResponseDTO: Codable, Equatable, Sendable {
    let id: UUID
    let targetType: String
    let targetId: UUID
    let token: String
    let fullAccess: Bool
    let status: String
    let createdAt: Date
    let expiresAt: Date?
}

struct ShareLinkListResponseDTO: Codable, Equatable, Sendable {
    let items: [ShareLinkDTO]
}

struct ShareLinkActionResponseDTO: Codable, Equatable, Sendable {
    let id: UUID
    let status: String
}

struct ShareLinkResolveResponseDTO: Codable, Equatable, Sendable {
    let id: UUID
    let targetType: String
    let targetId: UUID
    let fullAccess: Bool
    let status: String
    let expiresAt: Date?
}

struct ShareLinkAcceptResponseDTO: Codable, Equatable, Sendable {
    let shareId: UUID
    let targetType: String
    let targetId: UUID
    let fullAccess: Bool
    let status: String
}

struct SharedFolderResourceDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let displayOrder: Int
    let archived: Bool
    let shared: Bool
    let fullAccess: Bool
    let canAccessFolderContent: Bool
    let version: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct SharedResourcesResponseDTO: Codable, Equatable, Sendable {
    let folders: [SharedFolderResourceDTO]
    let goals: [GoalDTO]
    let tasks: [TaskDTO]
    let ideas: [IdeaDTO]
    let createTaskGoalIds: [UUID]
}

struct ShareRequestDTO: Codable, Equatable, Sendable {
    let email: String?
    let userId: UUID?
    let fullAccess: Bool?
}

struct ShareLinkRequestDTO: Codable, Equatable, Sendable {
    let expiresAt: Date?
    let fullAccess: Bool?
}
