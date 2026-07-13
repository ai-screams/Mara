import Combine
import Foundation
import Network

/// Combine/`NWPathMonitor` adapter over `RoutingTableParser`.
/// Publishes the current gateway identity (default-gateway MAC) and refreshes it
/// whenever the network path changes. All routing-table parsing lives in
/// `RoutingTableParser`; this type only owns the monitor and the published value.
@MainActor
public final class RoutingTableNetworkProvider: NetworkIdentityProviding {
    typealias IdentityReader = @Sendable () -> NetworkIdentity?

    private let subject: CurrentValueSubject<NetworkIdentity?, Never>
    private let monitor: NWPathMonitor?
    private let readIdentity: IdentityReader
    private let retryDelays: [Duration]
    private var refreshTask: Task<Void, Never>?

    public init() {
        subject = CurrentValueSubject(nil)
        readIdentity = { Self.readGatewayIdentity() }
        retryDelays = [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(2)]
        let monitor = NWPathMonitor()
        self.monitor = monitor
        let queue = DispatchQueue(label: "com.aiscream.Mara.RoutingTableNetworkProvider")
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.startRefresh() }
        }
        monitor.start(queue: queue)
    }

    /// 테스트용 주입 경계. monitor 없이 동일한 retry 로직을 직접 검증한다.
    init(readIdentity: @escaping IdentityReader, retryDelays: [Duration]) {
        subject = CurrentValueSubject(nil)
        monitor = nil
        self.readIdentity = readIdentity
        self.retryDelays = retryDelays
    }

    deinit {
        refreshTask?.cancel()
        monitor?.cancel()
    }

    public var current: NetworkIdentity? { subject.value }
    public var changes: AnyPublisher<NetworkIdentity?, Never> { subject.eraseToAnyPublisher() }

    private func startRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshAndPublish()
        }
    }

    func refreshForTesting() async {
        refreshTask?.cancel()
        await refreshAndPublish()
    }

    private func refreshAndPublish() async {
        for attempt in 0...retryDelays.count {
            let reader = readIdentity
            let identity = await Task.detached(priority: .utility) { reader() }.value
            guard !Task.isCancelled else { return }
            if let identity {
                subject.send(identity)
                return
            }
            guard attempt < retryDelays.count else { break }
            do {
                try await Task.sleep(for: retryDelays[attempt])
            } catch {
                return
            }
        }
        subject.send(nil)
    }

    /// Resolves the default-gateway identity: default gateway IP → its link-layer MAC.
    nonisolated private static func readGatewayIdentity() -> NetworkIdentity? {
        guard let gwIP = RoutingTableParser.defaultGatewayIP(),
              let mac = RoutingTableParser.macForIP(gwIP) else { return nil }
        return NetworkIdentity(gatewayMAC: mac)
    }
}
