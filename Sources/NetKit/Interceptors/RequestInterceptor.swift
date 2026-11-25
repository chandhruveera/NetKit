//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation

/// Modifies every outgoing request, e.g. to add auth or tracing headers.
///
/// Interceptors run in array order on every attempt (including retries), after the URL is
/// built and before ``SecurityPolicy`` checks.
public protocol RequestInterceptor: Sendable {
    /// Returns the request to send.
    ///
    /// Throwing aborts the request: `CancellationError` becomes ``NetworkError/cancelled``,
    /// any other error becomes ``NetworkError/unknown(_:)``. Neither is retried.
    func adapt(_ request: URLRequest) async throws -> URLRequest
}

/// Adds `Authorization: Bearer <token>` to every request.
///
/// The provider is called on every attempt, so a refreshed token is used on retries.
/// Returning `nil` sends the request without the header.
///
/// - Important: The header is added for **every** host, including full URLs passed as a path.
///   Set ``SecurityPolicy/allowedHosts`` so the token can only go to your own servers.
public struct BearerTokenInterceptor: RequestInterceptor {
    private let tokenProvider: @Sendable () async -> String?

    /// - Parameter tokenProvider: Returns the current access token, or `nil` for none.
    public init(tokenProvider: @escaping @Sendable () async -> String?) {
        self.tokenProvider = tokenProvider
    }

    /// Sets the `Authorization` header when the provider returns a token.
    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        if let token = await tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
