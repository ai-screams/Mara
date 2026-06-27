import Foundation
import Combine

public final class SessionManager: ObservableObject {
    @Published public private(set) var state: SessionState = .inactive

    private let engine: SleepEngine
    private let scheduler: Scheduling
    private let clock: Clock
    private var timer: Cancellable?

    public init(engine: SleepEngine, scheduler: Scheduling, clock: Clock) {
        self.engine = engine
        self.scheduler = scheduler
        self.clock = clock
    }

    public func start(_ config: SessionConfig) {
        timer?.cancel(); timer = nil
        engine.apply(display: config.scope.keepsDisplayAwake, system: true)
        let expiresAt = expiry(for: config.duration)
        state = .active(config, expiresAt: expiresAt)
        // 타이머 무장은 Task 6에서 구현
    }

    public func stop() {
        timer?.cancel(); timer = nil
        engine.releaseAll()
        state = .inactive
    }

    public func toggle(_ config: SessionConfig) {
        state.isActive ? stop() : start(config)
    }

    private func expiry(for duration: SessionDuration) -> Date? {
        switch duration {
        case .indefinite: return nil
        case .duration(let t): return clock.now.addingTimeInterval(t)
        case .until(let date): return date
        }
    }
}
