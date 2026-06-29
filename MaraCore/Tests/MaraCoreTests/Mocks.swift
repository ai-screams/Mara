import Foundation
@testable import MaraCore

final class MockPowerAssertionProvider: PowerAssertionProviding {
    private(set) var live: [PowerAssertionToken: PowerAssertionType] = [:]
    private var nextID: UInt32 = 1
    var failNextCreate = false

    func create(type: PowerAssertionType, name: String) -> PowerAssertionToken? {
        if failNextCreate { failNextCreate = false; return nil }
        let token = PowerAssertionToken(id: nextID); nextID += 1
        live[token] = type
        return token
    }
    func release(_ token: PowerAssertionToken) { live[token] = nil }
}

final class MockClock: Clock {
    var now: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) { now = start }
}

final class MockScheduler: Scheduling {
    final class Pending { let fire: () -> Void; var cancelled = false; init(_ f: @escaping () -> Void) { fire = f } }
    private(set) var pending: [Pending] = []
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> Cancellable {
        let p = Pending(action); pending.append(p)
        return C(p)
    }
    /// 테스트에서 수동으로 타이머 발화
    func fireAll() { pending.filter { !$0.cancelled }.forEach { $0.fire() } }
    private final class C: Cancellable { let p: Pending; init(_ p: Pending) { self.p = p }; func cancel() { p.cancelled = true } }
}
