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
        retryPolicy: RetryPolicy? = nil,
        security: SecurityPolicy = .standard
    ) -> URLSessionNetworkClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSessionNetworkClient(
            baseURL: URL(string: "https://test.com")!,
            security: security,
            sessionConfiguration: config,
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

    // MARK: - Basic

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

    // MARK: - Interceptor and retry

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

    // MARK: - Error message

    func test_serverMessage_isExtractedFromErrorBody() async {
        MockURLProtocol.handler = { [self] request in
            (response(for: request, status: 400), Data(#"{"message": "Invalid OTP"}"#.utf8))
        }

        do {
            _ = try await makeClient().send(Endpoint(path: "verify"), as: Item.self)
            XCTFail("Should have thrown")
        } catch let error as NetworkError {
            XCTAssertEqual(error.serverMessage, "Invalid OTP")
            XCTAssertEqual(error.statusCode, 400)
            XCTAssertEqual(error.localizedDescription, "Invalid OTP")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - call API

    func test_call_post_usesFullURL_token_andJSONHeader() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { [self] request in
            captured = request
            return (response(for: request, status: 200), Data(#"{"id": 1}"#.utf8))
        }

        let item: Item = try await makeClient().call(
            "https://api.example.com/login",
            method: .post,
            parameter: ["user": "a"],
            token: "abc"
        )

        XCTAssertEqual(item.id, 1)
        XCTAssertEqual(captured?.url?.absoluteString, "https://api.example.com/login")
        XCTAssertEqual(captured?.httpMethod, "POST")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func test_call_get_putsParameterInQuery() async throws {
        var capturedURL: URL?
        MockURLProtocol.handler = { [self] request in
            capturedURL = request.url
            return (response(for: request, status: 200), Data(#"{"id": 1}"#.utf8))
        }

        let _: Item = try await makeClient().call("items", parameter: ["page": 2])

        XCTAssertEqual(capturedURL?.absoluteString, "https://test.com/items?page=2")
    }

    func test_delete_withEmptyBody_returnsEmptyResponse() async throws {
        MockURLProtocol.handler = { [self] request in
            (response(for: request, status: 204), Data())
        }

        let _: EmptyResponse = try await makeClient().call("items/1", method: .delete)
    }

    // MARK: - Security

    func test_http_isBlocked() async {
        do {
            let _: Item = try await makeClient().call("http://api.example.com/x", token: "abc")
            XCTFail("Should have thrown")
        } catch NetworkError.security(.insecureConnection) {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_hostNotAllowed_isBlocked() async {
        let policy = SecurityPolicy.strict(allowedHosts: ["api.shop.com"])
        do {
            let _: Item = try await makeClient(security: policy).call("https://evil.com/x", token: "abc")
            XCTFail("Should have thrown")
        } catch NetworkError.security(.hostNotAllowed(let host)) {
            XCTAssertEqual(host, "evil.com")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_sensitiveQueryKey_isBlocked() async {
        do {
            let _: Item = try await makeClient().call("items", parameter: ["token": "abc"])
            XCTFail("Should have thrown")
        } catch NetworkError.security(.sensitiveQueryParameter(let key)) {
            XCTAssertEqual(key, "token")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_integrityCheckFailure_blocksRequest() async {
        var policy = SecurityPolicy.standard
        policy.integrityCheck = { false }
        var reachedNetwork = false
        MockURLProtocol.handler = { [self] request in
            reachedNetwork = true
            return (response(for: request, status: 200), Data(#"{"id": 1}"#.utf8))
        }

        do {
            let _: Item = try await makeClient(security: policy).send(Endpoint(path: "x"), as: Item.self)
            XCTFail("Should have thrown")
        } catch NetworkError.security(.integrityCheckFailed) {
            XCTAssertFalse(reachedNetwork)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_post_isNotRetried_byDefault() async {
        var callCount = 0
        MockURLProtocol.handler = { [self] request in
            callCount += 1
            return (response(for: request, status: 500), Data())
        }

        let client = makeClient(retryPolicy: ExponentialBackoffRetry(maxAttempts: 3, baseDelay: 0.01))

        do {
            let _: Item = try await client.call("items", method: .post, parameter: ["a": 1])
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(callCount, 1)
        }
    }

    func test_post_withIdempotencyKeys_retriesWithSameKey() async throws {
        var keys: [String] = []
        MockURLProtocol.handler = { [self] request in
            keys.append(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "")
            if keys.count < 2 { return (response(for: request, status: 500), Data()) }
            return (response(for: request, status: 200), Data(#"{"id": 1}"#.utf8))
        }

        var policy = SecurityPolicy.standard
        policy.idempotencyKeys = true
        let client = makeClient(
            retryPolicy: ExponentialBackoffRetry(maxAttempts: 3, baseDelay: 0.01),
            security: policy
        )

        let _: Item = try await client.call("items", method: .post, parameter: ["a": 1])

        XCTAssertEqual(keys.count, 2)
        XCTAssertFalse(keys[0].isEmpty)
        XCTAssertEqual(keys[0], keys[1])
    }

    func test_redactor_masksNestedSensitiveKeys() {
        let data = Data(#"{"user":"a","password":"p","nested":{"token":"t"}}"#.utf8)
        let text = Redactor.redactedBody(data)

        XCTAssertFalse(text.contains("\"p\""))
        XCTAssertFalse(text.contains("\"t\""))
        XCTAssertTrue(text.contains("***"))
    }
}
