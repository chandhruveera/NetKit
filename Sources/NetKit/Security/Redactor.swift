//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 25/11/26.
//

import Foundation

/// Masks secrets before anything is logged. Used by ``LoggingInterceptor`` and ``SecurityPolicy``.
public enum Redactor {
    /// Lowercase JSON/query key names treated as secrets (exact match after lowercasing).
    public static let sensitiveKeys: Set<String> = [
        "password", "passwd", "pwd", "token", "access_token", "refresh_token", "id_token",
        "secret", "api_key", "apikey", "otp", "pin", "cvv", "card_number", "cardnumber", "authorization"
    ]

    /// Lowercase header names whose values are masked in logs.
    public static let sensitiveHeaders: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key"
    ]

    /// Returns a copy of a JSON object (dictionaries/arrays, any depth) with the values of
    /// ``sensitiveKeys`` replaced by `"***"`. Other values are returned unchanged.
    public static func redact(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return dict.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = sensitiveKeys.contains(pair.key.lowercased()) ? "***" : redact(pair.value)
            }
        }
        if let array = value as? [Any] { return array.map { redact($0) } }
        return value
    }

    /// A log-safe string for a request/response body: redacted JSON with sorted keys,
    /// `"<non-JSON body, N bytes>"` for other content, or `""` when empty.
    public static func redactedBody(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "" }
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return "<non-JSON body, \(data.count) bytes>"
        }
        let safe = redact(json)
        guard JSONSerialization.isValidJSONObject(safe),
              let out = try? JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys]),
              let text = String(data: out, encoding: .utf8) else { return "<unprintable>" }
        return text
    }
}
