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
/// Until the first path update arrives the status is unknown and ``isConnected`` is `true`,
/// so requests made right after creation are not rejected.
public final class NetworkMonitor: @unchecked Sendable {
    /// Shared monitor, started on first access.
    public static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "netkit.network-monitor")
    private let lock = NSLock()
    private var handler: (@Sendable (Bool) -> Void)?
    /// Latest status from NWPathMonitor. nil = no update yet (unknown).
    private var status: NWPath.Status?

    /// Called with ``isConnected`` whenever the network path is updated.
    ///
    /// Called on a background queue; dispatch to the main thread before updating UI.
    /// Only one handler is kept: setting it replaces the previous one.
    public var onChange: (@Sendable (Bool) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return handler }
        set { lock.lock(); handler = newValue; lock.unlock() }
    }

    /// Creates a monitor and starts observing immediately.
    public convenience init() {
        self.init(startMonitoring: true)
    }

    /// `startMonitoring: false` is for tests: feed statuses with ``update(_:)``.
    init(startMonitoring: Bool) {
        guard startMonitoring else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            self?.update(path.status)
        }
        monitor.start(queue: queue)
    }

    func update(_ newStatus: NWPath.Status) {
        lock.lock()
        status = newStatus
        let handler = handler
        lock.unlock()
        handler?(newStatus != .unsatisfied)
    }

    /// `false` only when the network is known to be unreachable.
    ///
    /// Returns `true` before the first path update arrives (status unknown, usually the first few
    /// milliseconds after creation), and for paths that can be brought up on demand
    /// (`.requiresConnection`, e.g. VPN on demand). A real offline device then still fails quickly
    /// inside URLSession with ``NetworkError/noConnection``.
    public var isConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let status else { return true }       // innum update varala: unknown = offline illa
        return status != .unsatisfied
    }
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
