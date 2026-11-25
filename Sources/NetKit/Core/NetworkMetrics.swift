//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation

/// Timing and size of one request attempt, delivered to `URLSessionNetworkClient`'s `onMetrics`.
///
/// Reported once per attempt, so a request that is retried twice produces three entries.
/// Contains no headers, bodies or query strings.
public struct NetworkMetrics: Sendable {
    /// HTTP method string, e.g. `"GET"`.
    public let method: String
    /// ``Endpoint/path`` with any query string removed (a full URL if the endpoint used one).
    public let path: String
    /// HTTP status code, or `nil` if the request failed before a response arrived.
    public let statusCode: Int?
    /// Time from sending to receiving the full response (or failing), in seconds.
    public let duration: TimeInterval
    /// Size of the response body in bytes (0 on network failure).
    public let responseBytes: Int

    /// ``duration`` in whole milliseconds.
    public var milliseconds: Int { Int(duration * 1000) }

    /// Response size divided by duration, in KB/s. `nil` when either is zero.
    ///
    /// For small responses this mostly measures latency, not bandwidth.
    public var throughputKBps: Double? {
        guard duration > 0, responseBytes > 0 else { return nil }
        return Double(responseBytes) / 1024 / duration
    }
}
