import Foundation

public enum KeepAwakeScope: Equatable, Sendable {
    case systemOnly
    case displayAndSystem
    public var keepsDisplayAwake: Bool { self == .displayAndSystem }
}

public extension KeepAwakeScope {
    init(keepDisplay: Bool) {
        self = keepDisplay ? .displayAndSystem : .systemOnly
    }
}

public enum SessionDuration: Equatable, Sendable {
    case indefinite
    case duration(TimeInterval)
    case until(Date)
}

public extension SessionDuration {
    static let maximumFiniteInterval: TimeInterval = 24 * 3600
}

public enum SessionOrigin: Equatable, Sendable {
    case manual
    case trigger
}

public struct SessionConfig: Equatable, Sendable {
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

public enum SessionState: Equatable, Sendable {
    case inactive
    case active(SessionConfig, expiresAt: Date?)
    public var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}

/// 세션이 꺼진 이유. UI 문자열 없이 도메인 의미만 담는다(문구는 App 레이어 책임).
public enum SessionStopReason: Equatable, Sendable {
    case manual
    case timerExpired
    case lowBattery(percent: Int)
    case triggerCleared
    case replacedByNewSession
}

/// 세션 수명 이벤트. SessionManager가 최근 이력을 bounded로 보관하고 publisher로도 방출한다.
public struct SessionEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case started(SessionConfig)
        case stopped(SessionStopReason)
        case scopeChanged(KeepAwakeScope)
        /// 시작이 거부됨(예: 저배터리). config로 origin을 알 수 있어 App이 알림/문구를
        /// 분기한다(트리거 자동 시도 실패를 배너로, 수동은 조용히).
        case startRejected(SessionConfig, SessionFailure)
    }
    public let at: Date
    public let kind: Kind
    public init(at: Date, kind: Kind) {
        self.at = at
        self.kind = kind
    }
}

public enum SessionFailure: Error, Equatable, Sendable {
    case lowBattery(percent: Int)
    case invalidDuration
    case invalidUntilDate
    case power(SleepEngineFailure)
}
