import Combine
import MaraCore

/// 세션 이벤트 → 알림 매핑. 원칙: 사용자가 직접 하지 않은 일만 알린다 —
/// 트리거 자동 시작, 그리고 자동 종료(타이머/저배터리/트리거 해제). 수동·교체는 침묵.
@MainActor
final class SessionNotifier {
    private var cancellable: AnyCancellable?

    init(session: SessionManager, isEnabled: @escaping () -> Bool, service: NotificationService) {
        cancellable = session.events.sink { event in
            MainActor.assumeIsolated {
                guard isEnabled(), let c = Self.content(for: event) else { return }
                service.post(title: c.title, body: c.body)
            }
        }
        // 런치 레이스 보정: AppEnvironment.init이 applicationDidFinishLaunching보다 먼저
        // 트리거를 조정해 세션을 열 수 있다. PassthroughSubject는 재방출하지 않으므로,
        // 구독 설정 후 현재 상태를 동기로 확인해 놓친 start 알림을 보상한다.
        // @MainActor이므로 init 완료 전 eventsSubject가 인터리브할 수 없어 이중 발송은 없다.
        if case .active(let cfg, _) = session.state,
           cfg.origin == .trigger,
           isEnabled(),
           let c = Self.content(for: SessionEvent(at: .now, kind: .started(cfg))) {
            service.post(title: c.title, body: c.body)
        }
    }

    /// nil = 알리지 않는 이벤트. 문구는 App 전용(영어) — Core enum에는 문자열이 없다.
    static func content(for event: SessionEvent) -> (title: String, body: String)? {
        switch event.kind {
        case .started(let cfg) where cfg.origin == .trigger:
            return ("Mara is keeping your Mac awake", "Started automatically by a trigger.")
        case .stopped(.timerExpired):
            return ("Keep-awake ended", "Timer expired.")
        case .stopped(.lowBattery(let percent)):
            return ("Keep-awake ended", "Low battery (\(percent)%) — session ended safely.")
        case .stopped(.triggerCleared):
            return ("Keep-awake ended", "Automation trigger cleared.")
        // 트리거 자동 시도가 거부됨 — 사용자가 안 한 일이라 배너로만 알린다(메뉴엔 안 띄운다).
        case .startRejected(let cfg, .lowBattery(let percent)) where cfg.origin == .trigger:
            return ("Mara didn't activate", "Low battery (\(percent)%) — kept off to protect your charge.")
        case .startRejected(let cfg, _) where cfg.origin == .trigger:
            return ("Mara didn't activate", "Keep-awake is unavailable right now.")
        case .started, .stopped(.manual), .stopped(.replacedByNewSession), .scopeChanged, .startRejected:
            return nil
        }
    }
}
