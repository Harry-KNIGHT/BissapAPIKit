import Foundation

/// Endpoint routing helpers for `APIClient`.
extension APIClient {
    /// Router describing a single HTTP request.
    ///
    /// This enum intentionally uses a single `.direct` case so callers provide
    /// a full URL and avoid hidden base-URL behavior.
    public enum Endpoint {
        /// Defines a request from a full URL, HTTP method, optional payload, and optional headers.
        ///
        /// - Parameters:
        ///   - url: Destination URL.
        ///   - method: HTTP verb to use.
        ///   - payload: Optional values used as query items for `GET` and JSON body for non-`GET`.
        ///     `nil` values are dropped.
        ///   - headers: Additional HTTP headers to send with the request.
        /// - Note:
        ///   For `GET`, only `String`, `Int`, `Double`, and `Bool` payload values are converted
        ///   into query items. Unsupported types are ignored for query encoding.
        case direct(
            url: URL,
            method: HTTPMethod,
            payload: [String: Any?]? = nil,
            headers: [String: String] = [:]
        )

        var url: URL {
            switch self {
            case let .direct(url, _, _, _):
                return url
            }
        }

        var method: HTTPMethod {
            switch self {
            case let .direct(_, method, _, _):
                return method
            }
        }

        var payload: [String: Any?]? {
            switch self {
            case let .direct(_, _, payload, _):
                return payload
            }
        }

        var headers: [String: String] {
            switch self {
            case let .direct(_, _, _, headers):
                return headers
            }
        }

        /// Builds URL components from `url` and appends query items for GET payloads.
        var urlComponents: URLComponents {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()

            // For GET, encode payload into query items.
            if method == .get, let payload, !payload.isEmpty {
                let existing = comps.queryItems ?? []
                let added = payload.compactMap { (key, value) -> URLQueryItem? in
                    guard let queryValue = APIClient.toQueryValue(value) else { return nil }
                    return URLQueryItem(name: key, value: queryValue)
                }
                comps.queryItems = existing + added
            }

            return comps
        }

        /// Final URL after applying computed query items.
        var resolvedURL: URL {
            urlComponents.url ?? url
        }

        /// Encodes non-GET payload into JSON request body data.
        ///
        /// - Throws: Any `JSONSerialization` error when payload values are not JSON-compatible.
        var bodyData: Data? {
            get throws {
                guard method != .get, let payload else { return nil }
                let filtered = payload.compactMapValues { $0 }
                guard !filtered.isEmpty else { return nil }
                return try JSONSerialization.data(withJSONObject: filtered, options: [])
            }
        }
    }

    /// Converts supported query value types to string form.
    ///
    /// Unsupported types return `nil` so they are omitted from the query string.
    private static func toQueryValue(_ any: Any?) -> String? {
        switch any {
        case let v as String: return v
        case let v as Int: return String(v)
        case let v as Double: return String(v)
        case let v as Bool: return v ? "true" : "false"
        default: return nil
        }
    }
}
