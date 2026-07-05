import Foundation

/// Domain-level errors surfaced by `BissapAPIKit`.
///
/// Use these cases in `catch` blocks to branch between transport, server, and data-shape failures.
public enum ServiceError: Error {
    /// The URL is unknown or could not be resolved.
    /// Fix: verify URL creation and ensure it is absolute.
    case unknownURL

    /// The response was not an `HTTPURLResponse`.
    /// Fix: ensure the request uses an HTTP/HTTPS URL and that transport succeeded.
    case notAnHTTPResponse

    /// A requested resource was not found on the server.
    /// Fix: verify identifiers, route, and server-side existence.
    case ressourceDoesNotExists

    /// The server returned a non-success status code.
    /// Fix: inspect status code/body logs, then validate auth, payload, and endpoint URL.
    ///
    /// - Note: Kept for source compatibility. New HTTP validation failures throw
    ///   `httpError(statusCode:message:body:url:)` so callers can display the backend message.
    case serverIssue

    /// The server returned a non-success status code with a response payload.
    /// Fix: inspect `statusCode`, display/log `message`, and use `body` for deeper diagnostics.
    case httpError(statusCode: Int, message: String, body: String?, url: URL?)

    /// The response body was empty when data was required for decoding.
    /// Fix: use a no-body endpoint variant or correct backend response payload.
    case emptyData

    /// A required presigned upload URL was missing.
    /// Fix: request a fresh presigned URL from the backend before upload.
    case noPresignedURL
}

public extension ServiceError {
    /// HTTP status returned by the backend when available.
    var statusCode: Int? {
        guard case let .httpError(statusCode, _, _, _) = self else { return nil }
        return statusCode
    }

    /// Message extracted from the backend error payload when available.
    var backendMessage: String? {
        guard case let .httpError(_, message, _, _) = self else { return nil }
        return message
    }

    /// Raw backend response body when available.
    var responseBody: String? {
        guard case let .httpError(_, _, body, _) = self else { return nil }
        return body
    }

    /// URL that returned the HTTP error when available.
    var responseURL: URL? {
        guard case let .httpError(_, _, _, url) = self else { return nil }
        return url
    }
}

extension ServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unknownURL:
            "Unknown URL."
        case .notAnHTTPResponse:
            "Response was not HTTP."
        case .ressourceDoesNotExists:
            "Resource does not exist."
        case .serverIssue:
            "Server error."
        case let .httpError(_, message, _, _):
            message
        case .emptyData:
            "Response body was empty."
        case .noPresignedURL:
            "Missing presigned upload URL."
        }
    }
}

extension ServiceError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknownURL:
            "ServiceError.unknownURL"
        case .notAnHTTPResponse:
            "ServiceError.notAnHTTPResponse"
        case .ressourceDoesNotExists:
            "ServiceError.ressourceDoesNotExists"
        case .serverIssue:
            "ServiceError.serverIssue"
        case let .httpError(statusCode, message, body, url):
            [
                "ServiceError.httpError(statusCode: \(statusCode)",
                "message: \(message)",
                url.map { "url: \($0.absoluteString)" },
                body.map { "body: \($0)" },
            ]
            .compactMap { $0 }
            .joined(separator: ", ") + ")"
        case .emptyData:
            "ServiceError.emptyData"
        case .noPresignedURL:
            "ServiceError.noPresignedURL"
        }
    }
}
