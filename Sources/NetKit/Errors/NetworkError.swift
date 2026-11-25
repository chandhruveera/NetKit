//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation

public enum SecurityViolation: Error, Sendable {
    case insecureConnection
    case hostNotAllowed(String)
    case sensitiveQueryParameter(String)
    case integrityCheckFailed
    case pinningFailed(String)
}

public enum NetworkError: Error, Sendable {
    case invalidURL
    case noConnection
    case timeout
    case unauthorized(Data)
    case httpError(statusCode: Int, data: Data)
    case decoding(Error)
    case cancelled
    case security(SecurityViolation)
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

    /// HTTP status code (httpError / unauthorized ku mattum)
    var statusCode: Int? {
        switch self {
        case .httpError(let code, _): return code
        case .unauthorized: return 401
        default: return nil
        }
    }

    /// Backend anuppina raw body
    var responseData: Data? {
        switch self {
        case .httpError(_, let data): return data
        case .unauthorized(let data): return data
        default: return nil
        }
    }

    /// Backend message (JSON la irundhu auto ah edukkum)
    var serverMessage: String? {
        guard let data = responseData, !data.isEmpty else { return nil }
        return Self.extractMessage(from: data)
    }

    /// Backend-oda own error format-ah decode panna
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
