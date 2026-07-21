import Combine

@MainActor
public final class TriggerEngine: ObservableObject {
    private let session: SessionManager
    private let scope: () -> KeepAwakeScope

    // kind별 활성 평가기와 그 구독 (재조정 대상). diagnostics는 TriggerDiagnosing 채택 시에만.
    private var active: [TriggerKind: (evaluator: TriggerEvaluator,
                                       cancellable: AnyCancellable,
                                       diagnostics: AnyCancellable?)] = [:]
    private var sessionCancellable: AnyCancellable?
    private var eligibilityCancellable: AnyCancellable?
    private var suppressed = false {
        didSet { if suppressed != oldValue { refreshSnapshot() } }
    }
    // 재조정 중 중간 reevaluate()/refreshSnapshot() 호출을 막는 플래그
    private var reconciling = false

    /// 진단 스냅샷 — Settings 진단 패널이 구독하는 read-only 상태. 변이 API는 없다.
    @Published public private(set) var snapshot: TriggerEngineSnapshot = .empty

    public init(session: SessionManager, scope: @escaping () -> KeepAwakeScope) {
        self.session = session
        self.scope = scope
        // 수동 종료만 suppression으로 이어진다(README 계약: "수동으로 껐을 때만 재무장까지 억제").
        // 그래서 SessionState(active/inactive)가 아니라 종료 이유를 담은 이벤트를 구독한다 —
        // 저배터리/타이머/트리거해제 종료를 수동 억제로 오분류하지 않기 위함. delivery는 main.
        sessionCancellable = session.events.sink { [weak self] event in
            MainActor.assumeIsolated { self?.handleSessionEvent(event) }
        }
        // 저배터리로 거부/종료된 트리거 세션이 전원 회복 후 재개되도록: eligibility가
        // blocked→allowed로 바뀌는 에지에서만 재평가한다. dropFirst로 구독 시 현재값 replay를
        // 흘리고, removeDuplicates로 동일 상태 반복 발행에 대한 busy-retry를 차단한다(전원
        // assertion 실패 같은 일시적 실패는 eligibility를 바꾸지 않으므로 여기서 루프를 만들지 않는다).
        eligibilityCancellable = session.$startEligibility
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] eligibility in
                MainActor.assumeIsolated {
                    guard eligibility == .allowed else { return }
                    self?.reevaluate()
                }
            }
    }

    public var isAnySatisfied: Bool { active.values.contains { $0.evaluator.isSatisfied } }

    /// 원하는 평가기 목록으로 구독을 재조정한다. kind별 하나를 가정한다.
    /// 변하지 않은 kind는 구독을 유지하고, 추가/교체/제거만 반영한다. suppression은 보존된다.
    public func updateEvaluators(_ evaluators: [TriggerEvaluator]) {
        let desired = Dictionary(evaluators.map { ($0.kind, $0) }, uniquingKeysWith: { _, last in last })
        reconciling = true
        // 제거된 kind
        for kind in active.keys where desired[kind] == nil {
            active[kind] = nil   // AnyCancellable deinit → 구독 해제
        }
        // 추가되거나 인스턴스가 바뀐 kind
        for (kind, evaluator) in desired {
            if active[kind]?.evaluator === evaluator { continue }   // 동일 인스턴스 → 유지
            let c = evaluator.satisfied.sink { [weak self] _ in
                MainActor.assumeIsolated { self?.reevaluate() }
            }
            // 진단 상세 변화(satisfied Bool로는 안 잡히는 화면 수·매칭 앱 변화) → 스냅샷 갱신.
            // 어댑터 publisher는 CurrentValueSubject 파생(didSet)이라 sink에서 현재값 재-read가 안전
            // (@Published willSet 규칙과 다른 케이스). 구독 시 동기 replay는 reconciling 가드가 흡수.
            let d = (evaluator as? TriggerDiagnosing)?.diagnostics.sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSnapshot() }
            }
            active[kind] = (evaluator, c, d)
        }
        reconciling = false
        // 재조정 완료 후 딱 한 번만 평가 — 스냅샷 갱신은 reevaluate()의 defer가 담당한다.
        reevaluate()
    }

    public func stop() {
        active.removeAll()
        sessionCancellable = nil
        eligibilityCancellable = nil
        // 트리거가 전부 사라졌으므로 suppression도 해제 — "모든 트리거 해제 시 재무장" 정의와 일관,
        // 스냅샷이 (triggers: [], isSuppressed: true)로 남는 어정쩡한 상태를 막는다.
        suppressed = false
        // trigger-origin 세션이 활성이면 함께 종료 (orphan 방지)
        if case let .active(cfg, _) = session.state, cfg.origin == .trigger {
            session.stop(reason: .triggerCleared)
        }
        refreshSnapshot()
    }

    private func handleSessionEvent(_ event: SessionEvent) {
        // 수동 종료(.manual)만 suppression으로 이어진다. 트리거가 여전히 충족 중이면 재무장 전까지 억제.
        // 저배터리·타이머·트리거해제 종료는 억제하지 않는다 — 저배터리 종료는 전원 회복 후
        // eligibility 에지로 재개되고, 그 사이 UI에도 "manually"로 오표기되지 않는다.
        if case .stopped(.manual) = event.kind, isAnySatisfied {
            suppressed = true
        }
    }

    private func reevaluate() {
        guard !reconciling else { return }   // 재조정 중 중간 호출 → no-op
        defer { refreshSnapshot() }          // satisfied 변화도 스냅샷에 반영
        guard isAnySatisfied else {
            suppressed = false   // 모든 트리거 false → 재무장
            if case let .active(cfg, _) = session.state, cfg.origin == .trigger {
                session.stop(reason: .triggerCleared)
            }
            return
        }
        guard !suppressed else { return }
        if !session.state.isActive {
            session.start(SessionConfig(scope: scope(), duration: .indefinite, origin: .trigger))
        }
        // 이미 활성(수동 포함)이면 no-op — 수동 > 트리거
    }

    /// active 목록·만족 여부·진단·suppression으로 스냅샷 재구성. 동일 값이면 발행하지 않는다.
    private func refreshSnapshot() {
        guard !reconciling else { return }   // 부분 재조정 상태의 중간 스냅샷 발행 금지
        let triggers = TriggerKind.allCases.compactMap { kind -> TriggerSnapshot? in
            guard let entry = active[kind] else { return nil }
            return TriggerSnapshot(kind: kind,
                                   isSatisfied: entry.evaluator.isSatisfied,
                                   diagnostic: (entry.evaluator as? TriggerDiagnosing)?.diagnostic)
        }
        let next = TriggerEngineSnapshot(triggers: triggers, isSuppressed: suppressed)
        if next != snapshot { snapshot = next }
    }
}
