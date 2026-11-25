//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 25/11/26.
//

import Foundation

/// Security rules for a ``URLSessionNetworkClient``, chosen per app type.
///
/// Start from a preset and adjust individual properties:
///
/// | Preset | For | Adds |
/// |---|---|---|
/// | ``standard`` | e-commerce, social, content | HTTPS, TLS 1.2+, redirect + query-key protection |
/// | ``strict(allowedHosts:)`` | fintech, wallet, health | host allowlist, no cache/cookies, 20 s timeout |
/// | ``banking(allowedHosts:pinning:integrityCheck:attestation:)`` | banking, payments | pinning, 15 s timeout, device hooks |
/// | ``relaxed`` | local dev / staging, DEBUG builds only | allows HTTP, no TLS minimum, no blocked keys |
///
/// ```swift
/// var policy = SecurityPolicy.strict(allowedHosts: ["api.shop.com"])
/// policy.idempotencyKeys = true
/// ```
public struct SecurityPolicy: Sendable {

    /// Minimum TLS protocol version.
    public enum TLSVersion: Sendable {
        /// TLS 1.2
        case v12
        /// TLS 1.3
        case v13
    }

    // Transport (1-3)

    /// Reject non-HTTPS URLs and redirects to non-HTTPS URLs (also when ``blockUnsafeRedirects`` is off).
    /// `localhost`/`127.0.0.1` are allowed in DEBUG builds. Default `true`.
    public var requireHTTPS = true
    /// Hosts requests may go to, e.g. `["api.shop.com", "*.cdn.shop.com"]`.
    /// `*.` matches any subdomain but not the bare domain. `nil` (default) allows every host.
    /// Also defines which hosts receive credentials added by interceptors; when `nil`,
    /// only the client's `baseURL` host does. Redirect targets are checked against it too.
    public var allowedHosts: Set<String>? = nil
    /// Minimum TLS version for the session. `nil` uses the system default. Default `.v12`.
    public var minimumTLS: TLSVersion? = .v12

    // Trust (4-5)

    /// Certificate pins (exact or `*.` wildcard hosts). Default `nil`.
    ///
    /// When ``allowedHosts`` is also set, every host must have a matching pin or the connection
    /// fails with ``SecurityViolation/pinningFailed(_:)``. Without `allowedHosts`, hosts with no
    /// matching pin use normal system trust.
    public var pinning: CertificatePinning? = nil
    /// Block redirects to a different host. Default `true`.
    ///
    /// Always applied to redirects, whatever this setting: ``requireHTTPS`` and ``allowedHosts`` are
    /// re-checked for the target, and when the origin (host, scheme or port) changes, sensitive headers
    /// (``Redactor/sensitiveHeaders`` plus names like `X-Auth-Token` or `X-App-Attestation`) are removed
    /// before the redirect is followed. Non-sensitive headers are kept.
    ///
    /// A blocked redirect surfaces as ``NetworkError/httpError(statusCode:data:)`` with the 3xx status.
    public var blockUnsafeRedirects = true

    // Session behavior (6, 9)

    /// Turn off the URL cache and cookies for the session. Default `false`.
    public var disableCaching = false
    /// Per-request timeout in seconds. Default 30.
    public var requestTimeout: TimeInterval = 30

    // Data hygiene (10)

    /// Query keys that may never appear in a URL. Matching ignores case and `_ - .` separators
    /// (`access_token` also blocks `accessToken` and `Access-Token`) but is otherwise exact,
    /// so pagination keys like `pageToken` or `next_token` are allowed.
    /// Requests containing one fail with ``SecurityViolation/sensitiveQueryParameter(_:)``.
    /// Default ``Redactor/sensitiveKeys``.
    public var blockedQueryKeys: Set<String> = Redactor.sensitiveKeys

    // Safe retries (8)

    /// Add a UUID `Idempotency-Key` header to POST/PATCH (kept across retries) and allow retrying them.
    /// Only enable when your backend deduplicates on that header. Default `false`.
    public var idempotencyKeys = false

    // Hooks (11-12)

    /// Called before every attempt; returning `false` blocks the request with
    /// ``SecurityViolation/integrityCheckFailed`` (e.g. jailbreak/root detection). Default `nil`.
    public var integrityCheck: (@Sendable () async -> Bool)? = nil
    /// Header name for the ``attestationProvider`` value. Default `"X-App-Attestation"`.
    public var attestationHeader = "X-App-Attestation"
    /// Called before every attempt with the final request; a non-`nil` result is sent in
    /// ``attestationHeader`` (e.g. an App Attest assertion). Default `nil`.
    public var attestationProvider: (@Sendable (URLRequest) async -> String?)? = nil

    /// Set only by ``relaxed`` (kept by modified copies). Such policies block every request in Release builds.
    var isDevelopmentOnly = false

    /// Creates a policy with the ``standard`` defaults.
    public init() {}

    // MARK: - Presets

