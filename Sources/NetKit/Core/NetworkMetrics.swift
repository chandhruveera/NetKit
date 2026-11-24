//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation

public struct NetworkMetrics: Sendable {
    public let method: String
    public let path: String
    public let statusCode: Int?        // network fail aana nil
    public let duration: TimeInterval  // seconds
    public let responseBytes: Int

    public var milliseconds: Int { Int(duration * 1000) }

    /// KB/s (response chinna na idhu accurate illa, keezha paarunga)
    public var throughputKBps: Double? {
        guard duration > 0, responseBytes > 0 else { return nil }
        return Double(responseBytes) / 1024 / duration
    }
}
