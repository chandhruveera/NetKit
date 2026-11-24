//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import XCTest
@testable import NetKit

final class NetworkClientTests: XCTestCase {

    struct Item: Decodable, Sendable, Equatable {
        let id: Int
    }

    // MARK: - Helpers

    private func makeClient(
        interceptors: [RequestInterceptor] = [],
        retryPolicy: RetryPolicy? = nil
    ) -> URLSessionNetworkClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSessionNetworkClient(
            baseURL: URL(string: "https://test.com")!,
            session: URLSession(configuration: config),
            interceptors: interceptors,
            retryPolicy: retryPolicy
        )
    }

    private func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - Basic tests

    func test_success_decodesResponse() async throws {
        MockURLProtocol.handler = { [self] request in
            (response(for: request, status: 200), Data(#"{"id": 5}"#.utf8))
        }

        let item = try await makeClient().send(Endpoint(path: "item"), as: Item.self)

        XCTAssertEqual(item, Item(id: 5))
    }

    func test_401_throwsUnauthorized() async {
        MockURLProtocol.handler = { [self] request in
            (response(for: request, status: 401), Data())
        }

        do {
            _ = try await makeClient().send(Endpoint(path: "item"), as: Item.self)
            XCTFail("Should have thrown")
        } catch NetworkError.unauthorized {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_500_throwsHttpError() async {
        MockURLProtocol.handler = { [self] request in
            (response(for: request, status: 500), Data())
        }

        do {
            _ = try await makeClient().send(Endpoint(path: "item"), as: Item.self)
            XCTFail("Should have thrown")
        } catch NetworkError.httpError(let code, _) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_invalidJSON_throwsDecodingError() async {
        MockURLProtocol.handler = { [self] request in
            (response(for: request, status: 200), Data("not json".utf8))
        }

        do {
            _ = try await makeClient().send(Endpoint(path: "item"), as: Item.self)
            XCTFail("Should have thrown")
        } catch NetworkError.decoding {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_queryItems_areAddedToURL() async throws {
        var capturedURL: URL?
        MockURLProtocol.handler = { [self] request in
            capturedURL = request.url
            return (response(for: request, status: 200), Data(#"{"id": 1}"#.utf8))
        }

        let endpoint = Endpoint(path: "items", queryItems: [URLQueryItem(name: "page", value: "2")])
        _ = try await makeClient().send(endpoint, as: Item.self)

        XCTAssertEqual(capturedURL?.absoluteString, "https://test.com/items?page=2")
    }

    // MARK: - Interceptor and retry tests

    func test_bearerInterceptor_addsAuthorizationHeader() async throws {
        var authHeader: String?
        MockURLProtocol.handler = { [self] request in
            authHeader = request.value(forHTTPHeaderField: "Authorization")
            return (response(for: request, status: 200), Data(#"{"id": 1}"#.utf8))
        }

        let client = makeClient(interceptors: [BearerTokenInterceptor { "abc123" }])
        _ = try await client.send(Endpoint(path: "item"), as: Item.self)

        XCTAssertEqual(authHeader, "Bearer abc123")
    }

    func test_retry_on500_thenSucceeds() async throws {
        var callCount = 0
        MockURLProtocol.handler = { [self] request in
            callCount += 1
            if callCount < 3 {
                return (response(for: request, status: 500), Data())
            }
            return (response(for: request, status: 200), Data(#"{"id": 9}"#.utf8))
        }

        let client = makeClient(retryPolicy: ExponentialBackoffRetry(maxAttempts: 3, baseDelay: 0.01))
        let item = try await client.send(Endpoint(path: "item"), as: Item.self)

        XCTAssertEqual(item.id, 9)
        XCTAssertEqual(callCount, 3)
    }

    func test_noRetry_on404() async {
        var callCount = 0
        MockURLProtocol.handler = { [self] request in
            callCount += 1
            return (response(for: request, status: 404), Data())
        }

        let client = makeClient(retryPolicy: ExponentialBackoffRetry(maxAttempts: 3, baseDelay: 0.01))

        do {
            _ = try await client.send(Endpoint(path: "item"), as: Item.self)
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(callCount, 1)
        }
    }
}
