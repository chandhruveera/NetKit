//
//  NetworkClient+Convenience.swift
//  NetKit
//

import Foundation

public extension NetworkClient {

    /// Old APIManager.makeApi style call.
    /// - GET/DELETE: `parameter` goes into the URL query.
    /// - POST/PUT/PATCH: `parameter` is sent as a JSON body.
    /// - `token` is only ever sent as an `Authorization: Bearer` header, never in the URL.
    /// `url` can be a full http(s) URL or a path relative to the client's baseURL.
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
                    .map { URLQueryItem(name: $0.key, value: Self.queryValue($0.value)) }
            case .post, .put, .patch:
                guard JSONSerialization.isValidJSONObject(parameter) else {
                    throw NetworkError.unknown(CallError.invalidJSONParameter)
                }
                body = try JSONSerialization.data(withJSONObject: parameter, options: [.sortedKeys])
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
    static func queryValue(_ value: Any) -> String {
        if let bool = value as? Bool, type(of: value) == Bool.self { return bool ? "true" : "false" }
        return String(describing: value)
    }
}
