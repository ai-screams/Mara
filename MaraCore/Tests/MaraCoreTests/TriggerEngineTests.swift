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
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        engine.updateEvaluators([t])
        XCTAssertFalse(sm.state.isActive)
        t.set(true)
        XCTAssertTrue(sm.state.isActive)
        if case let .active(cfg, _) = sm.state { XCTAssertEqual(cfg.origin, .trigger) } else { XCTFail() }
    }

    func test_triggerFalling_stopsTriggerSession() {
        let (sm, _) = makeSession()
        let t = MockTrigger(satisfied: true)
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        engine.updateEvaluators([t])
        XCTAssertTrue(sm.state.isActive)   // 시작 시 이미 true면 켜짐
        t.set(false)
        XCTAssertFalse(sm.state.isActive)
    }

    func test_orCombination_multipleEvaluators() {
        let (sm, _) = makeSession()
        let a = MockTrigger(kind: .charging, satisfied: false)
        let b = MockTrigger(kind: .appRunning, satisfied: false)
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        engine.updateEvaluators([a, b])
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
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        engine.updateEvaluators([t])
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
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        engine.updateEvaluators([t])
        XCTAssertTrue(sm.state.isActive)   // 트리거로 켜짐
        sm.stop()                          // 사용자가 수동으로 끔 (트리거 여전히 true)
        XCTAssertFalse(sm.state.isActive)
        // 트리거가 여전히 true여도 다시 켜지지 않아야 함 (suppressed)
        XCTAssertFalse(sm.state.isActive)
        t.set(false)                       // 트리거 사라짐 → 재무장
        t.set(true)                        // 다시 충족 → 이제 켜져야 함
        XCTAssertTrue(sm.state.isActive)
    }

    func test_manualStopWhileTriggerTrue_evaluatorReemit_doesNotRestart() {
        let (sm, _) = makeSession()
        let a = MockTrigger(kind: .charging, satisfied: true)
        let b = MockTrigger(kind: .appRunning, satisfied: false)
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        engine.updateEvaluators([a, b])
        XCTAssertTrue(sm.state.isActive)     // a가 true → 세션 시작
        sm.stop()                             // 수동 종료 (a 여전히 true) → suppressed
        XCTAssertFalse(sm.state.isActive)
        b.set(true)                           // 다른 평가기 이벤트 발생 — 억제 중이므로 재시작 금지
        XCTAssertFalse(sm.state.isActive)
        a.set(false); b.set(false)            // 모든 트리거 false → 재무장
        a.set(true)                           // 다시 충족 → 재시작 허용
        XCTAssertTrue(sm.state.isActive)
    }
}

extension TriggerEngineTests {
    // 트리거로 켠 뒤 수동 OFF(suppressed) 상태가, 평가기 재조정(설정 변경)에도 살아남아야 한다.
    func test_suppression_survivesUpdateEvaluators() {
        let (sm, _) = makeSession()
        let t = MockTrigger(kind: .charging, satisfied: true)
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        engine.updateEvaluators([t])
        XCTAssertTrue(sm.state.isActive)      // 트리거로 켜짐
        sm.stop()                              // 사용자가 수동 OFF (트리거 여전히 true)
        XCTAssertFalse(sm.state.isActive)
        // 설정 변경을 모사: 동일 트리거 유지한 채 재조정
        engine.updateEvaluators([t])
        XCTAssertFalse(sm.state.isActive)      // suppressed 유지 → 재가동 안 됨 (M1)
        // 다른 트리거를 추가해도 여전히 억제 상태여야 함
        let t2 = MockTrigger(kind: .externalDisplay, satisfied: true)
        engine.updateEvaluators([t, t2])
        XCTAssertFalse(sm.state.isActive)      // 여전히 suppressed
    }

    // 실제 앱 경로(reconcileTriggers)는 동일 kind라도 항상 새 인스턴스를 생성한다.
    // 새 인스턴스로 updateEvaluators 해도 suppression이 유지되는지 검증 (M1 실환경 증명).
    func test_suppression_survivesUpdateEvaluators_withFreshInstance() {
        let (sm, _) = makeSession()
        let t1 = MockTrigger(kind: .charging, satisfied: true)
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        engine.updateEvaluators([t1])
        XCTAssertTrue(sm.state.isActive)       // 트리거로 켜짐
        sm.stop()                               // 사용자 수동 OFF (트리거 여전히 true) → suppressed
        XCTAssertFalse(sm.state.isActive)

        // 실제 앱처럼 동일 kind의 완전히 새 인스턴스로 재조정
        let t2 = MockTrigger(kind: .charging, satisfied: true)
        engine.updateEvaluators([t2])
        XCTAssertFalse(sm.state.isActive)      // suppression 유지 — 인스턴스 교체에도 재가동 금지
    }

