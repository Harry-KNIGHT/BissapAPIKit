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
    private static let logger = Logger()

    // MARK: - Public

    /// Executes an HTTP request and decodes a JSON response.
    ///
    /// - Parameters:
    ///   - endpoint: Request definition containing URL, method, and optional payload.
    ///   - responseType: Expected decodable model type. Defaults to `T.self`.
    ///   - accessToken: Optional bearer token sent as `Authorization: Bearer <token>`.
    /// - Returns: A decoded value of type `T`.
    /// - Throws:
    ///   - `ServiceError.notAnHTTPResponse` when the transport response is not HTTP.
    ///   - `ServiceError.serverIssue` when status code is outside `200..<300`.
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
        accessToken: String? = nil
    ) async throws -> T {
        let request = try makeURLRequest(for: endpoint, accessToken: accessToken)
        let (data, response) = try await session.data(for: request)
        let validated = try validate(response: response, data: data, allowEmptyBody: false)
        return try decoder.decode(T.self, from: validated)
    }

    /// Executes an HTTP request where the caller does not need to decode a response body.
    ///
    /// - Parameters:
    ///   - endpoint: Request definition containing URL, method, and optional payload.
    ///   - accessToken: Optional bearer token sent as `Authorization: Bearer <token>`.
    /// - Throws:
    ///   - `ServiceError.notAnHTTPResponse` when the transport response is not HTTP.
    ///   - `ServiceError.serverIssue` when status code is outside `200..<300`.
    ///   - `URLError` or other `URLSession` transport errors.
    public static func request(
        _ endpoint: Endpoint,
        accessToken: String? = nil
    ) async throws {
        let request = try makeURLRequest(for: endpoint, accessToken: accessToken)
        let (data, response) = try await session.data(for: request)
        _ = try validate(response: response, data: data, allowEmptyBody: true)
    }

    // MARK: - Internals

    /// Builds the final `URLRequest` from endpoint data and optional auth.
    ///
    /// - Note: For non-GET requests, payload is encoded as JSON by `Endpoint.bodyData`.
    private static func makeURLRequest(for endpoint: Endpoint, accessToken: String?) throws -> URLRequest {
        let finalURL = endpoint.resolvedURL
        let method = endpoint.method

        var req = URLRequest(url: finalURL)
        req.httpMethod = method.rawValue

        // Apply auth
        if let accessToken {
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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
    ///   - `ServiceError.serverIssue` for any non-2xx status code.
    ///   - `ServiceError.emptyData` when `allowEmptyBody` is `false` and body is empty.
    private static func validate(
        response: URLResponse,
        data: Data,
        allowEmptyBody: Bool,
        context: String? = nil
    ) throws -> Data {
        guard let http = response as? HTTPURLResponse else { throw ServiceError.notAnHTTPResponse }
        guard (200..<300).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            // Keep server context in logs so callers can quickly diagnose request failures.
            logger.error(
            """
            HTTP error status=\(http.statusCode),
            url=\(http.url?.absoluteString ?? "<unknown>"),
            body=\(errorText, privacy: .public),
            headers=\(String(describing: http.allHeaderFields), privacy: .public),
            context=\(String(describing: context), privacy: .public)
            """
            )
            throw ServiceError.serverIssue
        }

        if allowEmptyBody {
            return data
        }

        if data.isEmpty {
            throw ServiceError.emptyData
        }

        return data
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
    ///   - `ServiceError.serverIssue` when status code is outside `200..<300`.
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
