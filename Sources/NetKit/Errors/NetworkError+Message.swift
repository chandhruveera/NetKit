//
//  NetworkError+Message.swift
//  NetKit
//

import Foundation

// Never include URLs, headers or request bodies here (tokens must not leak).
extension NetworkError: LocalizedError {
    /// A message safe to show to users: ``serverMessage`` when available,
    /// otherwise a short fixed English text for the error case.
    /// Never contains URLs, headers or request data.
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
