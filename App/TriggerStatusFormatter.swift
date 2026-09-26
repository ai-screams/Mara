import MaraCore

/// Core `TriggerStatusText` 결정 → 메뉴 상태 줄 문구(영어). 분기 로직은 Core(테스트됨)에, 문구만 여기.
/// (본판 SettingsView.triggerStatus를 메뉴 문맥에 맞게 옮긴 것 — "below" 대신 서브메뉴를 가리킨다.)
enum TriggerStatusFormatter {
    static func text(_ kind: TriggerKind, config: TriggerConfig, snapshot: TriggerEngineSnapshot) -> String? {
        guard let status = TriggerStatusText.evaluate(kind, config: config, snapshot: snapshot) else { return nil }
        switch status {
        case .needsWatchList(.appRunning): return "Pick apps under Watched Apps to activate"
        case .needsWatchList(.network):    return "Remember a network under Networks to activate"
        case .needsWatchList:              return "Add entries to activate"
        case .checking:                    return "Checking…"
        case .charging(_, let onAC):       return onAC ? "Active — on AC power" : "Inactive — on battery"
        case .batteryUnavailable:          return "Unavailable — can't read power source"
        case .externalDisplay(let active, let count):
            return active ? "Active — \(count) \(count == 1 ? "display" : "displays")" : "Inactive — built-in display only"
        case .appRunningSingle(_, let id): return "Active — \(id) running"
        case .appRunningMultiple(let count): return "Active — \(count) watched apps running"
        case .appRunningNone(let watched):
            return "Inactive — \(watched) \(watched == 1 ? "app" : "apps") watched, none running"
        case .network(let active, let mac, let matched):
            guard let mac else { return "Inactive — can't resolve gateway" }
            return matched ? "Active — \(mac)" : (active ? "Active" : "Inactive — different network")
        case .plain(let active):           return active ? "Active" : "Inactive"
        }
    }
}
