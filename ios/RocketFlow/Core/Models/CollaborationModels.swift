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
    struct Identity: Equatable, Sendable {
        let type: LinkedEntityType
        let id: UUID
        let title: String
    }

    private static let redactedPlaceholderID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    let type: LinkedEntityType
    let id: UUID
    let title: String
    let subtitle: String?
    let status: String?
    let path: String?
    let archived: Bool?
    let accessible: Bool
    let redacted: Bool

    private let identityAvailable: Bool

    var identity: Identity? {
        guard identityAvailable else { return nil }
        return Identity(type: type, id: id, title: title)
    }

    init(
        type: LinkedEntityType,
        id: UUID,
        title: String,
        subtitle: String?,
        status: String?,
        path: String?,
        archived: Bool?,
        accessible: Bool,
        redacted: Bool
    ) {
        self.type = type
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.path = path
        self.archived = archived
        self.accessible = accessible
        self.redacted = redacted
        identityAvailable = !redacted
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case title
        case subtitle
        case status
        case path
        case archived
        case accessible
        case redacted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedType = try container.decodeIfPresent(LinkedEntityType.self, forKey: .type)
        let decodedID = try container.decodeIfPresent(UUID.self, forKey: .id)
        let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title)
        let isRedacted = try container.decodeIfPresent(Bool.self, forKey: .redacted) ?? false
        let isAccessible = try container.decodeIfPresent(Bool.self, forKey: .accessible) ?? !isRedacted
        let hasIdentity = !isRedacted && decodedType != nil && decodedID != nil && decodedTitle != nil

        guard hasIdentity || isRedacted else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Non-redacted entity references require type, id, and title."
            )
        }

        type = decodedType ?? .task
        id = decodedID ?? Self.redactedPlaceholderID
        title = decodedTitle ?? ""
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived)
        accessible = isRedacted ? false : isAccessible
        redacted = isRedacted
        identityAvailable = hasIdentity
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if identityAvailable {
            try container.encode(type, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
        } else {
            try container.encodeNil(forKey: .type)
            try container.encodeNil(forKey: .id)
            try container.encodeNil(forKey: .title)
        }
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(path, forKey: .path)
        try container.encodeIfPresent(archived, forKey: .archived)
        try container.encode(accessible, forKey: .accessible)
        try container.encode(redacted, forKey: .redacted)
    }
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
