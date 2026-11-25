//
//  SessionConfigurationTests.swift
//  NetKit
//
//  The caller's URLSessionConfiguration is never modified; the session gets a copy.
//

import XCTest
@testable import NetKit

final class SessionConfigurationTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }


    private func strictPolicy() -> SecurityPolicy {
        var p = SecurityPolicy.strict(allowedHosts: ["test.com"])   // disableCaching, 20 s
        p.minimumTLS = .v13
        return p
    }

    func test_secureSession_doesNotModifyCallersConfiguration() {
        let config = URLSessionConfiguration.default
        let cache = URLCache(memoryCapacity: 1024, diskCapacity: 0)
        config.urlCache = cache
        config.timeoutIntervalForRequest = 99
        let tlsBefore = config.tlsMinimumSupportedProtocolVersion

        let made = SecureSession.make(policy: strictPolicy(), configuration: config)

        XCTAssertEqual(config.timeoutIntervalForRequest, 99)
        XCTAssertTrue(config.urlCache === cache)
        XCTAssertNotNil(config.httpCookieStorage)
        XCTAssertTrue(config.httpShouldSetCookies)
        XCTAssertEqual(config.tlsMinimumSupportedProtocolVersion, tlsBefore)

        // ...but the session itself got the policy settings
        let used = made.session.configuration
        XCTAssertEqual(used.timeoutIntervalForRequest, 20)
        XCTAssertNil(used.urlCache)
        XCTAssertFalse(used.httpShouldSetCookies)
        XCTAssertEqual(used.tlsMinimumSupportedProtocolVersion, .TLSv13)
        made.session.invalidateAndCancel()
    }

    func test_sharedConfiguration_reusedForTwoClients_isNotPolluted() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 99
        _ = URLSessionNetworkClient(baseURL: URL(string: "https://test.com"),
                                    security: strictPolicy(), sessionConfiguration: config)
        XCTAssertEqual(config.timeoutIntervalForRequest, 99, "banking/strict settings leaked into the app's config")
        XCTAssertNotNil(config.urlCache)
    }

    func test_copiedConfiguration_keepsCallersProtocolClasses() async throws {
        MockURLProtocol.handler = { r in (mockResponse(r, 200), Data(#"{"id":1}"#.utf8)) }
        let item: TestItem = try await makeMockClient().send(Endpoint(path: "x"), as: TestItem.self)
        XCTAssertEqual(item.id, 1)
    }
}
