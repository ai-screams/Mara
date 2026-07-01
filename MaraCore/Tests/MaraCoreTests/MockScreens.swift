import Combine
@testable import MaraCore

final class MockScreens: ScreenCounting {
    private let subject: CurrentValueSubject<Int, Never>
    init(count: Int = 1) { subject = CurrentValueSubject(count) }
    var screenCount: Int { subject.value }
    var changes: AnyPublisher<Int, Never> { subject.eraseToAnyPublisher() }
    func set(_ n: Int) { subject.send(n) }
}
