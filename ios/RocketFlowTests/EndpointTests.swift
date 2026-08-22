import Foundation
import XCTest
@testable import RocketFlow

final class EndpointTests: XCTestCase {
    func testBuildsRelativePathQueryAuthorizationAndRequestID() throws {
        let endpoint = Endpoint<EmptyResponse>(
            method: .get,
            path: ["tasks", "name/with space"],
            queryItems: [URLQueryItem(name: "q", value: "цель & план")]
        )
        let requestID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

        let request = try endpoint.makeRequest(
            baseURL: URL(string: "http://45.10.110.42/rocket-api")!,
            bearerToken: "access-token",
            requestID: requestID
        )

        XCTAssertEqual(request.urlRequest.url?.path, "/rocket-api/tasks/name/with space")
        XCTAssertEqual(
            request.urlRequest.url?.percentEncodedPath,
            "/rocket-api/tasks/name%2Fwith%20space"
        )
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(request.urlRequest.url), resolvingAgainstBaseURL: false)?
                .queryItems?.first?.value,
            "цель & план"
        )
        XCTAssertEqual(request.urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(
            request.urlRequest.value(forHTTPHeaderField: "X-Request-ID"),
            requestID.uuidString.lowercased()
        )
    }

    func testProtectedEndpointRejectsMissingToken() {
        let endpoint = Endpoint<EmptyResponse>(method: .get, path: ["me"])

        XCTAssertThrowsError(
            try endpoint.makeRequest(baseURL: URL(string: "https://example.test/rocket-api")!)
        ) { error in
            XCTAssertEqual(error as? APIClientFailure, .missingAuthorization)
        }
    }

    func testAuthEndpointDoesNotRequireToken() throws {
        let endpoint = try AuthEndpoints.login(.init(email: "user@example.com", password: "password"))

        let request = try endpoint.makeRequest(baseURL: URL(string: "https://example.test/rocket-api")!)

        XCTAssertEqual(request.urlRequest.url?.path, "/rocket-api/auth/login")
        XCTAssertNil(request.urlRequest.value(forHTTPHeaderField: "Authorization"))
    }
}
