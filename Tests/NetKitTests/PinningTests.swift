//
//  PinningTests.swift
//  NetKit
//
//  Pinning is tested by calling SecurityDelegate directly with a fake server-trust
//  challenge built from self-signed test certificates. No network needed.
//  Expected pins were computed with:
//  openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
//

import XCTest
import Security
@testable import NetKit

final class PinningTests: XCTestCase {

    // Self-signed, CN/SAN = pinned.test, valid 2026-11-25 ... 2027-06-13 (200 days: Apple rejects
    // TLS certs valid > 398 days). Trust is evaluated at a fixed date, so tests never expire.
    static let rsaCertDER = "MIIDGTCCAgGgAwIBAgIUNgKT9nCuf8PIEPBQl0a0sUc2KiswDQYJKoZIhvcNAQELBQAwFjEUMBIGA1UEAwwLcGlubmVkLnRlc3QwHhcNMjYxMTI1MDUyNTAxWhcNMjcwNjEzMDUyNTAxWjAWMRQwEgYDVQQDDAtwaW5uZWQudGVzdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKyT5qsof3n3FsCxuzoBNRQ1MWXoqnb4U/H4ERlLAXQDaD8bgeiQDzw6Njrj6U6JLyy3hUWs0gySeXDUdOt362VvAZJSN+vb768roY1ML5jS8ivCAFKRgjVB3wqO7GUOIVoxRGIpXu8Vki3C84C0Wpdo3nryNYBv16O6IvuJpP1Y/woe/QCVXqMZDSvxJoiaw3SQizO+QRwY9lAN5TatZXKTD7BdNiJlk8w3fxGd749pSJBLpzY83JXY8xOrenIKsc7NNtavI2V3cv1kUxmcQw/oR4Om8TPvLrnX28rmjxrYewQ1GN6zGwtENax8EHsMDVurdpuy3vhX/xFP0RCYB70CAwEAAaNfMF0wHQYDVR0OBBYEFBgpX0bPjKkDO2+P4sO32qpzNSh7MA8GA1UdEwEB/wQFMAMBAf8wFgYDVR0RBA8wDYILcGlubmVkLnRlc3QwEwYDVR0lBAwwCgYIKwYBBQUHAwEwDQYJKoZIhvcNAQELBQADggEBAAoHr2auRBDhGs/1846KotjnwDtS1fhozSmfuFzg2vQInF28Dv1tsf3g7+Uw67YreIqoPZ76B3BaK+5aqadburwS90bCDAJjWjbXfYcL+ucRu69Wgl2M+hTqWyMAvlIIQqej679/DaDXHJ99P8DGDyv2D2DznIeJS3eyyfu4WhuP3IQIVoaHP95OXP0ByVxfEYgL01nr9d22Diho6hZyjIebM46u+43sO0XZgqOMVGUpzmEZJ2cQ8JMzkWcVAo1sPbbKP6jyJkL8ET7sjRz9KOwvQeb+eyDDY0ZAqYHwqC+n8XFSNrV75ty1CJxiDrvAZanjdkr4+VVvbsjKtQ4hQr0="
    static let rsaPin = "SLwLGL1q92DC781l5fQ8GIpg5P9Ih7ki3YobVEHdio4="

    static let ecCertDER = "MIIBjjCCATOgAwIBAgIUfKyS3U37mOMNkz7z+Sv/1SHlC48wCgYIKoZIzj0EAwIwFjEUMBIGA1UEAwwLcGlubmVkLnRlc3QwHhcNMjYxMTI1MDUyNTAxWhcNMjcwNjEzMDUyNTAxWjAWMRQwEgYDVQQDDAtwaW5uZWQudGVzdDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABMQ2SH1OfI/7thQcB9NXzmPsMCCC/N7jL2/27d5v2yft5NhDm7Riz01Sop5CmYAaJmaDkEQr/TPiRYRi+7oOfECjXzBdMB0GA1UdDgQWBBSSopN5QuSGMCSN+HsJVbcU1sRFLjAPBgNVHRMBAf8EBTADAQH/MBYGA1UdEQQPMA2CC3Bpbm5lZC50ZXN0MBMGA1UdJQQMMAoGCCsGAQUFBwMBMAoGCCqGSM49BAMCA0kAMEYCIQDq5myRgZCWix4v80YMa6M4ODoJXxQVVF84sMlpXp4RxAIhAOJ0X866QLxvZ9gdvbqH213l/AznEvzveSPvpF3Feuew"
    static let ecPin = "tPQHw8U32nA13nB1Ipt+qbc+FK8l338ALrm85gdm9pM="

    // MARK: - Helpers

    private func cert(_ base64: String) -> SecCertificate {
        SecCertificateCreateWithData(nil, Data(base64Encoded: base64)! as CFData)!
    }

