import Foundation

public protocol Clock { var now: Date { get } }

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

public protocol SchedulerToken { func cancel() }

public protocol Scheduling {
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> SchedulerToken
}

public final class DispatchScheduler: Scheduling {
    private let queue: DispatchQueue
    public init(queue: DispatchQueue = .main) { self.queue = queue }
    public func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> SchedulerToken {
        let item = DispatchWorkItem(block: action)
        queue.asyncAfter(deadline: .now() + interval, execute: item)
        return DispatchToken(item)
    }
    private final class DispatchToken: SchedulerToken {
        let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }
}
