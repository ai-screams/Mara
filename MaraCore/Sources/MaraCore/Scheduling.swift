import Foundation

public protocol Clock { var now: Date { get } }

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

public protocol Cancellable { func cancel() }

public protocol Scheduling {
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> Cancellable
}

public final class DispatchScheduler: Scheduling {
    private let queue: DispatchQueue
    public init(queue: DispatchQueue = .main) { self.queue = queue }
    public func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> Cancellable {
        let item = DispatchWorkItem(block: action)
        queue.asyncAfter(deadline: .now() + interval, execute: item)
        return DispatchCancellable(item)
    }
    private final class DispatchCancellable: Cancellable {
        let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }
}
