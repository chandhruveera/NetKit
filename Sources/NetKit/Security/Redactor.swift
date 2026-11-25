//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 25/11/26.
//

import Foundation

/// Masks secrets before anything is logged. Used by ``LoggingInterceptor`` and ``SecurityPolicy``.
public enum Redactor {
    /// Key names treated as secrets. Matching ignores case and `_ - .` separators, so `access_token`
    /// also covers `accessToken` and `Access-Token`. Used as the default ``SecurityPolicy/blockedQueryKeys``.
    public static let sensitiveKeys: Set<String> = [
        "password", "passwd", "pwd", "token", "access_token", "refresh_token", "id_token",
        "secret", "api_key", "apikey", "otp", "pin", "cvv", "card_number", "cardnumber", "authorization"
    ]

    /// Header names (lowercase) whose values are always masked in logs. Headers whose names match the
    /// key rules of ``redact(_:)`` (e.g. `X-Auth-Token`, `X-App-Attestation`) are masked too.
    public static let sensitiveHeaders: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key"
    ]

    // MARK: - Matching

    /// Lowercased with `_`, `-`, `.` and spaces removed: "Access-Token", "access_token" -> "accesstoken".
    static func normalize(_ key: String) -> String {
        String(key.lowercased().unicodeScalars.filter { !"_-. ".unicodeScalars.contains($0) })
    }

    /// Log-only: masked if the normalized key contains one of these (false positives are harmless in logs).
    private static let fragments = [
        "password", "passwd", "passcode", "token", "secret", "apikey", "auth", "cookie", "session",
        "credential", "privatekey", "cardnumber", "attestation", "signature",
    ]

    /// Short names that would match too much as fragments ("pin" in "shipping"): exact match only.
    private static let normalizedKeys: Set<String> = Set(sensitiveKeys.map(normalize)).union(["jwt", "ssn"])

    /// Loose match used for log redaction (body keys and headers).
    static func isSensitive(_ key: String) -> Bool {
        let n = normalize(key)
        return normalizedKeys.contains(n) || fragments.contains { n.contains($0) }
    }

    static func isSensitiveHeader(_ name: String) -> Bool {
        sensitiveHeaders.contains(name.lowercased()) || isSensitive(name)
    }

    /// Returns a copy of a JSON object (dictionaries/arrays, any depth) with sensitive values replaced by `"***"`.
    ///
    /// A key is sensitive if, ignoring case and `_ - .`, it equals one of ``sensitiveKeys``
    /// (or `jwt`, `ssn`) or contains a fragment such as `password`, `token`, `secret`, `apikey`,
    /// `auth`, `cookie` or `session` (`accessToken`, `newPassword`, `clientSecret`, …).
    public static func redact(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return dict.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = isSensitive(pair.key) ? "***" : redact(pair.value)
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
