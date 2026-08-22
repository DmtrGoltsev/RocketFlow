import Foundation
import XCTest
@testable import RocketFlow

@MainActor
final class SharingViewModelTests: XCTestCase {
    private let resourceID = UUID()
    private let now = Date(timeIntervalSince1970: 1_787_001_200)

    func testOwnerOnlyManagementAndReadOnlyCapability() async {
        let service = SharingViewServiceStub()
        let model = makeModel(
            service: service,
            context: context(isOwner: false, shared: true, fullAccess: false)
        )

        await model.load()
        await model.invite()

        XCTAssertFalse(model.canManage)
        XCTAssertEqual(model.context.access, .viewOnly)
        XCTAssertEqual(model.phase, .forbidden)
        XCTAssertEqual(model.issue?.code, "owner_required")
        let operations = await service.operations()
        XCTAssertEqual(operations, [])
    }

    func testInvitationModeProducesExactlyEmailXorUserID() async throws {
        let service = SharingViewServiceStub(createdInvitation: invitation())
        let model = makeModel(service: service)

        await model.invite()
        XCTAssertEqual(model.issue?.kind, .validation)
        let emptyOperations = await service.operations()
        XCTAssertEqual(emptyOperations, [])

        model.email = " person@example.com "
        model.invitationAccess = .full
        await model.invite()

        model.recipientMode = .userID
        let userID = UUID()
        model.userIDText = userID.uuidString
        model.invitationAccess = .viewOnly
        await model.invite()

        let operations = await service.operations()
        guard case let .createInvitation(emailRequest) = operations[0],
              case let .createInvitation(userRequest) = operations[1] else {
            return XCTFail("Expected invitation operations")
        }
        XCTAssertEqual(emailRequest.email, "person@example.com")
        XCTAssertNil(emailRequest.userId)
        XCTAssertEqual(emailRequest.fullAccess, true)
        XCTAssertNil(userRequest.email)
        XCTAssertEqual(userRequest.userId, userID)
        XCTAssertEqual(userRequest.fullAccess, false)
    }

    func testShareLinkExpiryMustBeFutureAndIsForwardedExactly() async {
        let service = SharingViewServiceStub(createdLink: createdLink())
        let model = makeModel(service: service)
        model.usesExpiry = true
        model.expiryDate = now

        await model.createShareLink()
        XCTAssertEqual(model.issue?.code, "validation_error:expiresAt")
        let emptyOperations = await service.operations()
        XCTAssertEqual(emptyOperations, [])

        let future = now.addingTimeInterval(3_600)
        model.expiryDate = future
        model.linkAccess = .full
        await model.createShareLink()

        let operations = await service.operations()
        guard case let .createLink(request) = operations.first else {
            return XCTFail("Expected link creation")
        }
        XCTAssertEqual(request?.expiresAt, future)
        XCTAssertEqual(request?.fullAccess, true)
    }

    func testCreationTokenIsPresentedOnceAndNeverRestoredFromList() async {
        let link = createdLink(token: "one-time-secret")
        let service = SharingViewServiceStub(
            links: [listedLink(id: link.id)],
            createdLink: link
        )
        var copied: [String] = []
        var shared: [String] = []
        let model = makeModel(
            service: service,
            onCopy: { copied.append($0) },
            onShare: { shared.append($0) }
        )

        await model.createShareLink()
        XCTAssertEqual(model.createdToken?.token, "one-time-secret")
        XCTAssertFalse(model.createdTokenAcknowledged)
        XCTAssertFalse(model.canCreateShareLink)
        model.copyCreatedToken()
        model.shareCreatedToken()
        XCTAssertEqual(copied, ["one-time-secret"])
        XCTAssertEqual(shared, ["one-time-secret"])

        model.dismissCreatedToken()
        XCTAssertTrue(model.createdTokenAcknowledged)
        await model.load()
        XCTAssertNil(model.createdToken)
        XCTAssertEqual(model.shareLinks.map(\.id), [link.id])
    }

