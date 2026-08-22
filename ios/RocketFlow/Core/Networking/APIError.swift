import Foundation

struct APIErrorDetail: Codable, Equatable, Sendable {
    let field: String?
    let message: String
}

struct APIError: Error, Equatable, Sendable, LocalizedError {
    let statusCode: Int
    let code: String
    let message: String
    let details: [APIErrorDetail]
    let traceID: String?
    let requestID: UUID

    var errorDescription: String? { message }
    var isUnauthorized: Bool { statusCode == 401 }

    var fieldErrors: [String: String] {
        details.reduce(into: [:]) { result, detail in
            if let field = detail.field, !field.isEmpty, result[field] == nil {
                result[field] = detail.message
            }
        }
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: Payload

    struct Payload: Decodable {
        let code: String?
        let message: String?
        let details: [APIErrorDetail]?
        let traceId: String?
    }
}

extension APIError {
    static func decode(statusCode: Int, data: Data, requestID: UUID) -> APIError {
        guard
            let envelope = try? WireJSON.decoder().decode(APIErrorEnvelope.self, from: data)
        else {
            return APIError(
                statusCode: statusCode,
                code: "internal_error",
                message: "Request failed.",
                details: [],
                traceID: nil,
                requestID: requestID
            )
        }

        return APIError(
            statusCode: statusCode,
            code: envelope.error.code?.nonEmpty ?? "internal_error",
            message: envelope.error.message?.nonEmpty ?? "Request failed.",
            details: envelope.error.details ?? [],
            traceID: envelope.error.traceId?.nonEmpty,
            requestID: requestID
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

enum APIClientFailure: Error, Equatable, Sendable, LocalizedError {
    case invalidBaseURL
    case invalidPathSegment(String)
    case missingAuthorization
    case nonHTTPResponse
    case responseDecoding(requestID: UUID)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: "The API base URL is invalid."
        case .invalidPathSegment: "The API path contains an invalid segment."
        case .missingAuthorization: "An authenticated request has no session token."
        case .nonHTTPResponse: "The server returned a non-HTTP response."
        case .responseDecoding: "The server response could not be decoded."
        }
    }
}
