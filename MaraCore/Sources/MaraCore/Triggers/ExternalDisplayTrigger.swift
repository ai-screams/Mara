import Combine
import AppKit
import CoreGraphics

public struct ScreenSnapshot: Equatable, Sendable {
    public let totalCount: Int
    public let externalCount: Int

    public init(totalCount: Int, externalCount: Int) {
        self.totalCount = max(0, totalCount)
        self.externalCount = min(max(0, externalCount), self.totalCount)
    }
}

@MainActor
public protocol ScreenCounting: AnyObject {
    var snapshot: ScreenSnapshot { get }
    var changes: AnyPublisher<ScreenSnapshot, Never> { get }
}

@MainActor
public final class NSScreenCounter: ScreenCounting {
    private let subject: CurrentValueSubject<ScreenSnapshot, Never>
    private var observer: NSObjectProtocol?

    public init() {
        subject = CurrentValueSubject(Self.readSnapshot())
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.subject.send(Self.readSnapshot()) }
        }
    }
    public var snapshot: ScreenSnapshot { subject.value }
    public var changes: AnyPublisher<ScreenSnapshot, Never> { subject.eraseToAnyPublisher() }
    deinit {
        MainActor.assumeIsolated {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }

    private static func readSnapshot() -> ScreenSnapshot {
        let screens = NSScreen.screens
        let externalCount = screens.reduce(into: 0) { count, screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? NSNumber else { return }
            if CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) == 0 {
                count += 1
            }
        }
        return ScreenSnapshot(totalCount: screens.count, externalCount: externalCount)
    }
}

@MainActor
public final class ExternalDisplayTrigger: TriggerEvaluator {
    public let kind: TriggerKind = .externalDisplay
    private let screens: ScreenCounting
    public init(screens: ScreenCounting) { self.screens = screens }

    public var isSatisfied: Bool { screens.snapshot.externalCount > 0 }
    public var satisfied: AnyPublisher<Bool, Never> {
        screens.changes.map { $0.externalCount > 0 }.removeDuplicates().eraseToAnyPublisher()
    }
}

extension ExternalDisplayTrigger: TriggerDiagnosing {
    public var diagnostic: TriggerDiagnostic { .externalDisplay(screenCount: screens.snapshot.totalCount) }
    public var diagnostics: AnyPublisher<TriggerDiagnostic, Never> {
        screens.changes
            .map { TriggerDiagnostic.externalDisplay(screenCount: $0.totalCount) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
