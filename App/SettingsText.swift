import Foundation
import MaraCore

/// 설정 창의 상태 줄·최근 이벤트 문구(영어). 분기는 Core가 정하고 여기서는 문구만 고른다
/// (SessionFailureText·TriggerKindText와 같은 규칙: Core에는 UI 문자열을 두지 않는다).
/// 앱 이름 조회(`InstalledAppInfo.lookup`)가 메인 액터 전용이라, View 안에 있던 때와 같은 격리를 유지한다.
@MainActor
enum SettingsText {
    // MARK: - Trigger diagnostics formatter

    /// Core `TriggerStatusText` 결정 → 표시 문구(영어) 매핑. 토글 OFF면 nil(행 숨김).
    /// 분기 로직은 Core(`TriggerStatusText.evaluate`, 테스트됨)에 있고, 이 함수는 문구 렌더링만 맡는다.
    static func triggerStatus(_ kind: TriggerKind, config: TriggerConfig, snapshot: TriggerEngineSnapshot)
        -> (active: Bool, text: String)? {
        guard let status = TriggerStatusText.evaluate(kind, config: config, snapshot: snapshot) else { return nil }
        switch status {
        case .needsWatchList(.appRunning):
            return (false, "Add an app below to activate")
        case .needsWatchList(.network):
            return (false, "Remember a network below to activate")
        case .needsWatchList:
            return (false, "Add entries below to activate")   // 도달 불가(appRunning/network만) — 망라성용
        case .checking:
            return (false, "Checking…")
        case .charging(let active, let onAC):
            return (active, onAC ? "Active — on AC power" : "Inactive — on battery")
        case .batteryUnavailable:
            return (false, "Unavailable — can't read power source")
        case .externalDisplay(let active, let count):
            return externalDisplayStatus(active: active, count: count)
        case .appRunningSingle(let active, let id):
            // 감시 목록과 같은 이름으로 — 설치되지 않은 ID는 ID 그대로.
            return (active, "Active — \(InstalledAppInfo.lookup(id)?.name ?? id) running")
        case .appRunningMultiple(let count):
            return (true, "Active — \(count) watched apps running")
        case .appRunningNone(let watched):
            return appRunningNoneStatus(watched: watched)
        case .network(let active, let mac, let matched):
            return networkStatus(active: active, label: mac.map { config.networkDisplayName($0) ?? $0 }, matched: matched)
        case .plain(let active):
            return (active, active ? "Active" : "Inactive")
        }
    }

    private static func externalDisplayStatus(active: Bool, count: Int) -> (active: Bool, text: String) {
        (active, active
            ? "Active — \(count) \(count == 1 ? "display" : "displays")"
            : "Inactive — built-in display only")
    }

    private static func appRunningNoneStatus(watched: Int) -> (active: Bool, text: String) {
        // 감시 개수를 함께 표기 — 오타 가능성 vs 앱 미실행으로 가설을 좁힐 수 있게 한다.
        (false, "Inactive — \(watched) \(watched == 1 ? "app" : "apps") watched, none running")
    }

    /// label: 지금 네트워크의 표시 이름(이름이 있으면 이름, 없으면 MAC). nil이면 게이트웨이 MAC을 못 읽은 것 —
    /// VPN·테더링이나 macOS 27의 ARP 제한. 그 이유를 이 한 줄이 말한다(목록 아래에 따로 두지 않는다).
    private static func networkStatus(active: Bool, label: String?, matched: Bool) -> (active: Bool, text: String) {
        guard let label else { return (active, "Inactive — can't identify this network (VPN or tethering?)") }
        return (active, matched ? "Active — \(label)" : "Inactive — not on a remembered network")
    }

    // MARK: - Event formatter

    /// 최근 이벤트 한 줄 요약(영어, 문장형 대문자) — 메뉴를 로그 뷰어로 만들지 않는다는 원칙에 따라 1개만.
    static func eventLine(_ event: SessionEvent) -> String {
        let time = event.at.formatted(date: .omitted, time: .shortened)
        switch event.kind {
        case .started(let cfg):
            if case let .trigger(kind) = cfg.origin {
                return "Started by \(TriggerKindText.name(kind)) · \(time)"
            }
            return "Started · \(time)"
        case .stopped(.manual):               return "Turned off · \(time)"
        case .stopped(.timerExpired):         return "Timer expired · \(time)"
        case .stopped(.lowBattery(let p)):    return "Ended — low battery \(p)% · \(time)"
        case .stopped(.triggerCleared):       return "Ended — trigger cleared · \(time)"
        case .stopped(.replacedByNewSession): return "Restarted · \(time)"
        case .scopeChanged:                   return "Scope changed · \(time)"
        case .startRejected(_, .lowBattery(let p)): return "Didn't start — low battery \(p)% · \(time)"
        case .startRejected:                  return "Didn't start · \(time)"
        }
    }
}
