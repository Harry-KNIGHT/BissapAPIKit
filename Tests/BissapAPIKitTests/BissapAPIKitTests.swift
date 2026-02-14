import XCTest
@testable import BissapAPIKit

final class BissapAPIKitTests: XCTestCase {
    func testCanConstructPublicEndpointAndHTTPMethod() {
        let url = URL(string: "https://example.com")!
        let endpoint = APIClient.Endpoint.direct(url: url, method: .get, payload: nil)

        switch endpoint {
        case let .direct(resolvedURL, method, payload):
            XCTAssertEqual(resolvedURL, url)
            XCTAssertEqual(method, .get)
            XCTAssertNil(payload)
        }
    }
}
