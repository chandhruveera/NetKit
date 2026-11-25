# NetKit

Lightweight Swift networking SDK (SPM, zero third-party dependencies), built on URLSession + async/await.
Goal: reusable across apps from e-commerce to banking. Security must be configurable per app type.

## Constraints (do not change without asking)
- swift-tools-version 5.9 (Swift 5 language mode). Do NOT move to Swift 6 mode.
- Platforms: iOS 15+, macOS 12+
- No third-party dependencies
- Response types are `Decodable` only. Do NOT add a `Sendable` constraint on response models
  (it breaks adoption in Swift 5 apps with main-actor-isolated models).
- Public API changes need my approval first. Explain the change and why.
- Never run git push, git tag, or modify GitHub settings.

## Architecture
- Core/: HTTPMethod, Endpoint, NetworkClient (protocol), URLSessionNetworkClient, NetworkClient+Convenience (`call` API), Net (shared shortcut), NetworkMonitor, NetworkMetrics
- Errors/: NetworkError (+Message, +Server)
- Interceptors/: RequestInterceptor, BearerTokenInterceptor, LoggingInterceptor
- Retry/: RetryPolicy, ExponentialBackoffRetry
- Security/: SecurityPolicy (presets: standard, relaxed, strict, banking), CertificatePinning, SecureSession, Redactor
- Tests/: MockURLProtocol + NetworkClientTests

## Design decisions
- `call(url, method:, parameter:, token:, as:)` mimics my old APIManager.makeApi: parameter -> query for GET/DELETE, JSON body for POST/PUT/PATCH.
- POST/PATCH are NOT retried unless SecurityPolicy.idempotencyKeys is true.
- Offline check happens before retry loop (fail fast).
- Tokens must never appear in logs, URLs, or error messages.

## Status
- As of 2026-11-25: `swift build` passes and `swift test` passes (19/19).
- Added NetworkClient+Convenience.swift (`call(_:method:parameter:token:headers:as:)`) and
  NetworkError+Message.swift (`LocalizedError`: server message first, else a safe fixed text). Both approved.
- Known gaps vs Architecture above (not yet built, need API approval):
  - `Net` shared shortcut does not exist.
  - No separate NetworkError+Server.swift; `serverMessage`/`statusCode`/`decodeBody` live in NetworkError.swift.
  - BearerTokenInterceptor lives in RequestInterceptor.swift; ExponentialBackoffRetry lives in RetryPolicy.swift.
- Tags released so far: 0.1.0, 0.1.2, 0.4.0 (do not touch tags).

## Commands
- Build: `swift build`
- Test: `swift test`
