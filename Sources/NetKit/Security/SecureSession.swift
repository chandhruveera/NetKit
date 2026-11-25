//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 25/11/26.
//

import Foundation
import Security

final class SecurityDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let policy: SecurityPolicy
    private let lock = NSLock()
    private var pinFailures = Set<String>()

    init(policy: SecurityPolicy) { self.policy = policy }

    /// Pinning fail aana host-ah client kitta solla
    func takePinFailure(host: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pinFailures.remove(host.lowercased()) != nil
    }

    private func recordPinFailure(_ host: String) {
        lock.lock(); pinFailures.insert(host.lowercased()); lock.unlock()
    }

    // 4. Certificate pinning
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }

        let host = challenge.protectionSpace.host.lowercased()
        guard let pinning = policy.pinning else {
            return (.performDefaultHandling, nil)       // pinning configure pannala
        }
        guard let expected = pinning.pins(for: host) else {
            // C3: allowedHosts irundha ella host-um pin aaganum. Pin illa na fail closed.
            if policy.allowedHosts != nil {
                recordPinFailure(host)
                return (.cancelAuthenticationChallenge, nil)
            }
            return (.performDefaultHandling, nil)       // allowedHosts illa: per-host opt-in
        }

        // #1: backup pin illa na fail closed (every build), even if the single pin matches
        guard expected.count >= CertificatePinning.minimumPinsPerHost else {
            #if DEBUG
            print("[NetKit] \(host): fewer than \(CertificatePinning.minimumPinsPerHost) pins configured (need current + backup).")
            #endif
            recordPinFailure(host)
            return (.cancelAuthenticationChallenge, nil)
        }

        // Mudhal la normal trust validation
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            recordPinFailure(host)
            return (.cancelAuthenticationChallenge, nil)
        }

        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        let hashes = chain.compactMap { CertificatePinning.spkiHash(of: $0) }

        if hashes.contains(where: { expected.contains($0) }) {
            return (.useCredential, URLCredential(trust: trust))
        }

        #if DEBUG
        print("[NetKit] Pin mismatch for \(host). Server pins: \(hashes)")
        #endif
        recordPinFailure(host)
        return (.cancelAuthenticationChallenge, nil)   // fail closed
    }

    // 5. Redirect safety
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let target = request.url, let toHost = target.host?.lowercased() else { return nil }

        // These apply even when blockUnsafeRedirects is off (#2)
        if policy.requireHTTPS, target.scheme?.lowercased() != "https",
           !SecurityPolicy.isLocalDebugHost(toHost) { return nil }                  // downgrade block
        if let allowed = policy.allowedHosts, !SecurityPolicy.matches(toHost, in: allowed) { return nil }

        if policy.blockUnsafeRedirects, response.url?.host?.lowercased() != toHost { return nil }  // vera host block

        // Origin maarina (host, scheme or port) credentials anuppa koodadhu
        guard let source = response.url, Self.origin(source) != Self.origin(target) else { return request }
        var stripped = request
        for name in (request.allHTTPHeaderFields ?? [:]).keys where Redactor.isSensitiveHeader(name) {
            stripped.setValue(nil, forHTTPHeaderField: name)
        }
        return stripped
    }

    /// "scheme://host:port" with default ports filled in, lowercased.
    static func origin(_ url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let port = url.port ?? (scheme == "https" ? 443 : scheme == "http" ? 80 : -1)
        return "\(scheme)://\(url.host?.lowercased() ?? ""):\(port)"
    }
}

enum SecureSession {
    static func make(
        policy: SecurityPolicy,
        configuration: URLSessionConfiguration
    ) -> (session: URLSession, delegate: SecurityDelegate) {
        // Caller oda config-ah maathakoodadhu: copy la mattum policy settings
        let configuration = configuration.copy() as! URLSessionConfiguration

        // 3. TLS minimum
        if let tls = policy.minimumTLS {
            configuration.tlsMinimumSupportedProtocolVersion = (tls == .v13) ? .TLSv13 : .TLSv12
        }

        // 9. Timeout
        configuration.timeoutIntervalForRequest = policy.requestTimeout

        // 6. No cache / cookies
        if policy.disableCaching {
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
        }

        let delegate = SecurityDelegate(policy: policy)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        return (session, delegate)
    }
}