    func testCreatedTokenCannotBeOverwrittenBeforeAcknowledgementAndDismissalClearsIt() async {
        let service = SharingViewServiceStub(createdLink: createdLink(token: "one-time-secret"))
        let model = makeModel(service: service)

        await model.createShareLink()
        await model.createShareLink()

        var operations = await service.operations()
        XCTAssertEqual(operations.filter { operation in
            if case .createLink = operation { return true }
            return false
        }.count, 1)
        XCTAssertEqual(model.createdToken?.token, "one-time-secret")
        XCTAssertFalse(model.createdTokenAcknowledged)

        model.handleSheetDismissal()
        XCTAssertNil(model.createdToken)
        XCTAssertTrue(model.createdTokenAcknowledged)
        XCTAssertTrue(model.canCreateShareLink)

        await model.createShareLink()
        operations = await service.operations()
        XCTAssertEqual(operations.filter { operation in
            if case .createLink = operation { return true }
            return false
        }.count, 2)
    }

    func testChangedTokenInvalidatesInFlightResolveAndPreventsMismatchedAccept() async {
        let gate = SharingAsyncGate()
        let service = SharingViewServiceStub(
            resolvedLink: resolvedLink(),
            resolveGate: gate
        )
        let model = makeModel(service: service)
        model.updateTokenInput(" token-a ")

        let resolve = Task { await model.resolveToken() }
        await gate.waitUntilSuspended()
        model.updateTokenInput("token-b")
        await gate.release()
        await resolve.value

        XCTAssertNil(model.resolvedLink)
        await model.acceptResolvedToken()
        XCTAssertEqual(model.issue?.kind, .validation)
        let operations = await service.operations()
        XCTAssertTrue(operations.contains(.resolve("token-a")))
        XCTAssertFalse(operations.contains(.accept("token-b")))
    }

    func testSuccessfulMutationInvalidatesOlderSharingLoad() async {
        let gate = SharingAsyncGate()
        let created = invitation()
        let service = SharingViewServiceStub(
            invitations: [],
            createdInvitation: created,
            listInvitationsGate: gate
        )
        let model = makeModel(service: service)

        let load = Task { await model.load() }
        await gate.waitUntilSuspended()
        XCTAssertTrue(model.isBusy)

        model.email = "person@example.com"
        await model.invite()
        await gate.release()
        await load.value

        XCTAssertEqual(model.invitations.map(\.id), [created.id])
        XCTAssertEqual(model.phase, .loaded)
        let operations = await service.operations()
        XCTAssertFalse(operations.contains(.listLinks))
    }

    func testConfirmedRevocationEmitsInvitationAndPostBackedLinkIntents() async {
        let invitation = invitation()
        let link = listedLink()
        let service = SharingViewServiceStub(invitations: [invitation], links: [link])
        let model = makeModel(service: service)
        await model.load()

        model.requestRevokeInvitation(id: invitation.id)
        await model.confirmRevocation()
        model.requestRevokeLink(id: link.id)
        await model.confirmRevocation()

        let operations = await service.operations()
        XCTAssertTrue(operations.contains(.revokeInvitation(invitation.id)))
        XCTAssertTrue(operations.contains(.revokeLink(link.id)))
        XCTAssertTrue(model.invitations.isEmpty)
        XCTAssertTrue(model.shareLinks.isEmpty)
    }

    func testUnauthorizedAndResolveAcceptStatesInvokeHooks() async {
        let unauthorized = SharingViewServiceStub(
            error: .unauthorized
        )
        var unauthorizedCount = 0
        let unauthorizedModel = makeModel(
            service: unauthorized,
            onUnauthorized: { unauthorizedCount += 1 }
        )

        await unauthorizedModel.load()
        XCTAssertEqual(unauthorizedModel.phase, .unauthorized)
        XCTAssertEqual(unauthorizedCount, 1)

        let accepted = acceptedLink()
        let service = SharingViewServiceStub(
            resolvedLink: resolvedLink(),
            acceptedLink: accepted
        )
        var acceptedValues: [ShareLinkAcceptResponseDTO] = []
        let model = makeModel(
            service: service,
            onAccepted: { acceptedValues.append($0) }
        )
        model.updateTokenInput(" opaque-token ")

        await model.resolveToken()
        XCTAssertNotNil(model.resolvedLink)
        await model.acceptResolvedToken()

        XCTAssertEqual(acceptedValues, [accepted])
        XCTAssertNil(model.resolvedLink)
        XCTAssertEqual(model.tokenInput, "")
        let operations = await service.operations()
        XCTAssertTrue(operations.contains(.resolve("opaque-token")))
        XCTAssertTrue(operations.contains(.accept("opaque-token")))
    }

