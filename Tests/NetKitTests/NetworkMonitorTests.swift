//
//  NetworkMonitorTests.swift
//  NetKit
//
//  Uses NetworkMonitor(startMonitoring: false) + update(_:) so no real network state is needed.
//

import XCTest
import Network
@testable import NetKit

final class NetworkMonitorTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private final class Values: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Bool] = []
        func add(_ v: Bool) { lock.lock(); items.append(v); lock.unlock() }
        var all: [Bool] { lock.lock(); defer { lock.unlock() }; return items }
    }

    // MARK: - Status

    func test_beforeFirstUpdate_isConnected() {
        XCTAssertTrue(NetworkMonitor(startMonitoring: false).isConnected, "unknown must not count as offline (I1)")
    }

    func test_unsatisfied_isNotConnected() {
        let m = NetworkMonitor(startMonitoring: false)
        m.update(.unsatisfied)
        XCTAssertFalse(m.isConnected)
    }

    func test_satisfied_isConnected() {
        let m = NetworkMonitor(startMonitoring: false)
        m.update(.unsatisfied)
        m.update(.satisfied)
        XCTAssertTrue(m.isConnected)
    }

    func test_requiresConnection_countsAsConnected() {
        let m = NetworkMonitor(startMonitoring: false)
        m.update(.requiresConnection)
        XCTAssertTrue(m.isConnected)
    }

    func test_onChange_reportsEachUpdate() {
        let m = NetworkMonitor(startMonitoring: false)
        let values = Values()
        m.onChange = { values.add($0) }

        m.update(.satisfied)
        m.update(.unsatisfied)
        m.update(.requiresConnection)

        XCTAssertEqual(values.all, [true, false, true])
    }

    func test_onChange_canBeReplacedFromInsideHandler() {
        let m = NetworkMonitor(startMonitoring: false)
        let values = Values()
        m.onChange = { _ in m.onChange = { values.add($0) } }   // must not deadlock

        m.update(.satisfied)
        m.update(.unsatisfied)

        XCTAssertEqual(values.all, [false])
    }

    // MARK: - Client fail-fast

    private func client(_ monitor: NetworkMonitor) -> URLSessionNetworkClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSessionNetworkClient(baseURL: URL(string: "https://test.com")!,
                                       sessionConfiguration: config, monitor: monitor)
    }

    private func send(_ client: URLSessionNetworkClient, calls: Counter) async -> Error? {
        MockURLProtocol.handler = { request in calls.increment(); return (mockResponse(request, 200), Data()) }
        do {
            let _: EmptyResponse = try await client.send(Endpoint(path: "x"), as: EmptyResponse.self)
            return nil
        } catch {
            return error
        }
    }

    func test_client_unknownStatus_sendsRequest() async {
        let calls = Counter()
        let error = await send(client(NetworkMonitor(startMonitoring: false)), calls: calls)
        XCTAssertNil(error)
        XCTAssertEqual(calls.count, 1)
    }

    func test_client_offline_failsFast_withoutNetwork() async {
        let m = NetworkMonitor(startMonitoring: false)
        m.update(.unsatisfied)
        let calls = Counter()

        let error = await send(client(m), calls: calls)

        guard case NetworkError.noConnection? = error else { return XCTFail("got \(String(describing: error))") }
        XCTAssertEqual(calls.count, 0)
    }

    func test_client_requiresConnection_sendsRequest() async {
        let m = NetworkMonitor(startMonitoring: false)
        m.update(.requiresConnection)
        let calls = Counter()

        let error = await send(client(m), calls: calls)

        XCTAssertNil(error)
        XCTAssertEqual(calls.count, 1)
    }
}
