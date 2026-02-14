# Agent Guide: Using BissapAPIKit API Library

Use this guide to execute `BissapAPIKit` requests deterministically and handle success and failure paths without guesswork.

## Quick Contract
- What this library does: Sends HTTP requests, decodes JSON into Swift `Decodable` models, and uploads raw bytes to S3 with a presigned URL.
- Main entrypoint(s): `APIClient.request<T>(...)`, `APIClient.request(...)`, `APIClient.putToS3(...)`, `APIClient.Endpoint.direct(...)`.
- Required inputs:
- A full `URL` for every request.
- An `HTTPMethod` (`get`, `post`, `delete`, `patch`, `put`).
- Optional payload as `[String: Any?]` (query for `GET`, JSON body for non-`GET`).
- Optional bearer token via `accessToken`.
- Outputs:
- Typed decoded model for `request<T>`.
- No return value for `request` (void overload) and `putToS3`.
- Errors thrown via `ServiceError` and standard Swift networking/decoding errors.

## Minimal Happy Path
### Install
Add `BissapAPIKit` as a SwiftPM dependency in your app package:

```swift
// Package.swift (consumer app/package)
dependencies: [
    .package(path: "../BissapAPIKit")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "BissapAPIKit", package: "BissapAPIKit")
        ]
    )
]
```

### Configure
```swift
import Foundation
import BissapAPIKit

let endpoint = APIClient.Endpoint.direct(
    url: URL(string: "https://jsonplaceholder.typicode.com/todos/1")!,
    method: .get,
    payload: nil
)
let accessToken: String? = nil
```

### Execute a single call
```swift
struct Todo: Decodable {
    let userId: Int
    let id: Int
    let title: String
    let completed: Bool
}

let todo: Todo = try await APIClient.request(
    endpoint,
    responseType: Todo.self,
    accessToken: accessToken
)
```

### Expected response shape (JSON)
```json
{
  "userId": 1,
  "id": 1,
  "title": "delectus aut autem",
  "completed": false
}
```

## API Surface
### `APIClient`
Signature:
```swift
public enum APIClient
```

### `APIClient.request<T>`
Signature:
```swift
public static func request<T: Decodable>(
    _ endpoint: Endpoint,
    responseType: T.Type = T.self,
    accessToken: String? = nil
) async throws -> T
```
Parameters:
- `endpoint`: Request description (`URL`, method, optional payload).
- `responseType`: Decodable target type.
- `accessToken`: Optional bearer token (`Authorization: Bearer <token>`).
Return type/shape:
- Returns decoded instance of `T`.
Errors and handling:
- `ServiceError.notAnHTTPResponse` if response is not `HTTPURLResponse`.
- `ServiceError.serverIssue` for non-2xx status.
- `ServiceError.emptyData` if body is empty when decoding is required.
- `DecodingError` if JSON shape does not match `T`.
- `URLError` or other networking errors from `URLSession`.

### `APIClient.request` (void overload)
Signature:
```swift
public static func request(
    _ endpoint: Endpoint,
    accessToken: String? = nil
) async throws
```
Parameters:
- `endpoint`: Request description.
- `accessToken`: Optional bearer token.
Return type/shape:
- No return value.
Errors and handling:
- Same HTTP/network validation path as above, but empty body is allowed.

### `APIClient.putToS3`
Signature:
```swift
public static func putToS3(
    presignedURL: URL,
    data: Data,
    contentType: String? = nil,
    signedHeaders: [String: String] = [:],
    filename: String? = "room\(UUID().uuidString)"
) async throws
```
Parameters:
- `presignedURL`: Fully signed S3 PUT URL.
- `data`: Raw bytes to upload.
- `contentType`: Optional explicit MIME type.
- `signedHeaders`: Headers from the presign response (applied except `Content-Type`/`Content-Disposition` overrides).
- `filename`: Optional filename used to infer MIME type if `contentType` is nil.
Return type/shape:
- No return value; success means upload accepted by S3.
Errors and handling:
- `ServiceError.serverIssue` on non-2xx.
- `ServiceError.notAnHTTPResponse` on malformed response.
- `URLError`/transport failures.

