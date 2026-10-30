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
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private let subject: CurrentValueSubject<NetworkIdentity?, Never>
    private let monitor: NWPathMonitor?
    private let readIdentity: IdentityReader
    private let retryDelays: [Duration]
    private let sleep: Sleeper
    private var refreshTask: Task<Void, Never>?

    public init() {
        subject = CurrentValueSubject(nil)
        readIdentity = { Self.readGatewayIdentity() }
        retryDelays = [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(2)]
        sleep = { try await Task.sleep(for: $0) }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        let queue = DispatchQueue(label: "com.aiscream.Mara.RoutingTableNetworkProvider")
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.startRefresh() }
        }
        monitor.start(queue: queue)
    }

    /// 테스트용 주입 경계. monitor 없이 동일한 retry 로직을 직접 검증한다.
    init(
        readIdentity: @escaping IdentityReader,
        retryDelays: [Duration],
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        subject = CurrentValueSubject(nil)
        monitor = nil
        self.readIdentity = readIdentity
        self.retryDelays = retryDelays
        self.sleep = sleep
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

    /// 테스트용: 경로 변경 콜백과 같은 경로(`startRefresh`)를 타고, 시작된 task를 돌려준다.
    func pathDidChangeForTesting() -> Task<Void, Never>? {
        startRefresh()
        return refreshTask
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
                try await sleep(retryDelays[attempt])
            } catch {
                return
            }
        }
        subject.send(nil)
    }

    /// Resolves the default-gateway identity: default gateway (IP + interface) → its link-layer MAC.
    nonisolated private static func readGatewayIdentity() -> NetworkIdentity? {
        gatewayIdentity(gateway: RoutingTableParser.defaultGateway(), mac: RoutingTableParser.mac(for:))
    }

    /// sysctl 호출과 분리한 조합 규칙. 경로나 MAC 중 하나라도 없으면 네트워크를 식별하지 않는다.
    nonisolated static func gatewayIdentity(
        gateway: RoutingTableParser.GatewayRoute?,
        mac: (RoutingTableParser.GatewayRoute) -> String?
    ) -> NetworkIdentity? {
        guard let gateway, let mac = mac(gateway) else { return nil }
        return NetworkIdentity(gatewayMAC: mac)
    }
}
