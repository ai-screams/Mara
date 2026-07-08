import Foundation
import Combine

@MainActor
public final class SessionManager: ObservableObject {
    @Published public private(set) var state: SessionState = .inactive

    private let engine: SleepEngine
    private let scheduler: Scheduling
    private let clock: Clock
    private let battery: BatteryMonitoring?
    public var lowBatteryThreshold: Int
    private var timer: SchedulerToken?
    private var cancellables = Set<AnyCancellable>()

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
        battery?.snapshots
            .dropFirst()  // 초기 현재값 재방출은 무시 (세션 시작 시점엔 start()가 직접 검사)
            // 배터리 알림은 CFRunLoopGetMain에서 delivery된다. assumeIsolated로 동기 타이밍을
            // 보존하면서 main-actor 격리를 보장한다(만약 off-main으로 들어오면 즉시 trap).
            .sink { [weak self] snap in MainActor.assumeIsolated { self?.handleBattery(snap) } }
            .store(in: &cancellables)
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
                // 스케줄러는 main 큐에서 발화(prod) / 테스트는 main에서 fireAll.
                MainActor.assumeIsolated { self?.stop() }
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

    /// 활성 세션의 scope만 라이브로 변경한다. 타이머/만료/origin은 보존.
    public func updateScope(_ scope: KeepAwakeScope) {
        guard case let .active(cfg, expiresAt) = state else { return }
        engine.apply(display: scope.keepsDisplayAwake, system: true)
        state = .active(cfg.withScope(scope), expiresAt: expiresAt)
    }

    private func expiry(for duration: SessionDuration) -> Date? {
        switch duration {
        case .indefinite: return nil
        case .duration(let t): return clock.now.addingTimeInterval(t)
        case .until(let date): return date
        }
    }
}
