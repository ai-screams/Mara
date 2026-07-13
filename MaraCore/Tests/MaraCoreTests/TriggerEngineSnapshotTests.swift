import XCTest
import Combine
@testable import MaraCore

/// TriggerEngine의 @Published snapshot — armed 목록·만족 여부·진단·suppression의 read-only 노출.
@MainActor
final class TriggerEngineSnapshotTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    private func makeSession() -> SessionManager {
        SessionManager(engine: SleepEngine(provider: MockPowerAssertionProvider()),
                       scheduler: MockScheduler(), clock: MockClock())
    }

    func test_updateEvaluators_populatesSnapshot_inKindOrder() {
        let sm = makeSession()
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        XCTAssertEqual(engine.snapshot, .empty)
        let net = MockDiagnosingTrigger(kind: .network, satisfied: false,
                                        diagnostic: .network(current: nil, matched: false))
        let chg = MockDiagnosingTrigger(kind: .charging, satisfied: true,
                                        diagnostic: .charging(onAC: true))
        engine.updateEvaluators([net, chg])   // 등록 역순으로 넣어도
        // 스냅샷은 TriggerKind.allCases 순서(charging → network)여야 한다.
        XCTAssertEqual(engine.snapshot.triggers.map(\.kind), [.charging, .network])
        XCTAssertEqual(engine.snapshot.trigger(.charging)?.isSatisfied, true)
        XCTAssertEqual(engine.snapshot.trigger(.charging)?.diagnostic, .charging(onAC: true))
        XCTAssertEqual(engine.snapshot.trigger(.network)?.isSatisfied, false)
        XCTAssertFalse(engine.snapshot.isSuppressed)
    }

    func test_nonDiagnosingEvaluator_snapshotHasNilDiagnostic() {
        let sm = makeSession()
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        let plain = MockTrigger(kind: .charging, satisfied: true)   // TriggerDiagnosing 미채택
        engine.updateEvaluators([plain])
        XCTAssertEqual(engine.snapshot.trigger(.charging)?.isSatisfied, true)
        XCTAssertNil(engine.snapshot.trigger(.charging)?.diagnostic)
    }

    func test_satisfiedChange_updatesSnapshot() {
        let sm = makeSession()
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        let t = MockDiagnosingTrigger(kind: .charging, satisfied: false,
                                      diagnostic: .charging(onAC: false))
        engine.updateEvaluators([t])
        XCTAssertEqual(engine.snapshot.trigger(.charging)?.isSatisfied, false)
        t.set(diagnostic: .charging(onAC: true))
        t.set(satisfied: true)
        XCTAssertEqual(engine.snapshot.trigger(.charging)?.isSatisfied, true)
        XCTAssertEqual(engine.snapshot.trigger(.charging)?.diagnostic, .charging(onAC: true))
    }

    func test_detailOnlyChange_updatesSnapshot_evenWhenSatisfiedUnchanged() {
        // 화면 2→3: satisfied는 계속 true지만 진단 상세는 갱신되어야 한다.
        let sm = makeSession()
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        let t = MockDiagnosingTrigger(kind: .externalDisplay, satisfied: true,
                                      diagnostic: .externalDisplay(screenCount: 2))
        engine.updateEvaluators([t])
        XCTAssertEqual(engine.snapshot.trigger(.externalDisplay)?.diagnostic,
                       .externalDisplay(screenCount: 2))
        t.set(diagnostic: .externalDisplay(screenCount: 3))
        XCTAssertEqual(engine.snapshot.trigger(.externalDisplay)?.diagnostic,
                       .externalDisplay(screenCount: 3))
    }

    func test_manualStopWhileSatisfied_snapshotShowsSuppressed_untilAllClear() {
        let sm = makeSession()
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        let t = MockDiagnosingTrigger(kind: .charging, satisfied: true,
                                      diagnostic: .charging(onAC: true))
        engine.updateEvaluators([t])
        XCTAssertTrue(sm.state.isActive)
        sm.stop()                                  // 수동 OFF → suppression
        XCTAssertTrue(engine.snapshot.isSuppressed)
        t.set(diagnostic: .charging(onAC: false))
        t.set(satisfied: false)                    // 모든 트리거 해제 → 재무장
        XCTAssertFalse(engine.snapshot.isSuppressed)
    }

    func test_updateEvaluatorsToEmpty_clearsSnapshotTriggers() {
        let sm = makeSession()
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        let t = MockDiagnosingTrigger(kind: .charging, satisfied: true,
                                      diagnostic: .charging(onAC: true))
        engine.updateEvaluators([t])
        XCTAssertFalse(engine.snapshot.triggers.isEmpty)
        engine.updateEvaluators([])
        XCTAssertEqual(engine.snapshot, .empty)
    }

    func test_snapshotPublisher_doesNotEmitDuplicates() {
        let sm = makeSession()
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        let t = MockDiagnosingTrigger(kind: .charging, satisfied: false,
                                      diagnostic: .charging(onAC: false))
        engine.updateEvaluators([t])
        var emissions = 0
        engine.$snapshot.dropFirst().sink { _ in emissions += 1 }.store(in: &cancellables)
        engine.updateEvaluators([t])   // 동일 인스턴스 재조정 → 스냅샷 내용 불변 → 발행 없음
        XCTAssertEqual(emissions, 0)
        t.set(diagnostic: .charging(onAC: true))   // 실제 변화 → 1회 발행
        XCTAssertEqual(emissions, 1)
    }

    // 회귀 가드: 스냅샷 배선(satisfied 이중 구독)이 기존 엔진 동작을 바꾸지 않아야 한다.
    func test_snapshotWiring_preservesSuppressionBehavior() {
        let sm = makeSession()
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        let t = MockDiagnosingTrigger(kind: .charging, satisfied: true,
                                      diagnostic: .charging(onAC: true))
        engine.updateEvaluators([t])
        XCTAssertTrue(sm.state.isActive)
        sm.stop()
        t.set(satisfied: true)                     // 재방출 — 억제 중 재시작 금지
        XCTAssertFalse(sm.state.isActive)
        t.set(satisfied: false)
        t.set(satisfied: true)                     // 재무장 후 재충족 → 재시작
        XCTAssertTrue(sm.state.isActive)
    }

    // stop()은 트리거를 전부 제거하므로 suppression도 해제되어 스냅샷이 .empty여야 한다
    // (M1: (triggers: [], isSuppressed: true)로 남는 상태 방지).
    func test_stopWhileSuppressed_clearsSuppressionInSnapshot() {
        let sm = makeSession()
        let engine = TriggerEngine(session: sm, scope: { .systemOnly })
        let t = MockDiagnosingTrigger(kind: .charging, satisfied: true,
                                      diagnostic: .charging(onAC: true))
        engine.updateEvaluators([t])
        XCTAssertTrue(sm.state.isActive)
        sm.stop()                                  // 수동 OFF → suppressed
        XCTAssertTrue(engine.snapshot.isSuppressed)
        engine.stop()
        XCTAssertEqual(engine.snapshot, .empty)
    }
}
