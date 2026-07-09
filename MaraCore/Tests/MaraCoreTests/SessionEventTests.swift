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
        let c = cfg(origin: .trigger)
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
