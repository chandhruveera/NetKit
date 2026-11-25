//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation

/// Why a request was blocked by a ``SecurityPolicy`` rule. Carried by ``NetworkError/security(_:)``.
public enum SecurityViolation: Error, Sendable {
    /// The URL is not HTTPS and ``SecurityPolicy/requireHTTPS`` is on.
    case insecureConnection
    /// The host (lowercased) is not in ``SecurityPolicy/allowedHosts``.
    case hostNotAllowed(String)
    /// The URL query contains this key from ``SecurityPolicy/blockedQueryKeys``.
    case sensitiveQueryParameter(String)
    /// ``SecurityPolicy/integrityCheck`` returned `false`.
    case integrityCheckFailed
    /// TLS validation or certificate pinning failed for this host, or the host has no pin while
    /// ``SecurityPolicy/allowedHosts`` and ``SecurityPolicy/pinning`` are both set. Nothing was sent.
    case pinningFailed(String)
}

/// The only error type thrown by NetKit's async APIs.
///
/// Use ``serverMessage`` or `localizedDescription` to show a message to the user,
/// ``statusCode`` to branch on HTTP status, and ``decodeBody(_:decoder:)`` for a custom error format.
public enum NetworkError: Error, Sendable {
    /// The URL could not be built (bad path, or relative path without a `baseURL`).
    case invalidURL
    /// The device is offline (from ``NetworkMonitor`` or `URLError.notConnectedToInternet` / `.networkConnectionLost`).
    case noConnection
    /// The request timed out.
    case timeout
    /// HTTP 401. Holds the response body. Never retried.
    case unauthorized(Data)
    /// Any other non-2xx HTTP status, with the response body.
    case httpError(statusCode: Int, data: Data)
    /// A 2xx response body could not be decoded into the requested type.
    case decoding(Error)
    /// The calling task was cancelled. Usually safe to ignore in UI.
    case cancelled
    /// A ``SecurityPolicy`` rule blocked the request.
    case security(SecurityViolation)
    /// Anything else: other `URLError`s, interceptor errors, request body encoding errors.
    case unknown(Error)
}

extension NetworkError {

    /// Converts any error into a NetworkError so every public API throws one error type.
    static func wrap(_ error: Error) -> NetworkError {
        switch error {
        case let error as NetworkError:
            return error
        case is CancellationError:
            return .cancelled
        case let error as URLError:
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost: return .noConnection
            case .timedOut: return .timeout
            case .cancelled: return .cancelled
            default: return .unknown(error)
            }
        default:
            return .unknown(error)
        }
    }
}

public extension NetworkError {

    /// HTTP status code for ``httpError(statusCode:data:)`` and ``unauthorized(_:)`` (401); otherwise `nil`.
    var statusCode: Int? {
        switch self {
        case .httpError(let code, _): return code
        case .unauthorized: return 401
        default: return nil
        }
    }

    /// Raw response body for HTTP errors; otherwise `nil`.
    var responseData: Data? {
        switch self {
        case .httpError(_, let data): return data
        case .unauthorized(let data): return data
        default: return nil
        }
    }

    /// Human-readable message extracted from the error response body, if any.
    ///
    /// Looks for `message`, `error`, `error_description`, `detail`, `msg` and `errorMessage`
    /// (in that order, also inside nested objects), then an `errors` array (joined with newlines),
    /// then a top-level array of strings. Plain-text bodies under 200 characters are used as-is;
    /// HTML is ignored.
    var serverMessage: String? {
        guard let data = responseData, !data.isEmpty else { return nil }
        return Self.extractMessage(from: data)
    }

    /// Decodes the error response body into your backend's own error type.
    ///
    /// ```swift
    /// struct APIError: Decodable { let code: Int; let message: String }
    /// if let apiError = error.decodeBody(APIError.self) { ... }
    /// ```
    /// - Returns: The decoded value, or `nil` if there is no body or it doesn't match `T`.
    func decodeBody<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) -> T? {
        guard let data = responseData else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static let messageKeys = [
        "message", "error", "error_description", "detail", "msg", "errorMessage"
    ]

    private static func extractMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) {
            if let dict = json as? [String: Any] { return message(in: dict) }
            if let array = json as? [String], let first = array.first { return first }
            return nil
        }
        // JSON illa na plain text (HTML page, long text avoid)
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty, text.count < 200, !text.hasPrefix("<") {
            return text
        }
        return nil
    }

    private static func message(in dict: [String: Any]) -> String? {
        for key in messageKeys {
            if let text = dict[key] as? String, !text.isEmpty { return text }
            if let nested = dict[key] as? [String: Any], let text = message(in: nested) {
                return text
            }
        }
        if let errors = dict["errors"] as? [Any] {
            let texts = errors.compactMap { item -> String? in
                if let s = item as? String { return s }
                if let d = item as? [String: Any] { return message(in: d) }
                return nil
            }
            if !texts.isEmpty { return texts.joined(separator: "\n") }
        }
        return nil
    }
}
