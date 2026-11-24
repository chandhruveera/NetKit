//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation

public protocol RetryPolicy: Sendable {
    /// nil return panna retry illa. Illa na evlo second wait pannanum.
    func delay(for error: NetworkError, attempt: Int) -> TimeInterval?
}

public struct ExponentialBackoffRetry: RetryPolicy {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval

    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 0.5) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
    }

    public func delay(for error: NetworkError, attempt: Int) -> TimeInterval? {
        guard attempt <= maxAttempts else { return nil }

        switch error {
        case .timeout, .noConnection:
            return baseDelay * pow(2, Double(attempt - 1))
        case .httpError(let code, _) where (500...599).contains(code):
            return baseDelay * pow(2, Double(attempt - 1))
        default:
            return nil   // 4xx, decoding, unauthorized ku retry pannakoodadhu
        }
    }
}
