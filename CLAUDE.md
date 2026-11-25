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
- As of 2026-11-25 (pushed main @ 7475eaa): build clean, `swift test` 172/172 passing (debug and release).
- Done: security layers, `call` API, `LocalizedError`, network-free tests, optimization pass
  (all async APIs throw only `NetworkError` via internal `NetworkError.wrap(_:)`; interceptor and
  body-encoding errors surface as `.unknown(underlying)`), English doc comments on all public APIs.
- C1 fixed (credential scope): sensitive headers added by interceptors are reset/removed for hosts
  outside allowedHosts (or baseURL's host when allowedHosts is nil). Explicit Endpoint/call(token:)
  headers are kept. No trust info (no baseURL, no allowedHosts) = unrestricted. See CredentialScopeTests.
- C3 fixed: CertificatePinning supports `*.` wildcard keys (exact > most specific wildcard). When
  allowedHosts AND pinning are set (banking), a host without a matching pin fails closed with
  .pinningFailed. Without allowedHosts, pinning stays per-host opt-in. Verified live against apple.com.
- I1 fixed: NetworkMonitor caches the status from path updates; before the first update it is unknown
  and isConnected = true. Only `.unsatisfied` counts as offline (`.requiresConnection` = connected).
  Tests use internal `NetworkMonitor(startMonitoring: false)` + `update(_:)`.
- I2 fixed: relative paths keep an inline `?query` (merged with queryItems) and existing `%XX` escapes;
  queryItems are appended to the existing percent-encoded query (full-URL queries sent as written).
  Inline query keys are now checked against blockedQueryKeys.
- `+` in query item names/values (queryItems, request(query:), call) is sent as `%2B`.
- I3 fixed: call() query values unwrap optionals, omit nil/NSNull, arrays repeat the key
  (`ids=1&ids=2`). JSON bodies unchanged (nil -> null).
- Sensitive-key matching fixed. Keys normalized via `Redactor.normalize` (lowercase, no `_ - .`).
  Logs: loose (`Redactor.isSensitive`: normalized sensitiveKeys + jwt/ssn exact, or contains a
  fragment like password/token/secret/apikey/auth/session). Query blocking: normalized EXACT match
  (accessToken blocked, pageToken/next_token allowed). Credential scope + log headers use
  `Redactor.isSensitiveHeader` (X-Auth-Token etc.).
- I4 fixed: `ExponentialBackoffRetry.maxAttempts` = total requests incl. the first (3 -> max 3 requests,
  <1 behaves like 1). RetryPolicy delays > 60 s are capped to 60 s and still retry (internal
  `maxRetryDelay`, lowered in tests); non-finite / <= 0 delays stop retrying.
- Backup pin enforced in every build: a host with < 2 distinct non-empty pins
  (`CertificatePinning.minimumPinsPerHost`) fails closed with .pinningFailed, even if its pin matches.
  The DEBUG `assert` was replaced by a DEBUG warning print (so it is testable). Release-mode check:
  `swift test -c release -Xswiftc -enable-testing --filter PinningTests`.
- Redirect hardening: requireHTTPS and allowedHosts are re-checked for every redirect target, even with
  `blockUnsafeRedirects = false`. On an origin change (host, scheme or port; default ports normalized)
  every `Redactor.isSensitiveHeader` header is removed; other headers kept. Verified live (localhost ->
  127.0.0.1 redirect: X-Api-Key stripped, X-Request-Id kept).
- SecureSession.make works on `configuration.copy()`; the caller's URLSessionConfiguration is never
  modified (protocolClasses etc. are kept in the copy). See SessionConfigurationTests.
- Decoder: the client keeps its own copy (`URLSessionNetworkClient.privateCopy(of:)` copies all
  JSONDecoder settings; subclasses are used as-is). No lock, so decodes run in parallel (TSan clean).
  If JSONDecoder gains new settings, add them to privateCopy + DecoderTests.
- R1 fixed: `.relaxed` sets internal `isDevelopmentOnly` (kept by modified copies); in non-DEBUG builds
  every request with it fails with .security(.insecureConnection) before sending (TestFlight too).
  Explicit opt-in still works: `.standard` + `requireHTTPS = false`. Tests use internal
  `apply(to:isDebugBuild:)`; check the real flag with `swift test -c release -Xswiftc -enable-testing`.
- Doc comments describe current behaviour incl. the open bugs below. Update docs in the same commit as a fix.
- Known gaps vs Architecture above (not yet built, need API approval):
  - `Net` shared shortcut does not exist.
  - No separate NetworkError+Server.swift; `serverMessage`/`statusCode`/`decodeBody` live in NetworkError.swift.
  - BearerTokenInterceptor lives in RequestInterceptor.swift; ExponentialBackoffRetry lives in RetryPolicy.swift.
- Tags released so far: 0.1.0, 0.1.2, 0.4.0, 0.5.0 (bfedfcc), 0.6.0 (9233566), 0.7.0 (3b6a810) (do not touch tags).

## Open issues (from reviews, not fixed yet; most change defaults or public API -> ask first)
Critical
- None open (C1, C3 fixed).
Important
- Callback `request(...onSuccess:onFailure:)` can't be cancelled; closures not typed `@MainActor`
  (only source of strict-concurrency warnings).
- `HTTPMethod`, `NetworkError`, `SecurityViolation` are public non-frozen enums: settle cases before 1.0.

## Testing notes
- Pinning tests use self-signed certs valid 200 days (Apple rejects TLS certs valid > 398 days) and
  evaluate trust at a fixed date (2027-01-01), so they never expire. Regenerate certs + pins together.
- MockURLProtocol.handler is a shared static: tests are not safe with `swift test --parallel`.
  Use `Counter` from TestSupport.swift for counts mutated inside handlers.

## Commands
- Build: `swift build`
- Test: `swift test`
