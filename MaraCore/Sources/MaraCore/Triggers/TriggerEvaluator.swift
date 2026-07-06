import Combine

public enum TriggerKind: String, CaseIterable, Sendable {
    case charging
    case externalDisplay
    case appRunning
    case network
}

public protocol TriggerEvaluator: AnyObject {
    var kind: TriggerKind { get }
    var isSatisfied: Bool { get }
    var satisfied: AnyPublisher<Bool, Never> { get }
}