    /// Trust for `host`. If `anchored`, the cert is its own trusted root, so normal validation passes.
    private func trust(_ certificate: SecCertificate, host: String, anchored: Bool) -> SecTrust {
        var trust: SecTrust?
        SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, host as CFString), &trust)
        if anchored {
            SecTrustSetAnchorCertificates(trust!, [certificate] as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust!, true)
        }
        // Fixed date inside the cert's validity so the tests never expire.
        SecTrustSetVerifyDate(trust!, ISO8601DateFormatter().date(from: "2027-01-01T00:00:00Z")! as CFDate)
        return trust!
    }

    private func challenge(host: String, trust: SecTrust?) -> URLAuthenticationChallenge {
        URLAuthenticationChallenge(
            protectionSpace: FakeServerTrustSpace(host: host, trust: trust),
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: NoopChallengeSender()
        )
    }

    private func delegate(pins: [String: Set<String>]?) -> SecurityDelegate {
        var policy = SecurityPolicy.standard
        policy.pinning = pins.map { CertificatePinning($0) }
        return SecurityDelegate(policy: policy)
    }

    // MARK: - SPKI hash

    func test_spkiHash_rsa2048_matchesOpenSSL() {
        XCTAssertEqual(CertificatePinning.spkiHash(of: cert(Self.rsaCertDER)), Self.rsaPin)
    }

    func test_spkiHash_ecP256_matchesOpenSSL() {
        XCTAssertEqual(CertificatePinning.spkiHash(of: cert(Self.ecCertDER)), Self.ecPin)
    }

    func test_pins_lookupIsCaseInsensitive() {
        let pinning = CertificatePinning(["API.Bank.com": ["a", "b"]])
        XCTAssertEqual(pinning.pins(for: "api.bank.COM"), ["a", "b"])
        XCTAssertNil(pinning.pins(for: "other.bank.com"))
    }

    // MARK: - Delegate decisions

    func test_matchingPin_usesCredential() async {
        let d = delegate(pins: ["pinned.test": [Self.rsaPin, "backup"]])
        let t = trust(cert(Self.rsaCertDER), host: "pinned.test", anchored: true)

        let (disposition, credential) = await d.urlSession(.shared, didReceive: challenge(host: "pinned.test", trust: t))

        XCTAssertEqual(disposition, .useCredential)
        XCTAssertNotNil(credential)
        XCTAssertFalse(d.takePinFailure(host: "pinned.test"))
    }

    func test_backupPin_alsoAccepted() async {
        let d = delegate(pins: ["pinned.test": ["old-pin", Self.ecPin]])
        let t = trust(cert(Self.ecCertDER), host: "pinned.test", anchored: true)

        let (disposition, _) = await d.urlSession(.shared, didReceive: challenge(host: "pinned.test", trust: t))

        XCTAssertEqual(disposition, .useCredential)
    }

    func test_wrongPin_failsClosed_andRecordsFailure() async {
        let d = delegate(pins: ["pinned.test": ["wrong1", "wrong2"]])
        let t = trust(cert(Self.rsaCertDER), host: "pinned.test", anchored: true)

        let (disposition, credential) = await d.urlSession(.shared, didReceive: challenge(host: "pinned.test", trust: t))

        XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
        XCTAssertNil(credential)
        XCTAssertTrue(d.takePinFailure(host: "PINNED.test"))
        XCTAssertFalse(d.takePinFailure(host: "pinned.test"), "failure is consumed once")
    }

    func test_untrustedCert_failsClosed_evenIfPinMatches() async {
        let d = delegate(pins: ["pinned.test": [Self.rsaPin, "backup"]])
        let t = trust(cert(Self.rsaCertDER), host: "pinned.test", anchored: false)   // not trusted

        let (disposition, _) = await d.urlSession(.shared, didReceive: challenge(host: "pinned.test", trust: t))

        XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
        XCTAssertTrue(d.takePinFailure(host: "pinned.test"))
    }

    func test_hostnameMismatch_failsClosed() async {
        let d = delegate(pins: ["other.test": [Self.rsaPin, "backup"]])
        let t = trust(cert(Self.rsaCertDER), host: "other.test", anchored: true)   // cert is for pinned.test

        let (disposition, _) = await d.urlSession(.shared, didReceive: challenge(host: "other.test", trust: t))

        XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
    }

    func test_hostWithoutPins_usesDefaultHandling() async {
        let d = delegate(pins: ["pinned.test": [Self.rsaPin, "backup"]])
        let t = trust(cert(Self.rsaCertDER), host: "unpinned.test", anchored: true)

        let (disposition, _) = await d.urlSession(.shared, didReceive: challenge(host: "unpinned.test", trust: t))

        XCTAssertEqual(disposition, .performDefaultHandling)
    }

    func test_noPinningConfigured_usesDefaultHandling() async {
        let d = delegate(pins: nil)
        let t = trust(cert(Self.rsaCertDER), host: "pinned.test", anchored: true)

        let (disposition, _) = await d.urlSession(.shared, didReceive: challenge(host: "pinned.test", trust: t))

        XCTAssertEqual(disposition, .performDefaultHandling)
    }

    func test_nonServerTrustChallenge_usesDefaultHandling() async {
        let d = delegate(pins: ["pinned.test": [Self.rsaPin, "backup"]])
        let space = URLProtectionSpace(host: "pinned.test", port: 443, protocol: "https",
                                       realm: nil, authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        let basic = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil, previousFailureCount: 0,
                                               failureResponse: nil, error: nil, sender: NoopChallengeSender())

        let (disposition, _) = await d.urlSession(.shared, didReceive: basic)

        XCTAssertEqual(disposition, .performDefaultHandling)
    }
}

// MARK: - Fakes

private final class FakeServerTrustSpace: URLProtectionSpace {
    private let fakeTrust: SecTrust?

    init(host: String, trust: SecTrust?) {
        self.fakeTrust = trust
        super.init(host: host, port: 443, protocol: "https", realm: nil,
                   authenticationMethod: NSURLAuthenticationMethodServerTrust)
    }

    required init?(coder: NSCoder) { nil }

    override var serverTrust: SecTrust? { fakeTrust }
    override var authenticationMethod: String { NSURLAuthenticationMethodServerTrust }
}

private final class NoopChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
