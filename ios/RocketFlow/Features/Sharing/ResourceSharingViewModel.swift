import Combine
import Foundation

@MainActor
final class ResourceSharingViewModel: ObservableObject {
    @Published private(set) var phase: SharingScreenPhase = .idle
    @Published private(set) var invitations: [ShareInvitationDTO] = []
    @Published private(set) var shareLinks: [ShareLinkDTO] = []
    @Published private(set) var issue: SharingIssue?
    @Published private(set) var isMutating = false
    @Published private(set) var createdToken: CreatedShareToken?
    @Published private(set) var createdTokenAcknowledged = true
    @Published private(set) var resolvedLink: ShareLinkResolveResponseDTO?
    @Published private(set) var pendingRevocation: SharingRevocation?

    @Published var recipientMode: SharingRecipientMode = .email
    @Published var email = ""
    @Published var userIDText = ""
    @Published var invitationAccess: SharingAccessChoice = .viewOnly
    @Published var linkAccess: SharingAccessChoice = .viewOnly
    @Published var usesExpiry = false
    @Published var expiryDate: Date
    @Published var tokenInput = ""

    let context: SharingResourceContext
    let language: AppLanguage

    private let service: any SharingFeatureServing
    private let now: @Sendable () -> Date
    private let onCopyToken: (String) -> Void
    private let onShareToken: (String) -> Void
    private let onAccepted: (ShareLinkAcceptResponseDTO) -> Void
    private let onUnauthorized: () -> Void
    private var loadGeneration: UInt64 = 0
    private var resolveGeneration: UInt64 = 0
    private var resolvedToken: String?

    init(
        context: SharingResourceContext,
        language: AppLanguage,
        service: any SharingFeatureServing,
        now: @escaping @Sendable () -> Date = Date.init,
        onCopyToken: @escaping (String) -> Void,
        onShareToken: @escaping (String) -> Void,
        onAccepted: @escaping (ShareLinkAcceptResponseDTO) -> Void = { _ in },
        onUnauthorized: @escaping () -> Void = {}
    ) {
        self.context = context
        self.language = language
        self.service = service
        self.now = now
        self.onCopyToken = onCopyToken
        self.onShareToken = onShareToken
        self.onAccepted = onAccepted
        self.onUnauthorized = onUnauthorized
        expiryDate = now().addingTimeInterval(7 * 24 * 60 * 60)
    }

    var copy: SharingCopy { SharingCopy(language: language) }
    var canManage: Bool { context.canManage }
    var isBusy: Bool { phase == .loading || isMutating }
    var canCreateShareLink: Bool {
        canManage && !isBusy && createdTokenAcknowledged
    }

