import Combine
@testable import MaraCore

@MainActor
final class MockScreens: ScreenCounting {
    private let subject: CurrentValueSubject<ScreenSnapshot, Never>
    init(count: Int = 1, externalCount: Int? = nil) {
        subject = CurrentValueSubject(ScreenSnapshot(
            totalCount: count,
            externalCount: externalCount ?? max(0, count - 1)
        ))
    }
    var snapshot: ScreenSnapshot { subject.value }
    var changes: AnyPublisher<ScreenSnapshot, Never> { subject.eraseToAnyPublisher() }
    func set(_ count: Int, externalCount: Int? = nil) {
        subject.send(ScreenSnapshot(
            totalCount: count,
            externalCount: externalCount ?? max(0, count - 1)
        ))
    }
}
