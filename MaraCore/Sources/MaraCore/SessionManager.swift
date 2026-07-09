import Foundation
import Combine

@MainActor
public final class SessionManager: ObservableObject {
    @Published public private(set) var state: SessionState = .inactive

    /// 최근 세션 이벤트(관측용, 최대 20개). 문구 생성은 App 레이어가 한다.
    @Published public private(set) var recentEvents: [SessionEvent] = []
    /// 이벤트 스트림 — 알림 어댑터 등 실시간 구독자용.
    public var events: AnyPublisher<SessionEvent, Never> { eventsSubject.eraseToAnyPublisher() }
    private let eventsSubject = PassthroughSubject<SessionEvent, Never>()
    private static let maxRecentEvents = 20

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
            stop(reason: .lowBattery(percent: snap.percentage))   // 최우선 거부권
        }
    }

    public func start(_ config: SessionConfig) {
        timer?.cancel(); timer = nil
        if state.isActive { record(.stopped(.replacedByNewSession)) }
        engine.apply(display: config.scope.keepsDisplayAwake, system: true)
        let expiresAt = expiry(for: config.duration)
        state = .active(config, expiresAt: expiresAt)
        record(.started(config))
        if let expiresAt {
            let interval = max(0, expiresAt.timeIntervalSince(clock.now))
            timer = scheduler.schedule(after: interval) { [weak self] in
                // 스케줄러는 main 큐에서 발화(prod) / 테스트는 main에서 fireAll.
                MainActor.assumeIsolated { self?.stop(reason: .timerExpired) }
            }
        }
        if let snap = battery?.snapshot { handleBattery(snap) }
    }

    public func stop(reason: SessionStopReason) {
        timer?.cancel(); timer = nil
        engine.releaseAll()
        let wasActive = state.isActive
        state = .inactive
        if wasActive { record(.stopped(reason)) }   // 비활성 중 stop(낡은 메뉴 등)은 무기록
    }

    /// 기존 호출부 호환 wrapper — 수동 종료.
    public func stop() { stop(reason: .manual) }

    public func toggle(_ config: SessionConfig) {
        state.isActive ? stop() : start(config)
    }

    /// 활성 세션의 scope만 라이브로 변경한다. 타이머/만료/origin은 보존.
    public func updateScope(_ scope: KeepAwakeScope) {
        guard case let .active(cfg, expiresAt) = state else { return }
        engine.apply(display: scope.keepsDisplayAwake, system: true)
        state = .active(cfg.withScope(scope), expiresAt: expiresAt)
        record(.scopeChanged(scope))
    }

    private func expiry(for duration: SessionDuration) -> Date? {
        switch duration {
        case .indefinite: return nil
        case .duration(let t): return clock.now.addingTimeInterval(t)
        case .until(let date): return date
        }
    }

    // MARK: - Private

    private func record(_ kind: SessionEvent.Kind) {
        let event = SessionEvent(at: clock.now, kind: kind)
        recentEvents.append(event)
        if recentEvents.count > Self.maxRecentEvents {
            recentEvents = Array(recentEvents.suffix(Self.maxRecentEvents))
        }
        eventsSubject.send(event)
    }
}
