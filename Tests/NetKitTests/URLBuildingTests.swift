//
//  URLBuildingTests.swift
//  NetKit
//
//  Locks in how Endpoint.path + baseURL + queryItems become the final URL.
//

import XCTest
@testable import NetKit

final class URLBuildingTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func finalURL(
        base: String = "https://test.com",
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> String? {
        nonisolated(unsafe) var captured: URL?
        MockURLProtocol.handler = { request in
            captured = request.url
            return (mockResponse(request, 200), Data())
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = URLSessionNetworkClient(baseURL: URL(string: base)!, sessionConfiguration: config)
        let _: EmptyResponse = try await client.send(Endpoint(path: path, queryItems: query), as: EmptyResponse.self)
        return captured?.absoluteString
    }

    func test_nestedPath() async throws {
        let url = try await finalURL("v1/users/42/orders")
        XCTAssertEqual(url, "https://test.com/v1/users/42/orders")
    }

    func test_leadingTrailingAndDoubleSlashes_areNormalized() async throws {
        let url = try await finalURL("/v1//items/")
        XCTAssertEqual(url, "https://test.com/v1/items")
    }

    func test_baseURLWithPath() async throws {
        let url = try await finalURL(base: "https://test.com/api", "items")
        XCTAssertEqual(url, "https://test.com/api/items")
    }

    func test_baseURLWithTrailingSlash() async throws {
        let url = try await finalURL(base: "https://test.com/api/", "/items")
        XCTAssertEqual(url, "https://test.com/api/items")
    }

    func test_spaceInPath_isPercentEncoded() async throws {
        let url = try await finalURL("search/a b")
        XCTAssertEqual(url, "https://test.com/search/a%20b")
    }

    func test_absoluteURL_ignoresBaseURL() async throws {
        let url = try await finalURL("https://other.com/x")
        XCTAssertEqual(url, "https://other.com/x")
    }

    func test_absoluteURLQuery_isMergedWithQueryItems() async throws {
        let url = try await finalURL("https://other.com/x?a=1", query: [URLQueryItem(name: "b", value: "2")])
        XCTAssertEqual(url, "https://other.com/x?a=1&b=2")
    }

    // MARK: - I2: query and percent-escapes inside a relative path

    func test_relativePath_withInlineQuery() async throws {
        let url = try await finalURL("items?page=2&sort=name")
        XCTAssertEqual(url, "https://test.com/items?page=2&sort=name")
    }

    func test_relativePath_inlineQuery_mergedWithQueryItems() async throws {
        let url = try await finalURL("items?page=2", query: [URLQueryItem(name: "size", value: "10")])
        XCTAssertEqual(url, "https://test.com/items?page=2&size=10")
    }

    func test_relativePath_inlineQuery_withSpace_isEncoded() async throws {
        let url = try await finalURL("search?q=a b")
        XCTAssertEqual(url, "https://test.com/search?q=a%20b")
    }

    func test_relativePath_onlyQuery_keepsBasePath() async throws {
        let url = try await finalURL(base: "https://test.com/api", "?page=2")
        XCTAssertEqual(url, "https://test.com/api?page=2")
    }

    func test_preEncodedPath_isNotDoubleEncoded() async throws {
        let url = try await finalURL("search/a%20b/caf%C3%A9")
        XCTAssertEqual(url, "https://test.com/search/a%20b/caf%C3%A9")
    }

    func test_lonePercent_isEncoded() async throws {
        let url = try await finalURL("discount/100%")
        XCTAssertEqual(url, "https://test.com/discount/100%25")
    }

    func test_inlineQuery_sensitiveKey_isBlocked() async {
        do {
            _ = try await finalURL("items?token=abc")
            XCTFail("Should have thrown")
        } catch NetworkError.security(.sensitiveQueryParameter(let key)) {
            XCTAssertEqual(key, "token")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_queryItemValues_arePercentEncoded() async throws {
        let url = try await finalURL("items", query: [URLQueryItem(name: "q", value: "a b&c")])
        XCTAssertEqual(url, "https://test.com/items?q=a%20b%26c")
    }
}