    /// Defaults for e-commerce, social and content apps: HTTPS only, TLS 1.2+,
    /// unsafe redirects blocked, sensitive query keys blocked, any host allowed.
    public static var standard: SecurityPolicy { SecurityPolicy() }

    /// For local development and staging only: allows plain HTTP, no TLS minimum, no blocked query keys.
    ///
    /// - Important: Works in DEBUG builds only. In Release builds (App Store **and TestFlight**) every
    ///   request made with this policy, or a modified copy of it, fails with
    ///   ``SecurityViolation/insecureConnection`` before it is sent. If a release build really needs
    ///   plain HTTP (e.g. a LAN/IoT device), opt in explicitly:
    ///   `var p = SecurityPolicy.standard; p.requireHTTPS = false`.
    public static var relaxed: SecurityPolicy {
        var p = SecurityPolicy()
        p.isDevelopmentOnly = true
        p.requireHTTPS = false
        p.minimumTLS = nil
        p.blockedQueryKeys = []
        return p
    }

    /// For fintech, wallet and healthcare apps: ``standard`` plus a host allowlist,
    /// no cache or cookies, and a 20 second timeout.
    /// - Parameter allowedHosts: Hosts requests may go to (see ``allowedHosts``).
    public static func strict(allowedHosts: Set<String>) -> SecurityPolicy {
        var p = SecurityPolicy()
        p.allowedHosts = allowedHosts
        p.disableCaching = true
        p.requestTimeout = 20
        return p
    }

    /// For banking and payment apps: ``strict(allowedHosts:)`` plus certificate pinning,
    /// a 15 second timeout and optional device integrity / attestation hooks.
    ///
    /// - Important: Every host reachable through `allowedHosts` must have a matching pin (exact or
    ///   `*.` wildcard); connections to an allowed host without one fail closed with
    ///   ``SecurityViolation/pinningFailed(_:)``.
    /// - Parameters:
    ///   - allowedHosts: Hosts requests may go to.
    ///   - pinning: SPKI pins per host (current + backup).
    ///   - integrityCheck: See ``integrityCheck``.
    ///   - attestation: See ``attestationProvider``.
    public static func banking(
        allowedHosts: Set<String>,
        pinning: CertificatePinning,
        integrityCheck: (@Sendable () async -> Bool)? = nil,
        attestation: (@Sendable (URLRequest) async -> String?)? = nil
    ) -> SecurityPolicy {
        var p = strict(allowedHosts: allowedHosts)
        p.pinning = pinning
        p.requestTimeout = 15
        p.integrityCheck = integrityCheck
        p.attestationProvider = attestation
        return p
    }

    // MARK: - Request-level checks (layers 1, 2, 6, 9, 10, 11, 12)

    func apply(to request: URLRequest, isDebugBuild: Bool = SecurityPolicy.isDebugBuild) async throws -> URLRequest {
        // R1: .relaxed release build la ship aaga koodadhu
        if isDevelopmentOnly, !isDebugBuild {
            throw NetworkError.security(.insecureConnection)
        }

        var request = request
        guard let url = request.url, let host = url.host?.lowercased() else {
            throw NetworkError.invalidURL
        }

        // 1. HTTPS only
        if requireHTTPS, url.scheme?.lowercased() != "https", !Self.isLocalDebugHost(host) {
            throw NetworkError.security(.insecureConnection)
        }

        // 2. Host allowlist
        if let allowedHosts, !Self.matches(host, in: allowedHosts) {
            throw NetworkError.security(.hostNotAllowed(host))
        }

        // 10. Sensitive data URL query la anuppa koodadhu
        if !blockedQueryKeys.isEmpty, url.query != nil,
           let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            // Case + separators ignore: accessToken == access_token. Exact match: pageToken allowed.
            let blocked = Set(blockedQueryKeys.map(Redactor.normalize))
            for item in items where blocked.contains(Redactor.normalize(item.name)) {
                throw NetworkError.security(.sensitiveQueryParameter(item.name))
            }
        }

        // 11. Device integrity (app tharum check)
        if let integrityCheck, !(await integrityCheck()) {
            throw NetworkError.security(.integrityCheckFailed)
        }

        // 12. Attestation header (app tharum token)
        if let attestationProvider, let value = await attestationProvider(request) {
            request.setValue(value, forHTTPHeaderField: attestationHeader)
        }

        // 6. No cache / cookies
        if disableCaching {
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpShouldHandleCookies = false
        }

        // 9. Timeout cap
        request.timeoutInterval = min(request.timeoutInterval, requestTimeout)
        return request
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func isLocalDebugHost(_ host: String) -> Bool {
        #if DEBUG
        return host == "localhost" || host == "127.0.0.1"
        #else
        return false
        #endif
    }

    static func matches(_ host: String, in allowed: Set<String>) -> Bool {
        for entry in allowed {
            let e = entry.lowercased()
            if e.hasPrefix("*.") {
                if host.hasSuffix(e.dropFirst(1)) { return true }   // "*.shop.com" -> ".shop.com"
            } else if host == e {
                return true
            }
        }
        return false
    }
}
