import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct EmptyResponse: Codable, Equatable, Sendable {
    init() {}
}

struct Endpoint<Response: Decodable & Sendable>: Sendable {
    let method: HTTPMethod
    let pathSegments: [String]
    let queryItems: [URLQueryItem]
    let body: Data?
    let requiresAuthorization: Bool

    init(
        method: HTTPMethod,
        path: [String],
        queryItems: [URLQueryItem] = [],
        requiresAuthorization: Bool = true
    ) {
        self.method = method
        pathSegments = path
        self.queryItems = queryItems
        body = nil
        self.requiresAuthorization = requiresAuthorization
    }

    init<Body: Encodable>(
        method: HTTPMethod,
        path: [String],
        queryItems: [URLQueryItem] = [],
        body: Body,
        requiresAuthorization: Bool = true
    ) throws {
        self.method = method
        pathSegments = path
        self.queryItems = queryItems
        self.body = try WireJSON.encoder().encode(body)
        self.requiresAuthorization = requiresAuthorization
    }

    func makeRequest(
        baseURL: URL,
        bearerToken: String? = nil,
        requestID: UUID = UUID()
    ) throws -> APIRequest<Response> {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIClientFailure.invalidBaseURL
        }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        let encodedSegments = try pathSegments.map { segment in
            guard
                !segment.isEmpty,
                segment != ".",
                segment != "..",
                let encoded = segment.addingPercentEncoding(withAllowedCharacters: allowed)
            else {
                throw APIClientFailure.invalidPathSegment(segment)
            }
            return encoded
        }

        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = "/" + ([basePath] + encodedSegments)
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw APIClientFailure.invalidBaseURL
        }
        if requiresAuthorization && bearerToken?.isEmpty != false {
            throw APIClientFailure.missingAuthorization
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(requestID.uuidString.lowercased(), forHTTPHeaderField: "X-Request-ID")
        if body != nil {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        return APIRequest(urlRequest: request, requestID: requestID)
    }
}

struct APIRequest<Response: Decodable & Sendable>: Sendable {
    let urlRequest: URLRequest
    let requestID: UUID
}
