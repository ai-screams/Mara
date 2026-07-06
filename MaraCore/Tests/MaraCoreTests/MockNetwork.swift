import Combine
@testable import MaraCore

final class MockNetwork: NetworkIdentityProviding {
    private let subject: CurrentValueSubject<NetworkIdentity?, Never>
    init(_ id: NetworkIdentity? = nil) { subject = CurrentValueSubject(id) }
    var current: NetworkIdentity? { subject.value }
    var changes: AnyPublisher<NetworkIdentity?, Never> { subject.eraseToAnyPublisher() }
    func set(_ id: NetworkIdentity?) { subject.send(id) }
}
