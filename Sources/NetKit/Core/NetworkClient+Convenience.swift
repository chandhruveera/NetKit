//
//  NetworkClient+Convenience.swift
//  NetKit
//

import Foundation

public extension NetworkClient {

    /// One-line request in the style of the old `APIManager.makeApi`.
    ///
    /// - GET/DELETE: `parameter` becomes the URL query (keys sorted; see `parameter` for how values are sent).
    /// - POST/PUT/PATCH: `parameter` is sent as a JSON body with `Content-Type: application/json`.
    ///
    /// ```swift
    /// let user: User = try await client.call("https://api.shop.com/login",
    ///                                        method: .post,
    ///                                        parameter: ["email": email, "password": password])
    /// let orders: [Order] = try await client.call("orders", parameter: ["page": 2], token: token)
    /// ```
    ///
    /// - Parameters:
    ///   - url: Relative path or full `http(s)://` URL (see ``Endpoint/path``).
    ///   - method: HTTP method. Defaults to `.get`.
    ///   - parameter: Query values (GET/DELETE) or JSON body (POST/PUT/PATCH). Must be JSON-serializable for bodies.
    ///     In a query: optionals are unwrapped and `nil`/`NSNull` values are left out; arrays repeat
    ///     the key (`["ids": [1, 2]]` → `ids=1&ids=2`); `Bool` is `true`/`false`; other values use
    ///     `String(describing:)` (nested dictionaries are not supported).
    ///     In a JSON body: `nil` is sent as `null`.
    ///   - token: Sent only as `Authorization: Bearer <token>`, never in the URL.
    ///     A ``BearerTokenInterceptor`` on the client runs later and overrides it.
    ///   - headers: Extra request headers.
    ///   - type: Response type to decode.
    /// - Throws: Always a ``NetworkError``. A non-JSON-serializable body is ``NetworkError/unknown(_:)``.
    func call<T: Decodable>(
        _ url: String,
        method: HTTPMethod = .get,
        parameter: [String: Any]? = nil,
        token: String? = nil,
        headers: [String: String] = [:],
        as type: T.Type = T.self
    ) async throws -> T {
        var allHeaders = headers
        var queryItems: [URLQueryItem] = []
        var body: Data?

        if let token, !token.isEmpty {
            allHeaders["Authorization"] = "Bearer \(token)"
        }

        if let parameter, !parameter.isEmpty {
            switch method {
            case .get, .delete:
                queryItems = parameter
                    .sorted { $0.key < $1.key }
                    .flatMap { Self.queryItems(name: $0.key, value: $0.value) }
            case .post, .put, .patch:
                guard JSONSerialization.isValidJSONObject(parameter) else {
                    throw NetworkError.unknown(CallError.invalidJSONParameter)
                }
                do {
                    body = try JSONSerialization.data(withJSONObject: parameter, options: [.sortedKeys])
                } catch {
                    throw NetworkError.wrap(error)
                }
                if allHeaders["Content-Type"] == nil {
                    allHeaders["Content-Type"] = "application/json"
                }
            }
        }

        let endpoint = Endpoint(
            path: url,
            method: method,
            queryItems: queryItems,
            headers: allHeaders,
            body: body
        )
        return try await send(endpoint, as: type)
    }
}

private enum CallError: Error, CustomStringConvertible {
    case invalidJSONParameter
    var description: String { "parameter contains values that cannot be encoded as JSON" }
}

private extension NetworkClient {
    /// nil / NSNull -> no item; array -> one item per element (key repeated); else one item.
    static func queryItems(name: String, value: Any) -> [URLQueryItem] {
        guard let value = unwrap(value) else { return [] }
        if let array = value as? [Any] {
            return array.compactMap(unwrap).map { URLQueryItem(name: name, value: queryValue($0)) }
        }
        return [URLQueryItem(name: name, value: queryValue(value))]
    }

    /// Unwraps any level of Optional; nil and NSNull become nil.
    static func unwrap(_ value: Any) -> Any? {
        if value is NSNull { return nil }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first.flatMap { unwrap($0.value) }
    }

    static func queryValue(_ value: Any) -> String {
        if let bool = value as? Bool, type(of: value) == Bool.self { return bool ? "true" : "false" }
        return String(describing: value)
    }
}
