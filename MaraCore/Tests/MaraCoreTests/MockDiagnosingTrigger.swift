import Foundation
import Combine
@testable import MaraCore

/// satisfied와 diagnostic을 독립적으로 조작할 수 있는 진단 제공 목.
/// (기존 MockTrigger는 TriggerDiagnosing 미채택 상태로 유지 — 미채택 경로(diagnostic == nil) 검증에 쓴다.)
@MainActor
final class MockDiagnosingTrigger: TriggerEvaluator, TriggerDiagnosing {
    let kind: TriggerKind
    private let satisfiedSubject: CurrentValueSubject<Bool, Never>
    private let diagSubject: CurrentValueSubject<TriggerDiagnostic, Never>

    init(kind: TriggerKind = .externalDisplay, satisfied: Bool = false,
         diagnostic: TriggerDiagnostic = .externalDisplay(screenCount: 1)) {
        self.kind = kind
        satisfiedSubject = CurrentValueSubject(satisfied)
        diagSubject = CurrentValueSubject(diagnostic)
    }

    var isSatisfied: Bool { satisfiedSubject.value }
    var satisfied: AnyPublisher<Bool, Never> { satisfiedSubject.eraseToAnyPublisher() }
    var diagnostic: TriggerDiagnostic { diagSubject.value }
    var diagnostics: AnyPublisher<TriggerDiagnostic, Never> { diagSubject.eraseToAnyPublisher() }

    func set(satisfied: Bool) { satisfiedSubject.send(satisfied) }
    func set(diagnostic: TriggerDiagnostic) { diagSubject.send(diagnostic) }
}
