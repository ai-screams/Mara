/// 트리거 진단 행의 **표시 결정**(어떤 상태를 보여줄지)만 담는 순수 값 — UI 문구는 없다.
/// `TriggerDiagnostic`(왜 충족/불충족인가)에서 한 단계 더 나아가, config·snapshot을 합쳐
/// "행을 숨길지 / 활성화 안내를 낼지 / 재조정 중인지 / 어떤 활성·비활성 상태인지"를 고른다.
/// App 계층이 이 값을 영어 문구로 렌더한다(Core에 UI 문자열 금지 규칙 유지).
public enum TriggerStatusText: Equatable, Sendable {
    /// enabled인데 감시 목록이 비어 armed되지 않음 — 목록 추가 안내 대상(appRunning/network).
    case needsWatchList(TriggerKind)
    /// 설정 반영 debounce(300ms) 중이라 스냅샷에 아직 없음(일시 상태).
    case checking
    case charging(active: Bool, onAC: Bool)
    case batteryUnavailable
    case externalDisplay(active: Bool, count: Int)
    /// 매칭 앱 정확히 1개(활성 여부는 함께 전달 — 원 로직의 튜플 active를 보존).
    case appRunningSingle(active: Bool, id: String)
    /// 활성이며 매칭이 1개가 아님(0 또는 ≥2). 항상 active.
    case appRunningMultiple(count: Int)
    /// 비활성 — 감시 개수를 함께 전달(오타 vs 미실행 가설 좁히기용). 항상 inactive.
    case appRunningNone(watched: Int)
    /// gatewayMAC == nil 이면 게이트웨이 미해석.
    case network(active: Bool, gatewayMAC: String?, matched: Bool)
    /// 진단 없는(TriggerDiagnosing 미채택) 평가기.
    case plain(active: Bool)

    /// config·snapshot으로 표시 상태를 고른다. `nil` = 토글 OFF(행 숨김).
    public static func evaluate(_ kind: TriggerKind,
                                config: TriggerConfig,
                                snapshot: TriggerEngineSnapshot) -> TriggerStatusText? {
        switch kind {
        case .charging:
            guard config.chargingEnabled else { return nil }
        case .externalDisplay:
            guard config.externalDisplayEnabled else { return nil }
        case .appRunning:
            guard config.appRunningEnabled else { return nil }
            guard !config.watchedBundleIDs.isEmpty else { return .needsWatchList(.appRunning) }
        case .network:
            guard config.networkEnabled else { return nil }
            guard !config.watchedNetworks.isEmpty else { return .needsWatchList(.network) }
        }
        guard let snap = snapshot.trigger(kind) else { return .checking }
        let active = snap.isSatisfied
        switch snap.diagnostic {
        case .charging(let onAC):
            return .charging(active: active, onAC: onAC)
        case .batteryUnavailable:
            return .batteryUnavailable
        case .externalDisplay(let count):
            return .externalDisplay(active: active, count: count)
        case .appRunning(let matched):
            if matched.count == 1, let id = matched.first {
                return .appRunningSingle(active: active, id: id)
            }
            if active {
                return .appRunningMultiple(count: matched.count)
            }
            return .appRunningNone(watched: config.watchedBundleIDs.count)
        case .network(let current, let matched):
            return .network(active: active, gatewayMAC: current?.gatewayMAC, matched: matched)
        case nil:
            return .plain(active: active)
        }
    }
}
