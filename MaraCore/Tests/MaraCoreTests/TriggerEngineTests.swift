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

extension TriggerEngineTests {
    private func manualConfig() -> SessionConfig {
        SessionConfig(scope: .displayAndSystem, duration: .indefinite, origin: .manual)
    }

    func test_manualActive_triggerDoesNotOverrideOrStop() {
        let (sm, _) = makeSession()
        let t = MockTrigger(satisfied: false)
        let engine = TriggerEngine(session: sm, evaluators: [t], scope: .systemOnly)
        engine.start()
        sm.start(manualConfig())          // 사용자가 수동 ON
        t.set(true)                        // 트리거도 true
        // 여전히 수동 세션이어야 함 (트리거가 덮어쓰지 않음)
        if case let .active(cfg, _) = sm.state { XCTAssertEqual(cfg.origin, .manual) } else { XCTFail() }
        t.set(false)                       // 트리거 false 여도 수동 세션은 유지
        XCTAssertTrue(sm.state.isActive)
        if case let .active(cfg, _) = sm.state { XCTAssertEqual(cfg.origin, .manual) } else { XCTFail() }
    }

    func test_manualStopWhileTriggerTrue_suppressesUntilTriggerDrops() {
        let (sm, _) = makeSession()
        let t = MockTrigger(satisfied: true)
        let engine = TriggerEngine(session: sm, evaluators: [t], scope: .systemOnly)
        engine.start()
        XCTAssertTrue(sm.state.isActive)   // 트리거로 켜짐
        sm.stop()                          // 사용자가 수동으로 끔 (트리거 여전히 true)
        XCTAssertFalse(sm.state.isActive)
        // 트리거가 여전히 true여도 다시 켜지지 않아야 함 (suppressed)
        XCTAssertFalse(sm.state.isActive)
        t.set(false)                       // 트리거 사라짐 → 재무장
        t.set(true)                        // 다시 충족 → 이제 켜져야 함
        XCTAssertTrue(sm.state.isActive)
    }

    // 현재 구현에서 실제로 RED가 되는 테스트:
    // sm.stop() 후 평가기가 이벤트를 재방출하면(트리거 여전히 true) 세션이 재시작되어서는 안 된다.
    func test_manualStopWhileTriggerTrue_evaluatorReemit_doesNotRestart() {
        let (sm, _) = makeSession()
        let a = MockTrigger(kind: .charging, satisfied: true)
        let b = MockTrigger(kind: .appRunning, satisfied: false)
        let engine = TriggerEngine(session: sm, evaluators: [a, b], scope: .systemOnly)
        engine.start()
        XCTAssertTrue(sm.state.isActive)     // a가 true → 세션 시작
        sm.stop()                             // 수동 종료 (a 여전히 true) → suppressed
        XCTAssertFalse(sm.state.isActive)
        b.set(true)                           // 다른 평가기 이벤트 발생 — 억제 중이므로 재시작 금지
        XCTAssertFalse(sm.state.isActive)    // 현재 구현은 여기서 isActive=true → FAIL
        a.set(false); b.set(false)            // 모든 트리거 false → 재무장
        a.set(true)                           // 다시 충족 → 재시작 허용
        XCTAssertTrue(sm.state.isActive)
    }
}
