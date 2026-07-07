import Foundation
import OSLog
import UniformTypeIdentifiers

/// Networking namespace for API calls and presigned S3 uploads.
///
/// `APIClient` executes fully-defined `Endpoint` values and validates HTTP responses.
/// It does not manage base URLs, retries, token refresh, or persistence.
public enum APIClient {
    /// Shared URL session used by all requests.
    ///
    /// Kept internal so request behavior remains centralized.
    static private let session: URLSession = .shared

    /// Shared JSON decoder for typed response decoding.
    private static let decoder = JSONDecoder()

    /// Logger used to capture server-side failure context.
    private static let logger = Logger(subsystem: "BissapAPIKit", category: "Networking")

    // MARK: - Public

    /// Executes an HTTP request and decodes a JSON response.
    ///
    /// - Parameters:
    ///   - endpoint: Request definition containing URL, method, and optional payload.
    ///   - responseType: Expected decodable model type. Defaults to `T.self`.
    ///   - bearerToken: Optional bearer token sent as `Authorization: Bearer <token>`.
    ///     The token format is intentionally opaque to the client: JWTs and opaque
    ///     access tokens are both supported when your backend accepts them as bearer credentials.
    ///     When provided, this value overrides an endpoint `Authorization` header.
    /// - Returns: A decoded value of type `T`.
    /// - Throws:
    ///   - `ServiceError.notAnHTTPResponse` when the transport response is not HTTP.
    ///   - `ServiceError.httpError` when status code is outside `200..<300`.
    ///   - `ServiceError.emptyData` when the body is empty.
    ///   - `DecodingError` when JSON shape does not match `T`.
    ///   - `URLError` or other `URLSession` transport errors.
    /// - Example:
    ///   ```swift
    ///   struct User: Decodable { let id: String }
    ///
    ///   let endpoint = APIClient.Endpoint.direct(
    ///       url: URL(string: "https://example.com/users/me")!,
    ///       method: .get
    ///   )
    ///
    ///   let user: User = try await APIClient.request(endpoint)
    ///   ```
    public static func request<T: Decodable>(
        _ endpoint: Endpoint,
        responseType: T.Type = T.self,
        bearerToken: String? = nil
    ) async throws -> T {
        let request = try makeURLRequest(for: endpoint, bearerToken: bearerToken)
        let (data, response) = try await session.data(for: request)
        let validated = try validate(response: response, data: data, allowEmptyBody: false)
        return try decoder.decode(T.self, from: validated)
    }

    /// Executes an HTTP request where the caller does not need to decode a response body.
    ///
    /// - Parameters:
    ///   - endpoint: Request definition containing URL, method, and optional payload.
    ///   - bearerToken: Optional bearer token sent as `Authorization: Bearer <token>`.
    ///     The token format is intentionally opaque to the client: JWTs and opaque
    ///     access tokens are both supported when your backend accepts them as bearer credentials.
    ///     When provided, this value overrides an endpoint `Authorization` header.
    /// - Throws:
    ///   - `ServiceError.notAnHTTPResponse` when the transport response is not HTTP.
    ///   - `ServiceError.httpError` when status code is outside `200..<300`.
    ///   - `URLError` or other `URLSession` transport errors.
    public static func request(
        _ endpoint: Endpoint,
        bearerToken: String? = nil
    ) async throws {
        let request = try makeURLRequest(for: endpoint, bearerToken: bearerToken)
        let (data, response) = try await session.data(for: request)
        _ = try validate(response: response, data: data, allowEmptyBody: true)
    }

    // MARK: - Internals

    /// Builds the final `URLRequest` from endpoint data and optional auth.
    ///
    /// - Note: For non-GET requests, payload is encoded as JSON by `Endpoint.bodyData`.
    static func makeURLRequest(for endpoint: Endpoint, bearerToken: String?) throws -> URLRequest {
        let finalURL = endpoint.resolvedURL
        let method = endpoint.method

        var req = URLRequest(url: finalURL)
        req.httpMethod = method.rawValue

        for (field, value) in endpoint.headers {
            req.setValue(value, forHTTPHeaderField: field)
        }

        // Apply auth
        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        // Body (non-GET)
        if let body = try endpoint.bodyData {
            req.httpBody = body
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        return req
    }

    /// Validates HTTP response status and body availability.
    ///
    /// - Parameters:
    ///   - response: Raw `URLSession` response object.
    ///   - data: Body bytes returned by the server.
    ///   - allowEmptyBody: `true` when empty body is acceptable.
    ///   - context: Optional label to enrich logs for debugging.
    /// - Returns: The original response data when validation succeeds.
    /// - Throws:
    ///   - `ServiceError.notAnHTTPResponse` if response is not `HTTPURLResponse`.
    ///   - `ServiceError.httpError` for any non-2xx status code.
    ///   - `ServiceError.emptyData` when `allowEmptyBody` is `false` and body is empty.
    private static func validate(
        response: URLResponse,
        data: Data,
        allowEmptyBody: Bool,
        context: String? = nil
    ) throws -> Data {
        guard let http = response as? HTTPURLResponse else { throw ServiceError.notAnHTTPResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = httpError(statusCode: http.statusCode, url: http.url, data: data)
            // Keep server context in logs so callers can quickly diagnose request failures.
            logger.error(
            """
            HTTP error status=\(http.statusCode),
            url=\(http.url?.absoluteString ?? "<unknown>"),
            message=\(error.backendMessage ?? "<none>", privacy: .public),
            body=\(error.responseBody ?? "<empty>", privacy: .public),
            headers=\(String(describing: http.allHeaderFields), privacy: .public),
            context=\(String(describing: context), privacy: .public)
            """
            )
            throw error
        }

        if allowEmptyBody {
            return data
        }

        if data.isEmpty {
            throw ServiceError.emptyData
        }

        return data
    }

    static func httpError(statusCode: Int, url: URL?, data: Data) -> ServiceError {
        let body = responseBodyText(from: data)
        let message = backendErrorMessage(from: data, body: body)
            ?? fallbackHTTPMessage(for: statusCode)

        return .httpError(
            statusCode: statusCode,
            message: message,
            body: body,
            url: url
        )
    }

    private static func responseBodyText(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8) ?? "<non-utf8 body: \(data.count) bytes>"
    }

