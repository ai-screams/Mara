import Combine

@MainActor
public final class NetworkTrigger: TriggerEvaluator {
    public let kind: TriggerKind = .network
    private let network: NetworkIdentityProviding
    private let watched: Set<NetworkIdentity>
    public init(network: NetworkIdentityProviding, watched: Set<NetworkIdentity>) {
        self.network = network
        self.watched = watched
    }
    public var isSatisfied: Bool { Self.matches(network.current, watched: watched) }
    public var satisfied: AnyPublisher<Bool, Never> {
        let watched = self.watched
        return network.changes
            .map { Self.matches($0, watched: watched) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// 충족 판정과 진단의 matched가 같은 규칙을 쓰도록 한 곳에 둔다. 식별 못 한 네트워크(nil)는 불일치.
    /// publisher의 map에서도 부르므로 nonisolated이고, 클로저가 self를 잡지 않게 watched를 인자로 받는다.
    nonisolated private static func matches(_ current: NetworkIdentity?, watched: Set<NetworkIdentity>) -> Bool {
        current.map { watched.contains($0) } ?? false
    }
}

extension NetworkTrigger: TriggerDiagnosing {
    public var diagnostic: TriggerDiagnostic {
        let current = network.current
        return .network(current: current, matched: Self.matches(current, watched: watched))
    }
    public var diagnostics: AnyPublisher<TriggerDiagnostic, Never> {
        let watched = self.watched
        return network.changes
            .map { TriggerDiagnostic.network(current: $0, matched: Self.matches($0, watched: watched)) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
