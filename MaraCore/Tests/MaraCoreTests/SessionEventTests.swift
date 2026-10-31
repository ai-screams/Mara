import XCTest
import Combine
@testable import MaraCore

@MainActor
final class SessionEventTests: XCTestCase {
    private func makeSUT() -> (SessionManager, MockScheduler, MockClock) {
        let engine = SleepEngine(provider: MockPowerAssertionProvider())
        let scheduler = MockScheduler()
        let clock = MockClock()
        return (SessionManager(engine: engine, scheduler: scheduler, clock: clock), scheduler, clock)
    }
    private func cfg(_ duration: SessionDuration = .indefinite,
                     origin: SessionOrigin = .manual) -> SessionConfig {
        SessionConfig(scope: .systemOnly, duration: duration, origin: origin)
    }

    // 앱 시작 때 구독보다 먼저 일어난 트리거 결과를 알림이 보상한다.
    // 이것을 실패시키는 것: `lastTriggerOutcome`에서 `.started`를 빼는 것.
    func test_lastTriggerOutcome_startedByTrigger() {
        let (sm, _, _) = makeSUT()
        sm.start(cfg(origin: .trigger(.charging)))
        XCTAssertEqual(sm.lastTriggerOutcome?.kind, .started(cfg(origin: .trigger(.charging))))
    }

    // 이것을 실패시키는 것: `lastTriggerOutcome`에서 `.startRejected`를 빼는 것.
    func test_lastTriggerOutcome_rejectedTrigger() {
        let sm = SessionManager(engine: SleepEngine(provider: MockPowerAssertionProvider()),
                                scheduler: MockScheduler(), clock: MockClock(),
                                battery: MockBattery(percentage: 30, isOnAC: false), lowBatteryThreshold: 45)
        let config = cfg(origin: .trigger(.network))
        sm.start(config)
        XCTAssertEqual(sm.lastTriggerOutcome?.kind, .startRejected(config, .lowBattery(percent: 30)))
    }

    // 사용자가 직접 한 일은 배너로 알리지 않는다.
    // 이것을 실패시키는 것: `config.origin.isTrigger` 조건을 빼는 것.
    func test_lastTriggerOutcome_ignoresManualStart() {
        let (sm, _, _) = makeSUT()
        sm.start(cfg())
        XCTAssertNil(sm.lastTriggerOutcome)
    }

    // 결과 뒤에 다른 일이 있었으면 이미 지난 결과라 보상하지 않는다.
    // 이것을 실패시키는 것: `recentEvents.last` 대신 마지막 시작·거부 이벤트를 찾는 것.
    func test_lastTriggerOutcome_nilAfterLaterEvent() {
        let (sm, _, _) = makeSUT()
        XCTAssertNil(sm.lastTriggerOutcome)
        sm.start(cfg(origin: .trigger(.charging)))
        sm.stop()
        XCTAssertNil(sm.lastTriggerOutcome)
    }

    func test_manualStop_recordsManual() {
        let (sm, _, _) = makeSUT()
        sm.start(cfg())
        sm.stop()
        XCTAssertEqual(sm.recentEvents.last?.kind, .stopped(.manual))
    }

    func test_timerExpiry_recordsTimerExpired() {
        let (sm, scheduler, _) = makeSUT()
        sm.start(cfg(.duration(60)))
        scheduler.fireAll()
        XCTAssertEqual(sm.recentEvents.last?.kind, .stopped(.timerExpired))
    }

    func test_lowBattery_recordsBatteryPercent() {
        let battery = MockBattery(percentage: 50, isOnAC: false)
        let sm = SessionManager(engine: SleepEngine(provider: MockPowerAssertionProvider()),
                                scheduler: MockScheduler(), clock: MockClock(),
                                battery: battery, lowBatteryThreshold: 20)
        sm.start(cfg())
        battery.emit(percentage: 15, isOnAC: false)
        XCTAssertEqual(sm.recentEvents.last?.kind, .stopped(.lowBattery(percent: 15)))
    }

    func test_start_recordsStartedWithConfig() {
        let (sm, _, _) = makeSUT()
        let c = cfg(origin: .trigger(.charging))
        sm.start(c)
        XCTAssertEqual(sm.recentEvents.last?.kind, .started(c))
    }

    func test_startOverActive_recordsReplacedThenStarted() {
        let (sm, _, _) = makeSUT()
        sm.start(cfg())
        sm.start(cfg(.duration(60)))
        let kinds = sm.recentEvents.map(\.kind)
        XCTAssertEqual(kinds.suffix(2).first, .stopped(.replacedByNewSession))
        XCTAssertEqual(kinds.last, .started(cfg(.duration(60))))
    }

    func test_stopWhenInactive_recordsNothing() {
        let (sm, _, _) = makeSUT()
        sm.stop()
        XCTAssertTrue(sm.recentEvents.isEmpty)
    }

    func test_scopeChange_recordsScopeChanged() {
        let (sm, _, _) = makeSUT()
        sm.start(cfg())
        sm.updateScope(.displayAndSystem)
        XCTAssertEqual(sm.recentEvents.last?.kind, .scopeChanged(.displayAndSystem))
    }

    func test_recentEvents_keepsBoundedHistory() {
        let (sm, _, _) = makeSUT()
        for _ in 0..<30 { sm.start(cfg()); sm.stop() }
        XCTAssertEqual(sm.recentEvents.count, 20)
        XCTAssertEqual(sm.recentEvents.last?.kind, .stopped(.manual))
    }

    func test_eventsPublisher_emitsEachEvent() {
        let (sm, _, _) = makeSUT()
        var seen: [SessionEvent.Kind] = []
        let c = sm.events.sink { seen.append($0.kind) }
        sm.start(cfg()); sm.stop()
        XCTAssertEqual(seen, [.started(cfg()), .stopped(.manual)])
        c.cancel()
    }

    func test_eventTimestamp_usesInjectedClock() {
        let (sm, _, clock) = makeSUT()
        sm.start(cfg())
        XCTAssertEqual(sm.recentEvents.last?.at, clock.now)
    }
}
