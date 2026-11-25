//
//  TestSupport.swift
//  NetKit
//

import Foundation
@testable import NetKit

struct TestItem: Decodable, Equatable {
    let id: Int
}

func makeMockClient(
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

func mockResponse(_ request: URLRequest, _ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
}

/// Thread-safe counter: MockURLProtocol handlers run on URLSession's thread.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
