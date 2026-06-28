import XCTest
@testable import MaraCore

final class SessionManagerTests: XCTestCase {
    private func makeSUT() -> (SessionManager, MockPowerAssertionProvider, MockScheduler, MockClock) {
        let p = MockPowerAssertionProvider()
        let engine = SleepEngine(provider: p)
        let scheduler = MockScheduler()
        let clock = MockClock()
        let sm = SessionManager(engine: engine, scheduler: scheduler, clock: clock)
        return (sm, p, scheduler, clock)
    }

    func test_start_displayAndSystem_setsActiveAndAcquiresBoth() {
        let (sm, p, _, _) = makeSUT()
        sm.start(SessionConfig(scope: .displayAndSystem, duration: .indefinite, origin: .manual))
        XCTAssertTrue(sm.state.isActive)
        XCTAssertEqual(p.live.count, 2)
    }

    func test_stop_returnsInactiveAndReleasesAll() {
        let (sm, p, _, _) = makeSUT()
        sm.start(SessionConfig(scope: .systemOnly, duration: .indefinite, origin: .manual))
        sm.stop()
        XCTAssertFalse(sm.state.isActive)
        XCTAssertEqual(p.live.count, 0)
    }

    func test_toggle_togglesActiveState() {
        let (sm, _, _, _) = makeSUT()
        let cfg = SessionConfig(scope: .systemOnly, duration: .indefinite, origin: .manual)
        sm.toggle(cfg); XCTAssertTrue(sm.state.isActive)
        sm.toggle(cfg); XCTAssertFalse(sm.state.isActive)
    }
}

extension SessionManagerTests {
    func test_durationSession_firesTimer_thenStops() {
        let (sm, p, scheduler, _) = makeSUT()
        sm.start(SessionConfig(scope: .systemOnly, duration: .duration(60), origin: .manual))
        XCTAssertTrue(sm.state.isActive)
        scheduler.fireAll()
        XCTAssertFalse(sm.state.isActive)
        XCTAssertEqual(p.live.count, 0)
    }

    func test_indefiniteSession_schedulesNoTimer() {
        let (sm, _, scheduler, _) = makeSUT()
        sm.start(SessionConfig(scope: .systemOnly, duration: .indefinite, origin: .manual))
        XCTAssertEqual(scheduler.pending.count, 0)
    }

    func test_untilSession_usesIntervalFromClockNow() {
        let (sm, _, scheduler, clock) = makeSUT()
        let target = clock.now.addingTimeInterval(120)
        sm.start(SessionConfig(scope: .systemOnly, duration: .until(target), origin: .manual))
        XCTAssertEqual(scheduler.pending.count, 1)
        scheduler.fireAll()
        XCTAssertFalse(sm.state.isActive)
    }
}

extension SessionManagerTests {
    private func makeSUTWithBattery(threshold: Int = 20, percentage: Int = 100, isOnAC: Bool = true)
        -> (SessionManager, MockBattery) {
        let p = MockPowerAssertionProvider()
        let engine = SleepEngine(provider: p)
        let battery = MockBattery(percentage: percentage, isOnAC: isOnAC)
        let sm = SessionManager(engine: engine, scheduler: MockScheduler(), clock: MockClock(),
                                battery: battery, lowBatteryThreshold: threshold)
        return (sm, battery)
    }

    func test_lowBatteryOnBattery_stopsActiveSession() {
        let (sm, battery) = makeSUTWithBattery(threshold: 20)
        sm.start(SessionConfig(scope: .systemOnly, duration: .indefinite, origin: .manual))
        battery.emit(percentage: 15, isOnAC: false)
        XCTAssertFalse(sm.state.isActive)
    }

    func test_lowBatteryButOnAC_doesNotStop() {
        let (sm, battery) = makeSUTWithBattery(threshold: 20)
        sm.start(SessionConfig(scope: .systemOnly, duration: .indefinite, origin: .manual))
        battery.emit(percentage: 5, isOnAC: true)
        XCTAssertTrue(sm.state.isActive)
    }

    func test_startWhileBelowThresholdOnBattery_immediatelyStops() {
        let (sm, _) = makeSUTWithBattery(threshold: 20, percentage: 10, isOnAC: false)
        sm.start(SessionConfig(scope: .systemOnly, duration: .indefinite, origin: .manual))
        XCTAssertFalse(sm.state.isActive)
    }

    func test_startWhileBelowThresholdOnAC_staysActive() {
        let (sm, _) = makeSUTWithBattery(threshold: 20, percentage: 10, isOnAC: true)
        sm.start(SessionConfig(scope: .systemOnly, duration: .indefinite, origin: .manual))
        XCTAssertTrue(sm.state.isActive)
    }
}
