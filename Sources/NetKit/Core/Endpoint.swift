//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation

/// Description of a single HTTP request, sent with ``NetworkClient/send(_:as:)``.
///
/// ```swift
/// let endpoint = Endpoint(path: "users/42", queryItems: [URLQueryItem(name: "expand", value: "orders")])
/// let user = try await client.send(endpoint, as: User.self)
/// ```
public struct Endpoint: Sendable {
    /// Path relative to the client's `baseURL` (e.g. `"v1/users/42"`), or a full `http(s)://` URL.
    ///
    /// Leading, trailing and repeated slashes in a relative path are ignored.
    /// A full URL bypasses `baseURL`; use ``SecurityPolicy/allowedHosts`` to restrict where requests can go.
    /// Interceptor-added credentials are not sent to hosts other than `baseURL`'s unless allowed there.
    public let path: String
    /// HTTP method. Defaults to ``HTTPMethod/get``.
    public let method: HTTPMethod
    /// Query parameters appended to the URL (after any query already in `path`).
    /// Keys listed in ``SecurityPolicy/blockedQueryKeys`` are rejected before sending.
    public var queryItems: [URLQueryItem]
    /// Extra request headers. Interceptors run afterwards and may override them.
    public var headers: [String: String]
    /// Raw request body. Set `Content-Type` in ``headers`` yourself when using this directly.
    public var body: Data?

    /// Creates an endpoint.
    /// - Parameters:
    ///   - path: Relative path or full `http(s)://` URL.
    ///   - method: HTTP method. Defaults to `.get`.
    ///   - queryItems: Query parameters to append.
    ///   - headers: Extra request headers.
    ///   - body: Raw request body.
    public init(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
    }
}
