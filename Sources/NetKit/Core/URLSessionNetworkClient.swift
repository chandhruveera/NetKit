//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//


import Foundation

/// The production ``NetworkClient``, built on `URLSession` and async/await.
///
/// Each request goes through: build URL → interceptors → ``SecurityPolicy`` checks →
/// `URLSession` (TLS minimum, pinning, redirect rules) → status check → JSON decoding.
/// Failures may be retried by a ``RetryPolicy``.
///
/// ```swift
/// let client = URLSessionNetworkClient(
///     baseURL: URL(string: "https://api.shop.com")!,
///     security: .strict(allowedHosts: ["api.shop.com"]),
///     interceptors: [BearerTokenInterceptor { await auth.token }],
///     retryPolicy: ExponentialBackoffRetry()
/// )
/// ```
///
/// Create one client per backend and reuse it; each instance owns its own `URLSession`.
public final class URLSessionNetworkClient: NetworkClient, @unchecked Sendable {

    // MARK: - Properties

    private let baseURL: URL?
    private let security: SecurityPolicy
    private let session: URLSession
    private let securityDelegate: SecurityDelegate
    private let decoder: JSONDecoder
    private let decoderLock = NSLock()
    private let interceptors: [RequestInterceptor]
    private let retryPolicy: RetryPolicy?
    private let monitor: NetworkMonitor?
    private let onMetrics: (@Sendable (NetworkMetrics) -> Void)?

    // MARK: - Init

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - baseURL: Base for relative ``Endpoint/path`` values. Without it only full URLs work.
    ///   - security: Transport and request security rules. Defaults to ``SecurityPolicy/standard``.
    ///   - sessionConfiguration: Base configuration. Note: the policy's TLS, timeout and cache
    ///     settings are written into this object. Defaults to `.ephemeral` (no disk cache, no persistent cookies).
    ///   - decoder: Decoder for response bodies. Don't change its settings after passing it in.
    ///   - interceptors: Run in order on every attempt, before the security checks.
    ///   - retryPolicy: Decides whether and when to retry. `nil` means no retries.
    ///   - monitor: When set, requests fail immediately with ``NetworkError/noConnection`` while offline.
    ///   - onMetrics: Called once per attempt with timing and size information, on a background thread.
    public init(
        baseURL: URL? = nil,
        security: SecurityPolicy = .standard,
        sessionConfiguration: URLSessionConfiguration = .ephemeral,
        decoder: JSONDecoder = JSONDecoder(),
        interceptors: [RequestInterceptor] = [],
        retryPolicy: RetryPolicy? = nil,
        monitor: NetworkMonitor? = nil,
        onMetrics: (@Sendable (NetworkMetrics) -> Void)? = nil
    ) {
        let secured = SecureSession.make(policy: security, configuration: sessionConfiguration)
        self.baseURL = baseURL
        self.security = security
        self.session = secured.session
        self.securityDelegate = secured.delegate
        self.decoder = decoder
        self.interceptors = interceptors
        self.retryPolicy = retryPolicy
        self.monitor = monitor
        self.onMetrics = onMetrics
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    // MARK: - Public API

    /// Sends the endpoint, retrying according to the ``RetryPolicy``, and decodes the response.
    ///
    /// Never retried: ``NetworkError/cancelled``, ``NetworkError/unauthorized(_:)``, ``NetworkError/security(_:)``,
    /// and POST/PATCH unless ``SecurityPolicy/idempotencyKeys`` is on.
    /// Cancelling the calling task stops the request or the backoff wait and throws ``NetworkError/cancelled``.
    ///
    /// - Throws: Always a ``NetworkError``.
    public func send<T: Decodable>(
        _ endpoint: Endpoint,
        as type: T.Type = T.self
    ) async throws -> T {

        var endpoint = endpoint

        // Layer 8: POST/PATCH ku idempotency key (opt-in). Ella retries-kum same key.
        if security.idempotencyKeys,
           !endpoint.method.isIdempotent,
           endpoint.headers["Idempotency-Key"] == nil {
            endpoint.headers["Idempotency-Key"] = UUID().uuidString
        }

        // POST/PATCH retry: idempotency keys on irundha mattum
        let canRetry = endpoint.method.isIdempotent || security.idempotencyKeys

        // URL + headers ore oru thadava build; interceptors/security ovvoru attempt-kum run aagum
        let baseRequest = try makeRequest(from: endpoint)

        var attempt = 0

        while true {
            if Task.isCancelled { throw NetworkError.cancelled }

            if let monitor, !monitor.isConnected {
                throw NetworkError.noConnection
            }

            do {
                return try await perform(baseRequest, for: endpoint, as: type)

            } catch let error as NetworkError {

                // Intha errors retry aagakoodadhu
                switch error {
                case .cancelled, .unauthorized, .security:
                    throw error
                default:
                    break
                }

                guard canRetry else { throw error }

                attempt += 1

                guard let delay = retryPolicy?.delay(for: error, attempt: attempt),
                      delay.isFinite, delay > 0, delay <= 60 else {
                    throw error
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    throw NetworkError.cancelled
                }

            } catch {
                throw NetworkError.wrap(error)   // interceptor errors, CancellationError
            }
        }
    }

    // MARK: - Core

    private func perform<T: Decodable>(
        _ baseRequest: URLRequest,
        for endpoint: Endpoint,
        as type: T.Type
    ) async throws -> T {

        var request = baseRequest

        // 2. Interceptors (token header inga add aagum)
        for interceptor in interceptors {
            if Task.isCancelled { throw NetworkError.cancelled }
            request = try await interceptor.adapt(request)
        }

        // 3. Security layers (1, 2, 6, 9, 10, 11, 12)
        request = try await security.apply(to: request)

        // 4. Network call
        let startTime = ProcessInfo.processInfo.systemUptime
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)

        } catch {
            report(endpoint, status: nil, bytes: 0, since: startTime)

            // Layer 4: pinning fail aana
            if error is URLError, let host = request.url?.host, securityDelegate.takePinFailure(host: host) {
                throw NetworkError.security(.pinningFailed(host))
            }
            throw NetworkError.wrap(error)
        }

