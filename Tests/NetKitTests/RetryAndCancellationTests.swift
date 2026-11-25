//
//  RetryAndCancellationTests.swift
//  NetKit
//

import XCTest
@testable import NetKit

final class RetryAndCancellationTests: XCTestCase {

    private let fastRetry = ExponentialBackoffRetry(maxAttempts: 3, baseDelay: 0.01)

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func send(_ client: URLSessionNetworkClient, _ endpoint: Endpoint = Endpoint(path: "item")) async -> Result<TestItem, Error> {
        do { return .success(try await client.send(endpoint, as: TestItem.self)) } catch { return .failure(error) }
    }

    // MARK: - Retry

    func test_timeout_isRetried_thenSucceeds() async throws {
        let calls = Counter()
        MockURLProtocol.handler = { request in
            calls.increment()
            if calls.count == 1 { throw URLError(.timedOut) }
            return (mockResponse(request, 200), Data(#"{"id": 1}"#.utf8))
        }

        let item = try await makeMockClient(retryPolicy: fastRetry).send(Endpoint(path: "item"), as: TestItem.self)

        XCTAssertEqual(item.id, 1)
        XCTAssertEqual(calls.count, 2)
    }

    func test_401_isNotRetried() async {
        let calls = Counter()
        MockURLProtocol.handler = { request in calls.increment(); return (mockResponse(request, 401), Data()) }

        let result = await send(makeMockClient(retryPolicy: fastRetry))

        guard case .failure(NetworkError.unauthorized) = result else { return XCTFail("got \(result)") }
        XCTAssertEqual(calls.count, 1)
    }

    func test_decodingError_isNotRetried() async {
        let calls = Counter()
        MockURLProtocol.handler = { request in calls.increment(); return (mockResponse(request, 200), Data("x".utf8)) }

        let result = await send(makeMockClient(retryPolicy: fastRetry))

        guard case .failure(NetworkError.decoding) = result else { return XCTFail("got \(result)") }
        XCTAssertEqual(calls.count, 1)
    }

    func test_noRetryPolicy_meansSingleAttempt() async {
        let calls = Counter()
        MockURLProtocol.handler = { request in calls.increment(); return (mockResponse(request, 503), Data()) }

        let result = await send(makeMockClient(retryPolicy: nil))

        guard case .failure(NetworkError.httpError(503, _)) = result else { return XCTFail("got \(result)") }
        XCTAssertEqual(calls.count, 1)
    }

    func test_retriesExhausted_throwsLastError() async {
        let calls = Counter()
        MockURLProtocol.handler = { request in calls.increment(); return (mockResponse(request, 502), Data()) }

        let result = await send(makeMockClient(retryPolicy: fastRetry))

        guard case .failure(NetworkError.httpError(502, _)) = result else { return XCTFail("got \(result)") }
        XCTAssertEqual(calls.count, 3, "maxAttempts: 3 means 3 requests in total")
    }

    func test_maxAttempts_isTotalRequestCount() async {
        for (maxAttempts, expected) in [(1, 1), (2, 2), (4, 4), (0, 1), (-5, 1)] {
            let calls = Counter()
            MockURLProtocol.handler = { request in calls.increment(); return (mockResponse(request, 503), Data()) }

            _ = await send(makeMockClient(retryPolicy: ExponentialBackoffRetry(maxAttempts: maxAttempts, baseDelay: 0.001)))

            XCTAssertEqual(calls.count, expected, "maxAttempts: \(maxAttempts)")
        }
    }

    func test_backoffDelays_doublePerRetry() {
        let policy = ExponentialBackoffRetry(maxAttempts: 4, baseDelay: 0.5)
        let error = NetworkError.timeout
        XCTAssertEqual(policy.delay(for: error, attempt: 1), 0.5)
        XCTAssertEqual(policy.delay(for: error, attempt: 2), 1.0)
        XCTAssertEqual(policy.delay(for: error, attempt: 3), 2.0)
        XCTAssertNil(policy.delay(for: error, attempt: 4), "4 attempts = 3 retries")
    }

    func test_delayOver60Seconds_stopsRetrying() async {
        struct HugeDelay: RetryPolicy {
            func delay(for error: NetworkError, attempt: Int) -> TimeInterval? { 120 }
        }
        let calls = Counter()
        MockURLProtocol.handler = { request in calls.increment(); return (mockResponse(request, 500), Data()) }

        let result = await send(makeMockClient(retryPolicy: HugeDelay()))

        guard case .failure(NetworkError.httpError(500, _)) = result else { return XCTFail("got \(result)") }
        XCTAssertEqual(calls.count, 1)
    }

    func test_put_isRetried() async throws {
        let calls = Counter()
        MockURLProtocol.handler = { request in
            calls.increment()
            if calls.count == 1 { return (mockResponse(request, 500), Data()) }
            return (mockResponse(request, 200), Data(#"{"id": 1}"#.utf8))
        }

        _ = try await makeMockClient(retryPolicy: fastRetry).send(Endpoint(path: "item", method: .put), as: TestItem.self)

        XCTAssertEqual(calls.count, 2)
    }

    func test_patch_isNotRetried_byDefault() async {
        let calls = Counter()
        MockURLProtocol.handler = { request in calls.increment(); return (mockResponse(request, 500), Data()) }

        _ = await send(makeMockClient(retryPolicy: fastRetry), Endpoint(path: "item", method: .patch))

        XCTAssertEqual(calls.count, 1)
    }

    func test_get_hasNoIdempotencyKey_evenWhenEnabled() async throws {
        nonisolated(unsafe) var key: String?
        MockURLProtocol.handler = { request in
            key = request.value(forHTTPHeaderField: "Idempotency-Key")
            return (mockResponse(request, 200), Data(#"{"id": 1}"#.utf8))
        }
        var policy = SecurityPolicy.standard
        policy.idempotencyKeys = true

        _ = try await makeMockClient(security: policy).send(Endpoint(path: "item"), as: TestItem.self)

        XCTAssertNil(key)
    }

    func test_callerIdempotencyKey_isKept() async throws {
        nonisolated(unsafe) var key: String?
        MockURLProtocol.handler = { request in
            key = request.value(forHTTPHeaderField: "Idempotency-Key")
            return (mockResponse(request, 200), Data(#"{"id": 1}"#.utf8))
        }
        var policy = SecurityPolicy.standard
        policy.idempotencyKeys = true

        _ = try await makeMockClient(security: policy)
            .send(Endpoint(path: "item", method: .post, headers: ["Idempotency-Key": "mine"]), as: TestItem.self)

        XCTAssertEqual(key, "mine")
    }

    // MARK: - Cancellation

    func test_alreadyCancelledTask_neverHitsNetwork() async {
        let calls = Counter()
        MockURLProtocol.handler = { request in calls.increment(); return (mockResponse(request, 200), Data(#"{"id": 1}"#.utf8)) }
        let client = makeMockClient()

        let task = Task { () -> Result<TestItem, Error> in
            try? await Task.sleep(nanoseconds: 1_000_000_000)   // cancelled while sleeping
            return await self.send(client)
        }
        task.cancel()
        let result = await task.value

        guard case .failure(NetworkError.cancelled) = result else { return XCTFail("got \(result)") }
        XCTAssertEqual(calls.count, 0)
    }

    func test_cancelDuringBackoff_throwsCancelledQuickly() async {
        let calls = Counter()
        MockURLProtocol.handler = { request in calls.increment(); return (mockResponse(request, 500), Data()) }
        let client = makeMockClient(retryPolicy: ExponentialBackoffRetry(maxAttempts: 3, baseDelay: 10))

        let start = Date()
        let task = Task { await self.send(client) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let result = await task.value

        guard case .failure(NetworkError.cancelled) = result else { return XCTFail("got \(result)") }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertEqual(calls.count, 1)
    }

    func test_interceptorCancellation_mapsToCancelled() async {
        struct Cancelling: RequestInterceptor {
            func adapt(_ request: URLRequest) async throws -> URLRequest { throw CancellationError() }
        }
        let calls = Counter()
        MockURLProtocol.handler = { request in calls.increment(); return (mockResponse(request, 200), Data()) }

        let result = await send(makeMockClient(interceptors: [Cancelling()], retryPolicy: fastRetry))

        guard case .failure(NetworkError.cancelled) = result else { return XCTFail("got \(result)") }
        XCTAssertEqual(calls.count, 0)
    }

    func test_urlErrorCancelled_isNotRetried() async {
        let calls = Counter()
        MockURLProtocol.handler = { _ in calls.increment(); throw URLError(.cancelled) }

        let result = await send(makeMockClient(retryPolicy: fastRetry))

        guard case .failure(NetworkError.cancelled) = result else { return XCTFail("got \(result)") }
        XCTAssertEqual(calls.count, 1)
    }

    // MARK: - Error consistency

    func test_interceptorError_isWrappedAsUnknown() async {
        struct Boom: Error {}
        struct Failing: RequestInterceptor {
            func adapt(_ request: URLRequest) async throws -> URLRequest { throw Boom() }
        }

        let result = await send(makeMockClient(interceptors: [Failing()]))

        guard case .failure(NetworkError.unknown(let underlying)) = result else { return XCTFail("got \(result)") }
        XCTAssertTrue(underlying is Boom)
    }

    func test_request_encodingFailure_throwsNetworkError() async {
        struct Unencodable: Encodable {
            func encode(to encoder: Encoder) throws { throw EncodingError.invalidValue(0, .init(codingPath: [], debugDescription: "no")) }
        }
        do {
            let _: TestItem = try await makeMockClient().request("x", method: .post, body: Unencodable())
            XCTFail("Should have thrown")
        } catch NetworkError.unknown(let underlying) {
            XCTAssertTrue(underlying is EncodingError)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - URLError mapping

    func test_notConnected_mapsToNoConnection() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        let result = await send(makeMockClient())

        guard case .failure(NetworkError.noConnection) = result else { return XCTFail("got \(result)") }
    }
}
