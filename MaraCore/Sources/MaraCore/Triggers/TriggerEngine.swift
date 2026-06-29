import Combine

public final class TriggerEngine {
    private let session: SessionManager
    private let evaluators: [TriggerEvaluator]
    private let scope: KeepAwakeScope
    private var cancellables = Set<AnyCancellable>()
    private var running = false

    public init(session: SessionManager, evaluators: [TriggerEvaluator], scope: KeepAwakeScope) {
        self.session = session
        self.evaluators = evaluators
        self.scope = scope
    }

    public var isAnySatisfied: Bool { evaluators.contains { $0.isSatisfied } }

    public func start() {
        guard !running else { return }
        running = true
        // 각 평가기의 변화를 구독 → 매 변화마다 OR 재평가
        for e in evaluators {
            e.satisfied
                .sink { [weak self] _ in self?.reevaluate() }
                .store(in: &cancellables)
        }
        reevaluate()
    }

    public func stop() {
        running = false
        cancellables.removeAll()
    }

    private func reevaluate() {
        let any = isAnySatisfied
        if any {
            if !session.state.isActive {
                session.start(SessionConfig(scope: scope, duration: .indefinite, origin: .trigger))
            }
        } else {
            if case let .active(cfg, _) = session.state, cfg.origin == .trigger {
                session.stop()
            }
        }
    }
}