        // 5. Response validation
        guard let http = response as? HTTPURLResponse else {
            report(endpoint, status: nil, bytes: data.count, since: startTime)
            throw NetworkError.unknown(URLError(.badServerResponse))
        }

        report(endpoint, status: http.statusCode, bytes: data.count, since: startTime)

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw NetworkError.unauthorized(data) }
            throw NetworkError.httpError(statusCode: http.statusCode, data: data)
        }

        // 6. Empty body (204, delete, logout)
        if data.isEmpty, let empty = EmptyResponse() as? T {
            return empty
        }

        // 7. Decode
        do {
            return try decode(data, as: type)
        } catch {
            throw NetworkError.decoding(error)
        }
    }

    // MARK: - Decoding

    private func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        decoderLock.lock()
        defer { decoderLock.unlock() }
        return try decoder.decode(type, from: data)
    }

    // MARK: - Request builder (relative path + full URL rendum support)

    private func makeRequest(from endpoint: Endpoint) throws -> URLRequest {
        let rawPath = endpoint.path
        let url: URL

        let lowered = rawPath.lowercased()
        if lowered.hasPrefix("https://") || lowered.hasPrefix("http://") {
            guard let absolute = URL(string: rawPath) else { throw NetworkError.invalidURL }
            url = absolute
        } else {
            guard let baseURL else { throw NetworkError.invalidURL }
            // Empty segments drop aagum: "/v1//items/" -> "v1/items". Ore oru URL allocation.
            let path = rawPath.split(separator: "/").joined(separator: "/")
            url = path.isEmpty ? baseURL : baseURL.appendingPathComponent(path)
        }

        var finalURL = url
        if !endpoint.queryItems.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw NetworkError.invalidURL
            }
            components.queryItems = (components.queryItems ?? []) + endpoint.queryItems
            guard let merged = components.url else { throw NetworkError.invalidURL }
            finalURL = merged
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        for (key, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    // MARK: - Metrics

    private func report(_ endpoint: Endpoint, status: Int?, bytes: Int, since startTime: TimeInterval) {
        guard let onMetrics else { return }

        // Query string metrics la varadhu (no allocation when there is no "?")
        let path = endpoint.path
        let cleanPath = path.firstIndex(of: "?").map { String(path[..<$0]) } ?? path

        onMetrics(NetworkMetrics(
            method: endpoint.method.rawValue,
            path: cleanPath,
            statusCode: status,
            duration: ProcessInfo.processInfo.systemUptime - startTime,
            responseBytes: bytes
        ))
    }
}