    func testTransportErrorsMapToVisiblePermissionConflictAndOfflineStates() async {
        let cases: [(RemoteActionError, SharingScreenPhase, SharingIssueKind)] = [
            (.forbidden(code: "forbidden", message: "No access"), .forbidden, .forbidden),
            (.notFound(code: "not_found", message: "Missing"), .notFound, .notFound),
            (.conflict(code: "conflict", message: "Changed"), .conflict, .conflict),
            (.retryable(code: "network_-1009", message: "Offline"), .offline, .offline),
            (.retryable(code: "server_error", message: "Temporarily unavailable"), .error, .unavailable),
            (.unexpected(statusCode: 500, code: "server_error", message: "Down"), .error, .unavailable)
        ]

        for (error, expectedPhase, expectedIssue) in cases {
            let model = makeModel(service: SharingViewServiceStub(error: error))
            await model.load()
            XCTAssertEqual(model.phase, expectedPhase)
            XCTAssertEqual(model.issue?.kind, expectedIssue)
        }
    }

    private func makeModel(
        service: SharingViewServiceStub,
        context: SharingResourceContext? = nil,
        onCopy: @escaping (String) -> Void = { _ in },
        onShare: @escaping (String) -> Void = { _ in },
        onAccepted: @escaping (ShareLinkAcceptResponseDTO) -> Void = { _ in },
        onUnauthorized: @escaping () -> Void = {}
    ) -> ResourceSharingViewModel {
        let fixedNow = now
        return ResourceSharingViewModel(
            context: context ?? self.context(),
            language: .en,
            service: service,
            now: { fixedNow },
            onCopyToken: onCopy,
            onShareToken: onShare,
            onAccepted: onAccepted,
            onUnauthorized: onUnauthorized
        )
    }

    private func context(
        isOwner: Bool = true,
        shared: Bool = false,
        fullAccess: Bool = true
    ) -> SharingResourceContext {
        SharingResourceContext(
            kind: .task,
            id: resourceID,
            title: "Task",
            isOwner: isOwner,
            shared: shared,
            fullAccess: fullAccess
        )
    }

    private func invitation() -> ShareInvitationDTO {
        ShareInvitationDTO(
            id: UUID(),
            targetType: "task",
            targetId: resourceID,
            targetEmail: "person@example.com",
            targetUserId: nil,
            fullAccess: false,
            status: "pending",
            createdAt: now,
            expiresAt: nil
        )
    }

    private func createdLink(token: String = "token") -> ShareLinkCreateResponseDTO {
        ShareLinkCreateResponseDTO(
            id: UUID(),
            targetType: "task",
            targetId: resourceID,
            token: token,
            fullAccess: false,
            status: "active",
            createdAt: now,
            expiresAt: nil
        )
    }

    private func listedLink(id: UUID = UUID()) -> ShareLinkDTO {
        ShareLinkDTO(
            id: id,
            targetType: "task",
            targetId: resourceID,
            fullAccess: false,
            status: "active",
            createdAt: now,
            expiresAt: nil,
            revokedAt: nil
        )
    }

    private func resolvedLink() -> ShareLinkResolveResponseDTO {
        ShareLinkResolveResponseDTO(
            id: UUID(),
            targetType: "task",
            targetId: resourceID,
            fullAccess: false,
            status: "active",
            expiresAt: nil
        )
    }

    private func acceptedLink() -> ShareLinkAcceptResponseDTO {
        ShareLinkAcceptResponseDTO(
            shareId: UUID(),
            targetType: "task",
            targetId: resourceID,
            fullAccess: false,
            status: "active"
        )
    }
}

