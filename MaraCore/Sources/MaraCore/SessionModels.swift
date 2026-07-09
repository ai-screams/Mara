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

/// 세션이 꺼진 이유. UI 문자열 없이 도메인 의미만 담는다(문구는 App 레이어 책임).
public enum SessionStopReason: Equatable {
    case manual
    case timerExpired
    case lowBattery(percent: Int)
    case triggerCleared
    case replacedByNewSession
}

/// 세션 수명 이벤트. SessionManager가 최근 이력을 bounded로 보관하고 publisher로도 방출한다.
public struct SessionEvent: Equatable {
    public enum Kind: Equatable {
        case started(SessionConfig)
        case stopped(SessionStopReason)
        case scopeChanged(KeepAwakeScope)
    }
    public let at: Date
    public let kind: Kind
    public init(at: Date, kind: Kind) {
        self.at = at
        self.kind = kind
    }
}
