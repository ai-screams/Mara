import Combine

public final class ChargingTrigger: TriggerEvaluator {
    public let kind: TriggerKind = .charging
    private let battery: BatteryMonitoring
    public init(battery: BatteryMonitoring) { self.battery = battery }

    public var isSatisfied: Bool { battery.snapshot.isOnAC }

    public var satisfied: AnyPublisher<Bool, Never> {
        battery.snapshots
            .map { $0.isOnAC }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
