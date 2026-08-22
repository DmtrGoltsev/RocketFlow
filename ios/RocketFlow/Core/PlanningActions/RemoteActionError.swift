import Foundation

enum RemoteActionError: Error, Equatable, Sendable, LocalizedError {
    case unauthorized
    case forbidden(code: String, message: String)
    case notFound(code: String, message: String)
    case versionConflict(code: String, message: String)
    case dependencyBlocked(code: String, message: String)
    case validation(message: String, fieldErrors: [String: String])
    case conflict(code: String, message: String)
    case retryable(code: String, message: String)
    case cancelled
    case unexpected(statusCode: Int, code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Authentication is required."
        case let .forbidden(_, message),
             let .notFound(_, message),
             let .versionConflict(_, message),
             let .dependencyBlocked(_, message),
             let .validation(message, _),
             let .conflict(_, message),
             let .retryable(_, message),
             let .unexpected(_, _, message):
            message
        case .cancelled:
            "The request was cancelled."
        }
    }
}

struct AuthenticatedActionTransport: Sendable {
    private let sender: any AuthenticatedRequestSending

    init(sender: any AuthenticatedRequestSending) {
        self.sender = sender
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint<Response>,
        versioned: Bool = false
    ) async throws -> Response {
        do {
            return try await sender.send(endpoint)
        } catch {
            throw Self.map(error, versioned: versioned)
        }
    }

    private static func map(_ error: Error, versioned: Bool) -> RemoteActionError {
        if error is CancellationError {
            return .cancelled
        }

        if let api = error as? APIError {
            switch api.statusCode {
            case 401:
                return .unauthorized
            case 403:
                return .forbidden(code: api.code, message: api.message)
            case 404:
                return .notFound(code: api.code, message: api.message)
            case 400, 422:
                return .validation(message: api.message, fieldErrors: api.fieldErrors)
            case 409 where api.code == "dependency_blocked":
                return .dependencyBlocked(code: api.code, message: api.message)
            case 409 where versioned && Self.isVersionConflict(api):
                return .versionConflict(code: api.code, message: api.message)
            case 409:
                return .conflict(code: api.code, message: api.message)
            case 412:
                return .versionConflict(code: api.code, message: api.message)
            case 408, 425, 429, 500...599:
                return .retryable(code: api.code, message: api.message)
            default:
                return .unexpected(statusCode: api.statusCode, code: api.code, message: api.message)
            }
        }

        if let auth = error as? AuthSessionError {
            switch auth {
            case .sessionMissing, .sessionPersistenceFailed:
                return .unauthorized
            case .sessionReplaced:
                return .retryable(code: "session_replaced", message: auth.localizedDescription)
            }
        }

        if let client = error as? APIClientFailure {
            switch client {
            case .missingAuthorization:
                return .unauthorized
            case .nonHTTPResponse:
                return .retryable(code: "non_http_response", message: client.localizedDescription)
            case .responseDecoding:
                return .unexpected(
                    statusCode: 0,
                    code: "response_decoding",
                    message: client.localizedDescription
                )
            case .invalidBaseURL, .invalidPathSegment:
                return .unexpected(
                    statusCode: 0,
                    code: "invalid_request",
                    message: client.localizedDescription
                )
            }
        }

        if let urlError = error as? URLError {
            return .retryable(
                code: "network_\(urlError.code.rawValue)",
                message: urlError.localizedDescription
            )
        }

        return .retryable(code: "transport_error", message: error.localizedDescription)
    }

    private static func isVersionConflict(_ api: APIError) -> Bool {
        api.code == "version_conflict"
            || api.message.localizedCaseInsensitiveContains("updated by another request")
    }
}
