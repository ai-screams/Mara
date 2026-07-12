import Foundation

/// keep-awake 상태 스냅샷 — Shortcuts/외부 명령 소비자용 읽기 값.
/// remaining은 유한 세션의 남은 초(무기한이면 nil), isTriggered는 트리거 시스템이 현재 세션을 소유 중인지.
public struct KeepAwakeStatus: Equatable {
    public let isActive: Bool
    public let remaining: TimeInterval?
    public let isTriggered: Bool
    public init(isActive: Bool, remaining: TimeInterval?, isTriggered: Bool) {
        self.isActive = isActive
        self.remaining = remaining
        self.isTriggered = isTriggered
    }
}

/// keep-awake 세션의 좁은 명령 표면 — App Intents 어댑터가 SessionManager 전체 대신 이것만 참조한다.
/// 목적은 표면 축소(경계 명시)이며, Core의 프로토콜-뒤 스타일(TriggerEvaluator/Clock 등)과 일치한다.
@MainActor
public protocol SessionCommanding {
    /// duration=nil이면 무기한, 유한이면 [0, 24h]로 클램프해 시작한다. origin은 .manual.
    func startKeepAwake(duration: TimeInterval?)
    /// 수동 종료(.manual). 비활성이면 무해한 no-op.
    func stopKeepAwake()
    func status() -> KeepAwakeStatus
}

/// SessionCommanding의 프로덕션 구현 — 클램프·SessionConfig 조립·상태 매핑(순수 결정, 테스트 대상).
/// OS 부작용은 주입된 SessionManager가 담당하고, scope는 App이 클로저로 주입(기존 TriggerEngine 패턴).
@MainActor
public final class SessionCommander: SessionCommanding {
    /// duration 클램프 상한. UI(CustomKeepAwakeView 0…24h 스테퍼)와 동일 범위를 Shortcuts 경로에도 강제.
    public static let maxDuration: TimeInterval = 24 * 3600

    private let session: SessionManager
    private let scope: () -> KeepAwakeScope
    private let clock: Clock

    public init(session: SessionManager, scope: @escaping () -> KeepAwakeScope, clock: Clock) {
        self.session = session
        self.scope = scope
        self.clock = clock
    }

    public func startKeepAwake(duration: TimeInterval?) {
        let sessionDuration: SessionDuration
        if let duration {
            // 비유한(NaN/∞)은 클램프를 우회한다 — Swift의 min/max는 NaN 비교가 false라 NaN을 그대로 통과시킨다.
            // 신뢰 불가 입력은 0으로 안전 축퇴(코드베이스 관례: DurationFormat/PrefsStore도 비유한→0/drop).
            // keep-awake 도구에선 "쓰레기 입력 → 무기한 유지"보다 "→ 유지 안 함"이 fail-safe.
            let clamped = duration.isFinite ? min(max(duration, 0), Self.maxDuration) : 0
            sessionDuration = .duration(clamped)
        } else {
            sessionDuration = .indefinite
        }
        session.start(SessionConfig(scope: scope(), duration: sessionDuration, origin: .manual))
    }

    public func stopKeepAwake() {
        session.stop(reason: .manual)
    }

    public func status() -> KeepAwakeStatus {
        guard case let .active(cfg, expiresAt) = session.state else {
            return KeepAwakeStatus(isActive: false, remaining: nil, isTriggered: false)
        }
        let remaining = expiresAt.map { max(0, $0.timeIntervalSince(clock.now)) }
        return KeepAwakeStatus(isActive: true, remaining: remaining, isTriggered: cfg.origin == .trigger)
    }
}