private actor SharingViewServiceStub: SharingFeatureServing {
    enum Operation: Equatable, Sendable {
        case listInvitations
        case listLinks
        case createInvitation(SharingInvitationRequest)
        case revokeInvitation(UUID)
        case createLink(ShareLinkRequestDTO?)
        case revokeLink(UUID)
        case resolve(String)
        case accept(String)
    }

    private let invitations: [ShareInvitationDTO]
    private let links: [ShareLinkDTO]
    private let createdInvitation: ShareInvitationDTO
    private let createdLink: ShareLinkCreateResponseDTO
    private let resolvedLink: ShareLinkResolveResponseDTO
    private let acceptedLink: ShareLinkAcceptResponseDTO
    private let error: RemoteActionError?
    private let listInvitationsGate: SharingAsyncGate?
    private let resolveGate: SharingAsyncGate?
    private var recorded: [Operation] = []

    init(
        invitations: [ShareInvitationDTO] = [],
        links: [ShareLinkDTO] = [],
        createdInvitation: ShareInvitationDTO? = nil,
        createdLink: ShareLinkCreateResponseDTO? = nil,
        resolvedLink: ShareLinkResolveResponseDTO? = nil,
        acceptedLink: ShareLinkAcceptResponseDTO? = nil,
        error: RemoteActionError? = nil,
        listInvitationsGate: SharingAsyncGate? = nil,
        resolveGate: SharingAsyncGate? = nil
    ) {
        let date = Date(timeIntervalSince1970: 1_787_001_200)
        self.invitations = invitations
        self.links = links
        self.createdInvitation = createdInvitation ?? ShareInvitationDTO(
            id: UUID(), targetType: "task", targetId: UUID(), targetEmail: "person@example.com",
            targetUserId: nil, fullAccess: false, status: "pending", createdAt: date, expiresAt: nil
        )
        self.createdLink = createdLink ?? ShareLinkCreateResponseDTO(
            id: UUID(), targetType: "task", targetId: UUID(), token: "token",
            fullAccess: false, status: "active", createdAt: date, expiresAt: nil
        )
        self.resolvedLink = resolvedLink ?? ShareLinkResolveResponseDTO(
            id: UUID(), targetType: "task", targetId: UUID(), fullAccess: false,
            status: "active", expiresAt: nil
        )
        self.acceptedLink = acceptedLink ?? ShareLinkAcceptResponseDTO(
            shareId: UUID(), targetType: "task", targetId: UUID(), fullAccess: false,
            status: "active"
        )
        self.error = error
        self.listInvitationsGate = listInvitationsGate
        self.resolveGate = resolveGate
    }

    func createInvitation(
        resource: ShareableResourceKind,
        id: UUID,
        request: SharingInvitationRequest
    ) async throws -> ShareInvitationDTO {
        try failIfNeeded()
        recorded.append(.createInvitation(request))
        return createdInvitation
    }

    func listInvitations() async throws -> [ShareInvitationDTO] {
        try failIfNeeded()
        recorded.append(.listInvitations)
        if let listInvitationsGate { await listInvitationsGate.wait() }
        return invitations
    }

    func revokeInvitation(id: UUID) async throws -> ShareInvitationActionResponseDTO {
        try failIfNeeded()
        recorded.append(.revokeInvitation(id))
        return ShareInvitationActionResponseDTO(id: id, status: "revoked")
    }

    func createShareLink(
        resource: ShareableResourceKind,
        id: UUID,
        request: ShareLinkRequestDTO?
    ) async throws -> ShareLinkCreateResponseDTO {
        try failIfNeeded()
        recorded.append(.createLink(request))
        return createdLink
    }

    func listShareLinks(resource: ShareableResourceKind, id: UUID) async throws -> [ShareLinkDTO] {
        try failIfNeeded()
        recorded.append(.listLinks)
        return links
    }

    func revokeShareLink(id: UUID) async throws -> ShareLinkActionResponseDTO {
        try failIfNeeded()
        recorded.append(.revokeLink(id))
        return ShareLinkActionResponseDTO(id: id, status: "revoked")
    }

    func resolveShareLink(token: String) async throws -> ShareLinkResolveResponseDTO {
        try failIfNeeded()
        recorded.append(.resolve(token))
        if let resolveGate { await resolveGate.wait() }
        return resolvedLink
    }

    func acceptShareLink(token: String) async throws -> ShareLinkAcceptResponseDTO {
        try failIfNeeded()
        recorded.append(.accept(token))
        return acceptedLink
    }

    func operations() -> [Operation] { recorded }

    private func failIfNeeded() throws {
        if let error { throw error }
    }
}

private actor SharingAsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func waitUntilSuspended() async {
        while waiters.isEmpty { await Task.yield() }
    }

    func release() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
