//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation

/// Decides whether a failed request is retried, and after how long.
///
/// Only consulted for retryable requests (see ``URLSessionNetworkClient/send(_:as:)``).
public protocol RetryPolicy: Sendable {
    /// Returns the delay before the next attempt, or `nil` to stop and throw `error`.
    ///
    /// - Parameters:
    ///   - error: The error from the attempt that just failed.
    ///   - attempt: 1 for the first retry, 2 for the second, and so on.
    /// - Returns: Seconds to wait. Values that are not finite, ≤ 0 or > 60 stop retrying.
    func delay(for error: NetworkError, attempt: Int) -> TimeInterval?
}

/// Retries timeouts, lost connections and 5xx responses with exponential backoff:
/// `baseDelay`, `2 × baseDelay`, `4 × baseDelay`, …
///
/// Never retries 4xx, 401, decoding, security or cancellation errors.
public struct ExponentialBackoffRetry: RetryPolicy {
    /// Maximum number of **retries** after the first attempt.
    /// `maxAttempts: 3` sends the request up to 4 times.
    public let maxAttempts: Int
    /// Delay before the first retry, in seconds.
    public let baseDelay: TimeInterval

    /// - Parameters:
    ///   - maxAttempts: Maximum retries after the first attempt. Defaults to 3.
    ///   - baseDelay: Delay before the first retry, in seconds. Defaults to 0.5.
    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 0.5) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
    }

    /// `baseDelay × 2^(attempt − 1)` for retryable errors while `attempt ≤ maxAttempts`, else `nil`.
    public func delay(for error: NetworkError, attempt: Int) -> TimeInterval? {
        guard attempt <= maxAttempts else { return nil }

        switch error {
        case .timeout, .noConnection:
            break
        case .httpError(let code, _) where (500...599).contains(code):
            break
        default:
            return nil   // 4xx, decoding, unauthorized ku retry pannakoodadhu
        }
        return baseDelay * pow(2, Double(attempt - 1))
    }
}