    // 재조정으로 모든 트리거가 사라지면 trigger-origin 세션은 정지된다(orphan 방지).
    func test_updateEvaluators_toEmpty_stopsTriggerSession() {
        let (sm, _) = makeSession()
        let t = MockTrigger(kind: .charging, satisfied: true)
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        engine.updateEvaluators([t])
        XCTAssertTrue(sm.state.isActive)
        engine.updateEvaluators([])            // 모든 트리거 비활성화
        XCTAssertFalse(sm.state.isActive)
    }

    // 재조정은 변하지 않은 kind의 구독을 유지한다(스모크: 여러 번 호출해도 동작 일관).
    func test_updateEvaluators_idempotentForUnchangedEvaluator() {
        let (sm, _) = makeSession()
        let t = MockTrigger(kind: .charging, satisfied: false)
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        engine.updateEvaluators([t])
        engine.updateEvaluators([t])   // 동일 인스턴스 재조정
        t.set(true)
        XCTAssertTrue(sm.state.isActive)   // 구독이 살아있어 반응
    }
}

extension TriggerEngineTests {
    // 동일 kind의 평가기 인스턴스 교체 시 중간 stop/start(assertion 해제·재취득)가 없어야 한다.
    func test_updateEvaluators_replacingInstance_noSpuriousChurn() {
        let (sm, p) = makeSession()
        let t1 = MockTrigger(kind: .charging, satisfied: true)
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        engine.updateEvaluators([t1])
        XCTAssertTrue(sm.state.isActive)
        if case let .active(cfg, _) = sm.state { XCTAssertEqual(cfg.origin, .trigger) } else { XCTFail("expected trigger session") }

        // assertion 토큰을 기록 — 해제+재취득이 없으면 동일 토큰 집합이 유지된다
        let tokensBefore = Set(p.live.keys)
        XCTAssertFalse(tokensBefore.isEmpty, "assertion should be held before swap")

        // 동일 kind, 다른 인스턴스, 동일하게 satisfied=true 인 평가기로 교체
        let t2 = MockTrigger(kind: .charging, satisfied: true)
        engine.updateEvaluators([t2])

        // 세션은 trigger-active 상태를 유지해야 하고 assertion 토큰이 바뀌지 않아야 한다
        XCTAssertTrue(sm.state.isActive, "session must stay active after instance swap")
        if case let .active(cfg, _) = sm.state { XCTAssertEqual(cfg.origin, .trigger) } else { XCTFail("expected trigger session") }
        XCTAssertEqual(Set(p.live.keys), tokensBefore, "power assertion was spuriously released and reacquired")
    }

    // engine.stop() 은 trigger-origin 세션을 함께 종료해야 한다.
    func test_stop_stopsActiveTriggerSession() {
        let (sm, _) = makeSession()
        let t = MockTrigger(kind: .charging, satisfied: true)
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        engine.updateEvaluators([t])
        XCTAssertTrue(sm.state.isActive)
        if case let .active(cfg, _) = sm.state { XCTAssertEqual(cfg.origin, .trigger) } else { XCTFail() }
        engine.stop()
        XCTAssertFalse(sm.state.isActive, "trigger session must be stopped by engine.stop()")
    }

    // engine.stop() 은 수동 세션을 중단하지 않아야 한다.
    func test_stop_doesNotStopManualSession() {
        let (sm, _) = makeSession()
        let t = MockTrigger(kind: .charging, satisfied: false)
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        engine.updateEvaluators([t])
        sm.start(SessionConfig(scope: .displayAndSystem, duration: .indefinite, origin: .manual))
        XCTAssertTrue(sm.state.isActive)
        if case let .active(cfg, _) = sm.state { XCTAssertEqual(cfg.origin, .manual) } else { XCTFail() }
        engine.stop()
        XCTAssertTrue(sm.state.isActive, "manual session must survive engine.stop()")
        if case let .active(cfg, _) = sm.state { XCTAssertEqual(cfg.origin, .manual) } else { XCTFail() }
    }
}
