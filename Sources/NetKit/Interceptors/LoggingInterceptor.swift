//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation

public struct LoggingInterceptor: RequestInterceptor {
    private let logBody: Bool

    public init(logBody: Bool = false) { self.logBody = logBody }

    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        #if DEBUG
        let headers = (request.allHTTPHeaderFields ?? [:])
            .map { key, value in
                Redactor.sensitiveHeaders.contains(key.lowercased()) ? "\(key): ***" : "\(key): \(value)"
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
