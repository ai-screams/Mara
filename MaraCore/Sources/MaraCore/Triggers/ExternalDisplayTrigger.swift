import Combine
import AppKit

public protocol ScreenCounting: AnyObject {
    var screenCount: Int { get }
    var changes: AnyPublisher<Int, Never> { get }
}

public final class NSScreenCounter: ScreenCounting {
    private let subject: CurrentValueSubject<Int, Never>
    private var observer: NSObjectProtocol?

    public init() {
        subject = CurrentValueSubject(NSScreen.screens.count)
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.subject.send(NSScreen.screens.count) }
    }
    public var screenCount: Int { subject.value }
    public var changes: AnyPublisher<Int, Never> { subject.eraseToAnyPublisher() }
    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }
}

public final class ExternalDisplayTrigger: TriggerEvaluator {
    public let kind: TriggerKind = .externalDisplay
    private let screens: ScreenCounting
    public init(screens: ScreenCounting) { self.screens = screens }

    public var isSatisfied: Bool { screens.screenCount > 1 }
    public var satisfied: AnyPublisher<Bool, Never> {
        screens.changes.map { $0 > 1 }.removeDuplicates().eraseToAnyPublisher()
    }
}

extension ExternalDisplayTrigger: TriggerDiagnosing {
    public var diagnostic: TriggerDiagnostic { .externalDisplay(screenCount: screens.screenCount) }
    public var diagnostics: AnyPublisher<TriggerDiagnostic, Never> {
        screens.changes
            .map { TriggerDiagnostic.externalDisplay(screenCount: $0) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
