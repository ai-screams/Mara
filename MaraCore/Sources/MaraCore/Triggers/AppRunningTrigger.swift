import Combine
import AppKit

public protocol RunningAppsObserving: AnyObject {
    var runningBundleIDs: Set<String> { get }
    var changes: AnyPublisher<Set<String>, Never> { get }
}

public final class NSWorkspaceAppsObserver: RunningAppsObserving {
    private let subject: CurrentValueSubject<Set<String>, Never>
    private var observers: [NSObjectProtocol] = []

    public init() {
        subject = CurrentValueSubject(Self.snapshot())
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.subject.send(Self.snapshot())
            })
        }
    }

    private static func snapshot() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
    }

    public var runningBundleIDs: Set<String> { subject.value }
    public var changes: AnyPublisher<Set<String>, Never> { subject.eraseToAnyPublisher() }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        observers.forEach { nc.removeObserver($0) }
    }
}

public final class AppRunningTrigger: TriggerEvaluator {
    public let kind: TriggerKind = .appRunning
    private let apps: RunningAppsObserving
    private let watched: Set<String>

    public init(apps: RunningAppsObserving, watched: Set<String>) {
        self.apps = apps
        self.watched = watched
    }

    public var isSatisfied: Bool { !apps.runningBundleIDs.isDisjoint(with: watched) }

    public var satisfied: AnyPublisher<Bool, Never> {
        let watched = self.watched
        return apps.changes
            .map { !$0.isDisjoint(with: watched) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
