import Foundation
import XCTest
@testable import RocketFlow

private actor StubHTTPTransport: HTTPTransport {
    enum Stub: Sendable {
        case response(status: Int, data: Data)
        case cancelled
    }

    private var stubs: [Stub]
    private var capturedRequests: [URLRequest] = []

    init(_ stubs: [Stub]) {
        self.stubs = stubs
    }

    func data(for request: URLRequest) async throws -> HTTPResult {
        capturedRequests.append(request)
        guard !stubs.isEmpty else { throw URLError(.badServerResponse) }
        switch stubs.removeFirst() {
        case let .response(status, data):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return HTTPResult(data: data, response: response)
        case .cancelled:
            throw URLError(.cancelled)
        }
    }

    func requests() -> [URLRequest] {
        capturedRequests
    }
}

final class APIClientTests: XCTestCase {
    func testDecodesSuccessAndAddsAuthorizationWithoutExposingItElsewhere() async throws {
        let transport = StubHTTPTransport([
            .response(status: 200, data: Data("{\"value\":\"ok\"}".utf8))
        ])
        let client = APIClient(baseURL: URL(string: "https://example.test/rocket-api")!, transport: transport)
        let endpoint = Endpoint<ValueResponse>(method: .get, path: ["resource"])

        let response = try await client.send(endpoint, bearerToken: "private-token")
        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(response.value, "ok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer private-token")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Request-ID"))
    }

    func testDecodes204AsEmptyObject() async throws {
        let transport = StubHTTPTransport([.response(status: 204, data: Data())])
        let client = APIClient(baseURL: URL(string: "https://example.test")!, transport: transport)
        let endpoint = Endpoint<EmptyResponse>(method: .delete, path: ["resource"])

        let response = try await client.send(endpoint, bearerToken: "token")

        XCTAssertEqual(response, EmptyResponse())
    }

    func testMapsCanonicalErrorBody() async {
        let data = Data(
            """
            {"error":{"code":"validation_error","message":"Invalid request","details":[{"field":"email","message":"Invalid email"}],"traceId":"trace-1"}}
            """.utf8
        )
        let transport = StubHTTPTransport([.response(status: 422, data: data)])
        let client = APIClient(baseURL: URL(string: "https://example.test")!, transport: transport)

        var mappedRequestID: UUID?
        do {
            let _: EmptyResponse = try await client.send(
                Endpoint(method: .get, path: ["resource"]),
                bearerToken: "token"
            )
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error.statusCode, 422)
            XCTAssertEqual(error.code, "validation_error")
            XCTAssertEqual(error.fieldErrors["email"], "Invalid email")
            XCTAssertEqual(error.traceID, "trace-1")
            mappedRequestID = error.requestID
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = await transport.requests()
        let requestHeader = requests.first?.value(forHTTPHeaderField: "X-Request-ID")
        XCTAssertEqual(requestHeader, mappedRequestID?.uuidString.lowercased())
    }

    func testMalformedErrorUsesSafeFallback() async {
        let transport = StubHTTPTransport([.response(status: 500, data: Data("not-json".utf8))])
        let client = APIClient(baseURL: URL(string: "https://example.test")!, transport: transport)

        do {
            let _: EmptyResponse = try await client.send(
                Endpoint(method: .get, path: ["resource"]),
                bearerToken: "token"
            )
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "internal_error")
            XCTAssertEqual(error.statusCode, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportCancellationRemainsCancellation() async {
        let transport = StubHTTPTransport([.cancelled])
        let client = APIClient(baseURL: URL(string: "https://example.test")!, transport: transport)

        do {
            let _: EmptyResponse = try await client.send(
                Endpoint(method: .get, path: ["resource"]),
                bearerToken: "token"
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private struct ValueResponse: Codable, Equatable, Sendable {
        let value: String
    }
}
