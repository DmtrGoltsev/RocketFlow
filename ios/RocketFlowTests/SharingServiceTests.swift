import Foundation
import XCTest
@testable import RocketFlow

private actor SharingRequestRecorder: AuthenticatedRequestSending {
    struct Captured: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data?
    }

    private var responses: [Data]
    private var captured: [Captured] = []

    init(responses: [Data]) {
        self.responses = responses
    }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let request = try endpoint.makeRequest(
            baseURL: URL(string: "https://example.test/rocket-api")!,
            bearerToken: "secret-test-token"
        ).urlRequest
        captured.append(
            Captured(
                method: request.httpMethod ?? "",
                path: request.url?.path ?? "",
                headers: request.allHTTPHeaderFields ?? [:],
                body: request.httpBody
            )
        )
        return try WireJSON.decoder().decode(Response.self, from: responses.removeFirst())
    }

    func requests() -> [Captured] { captured }
}

final class SharingServiceTests: XCTestCase {
    func testInvitationRecipientIsXorAndInvitationRoutesUsePostActions() async throws {
        XCTAssertThrowsError(try SharingInvitationRequest()) { error in
            guard let actionError = error as? RemoteActionError,
                  case .validation = actionError else {
                return XCTFail("Expected validation error, got \(error)")
            }
        }
        XCTAssertThrowsError(
            try SharingInvitationRequest(email: "person@example.com", userId: UUID())
        ) { error in
            guard let actionError = error as? RemoteActionError,
                  case .validation = actionError else {
                return XCTFail("Expected validation error, got \(error)")
            }
        }

        let resourceID = UUID(), invitationID = UUID(), userID = UUID()
        let invitationByEmail = invitationFixture(
            id: invitationID,
            targetType: "folder",
            targetID: resourceID,
            email: "person@example.com",
            userID: nil
        )
        let invitationByUser = invitationFixture(
            id: invitationID,
            targetType: "goal",
            targetID: resourceID,
            email: nil,
            userID: userID
        )
        let action = Data("{\"id\":\"\(invitationID)\",\"status\":\"accepted\"}".utf8)
        let sender = SharingRequestRecorder(responses: [
            invitationByEmail,
            invitationByUser,
            Data("{\"items\":[\(String(decoding: invitationByEmail, as: UTF8.self))]}".utf8),
            action,
            Data("{\"id\":\"\(invitationID)\",\"status\":\"declined\"}".utf8),
            Data("{\"id\":\"\(invitationID)\",\"status\":\"revoked\"}".utf8)
        ])
        let service = SharingService(sender: sender)

        _ = try await service.createInvitation(
            resource: .folder,
            id: resourceID,
            request: SharingInvitationRequest(email: " person@example.com ", fullAccess: true)
        )
        _ = try await service.createInvitation(
            resource: .goal,
            id: resourceID,
            request: SharingInvitationRequest(userId: userID, fullAccess: false)
        )
        _ = try await service.listInvitations()
        _ = try await service.acceptInvitation(id: invitationID)
        _ = try await service.declineInvitation(id: invitationID)
        _ = try await service.revokeInvitation(id: invitationID)

        let requests = await sender.requests()
        XCTAssertEqual(requests.map(\.method), ["POST", "POST", "GET", "POST", "POST", "POST"])
        XCTAssertEqual(requests.map(\.path), [
            "/rocket-api/folders/\(resourceID.wire)/share",
            "/rocket-api/goals/\(resourceID.wire)/share",
            "/rocket-api/shares/invitations",
            "/rocket-api/shares/invitations/\(invitationID.wire)/accept",
            "/rocket-api/shares/invitations/\(invitationID.wire)/decline",
            "/rocket-api/shares/invitations/\(invitationID.wire)/revoke"
        ])
        let emailBody = try body(requests[0])
        XCTAssertEqual(emailBody["email"] as? String, "person@example.com")
        XCTAssertNil(emailBody["userId"])
        XCTAssertEqual(emailBody["fullAccess"] as? Bool, true)
        XCTAssertNil(emailBody["idempotencyKey"])
        let userBody = try body(requests[1])
        XCTAssertNil(userBody["email"])
        XCTAssertEqual(try sharingDecodedUUID(userBody["userId"]), userID)
        XCTAssertEqual(header("Authorization", in: requests[0]), "Bearer secret-test-token")
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(header("X-Request-ID", in: requests[0]))))
        XCTAssertNil(header("Idempotency-Key", in: requests[0]))
        XCTAssertTrue(requests[3...5].allSatisfy { $0.body == nil })
    }

    func testShareLinkAndResourceRoutesMatchControllersWithoutListTokenLeakage() async throws {
        let resourceID = UUID(), linkID = UUID(), shareID = UUID()
        let resolveResponse = Data(
            "{\"id\":\"\(linkID)\",\"targetType\":\"folder\",\"targetId\":\"\(resourceID)\",\"fullAccess\":true,\"status\":\"active\",\"expiresAt\":null}".utf8
        )
        let acceptResponse = Data(
            "{\"shareId\":\"\(shareID)\",\"targetType\":\"folder\",\"targetId\":\"\(resourceID)\",\"fullAccess\":true,\"status\":\"active\"}".utf8
        )
        let revokeResponse = Data("{\"id\":\"\(linkID)\",\"status\":\"revoked\"}".utf8)
        let resourcesResponse = Data(
            "{\"folders\":[{\"id\":\"\(resourceID)\",\"name\":\"Shared\",\"description\":null,\"displayOrder\":0,\"archived\":false,\"shared\":true,\"fullAccess\":false,\"canAccessFolderContent\":true,\"version\":1,\"createdAt\":\"2024-08-22T10:00:00Z\",\"updatedAt\":\"2024-08-22T10:00:00Z\"}],\"goals\":[],\"tasks\":[],\"ideas\":[],\"createTaskGoalIds\":[]}".utf8
        )
        var responses: [Data] = []
        for resource in ShareableResourceKind.allCases {
            responses.append(
                shareLinkCreateFixture(
                    linkID: linkID,
                    targetType: resource.rawValue,
                    targetID: resourceID
                )
            )
            responses.append(
                shareLinkListFixture(
                    linkID: linkID,
                    targetType: resource.rawValue,
                    targetID: resourceID
                )
            )
        }
        responses.append(contentsOf: [resolveResponse, acceptResponse, revokeResponse, resourcesResponse])
        let sender = SharingRequestRecorder(responses: responses)
        let service = SharingService(sender: sender)
        let expiresAt = Date(timeIntervalSince1970: 1_824_323_200)
        var listed: [ShareLinkDTO] = []

        for resource in ShareableResourceKind.allCases {
            _ = try await service.createShareLink(
                resource: resource,
                id: resourceID,
                request: resource == .folder
                    ? nil
                    : ShareLinkRequestDTO(expiresAt: expiresAt, fullAccess: false)
            )
            listed = try await service.listShareLinks(resource: resource, id: resourceID)
        }
        _ = try await service.resolveShareLink(token: "opaque-token")
        _ = try await service.acceptShareLink(token: "opaque-token")
        _ = try await service.revokeShareLink(id: linkID)
        let resources = try await service.listSharedResources()

        XCTAssertEqual(listed.count, 1)
        let reencodedList = try WireJSON.encoder().encode(ShareLinkListResponseDTO(items: listed))
        let reencodedText = String(decoding: reencodedList, as: UTF8.self)
        XCTAssertFalse(reencodedText.contains("must-not-survive"))
        XCTAssertFalse(reencodedText.contains("\"token\""))
        XCTAssertEqual(resources.folders.count, 1)
        XCTAssertNil(resources.folders.first?.description)
        XCTAssertEqual(resources.createTaskGoalIds, [])

        let requests = await sender.requests()
        XCTAssertEqual(requests.map(\.method), [
            "POST", "GET", "POST", "GET", "POST", "GET", "POST", "GET",
            "GET", "POST", "POST", "GET"
        ])
        XCTAssertEqual(requests.map(\.path), [
            "/rocket-api/folders/\(resourceID.wire)/share-links",
            "/rocket-api/folders/\(resourceID.wire)/share-links",
            "/rocket-api/goals/\(resourceID.wire)/share-links",
            "/rocket-api/goals/\(resourceID.wire)/share-links",
            "/rocket-api/tasks/\(resourceID.wire)/share-links",
            "/rocket-api/tasks/\(resourceID.wire)/share-links",
            "/rocket-api/ideas/\(resourceID.wire)/share-links",
            "/rocket-api/ideas/\(resourceID.wire)/share-links",
            "/rocket-api/shares/links/opaque-token",
            "/rocket-api/shares/links/opaque-token/accept",
            "/rocket-api/shares/links/\(linkID.wire)/revoke",
            "/rocket-api/shares/resources"
        ])
        XCTAssertNil(requests[0].body)
        let goalCreateBody = try body(requests[2])
        XCTAssertEqual(goalCreateBody["fullAccess"] as? Bool, false)
        XCTAssertNotNil(goalCreateBody["expiresAt"] as? String)
        XCTAssertNil(goalCreateBody["idempotencyKey"])
        XCTAssertEqual(requests[10].method, "POST")
        XCTAssertNil(requests[10].body)
        XCTAssertTrue(requests.allSatisfy { header("Idempotency-Key", in: $0) == nil })
    }

    private func body(_ request: SharingRequestRecorder.Captured) throws -> [String: Any] {
        let data = try XCTUnwrap(request.body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func sharingDecodedUUID(
        _ value: Any?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> UUID {
        let string = try XCTUnwrap(value as? String, "Expected UUID string", file: file, line: line)
        return try XCTUnwrap(UUID(uuidString: string), "Invalid UUID string", file: file, line: line)
    }

    private func header(_ name: String, in request: SharingRequestRecorder.Captured) -> String? {
        request.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private func invitationFixture(
        id: UUID,
        targetType: String,
        targetID: UUID,
        email: String?,
        userID: UUID?
    ) -> Data {
        let emailJSON = email.map { "\"\($0)\"" } ?? "null"
        let userJSON = userID.map { "\"\($0)\"" } ?? "null"
        return Data(
            "{\"id\":\"\(id)\",\"targetType\":\"\(targetType)\",\"targetId\":\"\(targetID)\",\"targetEmail\":\(emailJSON),\"targetUserId\":\(userJSON),\"fullAccess\":true,\"status\":\"pending\",\"createdAt\":\"2024-08-22T10:00:00Z\",\"expiresAt\":null}".utf8
        )
    }

    private func shareLinkCreateFixture(linkID: UUID, targetType: String, targetID: UUID) -> Data {
        Data(
            "{\"id\":\"\(linkID)\",\"targetType\":\"\(targetType)\",\"targetId\":\"\(targetID)\",\"token\":\"one-time-token\",\"fullAccess\":true,\"status\":\"active\",\"createdAt\":\"2024-08-22T10:00:00Z\",\"expiresAt\":null}".utf8
        )
    }

    private func shareLinkListFixture(linkID: UUID, targetType: String, targetID: UUID) -> Data {
        Data(
            "{\"items\":[{\"id\":\"\(linkID)\",\"targetType\":\"\(targetType)\",\"targetId\":\"\(targetID)\",\"token\":\"must-not-survive\",\"fullAccess\":true,\"status\":\"active\",\"createdAt\":\"2024-08-22T10:00:00Z\",\"expiresAt\":null,\"revokedAt\":null}]}".utf8
        )
    }
}

private extension UUID {
    var wire: String { uuidString.lowercased() }
}
