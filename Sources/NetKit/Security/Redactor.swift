//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 25/11/26.
//

import Foundation

public enum Redactor {
    public static let sensitiveKeys: Set<String> = [
        "password", "passwd", "pwd", "token", "access_token", "refresh_token", "id_token",
        "secret", "api_key", "apikey", "otp", "pin", "cvv", "card_number", "cardnumber", "authorization"
    ]

    public static let sensitiveHeaders: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key"
    ]

    public static func redact(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return dict.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = sensitiveKeys.contains(pair.key.lowercased()) ? "***" : redact(pair.value)
            }
        }
        if let array = value as? [Any] { return array.map { redact($0) } }
        return value
    }

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
