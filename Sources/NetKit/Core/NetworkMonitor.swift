//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation
import Network

/// The interface the current network path uses.
public enum ConnectionType: Sendable {
    /// Wi-Fi.
    case wifi
    /// Cellular data.
    case cellular
    /// Wired Ethernet.
    case wired
    /// Connected through another interface (e.g. loopback, VPN-only).
    case other
    /// Not connected.
    case none
}

/// Observes network reachability using `NWPathMonitor`.
///
/// Pass one to ``URLSessionNetworkClient/init(baseURL:security:sessionConfiguration:decoder:interceptors:retryPolicy:monitor:onMetrics:)``
/// to fail fast with ``NetworkError/noConnection`` instead of waiting for a timeout.
///
/// - Important: Right after creation the path is not yet known and ``isConnected`` is `false`
///   until the first update arrives (usually within milliseconds). Create the monitor early,
///   e.g. at app launch, rather than right before the first request.
public final class NetworkMonitor: @unchecked Sendable {
    /// Shared monitor, started on first access.
    public static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "netkit.network-monitor")
    private let lock = NSLock()
    private var handler: (@Sendable (Bool) -> Void)?

    /// Called with `true`/`false` whenever connectivity changes.
    ///
    /// Called on a background queue; dispatch to the main thread before updating UI.
    /// Only one handler is kept: setting it replaces the previous one.
    public var onChange: (@Sendable (Bool) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return handler }
        set { lock.lock(); handler = newValue; lock.unlock() }
    }

    /// Creates a monitor and starts observing immediately.
    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onChange?(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    /// `true` when the current path can reach the network.
    public var isConnected: Bool { monitor.currentPath.status == .satisfied }
    /// `true` on cellular data or a personal hotspot.
    public var isExpensive: Bool { monitor.currentPath.isExpensive }
    /// `true` when Low Data Mode is on.
    public var isConstrained: Bool { monitor.currentPath.isConstrained }

    /// The interface used by the current path, or `.none` when not connected.
    public var connectionType: ConnectionType {
        let path = monitor.currentPath
        guard path.status == .satisfied else { return .none }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        return .other
    }
}
