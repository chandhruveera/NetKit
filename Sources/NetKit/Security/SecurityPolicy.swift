//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 25/11/26.
//

import Foundation

public struct SecurityPolicy: Sendable {

    public enum TLSVersion: Sendable { case v12, v13 }

    // Transport (1-3)
    public var requireHTTPS = true
    public var allowedHosts: Set<String>? = nil        // ["api.shop.com", "*.cdn.shop.com"]
    public var minimumTLS: TLSVersion? = .v12

    // Trust (4-5)
    public var pinning: CertificatePinning? = nil
    public var blockUnsafeRedirects = true

    // Session behavior (6, 9): disableCaching = cache + cookies off
    public var disableCaching = false
    public var requestTimeout: TimeInterval = 30

    // Data hygiene (10)
    public var blockedQueryKeys: Set<String> = Redactor.sensitiveKeys

    // Safe retries (8): backend "Idempotency-Key" support pannina mattum true pannunga
    public var idempotencyKeys = false

    // Hooks (11-12)
    public var integrityCheck: (@Sendable () async -> Bool)? = nil
    public var attestationHeader = "X-App-Attestation"
    public var attestationProvider: (@Sendable (URLRequest) async -> String?)? = nil

    public init() {}

    // MARK: - Presets

    /// E-commerce, social, content apps
    public static var standard: SecurityPolicy { SecurityPolicy() }

    /// Dev/staging mattum (release la use pannadheenga)
    public static var relaxed: SecurityPolicy {
        var p = SecurityPolicy()
        p.requireHTTPS = false
        p.minimumTLS = nil
        p.blockedQueryKeys = []
        return p
    }

    /// Fintech, wallet, healthcare
    public static func strict(allowedHosts: Set<String>) -> SecurityPolicy {
        var p = SecurityPolicy()
        p.allowedHosts = allowedHosts
        p.disableCaching = true
        p.requestTimeout = 20
        return p
    }

    /// Banking, payments: pinning kandippa venum
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

    func apply(to request: URLRequest) async throws -> URLRequest {
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
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items where blockedQueryKeys.contains(item.name.lowercased()) {
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

    private static func isLocalDebugHost(_ host: String) -> Bool {
        #if DEBUG
        return host == "localhost" || host == "127.0.0.1"
        #else
        return false
        #endif
    }

    private static func matches(_ host: String, in allowed: Set<String>) -> Bool {
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
