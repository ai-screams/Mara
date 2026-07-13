import Foundation
@testable import MaraCore

@MainActor
final class MockPowerAssertionProvider: PowerAssertionProviding {
    private(set) var live: [PowerAssertionToken: PowerAssertionType] = [:]
    private var nextID: UInt32 = 1
    var failNextCreate = false
    var failNextRelease = false
    var failingCreateTypes: Set<PowerAssertionType> = []

    func create(type: PowerAssertionType,
                name: String) -> Result<PowerAssertionToken, PowerAssertionFailure> {
        if failNextCreate || failingCreateTypes.remove(type) != nil {
            failNextCreate = false
            return .failure(.creationFailed(type: type, code: -1))
        }
        let token = PowerAssertionToken(id: nextID); nextID += 1
        live[token] = type
        return .success(token)
    }
    func release(_ token: PowerAssertionToken) -> Result<Void, PowerAssertionFailure> {
        if failNextRelease {
            failNextRelease = false
            return .failure(.releaseFailed(token: token, code: -2))
        }
        live[token] = nil
        return .success(())
    }
}

@MainActor
final class MockClock: Clock {
    var now: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) { now = start }
}

@MainActor
final class MockScheduler: Scheduling {
    final class Pending {
        let fire: @MainActor @Sendable () -> Void
        var cancelled = false
        init(_ fire: @escaping @MainActor @Sendable () -> Void) { self.fire = fire }
    }
    private(set) var pending: [Pending] = []
    func schedule(after interval: TimeInterval,
                  _ action: @escaping @MainActor @Sendable () -> Void) -> SchedulerToken {
        let p = Pending(action); pending.append(p)
        return MockToken(p)
    }
    /// 테스트에서 수동으로 타이머 발화
    func fireAll() { pending.filter { !$0.cancelled }.forEach { $0.fire() } }
    @MainActor
    private final class MockToken: SchedulerToken {
        let p: Pending
        init(_ p: Pending) { self.p = p }
        func cancel() { p.cancelled = true }
    }
}
