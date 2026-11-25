//
//  CredentialScopeTests.swift
//  NetKit
//
//  Credentials added by interceptors must only reach trusted hosts
//  (allowedHosts if set, otherwise baseURL's host).
//

import XCTest
@testable import NetKit

final class CredentialScopeTests: XCTestCase {

    private final class Captured: @unchecked Sendable {
        private let lock = NSLock()
        private var request: URLRequest?
        func set(_ r: URLRequest) { lock.lock(); request = r; lock.unlock() }
        func header(_ name: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            return request?.value(forHTTPHeaderField: name)
        }
    }

    private struct ApiKeyInterceptor: RequestInterceptor {
        func adapt(_ request: URLRequest) async throws -> URLRequest {
            var r = request
            r.setValue("KEY123", forHTTPHeaderField: "X-Api-Key")
            return r
        }
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func client(
        baseURL: String? = "https://api.shop.com",
        security: SecurityPolicy = .standard
    ) -> (URLSessionNetworkClient, Captured) {
        let captured = Captured()
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (mockResponse(request, 200), Data())
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = URLSessionNetworkClient(
            baseURL: baseURL.flatMap(URL.init(string:)),
            security: security,
            sessionConfiguration: config,
            interceptors: [BearerTokenInterceptor { "SECRET" }, ApiKeyInterceptor()]
        )
        return (client, captured)
    }

    private func get(_ client: URLSessionNetworkClient, _ path: String) async throws {
        let _: EmptyResponse = try await client.send(Endpoint(path: path), as: EmptyResponse.self)
    }

    // MARK: - Trusted hosts keep credentials

    func test_relativePath_sendsInterceptorCredentials() async throws {
        let (c, captured) = client()
        try await get(c, "orders")
        XCTAssertEqual(captured.header("Authorization"), "Bearer SECRET")
        XCTAssertEqual(captured.header("X-Api-Key"), "KEY123")
    }

    func test_absoluteURL_sameHostAsBase_sendsCredentials() async throws {
        let (c, captured) = client()
        try await get(c, "https://API.shop.com/orders")
        XCTAssertEqual(captured.header("Authorization"), "Bearer SECRET")
    }

    func test_allowedHostsWildcard_sendsCredentials() async throws {
        let (c, captured) = client(security: .strict(allowedHosts: ["api.shop.com", "*.shop.com"]))
        try await get(c, "https://cdn.shop.com/img")
        XCTAssertEqual(captured.header("Authorization"), "Bearer SECRET")
    }

    // MARK: - Untrusted hosts lose interceptor credentials (C1)

    func test_foreignHost_interceptorCredentialsRemoved() async throws {
        let (c, captured) = client()
        try await get(c, "https://cdn.other.com/img")
        XCTAssertNil(captured.header("Authorization"))
        XCTAssertNil(captured.header("X-Api-Key"))
    }

    func test_subdomainOfBase_isNotTrusted_withoutAllowedHosts() async throws {
        let (c, captured) = client()
        try await get(c, "https://evil.api.shop.com/x")
        XCTAssertNil(captured.header("Authorization"))
    }

    // MARK: - Explicit per-request credentials are kept

    func test_explicitToken_toForeignHost_isSent() async throws {
        let (c, captured) = client()
        let _: EmptyResponse = try await c.call("https://pay.other.com/charge", method: .post,
                                                parameter: ["a": 1], token: "EXPLICIT")
        XCTAssertEqual(captured.header("Authorization"), "Bearer EXPLICIT")
        XCTAssertNil(captured.header("X-Api-Key"))
    }

    func test_explicitHeader_isNotOverwrittenByInterceptor_onForeignHost() async throws {
        let (c, captured) = client()
        let endpoint = Endpoint(path: "https://partner.com/x", headers: ["x-api-key": "PARTNER"])
        let _: EmptyResponse = try await c.send(endpoint, as: EmptyResponse.self)
        XCTAssertEqual(captured.header("X-Api-Key"), "PARTNER")
        XCTAssertNil(captured.header("Authorization"))
    }

    // MARK: - No trust information: unchanged behaviour

    func test_noBaseURL_noAllowedHosts_sendsCredentials() async throws {
        let (c, captured) = client(baseURL: nil)
        try await get(c, "https://anything.com/x")
        XCTAssertEqual(captured.header("Authorization"), "Bearer SECRET")
    }
}
