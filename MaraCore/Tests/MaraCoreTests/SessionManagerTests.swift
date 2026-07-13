import XCTest
@testable import MaraCore

// @MainActor: SUT(SessionManager)가 @MainActor라 테스트도 main-actor에서 구동해야 한다.
// XCTest는 동기 테스트를 main 스레드에서 실행하므로 안전하며, 동기 타이밍이 보존된다.
@MainActor
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

    func test_unavailableBatteryDoesNotPretendLowOrStopSession() {
        let (sm, battery) = makeSUTWithBattery(threshold: 100, percentage: 10, isOnAC: true)
        sm.start(SessionConfig(scope: .systemOnly, duration: .indefinite, origin: .manual))

        battery.emitUnavailable()

        XCTAssertTrue(sm.state.isActive)
    }
}

extension SessionManagerTests {
    func test_updateScope_onActiveTimedSession_keepsDurationAndOrigin_togglesDisplay() {
        let (sm, p, _, _) = makeSUT()   // (SessionManager, MockPowerAssertionProvider, MockScheduler, MockClock)
        sm.start(SessionConfig(scope: .displayAndSystem, duration: .duration(3600), origin: .manual))
        XCTAssertEqual(p.live.count, 2)  // display + system
        guard case let .active(_, expiresAtBefore) = sm.state else { XCTFail("expected active before"); return }
        sm.updateScope(.systemOnly)
        XCTAssertTrue(sm.state.isActive)
        XCTAssertEqual(p.live.count, 1)  // display 해제, system 유지
        guard case let .active(cfg, expiresAtAfter) = sm.state else { XCTFail("expected active after"); return }
        XCTAssertEqual(expiresAtAfter, expiresAtBefore)   // 타이머(만료시각) 정확히 보존
        XCTAssertEqual(cfg.scope, .systemOnly)
        XCTAssertEqual(cfg.origin, .manual)               // origin 보존
    }

    func test_updateScope_whenInactive_isNoOp() {
        let (sm, p, _, _) = makeSUT()
        sm.updateScope(.displayAndSystem)
        XCTAssertFalse(sm.state.isActive)
        XCTAssertEqual(p.live.count, 0)
    }

    func test_startAssertionFailure_staysInactiveAndExposesFailure() {
        let (sm, p, scheduler, _) = makeSUT()
        p.failNextCreate = true

        guard case .failure(let failure) = sm.start(
            SessionConfig(scope: .systemOnly, duration: .duration(60), origin: .manual)
        ) else {
            return XCTFail("expected start failure")
        }

        XCTAssertFalse(sm.state.isActive)
        XCTAssertEqual(sm.lastFailure, failure)
        XCTAssertTrue(p.live.isEmpty)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func test_stopReleaseFailure_keepsSessionActiveAndCanRetry() {
        let (sm, p, _, _) = makeSUT()
        sm.start(SessionConfig(scope: .systemOnly, duration: .indefinite, origin: .manual))
        p.failNextRelease = true

        guard case .failure(let failure) = sm.stop() else {
            return XCTFail("expected stop failure")
        }
        XCTAssertTrue(sm.state.isActive)
        XCTAssertEqual(sm.lastFailure, failure)

        XCTAssertNoThrow(try sm.stop().get())
        XCTAssertFalse(sm.state.isActive)
        XCTAssertNil(sm.lastFailure)
    }

    func test_startRejectsNonFiniteDurationBeforeTouchingEngine() {
        let (sm, p, scheduler, _) = makeSUT()

        guard case .failure(.invalidDuration) = sm.start(
            SessionConfig(scope: .systemOnly, duration: .duration(.infinity), origin: .manual)
        ) else {
            return XCTFail("expected invalid duration")
        }
        XCTAssertFalse(sm.state.isActive)
        XCTAssertTrue(p.live.isEmpty)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func test_stopInactive_retriesAssertionLeftByFailedRollback() {
        let (sm, p, _, _) = makeSUT()
        p.failingCreateTypes = [.preventDisplaySleep]
        p.failNextRelease = true
        _ = sm.start(SessionConfig(
            scope: .displayAndSystem,
            duration: .indefinite,
            origin: .manual
        ))
        XCTAssertFalse(sm.state.isActive)
        XCTAssertEqual(p.live.count, 1)

        XCTAssertNoThrow(try sm.stop().get())
        XCTAssertTrue(p.live.isEmpty)
        XCTAssertNil(sm.lastFailure)
    }
}
