import XCTest
@testable import SleeplessCore

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
