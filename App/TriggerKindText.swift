import MaraCore

/// 트리거 종류 → 표시 이름(영어). Core enum에는 UI 문자열을 두지 않는다(SessionFailureText와 같은 규칙).
/// "Started by <name>"·"Auto-activated (<name>)" 양쪽에 들어가므로 소문자 구로 쓴다.
enum TriggerKindText {
    static func name(_ kind: TriggerKind) -> String {
        switch kind {
        case .charging:        return "charging"
        case .externalDisplay: return "external display"
        case .appRunning:      return "a watched app"
        case .network:         return "a remembered network"
        }
    }
}
