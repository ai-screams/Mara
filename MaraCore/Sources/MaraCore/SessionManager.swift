import Foundation
import Combine

@MainActor
public final class SessionManager: ObservableObject {
    @Published public private(set) var state: SessionState = .inactive
    @Published public private(set) var lastFailure: SessionFailure?

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
    private var batteryThreshold: Int
    public var lowBatteryThreshold: Int {
        get { batteryThreshold }
        set { batteryThreshold = Self.clampBatteryThreshold(newValue) }
    }
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
        self.batteryThreshold = Self.clampBatteryThreshold(lowBatteryThreshold)
        battery?.snapshots
            .dropFirst()  // 초기 현재값 재방출은 무시 (세션 시작 시점엔 start()가 직접 검사)
            // 배터리 알림은 CFRunLoopGetMain에서 delivery된다. assumeIsolated로 동기 타이밍을
            // 보존하면서 main-actor 격리를 보장한다(만약 off-main으로 들어오면 즉시 trap).
            .sink { [weak self] snap in MainActor.assumeIsolated { self?.handleBattery(snap) } }
            .store(in: &cancellables)
    }

    private func handleBattery(_ snap: BatterySnapshot) {
        guard state.isActive,
              case let .battery(percentage, isOnAC) = snap else { return }
        if !isOnAC && percentage <= lowBatteryThreshold {
            _ = stop(reason: .lowBattery(percent: percentage))   // 최우선 거부권
        }
    }

    /// 새 assertion 구성이 완전히 적용된 뒤에만 state를 active로 전환한다.
    /// 실패하면 기존 세션·타이머를 보존하고 lastFailure를 갱신한다.
    @discardableResult
    public func start(_ config: SessionConfig) -> Result<Void, SessionFailure> {
        if case let .battery(percentage, isOnAC) = battery?.snapshot,
           !isOnAC,
           percentage <= lowBatteryThreshold {
            let failure = SessionFailure.lowBattery(percent: percentage)
            lastFailure = failure
            return .failure(failure)
        }

        let expiresAt: Date?
        switch expiry(for: config.duration) {
        case .success(let value): expiresAt = value
        case .failure(let failure):
            lastFailure = failure
            return .failure(failure)
        }
        if case .failure(let failure) = engine.apply(
            display: config.scope.keepsDisplayAwake,
            system: true
        ) {
            let sessionFailure = SessionFailure.power(failure)
            lastFailure = sessionFailure
            return .failure(sessionFailure)
        }

        timer?.cancel(); timer = nil
        if state.isActive { record(.stopped(.replacedByNewSession)) }
        lastFailure = nil
        state = .active(config, expiresAt: expiresAt)
        record(.started(config))
        if let expiresAt {
            let interval = max(0, expiresAt.timeIntervalSince(clock.now))
            timer = scheduler.schedule(after: interval) { [weak self] in
                // 스케줄러는 main 큐에서 발화(prod) / 테스트는 main에서 fireAll.
                MainActor.assumeIsolated { _ = self?.stop(reason: .timerExpired) }
            }
        }
        return .success(())
    }

    /// assertion을 모두 해제한 뒤에만 inactive로 전환한다. 실패 토큰은 재시도를 위해 보존한다.
    @discardableResult
    public func stop(reason: SessionStopReason) -> Result<Void, SessionFailure> {
        let wasActive = state.isActive
        let hasAssertions = engine.isDisplayHeld || engine.isSystemHeld
        guard wasActive || hasAssertions else {
            lastFailure = nil
            return .success(())
        }
        if case .failure(let failure) = engine.releaseAll() {
            let sessionFailure = SessionFailure.power(failure)
            lastFailure = sessionFailure
            return .failure(sessionFailure)
        }
        timer?.cancel(); timer = nil
        lastFailure = nil
        state = .inactive
        if wasActive { record(.stopped(reason)) }
        return .success(())
    }

    /// 기존 호출부 호환 wrapper — 수동 종료.
    @discardableResult
    public func stop() -> Result<Void, SessionFailure> { stop(reason: .manual) }

    @discardableResult
    public func toggle(_ config: SessionConfig) -> Result<Void, SessionFailure> {
        state.isActive ? stop() : start(config)
    }

    /// 활성 세션의 scope만 라이브로 변경한다. 타이머/만료/origin은 보존.
    @discardableResult
    public func updateScope(_ scope: KeepAwakeScope) -> Result<Void, SessionFailure> {
        guard case let .active(cfg, expiresAt) = state else { return .success(()) }
        if case .failure(let failure) = engine.apply(display: scope.keepsDisplayAwake, system: true) {
            let sessionFailure = SessionFailure.power(failure)
            lastFailure = sessionFailure
            return .failure(sessionFailure)
        }
        lastFailure = nil
        state = .active(cfg.withScope(scope), expiresAt: expiresAt)
        record(.scopeChanged(scope))
        return .success(())
    }

    private func expiry(for duration: SessionDuration) -> Result<Date?, SessionFailure> {
        switch duration {
        case .indefinite:
            return .success(nil)
        case .duration(let interval):
            guard interval.isFinite,
                  (0...SessionDuration.maximumFiniteInterval).contains(interval) else {
                return .failure(.invalidDuration)
            }
            return .success(clock.now.addingTimeInterval(interval))
        case .until(let date):
            guard date.timeIntervalSinceReferenceDate.isFinite else {
                return .failure(.invalidUntilDate)
            }
            return .success(date)
        }
    }

    private static func clampBatteryThreshold(_ value: Int) -> Int {
        min(max(value, 5), 100)
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
