//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation
import Network

public enum ConnectionType: Sendable {
    case wifi, cellular, wired, other, none
}

public final class NetworkMonitor: @unchecked Sendable {
    public static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "netkit.network-monitor")
    private let lock = NSLock()
    private var handler: (@Sendable (Bool) -> Void)?

    /// Internet vandha/poga call aagum (background thread la, UI update ku main ku maathunga)
    public var onChange: (@Sendable (Bool) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return handler }
        set { lock.lock(); handler = newValue; lock.unlock() }
    }

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onChange?(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    public var isConnected: Bool { monitor.currentPath.status == .satisfied }
    public var isExpensive: Bool { monitor.currentPath.isExpensive }       // mobile data / hotspot
    public var isConstrained: Bool { monitor.currentPath.isConstrained }   // Low Data Mode

    public var connectionType: ConnectionType {
        let path = monitor.currentPath
        guard path.status == .satisfied else { return .none }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        return .other
    }
}
