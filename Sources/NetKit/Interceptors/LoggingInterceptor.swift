//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation

/// Prints each outgoing request in DEBUG builds. Does nothing in release builds.
///
/// The query string is removed from the URL, headers in ``Redactor/sensitiveHeaders`` are masked,
/// and bodies are redacted with ``Redactor/redactedBody(_:)``.
/// Logs the request as it is at this interceptor's position: put it last to include headers
/// added by earlier interceptors. Headers added by ``SecurityPolicy`` (attestation) are not shown.
public struct LoggingInterceptor: RequestInterceptor {
    private let logBody: Bool

    /// - Parameter logBody: Also print the (redacted) request body. Defaults to `false`.
    public init(logBody: Bool = false) { self.logBody = logBody }

    /// Prints the request and returns it unchanged.
    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        #if DEBUG
        let headers = (request.allHTTPHeaderFields ?? [:])
            .map { key, value in
                Redactor.isSensitiveHeader(key) ? "\(key): ***" : "\(key): \(value)"
            }
            .sorted()
            .joined(separator: ", ")

        var line = "[NetKit] \(request.httpMethod ?? "GET") \(Self.safeURL(request.url)) [\(headers)]"
        if logBody { line += " body: \(Redactor.redactedBody(request.httpBody))" }
        print(line)
        #endif
        return request
    }

    /// Query string remove (account numbers, ids log la varadhu)
    private static func safeURL(_ url: URL?) -> String {
        guard let url, var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "" }
        c.query = nil
        return c.string ?? ""
    }
}
