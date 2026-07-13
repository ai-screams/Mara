import Combine

@MainActor
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
    public var diagnostic: TriggerDiagnostic {
        battery.snapshot == .unavailable
            ? .batteryUnavailable
            : .charging(onAC: battery.snapshot.isOnAC)
    }
    public var diagnostics: AnyPublisher<TriggerDiagnostic, Never> {
        battery.snapshots
            .map {
                $0 == .unavailable
                    ? TriggerDiagnostic.batteryUnavailable
                    : TriggerDiagnostic.charging(onAC: $0.isOnAC)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
