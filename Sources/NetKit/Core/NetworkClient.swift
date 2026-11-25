//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation

/// Sends ``Endpoint``s and decodes their JSON responses.
///
/// ``URLSessionNetworkClient`` is the production implementation. Conform your own type to
/// this protocol to stub networking in app tests; ``request(_:method:query:headers:body:as:)``
/// and ``call(_:method:parameter:token:headers:as:)`` come for free via extensions.
public protocol NetworkClient: Sendable {
    /// Sends the endpoint and decodes a successful (2xx) response body as `T`.
    ///
    /// - Parameters:
    ///   - endpoint: The request to send.
    ///   - type: The `Decodable` type to decode. Use ``EmptyResponse`` when no body is expected.
    /// - Returns: The decoded response.
    /// - Throws: Always a ``NetworkError``.
    func send<T: Decodable>(
        _ endpoint: Endpoint,
        as type: T.Type
    ) async throws -> T
}

/// Use as the response type when the server returns no body (204, DELETE, logout).
///
/// An empty body always decodes to `EmptyResponse`. A JSON object body (e.g. `{}`) is also accepted.
///
/// ```swift
/// let _: EmptyResponse = try await client.call("items/1", method: .delete)
/// ```
public struct EmptyResponse: Decodable, Sendable {
    /// Creates an empty response value.
    public init() {}
}

public extension NetworkClient {

    // MARK: - async (SwiftUI / async code)

    /// Sends a request with string query parameters and an optional `Encodable` JSON body.
    ///
    /// ```swift
    /// let page: Page<Item> = try await client.request("items", query: ["page": "2"])
    /// let created: Item = try await client.request("items", method: .post, body: NewItem(name: "A"))
    /// ```
    ///
    /// - Parameters:
    ///   - path: Relative path or full `http(s)://` URL (see ``Endpoint/path``).
    ///   - method: HTTP method. Defaults to `.get`.
    ///   - query: Query parameters. Order in the URL is not guaranteed.
    ///   - headers: Extra request headers.
    ///   - body: Encoded with a default `JSONEncoder`; `Content-Type: application/json` is added unless set in `headers`.
    ///   - type: Response type to decode.
    /// - Throws: Always a ``NetworkError``. Body encoding failures are ``NetworkError/unknown(_:)``.
    func request<T: Decodable>(
        _ path: String,
        method: HTTPMethod = .get,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        body: (any Encodable)? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        var allHeaders = headers
        var bodyData: Data?

        if let body {
            do {
                bodyData = try JSONEncoder().encode(body)
            } catch {
                throw NetworkError.wrap(error)
            }
            if allHeaders["Content-Type"] == nil {
                allHeaders["Content-Type"] = "application/json"
            }
        }

        let items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        let endpoint = Endpoint(
            path: path,
            method: method,
            queryItems: items,
            headers: allHeaders,
            body: bodyData
        )
        return try await send(endpoint, as: type)
    }

    // MARK: - callback (UIKit), callbacks main thread la varum

    /// Callback version of ``request(_:method:query:headers:body:as:)`` for non-async (UIKit) code.
    ///
    /// Exactly one of `onSuccess` or `onFailure` is called, always on the main thread.
    /// The request cannot be cancelled, and the closures (and anything they capture) are
    /// kept alive until it finishes; capture `[weak self]` in view controllers.
    ///
    /// - Parameters:
    ///   - path: Relative path or full `http(s)://` URL.
    ///   - method: HTTP method. Defaults to `.get`.
    ///   - query: Query parameters.
    ///   - headers: Extra request headers.
    ///   - body: Optional `Encodable` JSON body.
    ///   - type: Response type to decode.
    ///   - onSuccess: Called on the main thread with the decoded value.
    ///   - onFailure: Called on the main thread with the error.
    func request<T: Decodable>(
        _ path: String,
        method: HTTPMethod = .get,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        body: (any Encodable)? = nil,
        as type: T.Type = T.self,
        onSuccess: @escaping (T) -> Void,
        onFailure: @escaping (NetworkError) -> Void
    ) {
        Task {
            do {
                let value: T = try await request(
                    path, method: method, query: query,
                    headers: headers, body: body, as: type
                )
                await MainActor.run { onSuccess(value) }
            } catch {
                await MainActor.run { onFailure(.wrap(error)) }
            }
        }
    }
}
