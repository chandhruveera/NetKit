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
- As of 2026-11-25 (pushed main @ 7475eaa): build clean, `swift test` 102/102 passing.
- Done: security layers, `call` API, `LocalizedError`, network-free tests, optimization pass
  (all async APIs throw only `NetworkError` via internal `NetworkError.wrap(_:)`; interceptor and
  body-encoding errors surface as `.unknown(underlying)`), English doc comments on all public APIs.
- C1 fixed (credential scope): sensitive headers added by interceptors are reset/removed for hosts
  outside allowedHosts (or baseURL's host when allowedHosts is nil). Explicit Endpoint/call(token:)
  headers are kept. No trust info (no baseURL, no allowedHosts) = unrestricted. See CredentialScopeTests.
- C3 fixed: CertificatePinning supports `*.` wildcard keys (exact > most specific wildcard). When
  allowedHosts AND pinning are set (banking), a host without a matching pin fails closed with
  .pinningFailed. Without allowedHosts, pinning stays per-host opt-in. Verified live against apple.com.
- Doc comments describe current behaviour incl. the open bugs below. Update docs in the same commit as a fix.
- Known gaps vs Architecture above (not yet built, need API approval):
  - `Net` shared shortcut does not exist.
  - No separate NetworkError+Server.swift; `serverMessage`/`statusCode`/`decodeBody` live in NetworkError.swift.
  - BearerTokenInterceptor lives in RequestInterceptor.swift; ExponentialBackoffRetry lives in RetryPolicy.swift.
- Tags released so far: 0.1.0, 0.1.2, 0.4.0, 0.5.0 (bfedfcc), 0.6.0 (9233566) (do not touch tags).

## Open issues (from reviews, not fixed yet; most change defaults or public API -> ask first)
Critical
- None open (C1, C3 fixed).
Important
- NetworkMonitor reports offline right after start (NWPathMonitor starts `unsatisfied`), so fail-fast
  can reject the first request. Not testable until the monitor can be injected.
- Relative paths with `?` or `%` get percent-encoded (`items?page=2` -> `items%3Fpage=2`).
- `call` sends Optional values as `Optional(2)` in query strings; arrays/dicts stringified.
- `ExponentialBackoffRetry.maxAttempts` counts retries (3 -> up to 4 requests); delay > 60 s stops retrying.
  Tests deliberately don't pin the exact count until this is decided.
- Blocked query keys / redaction are exact-name: `accessToken`, `refreshToken`, `X-Auth-Token` etc. slip
  through; a camelCase token in a query ends up in URLError userInfo (verified).
- With `blockUnsafeRedirects = false`, custom headers (API key, attestation) follow cross-host redirects
  and the allowlist isn't re-checked. (URLSession itself strips `Authorization` on redirects.)
- Callback `request(...onSuccess:onFailure:)` can't be cancelled; closures not typed `@MainActor`
  (only source of strict-concurrency warnings).
- `SecureSession.make` mutates the caller's URLSessionConfiguration; shared JSONDecoder can be mutated
  by the app under `decoderLock`, which also serializes all decoding.
- `CertificatePinning` backup-pin check is `assert` only (DEBUG); nothing stops `.relaxed` in release.
- `HTTPMethod`, `NetworkError`, `SecurityViolation` are public non-frozen enums: settle cases before 1.0.

## Testing notes
- Pinning tests use self-signed certs valid 200 days (Apple rejects TLS certs valid > 398 days) and
  evaluate trust at a fixed date (2027-01-01), so they never expire. Regenerate certs + pins together.
- MockURLProtocol.handler is a shared static: tests are not safe with `swift test --parallel`.
  Use `Counter` from TestSupport.swift for counts mutated inside handlers.

## Commands
- Build: `swift build`
- Test: `swift test`
