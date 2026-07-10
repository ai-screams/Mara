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

extension ChargingTrigger: TriggerDiagnosing {
    public var diagnostic: TriggerDiagnostic { .charging(onAC: battery.snapshot.isOnAC) }
    public var diagnostics: AnyPublisher<TriggerDiagnostic, Never> {
        battery.snapshots
            .map { TriggerDiagnostic.charging(onAC: $0.isOnAC) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
