import Foundation

struct HTTPResult: Sendable {
    let data: Data
    let response: HTTPURLResponse
}

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> HTTPResult
}

struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> HTTPResult {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw APIClientFailure.nonHTTPResponse
        }
        return HTTPResult(data: data, response: response)
    }
}

protocol APIClientProtocol: Sendable {
    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint<Response>,
        bearerToken: String?
    ) async throws -> Response
}

actor APIClient: APIClientProtocol {
    private let baseURL: URL
    private let transport: any HTTPTransport

    init(baseURL: URL, transport: any HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.transport = transport
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint<Response>,
        bearerToken: String? = nil
    ) async throws -> Response {
        try Task.checkCancellation()
        let request = try endpoint.makeRequest(baseURL: baseURL, bearerToken: bearerToken)

        let result: HTTPResult
        do {
            result = try await transport.data(for: request.urlRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
        try Task.checkCancellation()

        guard (200...299).contains(result.response.statusCode) else {
            throw APIError.decode(
                statusCode: result.response.statusCode,
                data: result.data,
                requestID: request.requestID
            )
        }

        let payload = result.data.isEmpty ? Data("{}".utf8) : result.data
        do {
            return try WireJSON.decoder().decode(Response.self, from: payload)
        } catch {
            throw APIClientFailure.responseDecoding(requestID: request.requestID)
        }
    }
}
