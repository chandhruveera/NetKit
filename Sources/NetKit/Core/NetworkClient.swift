//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation

public protocol NetworkClient: Sendable {
    func send<T: Decodable>(
        _ endpoint: Endpoint,
        as type: T.Type
    ) async throws -> T
}

/// Response body illa (204, delete, logout) na idha use pannunga
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}

public extension NetworkClient {

    // MARK: - async (SwiftUI / async code)

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
            bodyData = try JSONEncoder().encode(body)
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
            } catch let error as NetworkError {
                await MainActor.run { onFailure(error) }
            } catch {
                await MainActor.run { onFailure(.unknown(error)) }
            }
        }
    }
}
