import Foundation

struct SharingResourceContext: Equatable, Sendable {
    let kind: ShareableResourceKind
    let id: UUID
    let title: String
    let isOwner: Bool
    let shared: Bool
    let fullAccess: Bool

    var canManage: Bool { isOwner }
    var access: SharingAccessChoice { shared && !fullAccess ? .viewOnly : .full }
}

enum SharingAccessChoice: String, CaseIterable, Equatable, Sendable {
    case viewOnly
    case full

    var fullAccess: Bool { self == .full }
}

enum SharingRecipientMode: String, CaseIterable, Equatable, Sendable {
    case email
    case userID
}

enum SharingScreenPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case offline
    case unauthorized
    case forbidden
    case notFound
    case conflict
    case error
}

enum SharingIssueKind: Equatable, Sendable {
    case unauthorized
    case forbidden
    case notFound
    case conflict
    case validation
    case offline
    case unavailable
}

struct SharingIssue: Equatable, Sendable {
    let kind: SharingIssueKind
    let code: String
    let message: String
}

struct CreatedShareToken: Equatable, Identifiable, Sendable {
    let id: UUID
    let token: String
}

enum SharingRevocation: Equatable, Identifiable, Sendable {
    case invitation(UUID)
    case link(UUID)

    var id: String {
        switch self {
        case let .invitation(id): "invitation:\(id.uuidString.lowercased())"
        case let .link(id): "link:\(id.uuidString.lowercased())"
        }
    }
}

protocol SharingFeatureServing: Sendable {
    func createInvitation(
        resource: ShareableResourceKind,
        id: UUID,
        request: SharingInvitationRequest
    ) async throws -> ShareInvitationDTO
    func listInvitations() async throws -> [ShareInvitationDTO]
    func revokeInvitation(id: UUID) async throws -> ShareInvitationActionResponseDTO
    func createShareLink(
        resource: ShareableResourceKind,
        id: UUID,
        request: ShareLinkRequestDTO?
    ) async throws -> ShareLinkCreateResponseDTO
    func listShareLinks(resource: ShareableResourceKind, id: UUID) async throws -> [ShareLinkDTO]
    func revokeShareLink(id: UUID) async throws -> ShareLinkActionResponseDTO
    func resolveShareLink(token: String) async throws -> ShareLinkResolveResponseDTO
    func acceptShareLink(token: String) async throws -> ShareLinkAcceptResponseDTO
}

extension SharingService: SharingFeatureServing {}

struct SharingCopy: Sendable {
    let title: String
    let access: String
    let viewOnly: String
    let fullAccess: String
    let ownerOnly: String
    let invitations: String
    let invite: String
    let email: String
    let userID: String
    let recipient: String
    let pending: String
    let accepted: String
    let revoke: String
    let links: String
    let createLink: String
    let expires: String
    let noExpiry: String
    let createdToken: String
    let tokenWarning: String
    let copyToken: String
    let shareToken: String
    let done: String
    let dismiss: String
    let token: String
    let resolve: String
    let accept: String
    let resolved: String
    let loading: String
    let offline: String
    let unauthorized: String
    let forbidden: String
    let notFound: String
    let conflict: String
    let unavailable: String
    let retry: String
    let emptyInvitations: String
    let emptyLinks: String
    let confirmRevoke: String
    let cancel: String
    let validationRecipient: String
    let validationUserID: String
    let validationExpiry: String
    let validationToken: String

    init(language: AppLanguage) {
        if language == .ru {
            title = "Доступ"
            access = "Права"
            viewOnly = "Просмотр"
            fullAccess = "Полный доступ"
            ownerOnly = "Управлять доступом может только владелец"
            invitations = "Приглашения"
            invite = "Пригласить"
            email = "Email"
            userID = "ID пользователя"
            recipient = "Получатель"
            pending = "Ожидает"
            accepted = "Принято"
            revoke = "Отозвать"
            links = "Ссылки доступа"
            createLink = "Создать ссылку"
            expires = "Срок действия"
            noExpiry = "Без срока"
            createdToken = "Новая ссылка"
            tokenWarning = "Токен показывается только сейчас"
            copyToken = "Скопировать"
            shareToken = "Поделиться"
            done = "Готово"
            dismiss = "Скрыть"
            token = "Токен ссылки"
            resolve = "Проверить"
            accept = "Принять доступ"
            resolved = "Ссылка действительна"
            loading = "Загрузка"
            offline = "Нет сети"
            unauthorized = "Требуется вход"
            forbidden = "Недостаточно прав"
            notFound = "Ресурс не найден"
            conflict = "Состояние изменилось. Обновите данные"
            unavailable = "Действие сейчас недоступно"
            retry = "Повторить"
            emptyInvitations = "Нет активных приглашений"
            emptyLinks = "Нет активных ссылок"
            confirmRevoke = "Отозвать доступ?"
            cancel = "Отмена"
            validationRecipient = "Укажите ровно одного получателя"
            validationUserID = "Введите корректный UUID пользователя"
            validationExpiry = "Срок действия должен быть в будущем"
            validationToken = "Введите токен ссылки"
        } else {
            title = "Sharing"
            access = "Access"
            viewOnly = "View only"
            fullAccess = "Full access"
            ownerOnly = "Only the owner can manage sharing"
            invitations = "Invitations"
            invite = "Invite"
            email = "Email"
            userID = "User ID"
            recipient = "Recipient"
            pending = "Pending"
            accepted = "Accepted"
            revoke = "Revoke"
            links = "Share links"
            createLink = "Create link"
            expires = "Expiry"
            noExpiry = "No expiry"
            createdToken = "New share link"
            tokenWarning = "This token is shown only now"
            copyToken = "Copy"
            shareToken = "Share"
            done = "Done"
            dismiss = "Hide"
            token = "Share token"
            resolve = "Resolve"
            accept = "Accept access"
            resolved = "Link is valid"
            loading = "Loading"
            offline = "Offline"
            unauthorized = "Sign in required"
            forbidden = "You do not have permission"
            notFound = "Resource not found"
            conflict = "The state changed. Refresh and try again"
            unavailable = "This action is currently unavailable"
            retry = "Retry"
            emptyInvitations = "No active invitations"
            emptyLinks = "No active links"
            confirmRevoke = "Revoke access?"
            cancel = "Cancel"
            validationRecipient = "Provide exactly one recipient"
            validationUserID = "Enter a valid user UUID"
            validationExpiry = "Expiry must be in the future"
            validationToken = "Enter a share token"
        }
    }

    func accessTitle(_ value: SharingAccessChoice) -> String {
        value == .full ? fullAccess : viewOnly
    }

    func statusTitle(_ value: String) -> String {
        value == "accepted" ? accepted : pending
    }
}
