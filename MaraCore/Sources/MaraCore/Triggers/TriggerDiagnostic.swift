import Combine

/// 트리거 1개의 진단 정보 — "왜 지금 충족/불충족인가"에 답하는 순수 값.
/// UI 문구는 App 계층이 렌더한다 (Core에 UI 문자열 금지).
public enum TriggerDiagnostic: Equatable, Sendable {
    case charging(onAC: Bool)
    case batteryUnavailable
    case externalDisplay(screenCount: Int)
    /// 감시 목록 ∩ 실행 중 — 매칭된 것만. 전체 실행 앱 목록은 노출하지 않는다.
    case appRunning(matched: Set<String>)
    case network(current: NetworkIdentity?, matched: Bool)
}

/// 진단을 제공하는 평가기의 보조 프로토콜. TriggerEvaluator 본체에 요구사항을 늘리면
/// 모든 구현체가 강제 오염되므로 분리한다 (ISP). 미채택 평가기는 diagnostic 없이 동작한다.
@MainActor
public protocol TriggerDiagnosing: AnyObject {
    var diagnostic: TriggerDiagnostic { get }
    /// satisfied(Bool·removeDuplicates)가 놓치는 상세 변화(화면 2→3, 매칭 앱 교체)까지 방출한다.
    var diagnostics: AnyPublisher<TriggerDiagnostic, Never> { get }
}

/// armed(엔진에 등록된) 트리거 1개의 스냅샷.
public struct TriggerSnapshot: Equatable, Sendable {
    public let kind: TriggerKind
    public let isSatisfied: Bool
    public let diagnostic: TriggerDiagnostic?   // TriggerDiagnosing 미채택 평가기는 nil

    public init(kind: TriggerKind, isSatisfied: Bool, diagnostic: TriggerDiagnostic?) {
        self.kind = kind
        self.isSatisfied = isSatisfied
        self.diagnostic = diagnostic
    }
}

/// 엔진 전체의 진단 스냅샷 — UI가 구독하는 read-only 값. suppression 변이 API는 없다.
public struct TriggerEngineSnapshot: Equatable, Sendable {
    /// TriggerKind.allCases 순서로 정렬된, 현재 armed 트리거 목록.
    public let triggers: [TriggerSnapshot]
    /// 수동 OFF로 인한 재시작 억제 중인지 (모든 트리거 해제 시 재무장).
    public let isSuppressed: Bool

    public static let empty = TriggerEngineSnapshot(triggers: [], isSuppressed: false)

    public init(triggers: [TriggerSnapshot], isSuppressed: Bool) {
        self.triggers = triggers
        self.isSuppressed = isSuppressed
    }

    public func trigger(_ kind: TriggerKind) -> TriggerSnapshot? {
        triggers.first { $0.kind == kind }
    }
}
