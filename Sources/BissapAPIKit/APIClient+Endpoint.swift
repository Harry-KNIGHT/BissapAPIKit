import Foundation

extension APIClient {
    /// Router describing an HTTP request.
    public enum Endpoint {
        case direct(
            url: URL,
            method: HTTPMethod,
            payload: [String: Any?]? = nil
        )

        var url: URL {
            switch self {
            case let .direct(url, _, _):
                return url
            }
        }

        var method: HTTPMethod {
            switch self {
            case let .direct(_, method, _):
                return method
            }
        }

        var payload: [String: Any?]? {
            switch self {
            case let .direct(_, _, payload):
                return payload
            }
        }

        /// URLComponents built from `url` and, for GET requests, the `payload` as query items.
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

        /// Final URL after applying query items (GET only).
        var resolvedURL: URL {
            urlComponents.url ?? url
        }

        /// For non-GET requests, encodes payload into JSON data.
        var bodyData: Data? {
            get throws {
                guard method != .get, let payload else { return nil }
                let filtered = payload.compactMapValues { $0 }
                guard !filtered.isEmpty else { return nil }
                return try JSONSerialization.data(withJSONObject: filtered, options: [])
            }
        }
    }

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
