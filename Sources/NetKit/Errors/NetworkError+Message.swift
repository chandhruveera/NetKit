//
//  NetworkError+Message.swift
//  NetKit
//

import Foundation

/// User-facing messages. Server message first, otherwise a fixed safe text.
/// Never include URLs, headers or request bodies here (tokens must not leak).
extension NetworkError: LocalizedError {
    public var errorDescription: String? {
        if let serverMessage { return serverMessage }
        switch self {
        case .invalidURL:             return "Invalid request URL."
        case .noConnection:           return "No internet connection."
        case .timeout:                return "The request timed out."
        case .unauthorized:           return "Your session has expired. Please sign in again."
        case .httpError(let code, _): return "Server error (\(code))."
        case .decoding:               return "Unexpected response from server."
        case .cancelled:              return "Request was cancelled."
        case .security:               return "Connection blocked for security reasons."
        case .unknown:                return "Something went wrong. Please try again."
        }
    }
}
