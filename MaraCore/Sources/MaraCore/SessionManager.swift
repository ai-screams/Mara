import Foundation
import Combine

public final class SessionManager: ObservableObject {
    @Published public private(set) var state: SessionState = .inactive

    private let engine: SleepEngine
    private let scheduler: Scheduling
    private let clock: Clock
    private let battery: BatteryMonitoring?
    public var lowBatteryThreshold: Int
    private var timer: Cancellable?

    public init(engine: SleepEngine,
                scheduler: Scheduling,
                clock: Clock,
                battery: BatteryMonitoring? = nil,
                lowBatteryThreshold: Int = 20) {
        self.engine = engine
        self.scheduler = scheduler
        self.clock = clock
        self.battery = battery
        self.lowBatteryThreshold = lowBatteryThreshold
        self.battery?.onChange = { [weak self] snap in self?.handleBattery(snap) }
    }

    private func handleBattery(_ snap: BatterySnapshot) {
        guard state.isActive else { return }
        if !snap.isOnAC && snap.percentage <= lowBatteryThreshold {
            stop()   // 최우선 거부권
        }
    }

    public func start(_ config: SessionConfig) {
        timer?.cancel(); timer = nil
        engine.apply(display: config.scope.keepsDisplayAwake, system: true)
        let expiresAt = expiry(for: config.duration)
        state = .active(config, expiresAt: expiresAt)
        if let expiresAt {
            let interval = max(0, expiresAt.timeIntervalSince(clock.now))
            timer = scheduler.schedule(after: interval) { [weak self] in
                self?.stop()
            }
        }
        if let snap = battery?.snapshot { handleBattery(snap) }
    }

    public func stop() {
        timer?.cancel(); timer = nil
        engine.releaseAll()
        state = .inactive
    }

    public func toggle(_ config: SessionConfig) {
        state.isActive ? stop() : start(config)
    }

    private func expiry(for duration: SessionDuration) -> Date? {
        switch duration {
        case .indefinite: return nil
        case .duration(let t): return clock.now.addingTimeInterval(t)
        case .until(let date): return date
        }
    }
}
