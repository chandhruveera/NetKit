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

    func test_queryItemValues_arePercentEncoded() async throws {
        let url = try await finalURL("items", query: [URLQueryItem(name: "q", value: "a b&c")])
        XCTAssertEqual(url, "https://test.com/items?q=a%20b%26c")
    }
}