    private static func backendErrorMessage(from data: Data, body: String?) -> String? {
        guard !data.isEmpty else { return nil }

        if let json = try? JSONSerialization.jsonObject(with: data),
           let message = extractBackendMessage(from: json) {
            return message
        }

        return body?.trimmedNonEmpty
    }

    private static func fallbackHTTPMessage(for statusCode: Int) -> String {
        let reason = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        return "HTTP \(statusCode) \(reason.capitalized)"
    }

    private static func extractBackendMessage(from json: Any) -> String? {
        if let dictionary = json as? [String: Any] {
            let knownKeys = [
                "message",
                "msg",
                "detail",
                "errormessage",
                "error_description",
                "errordescription",
                "error",
                "reason",
                "title",
                "description",
                "errors",
            ]

            let valuesByLowercaseKey = dictionary.reduce(into: [String: Any]()) { values, element in
                values[element.key.lowercased()] = element.value
            }

            for key in knownKeys {
                if let message = valuesByLowercaseKey[key].flatMap(stringifyBackendMessage) {
                    return message
                }
            }

            for value in dictionary.values {
                if let nested = value as? [String: Any],
                   let message = extractBackendMessage(from: nested) {
                    return message
                }

                if let array = value as? [Any],
                   let message = extractBackendMessage(from: array) {
                    return message
                }
            }

            return nil
        }

        if let array = json as? [Any] {
            let messages = array.compactMap(stringifyBackendMessage)
            return messages.isEmpty ? nil : messages.joined(separator: ", ")
        }

        return stringifyBackendMessage(json)
    }

    private static func stringifyBackendMessage(_ value: Any) -> String? {
        switch value {
        case let string as String:
            return string.trimmedNonEmpty
        case let number as NSNumber:
            return String(describing: number)
        case let dictionary as [String: Any]:
            return extractBackendMessage(from: dictionary)
        case let array as [Any]:
            let messages = array.compactMap(stringifyBackendMessage)
            return messages.isEmpty ? nil : messages.joined(separator: ", ")
        default:
            return nil
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension APIClient {
    /// Uploads raw bytes to a presigned S3 URL using HTTP `PUT`.
    ///
    /// - Parameters:
    ///   - presignedURL: Fully signed URL returned by your backend/storage signer.
    ///   - data: Raw file bytes to upload.
    ///   - contentType: Optional explicit MIME type. When omitted, inferred from `filename` extension.
    ///   - signedHeaders: Additional headers required by the presigned signature.
    ///   - filename: Optional filename used to infer MIME type when `contentType` is absent.
    /// - Throws:
    ///   - `ServiceError.notAnHTTPResponse` when the transport response is not HTTP.
    ///   - `ServiceError.httpError` when status code is outside `200..<300`.
    ///   - `URLError` or other `URLSession` transport errors.
    /// - Note: Upload uses raw bytes (`upload(for:from:)`), not multipart form data.
    public static func putToS3(
        presignedURL: URL,
        data: Data,
        contentType: String? = nil,
        signedHeaders: [String: String] = [:],
        // Because we only use that for room for the moment.
        filename: String? = "room\(UUID().uuidString)"
    ) async throws {
        var req = URLRequest(url: presignedURL)
        req.httpMethod = HTTPMethod.put.rawValue

        // Resolve MIME type deterministically:
        // 1) explicit contentType
        // 2) inferred from filename extension
        // 3) fallback to image/jpeg
        let resolvedMime: String = {
            if let ct = contentType, !ct.isEmpty { return ct }
            if let fn = filename,
               let ut = UTType(filenameExtension: (fn as NSString).pathExtension),
               let m = ut.preferredMIMEType { return m }
            return "image/jpeg"
        }()

        // Send raw bytes with the correct content metadata.
        req.setValue(resolvedMime, forHTTPHeaderField: "Content-Type")
        // Inline disposition helps browsers render supported file types directly.
        req.setValue("inline", forHTTPHeaderField: "Content-Disposition")

        // Preserve signing contract: pass through signed headers except fields controlled above.
        for (k, v) in signedHeaders {
            if k.caseInsensitiveCompare("Content-Type") == .orderedSame { continue }
            if k.caseInsensitiveCompare("Content-Disposition") == .orderedSame { continue }
            req.setValue(v, forHTTPHeaderField: k)
        }

        // Include size explicitly for services that validate Content-Length.
        req.setValue(String(data.count), forHTTPHeaderField: "Content-Length")

        let (body, resp) = try await session.upload(for: req, from: data)
        _ = try validate(
            response: resp,
            data: body,
            allowEmptyBody: true,
            context: "S3 PUT"
        )
    }
}
