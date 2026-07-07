import Foundation
import XCTest
@testable import BissapAPIKit

final class BissapAPIKitTests: XCTestCase {
    func testCanConstructPublicEndpointAndHTTPMethod() {
        let url = URL(string: "https://example.com")!
        let endpoint = APIClient.Endpoint.direct(url: url, method: .get, payload: nil)

        switch endpoint {
        case let .direct(resolvedURL, method, payload, headers):
            XCTAssertEqual(resolvedURL, url)
            XCTAssertEqual(method, .get)
            XCTAssertNil(payload)
            XCTAssertTrue(headers.isEmpty)
        }
    }

    func testDirectEndpointCanCarryCustomHeaders() throws {
        let url = URL(string: "https://example.com/auth")!
        let endpoint = APIClient.Endpoint.direct(
            url: url,
            method: .post,
            payload: [:],
            headers: [
                "Authorization": "Token abc",
                "X-Request-ID": "request-1",
            ]
        )

        let request = try APIClient.makeURLRequest(for: endpoint, bearerToken: nil)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token abc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Request-ID"), "request-1")
        XCTAssertEqual(endpoint.payload?.count, 0)
    }

    func testBearerTokenOverridesDirectAuthorizationHeader() throws {
        let url = URL(string: "https://example.com/auth")!
        let endpoint = APIClient.Endpoint.direct(
            url: url,
            method: .post,
            headers: ["Authorization": "Token abc"]
        )

        let request = try APIClient.makeURLRequest(for: endpoint, bearerToken: "bearer-token")

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer bearer-token")
        XCTAssertNil(endpoint.payload)
    }

    func testDirectContentTypeHeaderIsPreservedForJSONBody() throws {
        let url = URL(string: "https://example.com/auth")!
        let endpoint = APIClient.Endpoint.direct(
            url: url,
            method: .post,
            payload: ["email": "user@example.com"],
            headers: ["Content-Type": "application/vnd.api+json"]
        )

        let request = try APIClient.makeURLRequest(for: endpoint, bearerToken: nil)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/vnd.api+json")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["email": "user@example.com"])
    }

    func testJSONBodyDefaultsContentTypeWhenHeaderIsMissing() throws {
        let url = URL(string: "https://example.com/auth")!
        let endpoint = APIClient.Endpoint.direct(
            url: url,
            method: .post,
            payload: ["email": "user@example.com"]
        )

        let request = try APIClient.makeURLRequest(for: endpoint, bearerToken: nil)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNotNil(request.httpBody)
    }

    func testHTTPErrorUsesPlainTextBackendMessage() {
        let url = URL(string: "https://example.com/auth")!
        let error = APIClient.httpError(
            statusCode: 401,
            url: url,
            data: Data("Invalid audience".utf8)
        )

        XCTAssertEqual(error.statusCode, 401)
        XCTAssertEqual(error.backendMessage, "Invalid audience")
        XCTAssertEqual(error.responseBody, "Invalid audience")
        XCTAssertEqual(error.responseURL, url)
        XCTAssertEqual(error.localizedDescription, "Invalid audience")
    }

    func testHTTPErrorExtractsJSONMessage() {
        let data = Data(#"{"message":"Invalid sign-in payload"}"#.utf8)
        let error = APIClient.httpError(statusCode: 400, url: nil, data: data)

        XCTAssertEqual(error.statusCode, 400)
        XCTAssertEqual(error.backendMessage, "Invalid sign-in payload")
        XCTAssertEqual(error.responseBody, #"{"message":"Invalid sign-in payload"}"#)
        XCTAssertEqual(error.localizedDescription, "Invalid sign-in payload")
    }

    func testHTTPErrorExtractsNestedJSONMessage() {
        let data = Data(#"{"detail":[{"loc":["body","token"],"msg":"invalid token","type":"value_error"}]}"#.utf8)
        let error = APIClient.httpError(statusCode: 403, url: nil, data: data)

        XCTAssertEqual(error.statusCode, 403)
        XCTAssertEqual(error.backendMessage, "invalid token")
        XCTAssertEqual(error.localizedDescription, "invalid token")
    }
}
