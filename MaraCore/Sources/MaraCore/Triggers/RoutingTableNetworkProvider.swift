import Combine
import Foundation
import Network

/// Combine/`NWPathMonitor` adapter over `RoutingTableParser`.
/// Publishes the current gateway identity (default-gateway MAC) and refreshes it
/// whenever the network path changes. All routing-table parsing lives in
/// `RoutingTableParser`; this type only owns the monitor and the published value.
public final class RoutingTableNetworkProvider: NetworkIdentityProviding {
    private let subject: CurrentValueSubject<NetworkIdentity?, Never>
    private let monitor: NWPathMonitor

    public init() {
        // Intentional one-shot startup read: runs on the launch/main path before monitor starts.
        subject = CurrentValueSubject(Self.readGatewayIdentity())
        monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.mara.RoutingTableNetworkProvider")
        monitor.pathUpdateHandler = { [weak self] _ in
            let id = Self.readGatewayIdentity() // sysctl stays off-main
            DispatchQueue.main.async { self?.subject.send(id) }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    public var current: NetworkIdentity? { subject.value }
    public var changes: AnyPublisher<NetworkIdentity?, Never> { subject.eraseToAnyPublisher() }

    /// Resolves the default-gateway identity: default gateway IP → its link-layer MAC.
    private static func readGatewayIdentity() -> NetworkIdentity? {
        guard let gwIP = RoutingTableParser.defaultGatewayIP(),
              let mac = RoutingTableParser.macForIP(gwIP) else { return nil }
        return NetworkIdentity(gatewayMAC: mac)
    }
}
