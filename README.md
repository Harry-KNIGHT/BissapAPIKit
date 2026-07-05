# BissapAPIKit (Super Simple Guide)

This guide helps you make your first API call with `BissapAPIKit` in very small steps, so you can copy, paste, run, and see a result without needing to understand advanced networking words.

## What is this?
`BissapAPIKit` is a helper library for Swift apps that talks to web APIs for you.
Think of it like a tiny delivery robot:
- You give it an address (`URL`).
- You tell it what action to do (`GET`, `POST`, and friends).
- It brings back data and puts it neatly into your Swift struct.

## Before you start
- You need a Swift project (usually in Xcode) that targets iOS 15 or newer.
- You need this `BissapAPIKit` folder on your machine.
- You need internet access for the demo request.
- You need to know where your app’s `Package.swift` is (if your app uses Swift Package Manager directly).

## Step 1: Install
Installing means “attach this helper library to your app so `import BissapAPIKit` works.”

Copy this into your app package’s `Package.swift`:

```swift
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

What you should see:
- Your project builds without “No such module `BissapAPIKit`”.
- `import BissapAPIKit` stops showing errors.

## Step 2: Set your bearer token (or config)
Good news: this library does not force an auth token by itself.
You only pass a bearer token when your API needs login/auth.

Copy this config idea into your code:

```swift
import Foundation
import BissapAPIKit

// For public endpoints, nil is fine.
let bearerToken: String? = nil

// Real URL for our tiny demo.
let demoURL = URL(string: "https://jsonplaceholder.typicode.com/todos/1")!
```

What you should see:
- No crash when creating `demoURL`.
- `bearerToken` can stay `nil` for the demo.

## Step 3: Run your first tiny example
Copy this Swift code:

```swift
import Foundation
import BissapAPIKit

// This is the shape of the JSON we expect to receive.
struct Todo: Decodable {
    let userId: Int
    let id: Int
    let title: String
    let completed: Bool
}

// Call this from your app (for example in a button action or onAppear).
func loadFirstTodo() {
    Task {
        // This builds the request description.
        let endpoint = APIClient.Endpoint.direct(
            url: URL(string: "https://jsonplaceholder.typicode.com/todos/1")!,
            method: .get,
            payload: nil
        )

        do {
            // This makes the request and decodes JSON into Todo.
            let todo: Todo = try await APIClient.request(endpoint)

            // This prints a simple success line.
            print("Todo title:", todo.title)
        } catch {
            // This prints the error if something goes wrong.
            print("Request failed:", error)
        }
    }
}
```

Expected output:

```text
Todo title: delectus aut autem
```

## Step 4: Next things you can do
- Send a `POST` by changing `method: .post` and adding `payload`.
- Add your own `Decodable` structs for your real API responses.
- Pass `bearerToken` when your API needs `Authorization: Bearer ...`.
- Use `APIClient.request(_:, bearerToken:)` (the no-return version) for endpoints with empty responses.
- Upload bytes to S3 with `APIClient.putToS3(...)` when you have a presigned URL.

## Technical TODO
- [ ] Keep `bearerToken` as the HTTP auth parameter for any token sent as `Authorization: Bearer ...`, whether the value is a JWT or an opaque access token.
- [ ] Define payment identity names before adding Stripe and Apple purchase flows. Use provider-specific names at provider boundaries, such as `appleAppAccountToken` for StoreKit and `stripeCustomerID` for Stripe, and keep app-level account identifiers separate.
- [ ] Revisit `putToS3` when upload work resumes, especially signed header handling, MIME type defaults, and large-file memory usage.
- [x] Improve HTTP error reporting so callers can inspect status codes such as 401, 403, 404, 409, and 429 without relying on logs.
- [ ] Redact or make private sensitive error logs before this package is used broadly.
- [ ] Add behavior tests for auth headers, query encoding, JSON bodies, empty responses, non-2xx responses, and S3 upload headers.

## Troubleshooting
If you see this, try this:

| If you see | Do this |
|---|---|
| `No such module 'BissapAPIKit'` | Check Step 1 dependency block and rebuild. |
| `ServiceError.httpError` | The server returned a non-2xx status. Read `backendMessage`, `statusCode`, `responseBody`, or `localizedDescription` for the real backend error. |
| `ServiceError.serverIssue` | Legacy generic server failure. New non-2xx responses should use `ServiceError.httpError`. |
| `ServiceError.emptyData` | You expected JSON but server sent empty body. Use the no-return `request` overload for empty responses. |
| `DecodingError` | Your struct does not match the JSON keys/types. Update your `Decodable` model. |
| `ServiceError.notAnHTTPResponse` | URL loading did not return a valid HTTP response. Verify URL and network setup. |

## FAQ
### Do I need an account?
Not for the library itself.
You only need an account for the API service you call.

### Is it free?
`BissapAPIKit` in this repository has no built-in paid feature.
The API provider you call might charge money.

### Where do I put my key?
Store your token in your app’s secure config, then pass it as `bearerToken` in `APIClient.request(..., bearerToken:)`.

### How do I update?
If your app uses Swift Package Manager, refresh dependencies in Xcode or run:

```bash
swift package update
```

## Swift 6.2 Migration Notes
- Required toolchain: Swift 6.2 (validated with `swift --version` showing Apple Swift 6.2.3).
- Xcode requirement: use an Xcode version that ships Swift 6.2.
- Package language mode: Swift 6 mode is enabled in `Package.swift` (`swiftLanguageModes: [.v6]`).
- Platform declarations: package now explicitly declares `.macOS(.v12)` in addition to `.iOS(.v15)` so async `URLSession` and `OSLog` APIs compile when building on macOS.
- Public API impact: none.
- Runtime behavior impact: none; migration changes are package/tooling configuration plus a smoke test target.

## Assumptions
- Your app targets iOS 15+ (this package declares iOS 15 in `Package.swift`).
- Your development machine is macOS 12+ if building this package directly on macOS.
- You are using Swift Package Manager.
- The demo endpoint `https://jsonplaceholder.typicode.com/todos/1` is reachable from your network.

## License
No `LICENSE` file is present in this repository right now.
