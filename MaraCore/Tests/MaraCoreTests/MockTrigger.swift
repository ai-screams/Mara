import Foundation
import Combine
@testable import MaraCore

final class MockTrigger: TriggerEvaluator {
    let kind: TriggerKind
    private let subject: CurrentValueSubject<Bool, Never>
    init(kind: TriggerKind = .charging, satisfied: Bool = false) {
        self.kind = kind
        subject = CurrentValueSubject(satisfied)
    }
    var isSatisfied: Bool { subject.value }
    var satisfied: AnyPublisher<Bool, Never> { subject.eraseToAnyPublisher() }
    func set(_ value: Bool) { subject.send(value) }
}
