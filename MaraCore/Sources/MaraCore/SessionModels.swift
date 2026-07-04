import Foundation

public enum KeepAwakeScope: Equatable {
    case systemOnly
    case displayAndSystem
    public var keepsDisplayAwake: Bool { self == .displayAndSystem }
}

public extension KeepAwakeScope {
    init(keepDisplay: Bool) {
        self = keepDisplay ? .displayAndSystem : .systemOnly
    }
}

public enum SessionDuration: Equatable {
    case indefinite
    case duration(TimeInterval)
    case until(Date)
}

public enum SessionOrigin: Equatable {
    case manual
    case trigger
}

public struct SessionConfig: Equatable {
    public var scope: KeepAwakeScope
    public var duration: SessionDuration
    public var origin: SessionOrigin
    public init(scope: KeepAwakeScope, duration: SessionDuration, origin: SessionOrigin) {
        self.scope = scope; self.duration = duration; self.origin = origin
    }
}

public extension SessionConfig {
    func withScope(_ scope: KeepAwakeScope) -> SessionConfig {
        SessionConfig(scope: scope, duration: duration, origin: origin)
    }
}

public enum SessionState: Equatable {
    case inactive
    case active(SessionConfig, expiresAt: Date?)
    public var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}
