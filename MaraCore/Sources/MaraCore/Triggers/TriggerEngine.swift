import Combine

public final class TriggerEngine {
    private let session: SessionManager
    private let evaluators: [TriggerEvaluator]
    private let scope: KeepAwakeScope
    private var cancellables = Set<AnyCancellable>()
    private var running = false
    private var suppressed = false
    private var lastActive = false   // 직전 세션 활성 여부 (수동 stop 감지용)

    public init(session: SessionManager, evaluators: [TriggerEvaluator], scope: KeepAwakeScope) {
        self.session = session
        self.evaluators = evaluators
        self.scope = scope
    }

    public var isAnySatisfied: Bool { evaluators.contains { $0.isSatisfied } }

    public func start() {
        guard !running else { return }
        running = true
        lastActive = session.state.isActive
        // 각 평가기의 변화를 구독 → 매 변화마다 OR 재평가
        for e in evaluators {
            e.satisfied
                .sink { [weak self] _ in self?.reevaluate() }
                .store(in: &cancellables)
        }
        // 세션 상태 변화 구독 → 수동 종료 감지 및 suppression 적용
        session.$state
            .sink { [weak self] state in self?.handleSessionChange(state) }
            .store(in: &cancellables)
        reevaluate()
    }

    public func stop() {
        running = false
        cancellables.removeAll()
    }

    private func handleSessionChange(_ state: SessionState) {
        let active = state.isActive
        // 세션이 active → inactive 로 떨어졌는데 트리거가 여전히 충족이면,
        // 이는 사용자/타이머/배터리에 의한 종료이므로 트리거 재가동을 억제한다(재무장 전까지).
        if lastActive && !active && isAnySatisfied {
            suppressed = true
        }
        lastActive = active
    }

    private func reevaluate() {
        let any = isAnySatisfied
        if !any {
            suppressed = false   // 모든 트리거가 false → 재무장
            if case let .active(cfg, _) = session.state, cfg.origin == .trigger {
                session.stop()
            }
            return
        }
        // any == true
        guard !suppressed else { return }
        if !session.state.isActive {
            session.start(SessionConfig(scope: scope, duration: .indefinite, origin: .trigger))
        }
        // 세션이 이미 활성(수동 포함)이면 아무것도 안 함 — 수동 > 트리거
    }
}
