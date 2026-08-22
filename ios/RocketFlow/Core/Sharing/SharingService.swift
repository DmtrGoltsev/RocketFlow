import Foundation

struct SharingService: SharingServicing, Sendable {
    private let transport: AuthenticatedActionTransport

    init(sender: any AuthenticatedRequestSending) {
        transport = AuthenticatedActionTransport(sender: sender)
    }

    func createInvitation(
        resource: ShareableResourceKind,
        id: UUID,
        request: SharingInvitationRequest
    ) async throws -> ShareInvitationDTO {
        try await transport.send(
            Endpoint(
                method: .post,
                path: [resource.pathSegment, id.wire, "share"],
                body: request
            )
        )
    }

    func listInvitations() async throws -> [ShareInvitationDTO] {
        let response: ShareInvitationListResponseDTO = try await transport.send(
            Endpoint(method: .get, path: ["shares", "invitations"])
        )
        return response.items
    }

    func acceptInvitation(id: UUID) async throws -> ShareInvitationActionResponseDTO {
        try await invitationAction(id: id, action: "accept")
    }

    func declineInvitation(id: UUID) async throws -> ShareInvitationActionResponseDTO {
        try await invitationAction(id: id, action: "decline")
    }

    func revokeInvitation(id: UUID) async throws -> ShareInvitationActionResponseDTO {
        try await invitationAction(id: id, action: "revoke")
    }

    func createShareLink(
        resource: ShareableResourceKind,
        id: UUID,
        request: ShareLinkRequestDTO?
    ) async throws -> ShareLinkCreateResponseDTO {
        let path = [resource.pathSegment, id.wire, "share-links"]
        let endpoint: Endpoint<ShareLinkCreateResponseDTO>
        if let request {
            endpoint = try Endpoint(method: .post, path: path, body: request)
        } else {
            endpoint = Endpoint(method: .post, path: path)
        }
        return try await transport.send(endpoint)
    }

    func listShareLinks(resource: ShareableResourceKind, id: UUID) async throws -> [ShareLinkDTO] {
        let response: ShareLinkListResponseDTO = try await transport.send(
            Endpoint(method: .get, path: [resource.pathSegment, id.wire, "share-links"])
        )
        return response.items
    }

    func resolveShareLink(token: String) async throws -> ShareLinkResolveResponseDTO {
        try await transport.send(Endpoint(method: .get, path: ["shares", "links", token]))
    }

    func acceptShareLink(token: String) async throws -> ShareLinkAcceptResponseDTO {
        try await transport.send(Endpoint(method: .post, path: ["shares", "links", token, "accept"]))
    }

    func revokeShareLink(id: UUID) async throws -> ShareLinkActionResponseDTO {
        try await transport.send(
            Endpoint(method: .post, path: ["shares", "links", id.wire, "revoke"])
        )
    }

    func listSharedResources() async throws -> ActionSharedResourcesResponseDTO {
        try await transport.send(Endpoint(method: .get, path: ["shares", "resources"]))
    }

    private func invitationAction(
        id: UUID,
        action: String
    ) async throws -> ShareInvitationActionResponseDTO {
        try await transport.send(
            Endpoint(method: .post, path: ["shares", "invitations", id.wire, action])
        )
    }
}

private extension UUID {
    var wire: String { uuidString.lowercased() }
}
