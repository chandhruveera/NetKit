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

    func test_presets_blockRedirectsByDefault() {
        XCTAssertTrue(SecurityPolicy.standard.blockUnsafeRedirects)
        XCTAssertTrue(SecurityPolicy.relaxed.blockUnsafeRedirects)
        XCTAssertTrue(SecurityPolicy.strict(allowedHosts: ["a.com"]).blockUnsafeRedirects)
    }
}
