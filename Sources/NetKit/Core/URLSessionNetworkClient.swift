//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation

public final class URLSessionNetworkClient: NetworkClient, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let interceptors: [RequestInterceptor]
    private let retryPolicy: RetryPolicy?
    private let monitor: NetworkMonitor?
    private let onMetrics: (@Sendable (NetworkMetrics) -> Void)?

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        interceptors: [RequestInterceptor] = [],
        retryPolicy: RetryPolicy? = nil,
        monitor: NetworkMonitor? = nil,
        onMetrics: (@Sendable (NetworkMetrics) -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = decoder
        self.interceptors = interceptors
        self.retryPolicy = retryPolicy
        self.monitor = monitor
        self.onMetrics = onMetrics
    }

    // MARK: - Public API

    public func send<T: Decodable>(
        _ endpoint: Endpoint,
        as type: T.Type = T.self
    ) async throws -> T {
        // Offline na retry pannaama udane fail
        if let monitor, !monitor.isConnected {
            throw NetworkError.noConnection
        }

        var attempt = 0
        while true {
            do {
                return try await perform(endpoint, as: type)
            } catch let error as NetworkError {
                attempt += 1
                guard let delay = retryPolicy?.delay(for: error, attempt: attempt) else {
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    // MARK: - Core

    private func perform<T: Decodable>(
        _ endpoint: Endpoint,
        as type: T.Type
    ) async throws -> T {
        var request = try makeRequest(from: endpoint)
        for interceptor in interceptors {
            request = try await interceptor.adapt(request)
        }

        let start = ProcessInfo.processInfo.systemUptime
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            report(endpoint, status: nil, bytes: 0, since: start)
            throw Self.map(error)
        } catch {
            report(endpoint, status: nil, bytes: 0, since: start)
            throw NetworkError.unknown(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.unknown(URLError(.badServerResponse))
        }
        report(endpoint, status: http.statusCode, bytes: data.count, since: start)

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw NetworkError.unauthorized(data) }
            throw NetworkError.httpError(statusCode: http.statusCode, data: data)
        }

        // Body illa (204, delete, logout) na EmptyResponse return pannalam
        if data.isEmpty, let empty = EmptyResponse() as? T {
            return empty
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decoding(error)
        }
    }

    // MARK: - Helpers

    private func report(_ endpoint: Endpoint, status: Int?, bytes: Int, since start: TimeInterval) {
        guard let onMetrics else { return }
        onMetrics(NetworkMetrics(
            method: endpoint.method.rawValue,
            path: endpoint.path,
            statusCode: status,
            duration: ProcessInfo.processInfo.systemUptime - start,
            responseBytes: bytes
        ))
    }

    private func makeRequest(from endpoint: Endpoint) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        ) else {
            throw NetworkError.invalidURL
        }

        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        for (key, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    private static func map(_ error: URLError) -> NetworkError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .noConnection
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        default:
            return .unknown(error)
        }
    }
}
