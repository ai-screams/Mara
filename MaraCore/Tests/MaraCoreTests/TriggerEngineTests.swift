import XCTest
import Combine
@testable import MaraCore

final class TriggerEngineTests: XCTestCase {
    private func makeSession() -> (SessionManager, MockPowerAssertionProvider) {
        let p = MockPowerAssertionProvider()
        let sm = SessionManager(engine: SleepEngine(provider: p),
                                scheduler: MockScheduler(), clock: MockClock())
        return (sm, p)
    }

    func test_triggerRising_startsTriggerSession() {
        let (sm, _) = makeSession()
        let t = MockTrigger(satisfied: false)
        let engine = TriggerEngine(session: sm, evaluators: [t], scope: .systemOnly)
        engine.start()
        XCTAssertFalse(sm.state.isActive)
        t.set(true)
        XCTAssertTrue(sm.state.isActive)
        if case let .active(cfg, _) = sm.state { XCTAssertEqual(cfg.origin, .trigger) } else { XCTFail() }
    }

    func test_triggerFalling_stopsTriggerSession() {
        let (sm, _) = makeSession()
        let t = MockTrigger(satisfied: true)
        let engine = TriggerEngine(session: sm, evaluators: [t], scope: .systemOnly)
        engine.start()
        XCTAssertTrue(sm.state.isActive)   // 시작 시 이미 true면 켜짐
        t.set(false)
        XCTAssertFalse(sm.state.isActive)
    }

    func test_orCombination_multipleEvaluators() {
        let (sm, _) = makeSession()
        let a = MockTrigger(kind: .charging, satisfied: false)
        let b = MockTrigger(kind: .appRunning, satisfied: false)
        let engine = TriggerEngine(session: sm, evaluators: [a, b], scope: .systemOnly)
        engine.start()
        a.set(true); XCTAssertTrue(sm.state.isActive)
        a.set(false); XCTAssertFalse(sm.state.isActive)  // b 아직 false
        b.set(true); XCTAssertTrue(sm.state.isActive)
    }
}
