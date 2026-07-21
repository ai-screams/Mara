import Foundation
import Combine

@MainActor
public final class SessionManager: ObservableObject {
    @Published public private(set) var state: SessionState = .inactive
    @Published public private(set) var lastFailure: SessionFailure?

    /// 배터리 사전조건 기반의 시작 가능성. TriggerEngine이 구독해 blocked→allowed 에지에서만
    /// 재평가한다 — 저배터리로 거부/종료된 트리거 세션이 AC 연결·충전 회복 후 재개되도록.
    /// 내부 조율용이라 public 아님(App은 state/lastFailure로 충분).
    @Published private(set) var startEligibility: SessionStartEligibility = .allowed

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
        set {
            batteryThreshold = Self.clampBatteryThreshold(newValue)
            // 활성 세션 중 임계값을 올려 지금 배터리가 위반이 되면, 다음 스냅샷을
            // 기다리지 않고 즉시 종료한다(설정과 라이브 세션이 어긋나는 창 제거).
            // init은 batteryThreshold를 직접 대입해 이 setter를 우회하므로 여기 안 온다.
            if state.isActive, let percent = batteryFloorBreach(battery?.snapshot) {
                _ = stop(reason: .lowBattery(percent: percent))
            }
            updateStartEligibility(battery?.snapshot)   // 임계값 변경도 eligibility에 반영
        }
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
        // 아래 sink는 dropFirst로 첫 스냅샷을 흘리므로, 초기 eligibility는 현재 스냅샷으로 seed한다
        // (저배터리로 시작하면 blocked로 출발 → 회복 스냅샷이 blocked→allowed 에지를 만들어 재평가).
        if let percent = batteryFloorBreach(battery?.snapshot) {
            self.startEligibility = .blocked(.lowBattery(percent: percent))
        }
        battery?.snapshots
            .dropFirst()  // 초기 현재값 재방출은 무시 (세션 시작 시점엔 start()가 직접 검사)
            // 배터리 알림은 CFRunLoopGetMain에서 delivery된다. assumeIsolated로 동기 타이밍을
            // 보존하면서 main-actor 격리를 보장한다(만약 off-main으로 들어오면 즉시 trap).
            .sink { [weak self] snap in MainActor.assumeIsolated { self?.handleBattery(snap) } }
            .store(in: &cancellables)
    }

    private func handleBattery(_ snap: BatterySnapshot) {
        updateStartEligibility(snap)   // 활성 여부와 무관하게 갱신 — inactive 회복도 신호로 남긴다
        guard state.isActive else { return }
        if let percent = batteryFloorBreach(snap) {
            _ = stop(reason: .lowBattery(percent: percent))   // 최우선 거부권
        }
    }

    /// 배터리 스냅샷으로 시작 가능성을 갱신한다. 값이 바뀔 때만 발행(중복 발행 억제 →
    /// 구독측의 busy-retry 원천 차단: 같은 상태 반복 스냅샷은 에지를 만들지 않는다).
    private func updateStartEligibility(_ snapshot: BatterySnapshot?) {
        let next: SessionStartEligibility = batteryFloorBreach(snapshot)
            .map { .blocked(.lowBattery(percent: $0)) } ?? .allowed
        if next != startEligibility { startEligibility = next }
    }

    /// The offending battery % if a session must not run on the current power state; nil otherwise.
    /// nil for .desktop / .unavailable / nil-battery, and for on-AC or above-floor states.
    private func batteryFloorBreach(_ snapshot: BatterySnapshot?) -> Int? {
        guard case let .battery(percentage, isOnAC) = snapshot,
              !isOnAC, percentage <= lowBatteryThreshold else { return nil }
        return percentage
    }

    /// 새 assertion 구성이 완전히 적용된 뒤에만 state를 active로 전환한다.
    /// 실패하면 기존 세션·타이머를 보존하고 lastFailure를 갱신한다.
    @discardableResult
    public func start(_ config: SessionConfig) -> Result<Void, SessionFailure> {
        if let percent = batteryFloorBreach(battery?.snapshot) {
            return reject(config, .lowBattery(percent: percent))
        }

        let expiresAt: Date?
        switch expiry(for: config.duration) {
        case .success(let value): expiresAt = value
        case .failure(let failure):
            return reject(config, failure)
        }
        if case .failure(let failure) = engine.apply(
            display: config.scope.keepsDisplayAwake,
            system: true
        ) {
            return reject(config, .power(failure))
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

    /// 저배터리 임계값의 허용 범위. App(입력 clamp·stepper range)도 이 상수를 참조한다.
    public static let batteryThresholdRange: ClosedRange<Int> = 5...100

    private static func clampBatteryThreshold(_ value: Int) -> Int {
        min(max(value, batteryThresholdRange.lowerBound), batteryThresholdRange.upperBound)
    }

    // MARK: - Private

    /// 시작 거부 공통 처리: assertion·state·타이머는 건드리지 않고 거부 이벤트만 기록한다.
    /// lastFailure는 수동(사용자가 직접 시도)일 때만 설정한다 — 트리거 자동 시도 실패를
    /// "Last operation failed"로 메뉴에 띄우지 않기 위함(알림은 App의 SessionNotifier가 처리).
    /// 트리거 거부는 기존 lastFailure를 건드리지 않아 앞선 수동 실패 정보를 지우지 않는다.
    private func reject(_ config: SessionConfig, _ failure: SessionFailure) -> Result<Void, SessionFailure> {
        if config.origin == .manual { lastFailure = failure }
        record(.startRejected(config, failure))
        return .failure(failure)
    }

    private func record(_ kind: SessionEvent.Kind) {
        let event = SessionEvent(at: clock.now, kind: kind)
        recentEvents.append(event)
        if recentEvents.count > Self.maxRecentEvents {
            recentEvents = Array(recentEvents.suffix(Self.maxRecentEvents))
        }
        eventsSubject.send(event)
    }
}
