import Foundation
import UniformTypeIdentifiers
import OSLog

enum APIClient {
    /// Injectable session for tests / future SPM usage.
    static private let session: URLSession = .shared

    private static let decoder = JSONDecoder()

    private static let logger = Logger()

    // MARK: - Public

    /// Request expecting a decodable JSON response.
    ///
    /// Usage:
    /// `let user: User = try await APIClient.request(endpoint, responseType: User.self, accessToken: token)`
    static func request<T: Decodable>(
        _ endpoint: Endpoint,
        responseType: T.Type = T.self,
        accessToken: String? = nil
    ) async throws -> T {
        let request = try makeURLRequest(for: endpoint, accessToken: accessToken)
        let (data, response) = try await session.data(for: request)
        let validated = try validate(response: response, data: data, allowEmptyBody: false)
        return try decoder.decode(T.self, from: validated)
    }

    /// Request where you don't have a return value.
    static func request(
        _ endpoint: Endpoint,
        accessToken: String? = nil
    ) async throws {
        let request = try makeURLRequest(for: endpoint, accessToken: accessToken)
        let (data, response) = try await session.data(for: request)
        _ = try validate(response: response, data: data, allowEmptyBody: true)
    }

    // MARK: - Internals

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

    private static func validate(
        response: URLResponse,
        data: Data,
        allowEmptyBody: Bool,
        context: String? = nil
    ) throws -> Data {
        guard let http = response as? HTTPURLResponse else { throw ServiceError.notAnHTTPResponse }
        guard (200..<300).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
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
    static func putToS3(
        presignedURL: URL,
        data: Data,
        contentType: String? = nil,
        signedHeaders: [String: String] = [:],
        // Because we only use that for room for the moment.
        filename: String? = "room\(UUID().uuidString)"
    ) async throws {
        var req = URLRequest(url: presignedURL)
        req.httpMethod = HTTPMethod.put.rawValue

        // Resolve the correct MIME type: prefer explicit contentType; otherwise infer from filename; fallback to JPEG
        let resolvedMime: String = {
            if let ct = contentType, !ct.isEmpty { return ct }
            if let fn = filename,
               let ut = UTType(filenameExtension: (fn as NSString).pathExtension),
               let m = ut.preferredMIMEType { return m }
            return "image/jpeg"
        }()

        // Send raw bytes with the correct Content-Type (NOT multipart/form-data)
        req.setValue(resolvedMime, forHTTPHeaderField: "Content-Type")
        // Helps browsers render instead of download by default
        req.setValue("inline", forHTTPHeaderField: "Content-Disposition")

        // Apply exactly the headers that were part of the signing, without overriding signed Content-Type/Disposition
        for (k, v) in signedHeaders {
            if k.caseInsensitiveCompare("Content-Type") == .orderedSame { continue }
            if k.caseInsensitiveCompare("Content-Disposition") == .orderedSame { continue }
            req.setValue(v, forHTTPHeaderField: k)
        }

        // Optional but explicit: send known length
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
