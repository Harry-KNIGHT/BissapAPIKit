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
    case serverIssue

    /// The response body was empty when data was required for decoding.
    /// Fix: use a no-body endpoint variant or correct backend response payload.
    case emptyData

    /// A required presigned upload URL was missing.
    /// Fix: request a fresh presigned URL from the backend before upload.
    case noPresignedURL
}
