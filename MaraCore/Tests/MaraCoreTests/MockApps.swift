import Combine
@testable import MaraCore

final class MockApps: RunningAppsObserving {
    private let subject: CurrentValueSubject<Set<String>, Never>
    init(_ ids: Set<String> = []) { subject = CurrentValueSubject(ids) }
    var runningBundleIDs: Set<String> { subject.value }
    var changes: AnyPublisher<Set<String>, Never> { subject.eraseToAnyPublisher() }
    func set(_ ids: Set<String>) { subject.send(ids) }
}
