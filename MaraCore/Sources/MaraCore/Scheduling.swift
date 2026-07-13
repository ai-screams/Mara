import Foundation

@MainActor
public protocol Clock { var now: Date { get } }

@MainActor
public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

@MainActor
public protocol SchedulerToken { func cancel() }

@MainActor
public protocol Scheduling {
    /// `interval` 후 `action`을 **main 스레드에서** 전달한다.
    /// SessionManager의 타이머 콜백은 main-actor 격리를 가정(assumeIsolated)하므로,
    /// 준수 스케줄러는 반드시 main 스레드에서 `action`을 호출해야 한다(계약).
    func schedule(after interval: TimeInterval,
                  _ action: @escaping @MainActor @Sendable () -> Void) -> SchedulerToken
}

@MainActor
public final class DispatchScheduler: Scheduling {
    // main 큐 고정: 임의 큐 주입을 허용하면 SessionManager의 assumeIsolated가
    // off-main 발화 시 hard-trap한다. main 전달을 구조적으로 보장한다.
    public init() {}
    public func schedule(after interval: TimeInterval,
                         _ action: @escaping @MainActor @Sendable () -> Void) -> SchedulerToken {
        let item = DispatchWorkItem {
            MainActor.assumeIsolated { action() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
        return DispatchToken(item)
    }
    @MainActor
    private final class DispatchToken: SchedulerToken {
        let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }
}
