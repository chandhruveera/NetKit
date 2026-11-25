//
//  MetricsTests.swift
//  NetKit
//

import XCTest
@testable import NetKit

final class MetricsTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [NetworkMetrics] = []
        func add(_ m: NetworkMetrics) { lock.lock(); items.append(m); lock.unlock() }
        var all: [NetworkMetrics] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func client(_ collector: Collector, retry: RetryPolicy? = nil) -> URLSessionNetworkClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSessionNetworkClient(baseURL: URL(string: "https://test.com")!, sessionConfiguration: config,
                                       retryPolicy: retry, onMetrics: { collector.add($0) })
    }

    func test_metrics_reportMethodPathStatusAndBytes() async throws {
        MockURLProtocol.handler = { request in (mockResponse(request, 200), Data(#"{"id": 1}"#.utf8)) }
        let collector = Collector()

        _ = try await client(collector).send(Endpoint(path: "items", method: .put), as: TestItem.self)

        let m = try XCTUnwrap(collector.all.first)
        XCTAssertEqual(collector.all.count, 1)
        XCTAssertEqual(m.method, "PUT")
        XCTAssertEqual(m.path, "items")
        XCTAssertEqual(m.statusCode, 200)
        XCTAssertEqual(m.responseBytes, 9)
        XCTAssertGreaterThanOrEqual(m.duration, 0)
    }

    func test_metrics_stripQueryFromAbsoluteURL() async throws {
        MockURLProtocol.handler = { request in (mockResponse(request, 200), Data()) }
        let collector = Collector()

        let _: EmptyResponse = try await client(collector).send(Endpoint(path: "https://test.com/a?id=5"), as: EmptyResponse.self)

        XCTAssertEqual(collector.all.first?.path, "https://test.com/a")
    }

    func test_metrics_networkFailure_hasNilStatus() async {
        MockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        let collector = Collector()

        _ = try? await client(collector).send(Endpoint(path: "x"), as: TestItem.self)

        XCTAssertEqual(collector.all.count, 1)
        XCTAssertNil(collector.all.first?.statusCode)
    }

    func test_metrics_reportedPerAttempt() async {
        MockURLProtocol.handler = { request in (mockResponse(request, 500), Data()) }
        let collector = Collector()

        _ = try? await client(collector, retry: ExponentialBackoffRetry(maxAttempts: 2, baseDelay: 0.01))
            .send(Endpoint(path: "x"), as: TestItem.self)

        XCTAssertGreaterThan(collector.all.count, 1)   // one entry per attempt
        XCTAssertTrue(collector.all.allSatisfy { $0.statusCode == 500 })
    }

    func test_metrics_throughput() {
        let m = NetworkMetrics(method: "GET", path: "x", statusCode: 200, duration: 2, responseBytes: 2048)
        XCTAssertEqual(m.throughputKBps, 1)
        XCTAssertEqual(m.milliseconds, 2000)
        XCTAssertNil(NetworkMetrics(method: "GET", path: "x", statusCode: nil, duration: 0, responseBytes: 10).throughputKBps)
    }
}
