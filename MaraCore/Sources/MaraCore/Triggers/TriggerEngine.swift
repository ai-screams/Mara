import Combine

@MainActor
public final class TriggerEngine {
    private let session: SessionManager
    private let scope: () -> KeepAwakeScope

    // kind별 활성 평가기와 그 구독 (재조정 대상)
    private var active: [TriggerKind: (evaluator: TriggerEvaluator, cancellable: AnyCancellable)] = [:]
    private var sessionCancellable: AnyCancellable?
    private var suppressed = false
    private var lastActive = false
    // 재조정 중 중간 reevaluate() 호출을 막는 플래그
    private var reconciling = false

    public init(session: SessionManager, scope: @escaping () -> KeepAwakeScope) {
        self.session = session
        self.scope = scope
        self.lastActive = session.state.isActive
        // 세션 상태 구독은 수명 내내 유지 (수동 종료 감지 → suppression)
        // @Published state는 main-actor SessionManager에서만 변이되므로 delivery도 main.
        sessionCancellable = session.$state.sink { [weak self] state in
            MainActor.assumeIsolated { self?.handleSessionChange(state) }
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
            active[kind] = (evaluator, c)
        }
        reconciling = false
        reevaluate()   // 재조정 완료 후 딱 한 번만 평가
    }

    public func stop() {
        active.removeAll()
        sessionCancellable = nil
        // trigger-origin 세션이 활성이면 함께 종료 (orphan 방지)
        if case let .active(cfg, _) = session.state, cfg.origin == .trigger {
            session.stop(reason: .triggerCleared)
        }
    }

    private func handleSessionChange(_ state: SessionState) {
        let isActive = state.isActive
        // active → inactive 인데 트리거가 여전히 충족이면, 사용자/타이머/배터리 종료이므로 재무장 전까지 억제.
        if lastActive && !isActive && isAnySatisfied {
            suppressed = true
        }
        lastActive = isActive
    }

    private func reevaluate() {
        guard !reconciling else { return }   // 재조정 중 중간 호출 → no-op
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
}