### `APIClient.Endpoint`
Signature:
```swift
public enum Endpoint {
    case direct(url: URL, method: HTTPMethod, payload: [String: Any?]? = nil)
}
```
Parameters:
- `url`: Absolute URL.
- `method`: HTTP verb.
- `payload`: Optional data map.
Return type/shape:
- `GET`: payload values (`String`, `Int`, `Double`, `Bool`) become query parameters.
- Non-`GET`: payload is encoded as JSON body (nil values removed).
Errors and handling:
- Non-JSON-serializable non-`GET` payload values throw during request construction.

### `HTTPMethod`
Signature:
```swift
public enum HTTPMethod: String {
    case get, post, delete, patch, put
}
```
Parameters:
- None.
Return type/shape:
- Raw values map to uppercase HTTP verbs.
Errors and handling:
- None directly.

### `ServiceError`
Signature:
```swift
public enum ServiceError: Error {
    case unknownURL
    case notAnHTTPResponse
    case ressourceDoesNotExists
    case serverIssue
    case emptyData
    case noPresignedURL
}
```
Parameters:
- None.
Return type/shape:
- Enum errors thrown by `APIClient` validation logic.
Errors and handling:
- Pattern-match in `catch` to branch behavior.

## Authentication & Configuration
### Env vars
- None required by the library itself.
- If your app stores secrets in env vars, read them in app code and pass them as `accessToken`.

### Programmatic configuration
- Pass `accessToken` to add `Authorization: Bearer <token>`.
- For non-`GET`, payload auto-encodes to JSON and defaults `Content-Type` to `application/json` if unset.
- For `putToS3`, bytes are sent raw with inferred or explicit MIME type.

## Rate Limits / Retries / Idempotency
- Rate limits: Not enforced by `BissapAPIKit`; they are defined by the upstream API/S3.
- Retries: Not automatic. Implement caller-side retry for transient failures (e.g., timeout, 5xx).
- Idempotency:
- `GET` is generally safe to retry.
- `PUT` to the same object key is usually idempotent.
- `POST` is not guaranteed idempotent; use server-side idempotency keys if required.

## Common Failure Modes
| Symptom | Likely cause | Fix |
|---|---|---|
| `ServiceError.serverIssue` | HTTP status outside 200-299 | Inspect server logs/response body; verify URL, auth, and payload. |
| `ServiceError.emptyData` | Decodable request got an empty body | Use the void `request` overload for no-content endpoints, or fix server response body. |
| `DecodingError` | Model does not match JSON | Update your `Decodable` model to match exact keys/types. |
| Query parameters missing | `GET` payload contains unsupported value types | Restrict query payload values to `String`, `Int`, `Double`, or `Bool`. |
| S3 upload rejected | Presigned URL expired or signed headers mismatch | Refresh presigned URL and pass exact `signedHeaders` from signer. |
| Upload opens as download | Missing/incorrect content metadata | Keep `Content-Disposition: inline` and correct `Content-Type`. |

## Do / Don't Rules
- Do pass fully qualified `URL`s; this library does not build base URLs for you.
- Do use typed `Decodable` models for deterministic decoding.
- Do use the void `request` overload for endpoints that return no body.
- Do catch `ServiceError` and `DecodingError` separately when behavior differs.
- Don't pass complex objects in `GET` payload query params.
- Don't assume automatic retries, refresh tokens, or base URL management.
- Don't override presigned `Content-Type`/`Content-Disposition` through `signedHeaders`.

## Tooling Notes
- Runtime/language: Swift package (`swift-tools-version: 6.2`).
- Supported platform declared in package: iOS 15+.
- Module name: `BissapAPIKit`.
- Module style: SwiftPM library (ESM/CJS are not applicable).

## Assumptions
- The consumer project is an iOS 15+ Swift app or package.
- Installation example uses local path dependency (`../BissapAPIKit`) because no canonical remote URL is defined in this repository.
- The happy-path endpoint (`jsonplaceholder.typicode.com`) is reachable during execution.
