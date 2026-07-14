import Combine
@testable import MaraCore

@MainActor
final class MockBattery: BatteryMonitoring {
    private let subject: CurrentValueSubject<BatterySnapshot, Never>
    init(percentage: Int = 100, isOnAC: Bool = true) {
        subject = CurrentValueSubject(BatterySnapshot(percentage: percentage, isOnAC: isOnAC))
    }
    var snapshot: BatterySnapshot { subject.value }
    var snapshots: AnyPublisher<BatterySnapshot, Never> { subject.eraseToAnyPublisher() }
    func emit(percentage: Int, isOnAC: Bool) {
        subject.send(BatterySnapshot(percentage: percentage, isOnAC: isOnAC))
    }
    func emitDesktop() { subject.send(.desktop) }
    func emitUnavailable() { subject.send(.unavailable) }
}
