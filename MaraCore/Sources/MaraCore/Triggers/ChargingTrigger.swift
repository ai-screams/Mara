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
    public var diagnostic: TriggerDiagnostic { Self.diagnostic(for: battery.snapshot) }
    public var diagnostics: AnyPublisher<TriggerDiagnostic, Never> {
        battery.snapshots
            .map(Self.diagnostic(for:))
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// 지금 값과 변경 알림이 같은 매핑을 쓰도록 한 곳에 둔다. publisher의 map에서도 부르므로 nonisolated.
    nonisolated private static func diagnostic(for snapshot: BatterySnapshot) -> TriggerDiagnostic {
        snapshot == .unavailable ? .batteryUnavailable : .charging(onAC: snapshot.isOnAC)
    }
}
