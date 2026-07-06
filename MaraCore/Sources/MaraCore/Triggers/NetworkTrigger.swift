import Combine

public final class NetworkTrigger: TriggerEvaluator {
    public let kind: TriggerKind = .network
    private let network: NetworkIdentityProviding
    private let watched: Set<NetworkIdentity>
    public init(network: NetworkIdentityProviding, watched: Set<NetworkIdentity>) {
        self.network = network
        self.watched = watched
    }
    public var isSatisfied: Bool { network.current.map { watched.contains($0) } ?? false }
    public var satisfied: AnyPublisher<Bool, Never> {
        let watched = self.watched
        return network.changes
            .map { $0.map { watched.contains($0) } ?? false }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
