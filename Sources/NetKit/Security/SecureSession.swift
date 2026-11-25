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
        guard let expected = policy.pinning?.pins(for: host) else {
            return (.performDefaultHandling, nil)       // intha host pin panna host illa
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
        guard policy.blockUnsafeRedirects else { return request }

        let from = response.url?.host?.lowercased()
        let to = request.url?.host?.lowercased()
        if from != to { return nil }                                   // vera host ku redirect block
        if policy.requireHTTPS, request.url?.scheme?.lowercased() != "https" { return nil }  // downgrade block
        return request
    }
}

enum SecureSession {
    static func make(
        policy: SecurityPolicy,
        configuration: URLSessionConfiguration
    ) -> (session: URLSession, delegate: SecurityDelegate) {

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
