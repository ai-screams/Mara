import OpenCombine
import Foundation
import AppKit

/// Combine/네트워크 변화 감지 adapter over `RoutingTableParser`.
/// Publishes the current gateway identity (default-gateway MAC) and refreshes it
/// whenever the network path changes. All routing-table parsing lives in
/// `RoutingTableParser`; this type only owns the change monitor and the published value.
///
/// 레거시(10.13): `Task`/`Duration`(10.15+/13+) 대신 `DispatchQueue` + 세대 번호로 재시도·취소한다.
/// 읽기는 utility 큐, 결과는 반드시 main으로 돌아와 세대를 확인한 뒤에만 방출한다 — 빠른 A→B→A
/// 전환에서 늦게 끝난 옛 읽기가 최신 값을 덮지 못한다.
@MainActor
public final class RoutingTableNetworkProvider: NetworkIdentityProviding {
    typealias IdentityReader = @Sendable () -> NetworkIdentity?

    private let subject: CurrentValueSubject<NetworkIdentity?, Never>
    private let monitor: NetworkChangeMonitoring?
    private let readIdentity: IdentityReader
    private let retryDelays: [TimeInterval]
    private var generation = 0
    private var wakeObserver: NSObjectProtocol?
    /// 테스트 전용: 한 세대의 새로고침이 끝나(값을 방출하고) 호출된다.
    var onRefreshFinishedForTesting: (() -> Void)?

    public init() {
        subject = CurrentValueSubject(nil)
        readIdentity = { Self.readGatewayIdentity() }
        retryDelays = [0.25, 0.5, 1, 2]
        let monitor: NetworkChangeMonitoring
        if #available(macOS 10.14, *) {
            monitor = NWPathChangeMonitor()
        } else {
            monitor = SCDynamicStoreChangeMonitor()
        }
        self.monitor = monitor
        monitor.start { [weak self] in unsafeAssumeMainActor { self?.startRefresh() } }
        // 잠자기 복귀 뒤 네트워크 키가 바뀌지 않아도 게이트웨이는 달라질 수 있다.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in unsafeAssumeMainActor { self?.startRefresh() } }
        // 이미 연결된 상태로 시작하면(콜드 스타트) 키 변화가 없으므로 한 번은 무조건 읽는다.
        startRefresh()
    }

    /// 테스트용 주입 경계. monitor 없이 동일한 retry 로직을 직접 검증한다.
    init(readIdentity: @escaping IdentityReader, retryDelays: [TimeInterval]) {
        subject = CurrentValueSubject(nil)
        monitor = nil
        self.readIdentity = readIdentity
        self.retryDelays = retryDelays
    }

    public var current: NetworkIdentity? { subject.value }
    public var changes: AnyPublisher<NetworkIdentity?, Never> { subject.eraseToAnyPublisher() }

    /// 감지 중지(멱등). 진행 중인 새로고침은 세대를 올려 결과를 버린다. `AppEnvironment.shutdown()`이 부른다.
    public func stop() {
        generation += 1
        monitor?.stop()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
    }

    func startRefresh() {
        generation += 1
        attempt(0, generation: generation)
    }

    private func attempt(_ index: Int, generation expected: Int) {
        let reader = readIdentity
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let identity = reader()
            DispatchQueue.main.async {
                unsafeAssumeMainActor { self?.handle(identity, attempt: index, generation: expected) }
            }
        }
    }

    private func handle(_ identity: NetworkIdentity?, attempt index: Int, generation expected: Int) {
        guard expected == generation else { return }   // 더 새로운 새로고침이 시작됐다
        if identity != nil || index >= retryDelays.count {
            subject.send(identity)
            onRefreshFinishedForTesting?()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelays[index]) { [weak self] in
            unsafeAssumeMainActor {
                guard let self, expected == self.generation else { return }   // 그 사이 새 세대가 시작됐으면 옛 재시도는 읽지도 않는다
                self.attempt(index + 1, generation: expected)
            }
        }
    }

    /// Resolves the default-gateway identity: default gateway IP → its link-layer MAC.
    nonisolated private static func readGatewayIdentity() -> NetworkIdentity? {
        guard let gwIP = RoutingTableParser.defaultGatewayIP(),
              let mac = RoutingTableParser.macForIP(gwIP) else { return nil }
        return NetworkIdentity(gatewayMAC: mac)
    }
}