    func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        guard canManage else {
            phase = .loaded
            issue = nil
            return
        }
        phase = .loading
        issue = nil
        do {
            let allInvitations = try await service.listInvitations()
            guard generation == loadGeneration else { return }
            let links = try await service.listShareLinks(resource: context.kind, id: context.id)
            guard generation == loadGeneration else { return }
            invitations = Self.visibleInvitations(allInvitations, context: context)
            shareLinks = links.sorted { $0.createdAt > $1.createdAt }
            phase = .loaded
        } catch is CancellationError {
            guard generation == loadGeneration else { return }
            phase = invitations.isEmpty && shareLinks.isEmpty ? .idle : .loaded
        } catch {
            guard generation == loadGeneration else { return }
            handle(error)
        }
    }

    func invite() async {
        guard beginOwnerMutation() else { return }
        defer { isMutating = false }
        do {
            let request = try invitationRequest()
            let invitation = try await service.createInvitation(
                resource: context.kind,
                id: context.id,
                request: request
            )
            invalidatePendingLoad()
            invitations.removeAll { $0.id == invitation.id }
            if Self.isVisibleInvitation(invitation, context: context) {
                invitations.insert(invitation, at: 0)
            }
            email = ""
            userIDText = ""
            issue = nil
            phase = .loaded
        } catch {
            handle(error)
        }
    }

    func createShareLink() async {
        guard createdTokenAcknowledged else { return }
        guard beginOwnerMutation() else { return }
        defer { isMutating = false }
        let expiry: Date?
        if usesExpiry {
            guard expiryDate > now() else {
                setValidation(copy.validationExpiry, field: "expiresAt")
                return
            }
            expiry = expiryDate
        } else {
            expiry = nil
        }

        do {
            let response = try await service.createShareLink(
                resource: context.kind,
                id: context.id,
                request: ShareLinkRequestDTO(
                    expiresAt: expiry,
                    fullAccess: linkAccess.fullAccess
                )
            )
            invalidatePendingLoad()
            let listed = ShareLinkDTO(
                id: response.id,
                targetType: response.targetType,
                targetId: response.targetId,
                fullAccess: response.fullAccess,
                status: response.status,
                createdAt: response.createdAt,
                expiresAt: response.expiresAt,
                revokedAt: nil
            )
            shareLinks.removeAll { $0.id == listed.id }
            shareLinks.insert(listed, at: 0)
            createdToken = CreatedShareToken(id: response.id, token: response.token)
            createdTokenAcknowledged = false
            issue = nil
            phase = .loaded
        } catch {
            handle(error)
        }
    }

    func dismissCreatedToken() {
        acknowledgeCreatedToken()
    }

    func acknowledgeCreatedToken() {
        createdToken = nil
        createdTokenAcknowledged = true
    }

    func handleSheetDismissal() {
        acknowledgeCreatedToken()
        invalidateResolvedToken(clearInput: true)
    }

    func copyCreatedToken() {
        guard let token = createdToken?.token else { return }
        onCopyToken(token)
    }

    func shareCreatedToken() {
        guard let token = createdToken?.token else { return }
        onShareToken(token)
    }

    func requestRevokeInvitation(id: UUID) {
        guard canManage else {
            setForbidden()
            return
        }
        pendingRevocation = .invitation(id)
    }

    func requestRevokeLink(id: UUID) {
        guard canManage else {
            setForbidden()
            return
        }
        pendingRevocation = .link(id)
    }

    func cancelRevocation() {
        pendingRevocation = nil
    }

    func confirmRevocation() async {
        guard let pendingRevocation, beginOwnerMutation() else { return }
        self.pendingRevocation = nil
        defer { isMutating = false }
        do {
            switch pendingRevocation {
            case let .invitation(id):
                _ = try await service.revokeInvitation(id: id)
                invalidatePendingLoad()
                invitations.removeAll { $0.id == id }
            case let .link(id):
                _ = try await service.revokeShareLink(id: id)
                invalidatePendingLoad()
                shareLinks.removeAll { $0.id == id }
                if createdToken?.id == id { acknowledgeCreatedToken() }
            }
            issue = nil
            phase = .loaded
        } catch {
            handle(error)
        }
    }

    func resolveToken() async {
        let token = Self.normalizedToken(tokenInput)
        guard !token.isEmpty else {
            setValidation(copy.validationToken, field: "token")
            return
        }
        guard !isMutating else { return }
        resolveGeneration &+= 1
        let generation = resolveGeneration
        resolvedToken = nil
        resolvedLink = nil
        isMutating = true
        defer { isMutating = false }
        do {
            let response = try await service.resolveShareLink(token: token)
            guard generation == resolveGeneration,
                  token == Self.normalizedToken(tokenInput) else { return }
            resolvedToken = token
            resolvedLink = response
            issue = nil
            phase = .loaded
        } catch {
            guard generation == resolveGeneration else { return }
            resolvedLink = nil
            resolvedToken = nil
            handle(error)
        }
    }

    func acceptResolvedToken() async {
        let token = Self.normalizedToken(tokenInput)
        guard resolvedLink != nil, resolvedToken == token, !token.isEmpty else {
            setValidation(copy.validationToken, field: "token")
            return
        }
        guard !isMutating else { return }
        let generation = resolveGeneration
        isMutating = true
        defer { isMutating = false }
        do {
            let accepted = try await service.acceptShareLink(token: token)
            issue = nil
            phase = .loaded
            if generation == resolveGeneration,
               token == Self.normalizedToken(tokenInput) {
                invalidateResolvedToken(clearInput: true)
            }
            onAccepted(accepted)
        } catch {
            handle(error)
        }
    }

    func updateTokenInput(_ value: String) {
        guard value != tokenInput else { return }
        tokenInput = value
        invalidateResolvedToken(clearInput: false)
    }

    private func invitationRequest() throws -> SharingInvitationRequest {
        switch recipientMode {
        case .email:
            let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                throw RemoteActionError.validation(
                    message: copy.validationRecipient,
                    fieldErrors: ["email": copy.validationRecipient]
                )
            }
            return try SharingInvitationRequest(
                email: value,
                fullAccess: invitationAccess.fullAccess
            )
        case .userID:
            guard let id = UUID(uuidString: userIDText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw RemoteActionError.validation(
                    message: copy.validationUserID,
                    fieldErrors: ["userId": copy.validationUserID]
                )
            }
            return try SharingInvitationRequest(
                userId: id,
                fullAccess: invitationAccess.fullAccess
            )
        }
    }

    private func beginOwnerMutation() -> Bool {
        guard canManage else {
            setForbidden()
            return false
        }
        guard !isMutating else { return false }
        isMutating = true
        return true
    }

    private func setForbidden() {
        issue = SharingIssue(kind: .forbidden, code: "owner_required", message: copy.ownerOnly)
        phase = .forbidden
    }

    private func setValidation(_ message: String, field: String) {
        issue = SharingIssue(kind: .validation, code: "validation_error:\(field)", message: message)
        phase = .error
    }

    private func handle(_ error: Error) {
        let mapped = Self.issue(error)
        issue = mapped
        switch mapped.kind {
        case .unauthorized:
            phase = .unauthorized
            acknowledgeCreatedToken()
            onUnauthorized()
        case .forbidden:
            phase = .forbidden
        case .notFound:
            phase = .notFound
        case .conflict:
            phase = .conflict
        case .offline:
            phase = .offline
        case .validation, .unavailable:
            phase = .error
        }
    }

    private static func visibleInvitations(
        _ values: [ShareInvitationDTO],
        context: SharingResourceContext
    ) -> [ShareInvitationDTO] {
        values
            .filter { isVisibleInvitation($0, context: context) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private static func isVisibleInvitation(
        _ value: ShareInvitationDTO,
        context: SharingResourceContext
    ) -> Bool {
        value.targetType == context.kind.rawValue
            && value.targetId == context.id
            && (value.status == "pending" || value.status == "accepted")
    }

    private static func issue(_ error: Error) -> SharingIssue {
        if let action = error as? RemoteActionError {
            switch action {
            case .unauthorized:
                return SharingIssue(kind: .unauthorized, code: "unauthorized", message: "Unauthorized")
            case let .forbidden(code, message):
                return SharingIssue(kind: .forbidden, code: code, message: message)
            case let .notFound(code, message):
                return SharingIssue(kind: .notFound, code: code, message: message)
            case let .versionConflict(code, message), let .conflict(code, message):
                return SharingIssue(kind: .conflict, code: code, message: message)
            case let .dependencyBlocked(code, message):
                return SharingIssue(kind: .conflict, code: code, message: message)
            case let .validation(message, _):
                return SharingIssue(kind: .validation, code: "validation_error", message: message)
            case let .retryable(code, message):
                return SharingIssue(
                    kind: isOfflineTransport(code: code) ? .offline : .unavailable,
                    code: code,
                    message: message
                )
            case .cancelled:
                return SharingIssue(kind: .unavailable, code: "cancelled", message: "Cancelled")
            case let .unexpected(_, code, message):
                return SharingIssue(kind: .unavailable, code: code, message: message)
            }
        }
        if let api = error as? APIError {
            switch api.statusCode {
            case 401: return SharingIssue(kind: .unauthorized, code: api.code, message: api.message)
            case 403: return SharingIssue(kind: .forbidden, code: api.code, message: api.message)
            case 404: return SharingIssue(kind: .notFound, code: api.code, message: api.message)
            case 409: return SharingIssue(kind: .conflict, code: api.code, message: api.message)
            case 400, 422: return SharingIssue(kind: .validation, code: api.code, message: api.message)
            default: return SharingIssue(kind: .unavailable, code: api.code, message: api.message)
            }
        }
        if error is URLError {
            return SharingIssue(kind: .offline, code: "network_error", message: error.localizedDescription)
        }
        return SharingIssue(kind: .unavailable, code: "unavailable", message: error.localizedDescription)
    }

    private func invalidatePendingLoad() {
        loadGeneration &+= 1
    }

    private func invalidateResolvedToken(clearInput: Bool) {
        resolveGeneration &+= 1
        resolvedToken = nil
        resolvedLink = nil
        if clearInput { tokenInput = "" }
    }

    private static func normalizedToken(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isOfflineTransport(code: String) -> Bool {
        code == "network_error"
            || code.hasPrefix("network_")
            || code == "transport_error"
            || code == "non_http_response"
    }
}
