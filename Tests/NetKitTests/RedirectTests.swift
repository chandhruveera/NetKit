//
//  RedirectTests.swift
//  NetKit
//
//  Calls SecurityDelegate's redirect handler directly. No network needed.
//

import XCTest
@testable import NetKit

final class RedirectTests: XCTestCase {

    private func redirect(
        from: String,
        to: String,
        policy: SecurityPolicy = .standard
    ) async -> URLRequest? {
        let delegate = SecurityDelegate(policy: policy)
        let response = HTTPURLResponse(url: URL(string: from)!, statusCode: 302, httpVersion: nil,
                                       headerFields: ["Location": to])!
        var newRequest = URLRequest(url: URL(string: to)!)
        newRequest.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.dataTask(with: URL(string: from)!)
        return await delegate.urlSession(.shared, task: task, willPerformHTTPRedirection: response, newRequest: newRequest)
    }

    func test_crossHostRedirect_isBlocked() async {
        let result = await redirect(from: "https://api.shop.com/a", to: "https://evil.com/b")
        XCTAssertNil(result)
    }

    func test_subdomainRedirect_isBlocked() async {
        let result = await redirect(from: "https://api.shop.com/a", to: "https://cdn.shop.com/b")
        XCTAssertNil(result)
    }

    func test_httpsToHttpDowngrade_isBlocked() async {
        let result = await redirect(from: "https://api.shop.com/a", to: "http://api.shop.com/b")
        XCTAssertNil(result)
    }

    func test_sameHostRedirect_isAllowed() async {
        let result = await redirect(from: "https://api.shop.com/a", to: "https://api.shop.com/b")
        XCTAssertEqual(result?.url?.absoluteString, "https://api.shop.com/b")
    }

    func test_hostComparison_isCaseInsensitive() async {
        let result = await redirect(from: "https://API.shop.com/a", to: "https://api.SHOP.com/b")
        XCTAssertNotNil(result)
    }

    func test_downgrade_allowed_whenHTTPSNotRequired() async {
        var policy = SecurityPolicy.standard
        policy.requireHTTPS = false
        let result = await redirect(from: "https://api.shop.com/a", to: "http://api.shop.com/b", policy: policy)
        XCTAssertNotNil(result)
    }

    func test_policyOff_allowsCrossHost() async {
        var policy = SecurityPolicy.standard
        policy.blockUnsafeRedirects = false
        let result = await redirect(from: "https://api.shop.com/a", to: "https://evil.com/b", policy: policy)
        XCTAssertNotNil(result)
    }

    // MARK: - Sensitive headers on redirects (#2)

    private static let headers = [
        "Authorization": "Bearer secret",
        "X-Api-Key": "KEY",
        "X-Auth-Token": "T1",
        "X-App-Attestation": "ATT",
        "Cookie": "sid=1",
        "X-Request-Id": "req-1",
        "Content-Type": "application/json",
    ]

    private func redirectWithHeaders(
        from: String,
        to: String,
        policy: SecurityPolicy
    ) async -> URLRequest? {
        let delegate = SecurityDelegate(policy: policy)
        let response = HTTPURLResponse(url: URL(string: from)!, statusCode: 302, httpVersion: nil,
                                       headerFields: ["Location": to])!
        var newRequest = URLRequest(url: URL(string: to)!)
        for (k, v) in Self.headers { newRequest.setValue(v, forHTTPHeaderField: k) }
        let task = URLSession.shared.dataTask(with: URL(string: from)!)
        return await delegate.urlSession(.shared, task: task, willPerformHTTPRedirection: response, newRequest: newRequest)
    }

    private var policyOff: SecurityPolicy {
        var p = SecurityPolicy.standard
        p.blockUnsafeRedirects = false
        return p
    }

    private func assertSensitiveStripped(_ r: URLRequest?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(r, "redirect should be followed", file: file, line: line)
        for name in ["Authorization", "X-Api-Key", "X-Auth-Token", "X-App-Attestation", "Cookie"] {
            XCTAssertNil(r?.value(forHTTPHeaderField: name), "\(name) must not follow", file: file, line: line)
        }
        XCTAssertEqual(r?.value(forHTTPHeaderField: "X-Request-Id"), "req-1", file: file, line: line)
        XCTAssertEqual(r?.value(forHTTPHeaderField: "Content-Type"), "application/json", file: file, line: line)
    }

    func test_policyOff_crossHost_stripsSensitiveHeaders() async {
        let r = await redirectWithHeaders(from: "https://api.shop.com/a", to: "https://evil.com/b", policy: policyOff)
        assertSensitiveStripped(r)
    }

    func test_policyOff_sameHost_keepsHeaders() async {
        let r = await redirectWithHeaders(from: "https://api.shop.com/a", to: "https://API.shop.com/b", policy: policyOff)
        XCTAssertEqual(r?.value(forHTTPHeaderField: "X-Api-Key"), "KEY")
        XCTAssertEqual(r?.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func test_policyOff_allowedHosts_reChecked_blocksOtherHost() async {
        var p = policyOff
        p.allowedHosts = ["api.shop.com", "*.shop.com"]
        let r = await redirectWithHeaders(from: "https://api.shop.com/a", to: "https://evil.com/b", policy: p)
        XCTAssertNil(r)
    }

    func test_policyOff_allowedHosts_allowedTarget_followed_butStripped() async {
        var p = policyOff
        p.allowedHosts = ["api.shop.com", "*.shop.com"]
        let r = await redirectWithHeaders(from: "https://api.shop.com/a", to: "https://cdn.shop.com/b", policy: p)
        assertSensitiveStripped(r)
    }

    func test_policyOff_requireHTTPS_stillBlocksDowngrade() async {
        let r = await redirectWithHeaders(from: "https://api.shop.com/a", to: "http://api.shop.com/b", policy: policyOff)
        XCTAssertNil(r, "requireHTTPS also covers redirects")
    }

    func test_schemeChange_sameHost_stripsSensitiveHeaders() async {
        var p = policyOff
        p.requireHTTPS = false
        let r = await redirectWithHeaders(from: "https://api.shop.com/a", to: "http://api.shop.com/b", policy: p)
        assertSensitiveStripped(r)
    }

    func test_portChange_sameHost_stripsSensitiveHeaders() async {
        let r = await redirectWithHeaders(from: "https://api.shop.com/a", to: "https://api.shop.com:8443/b",
                                          policy: .standard)
        assertSensitiveStripped(r)
    }

    func test_defaultPort_isSameOrigin() async {
        let r = await redirectWithHeaders(from: "https://api.shop.com/a", to: "https://api.shop.com:443/b",
                                          policy: .standard)
        XCTAssertEqual(r?.value(forHTTPHeaderField: "X-Api-Key"), "KEY")
    }

    func test_presets_blockRedirectsByDefault() {
        XCTAssertTrue(SecurityPolicy.standard.blockUnsafeRedirects)
        XCTAssertTrue(SecurityPolicy.relaxed.blockUnsafeRedirects)
        XCTAssertTrue(SecurityPolicy.strict(allowedHosts: ["a.com"]).blockUnsafeRedirects)
    }
}
