/// 메뉴바 활성 아이콘의 tint 선택지("The colors of the mara" 팔레트).
/// Core는 OS-free — case·기본값·저장 문자열 왕복만 정의하고, 실제 색(NSColor)과
/// 표시 이름은 App이 매핑한다(AppKit·UI 문자열은 Core에 넣지 않는다, 기존 규칙).
///
/// 색은 오직 "활성(깨우는 중)"만 의미한다 — 비활성 아이콘은 App에서 monochrome
/// template로 유지되므로, 어떤 tint를 골라도 "색 있으면 = 활성" 신호는 보존된다.
public enum MenuBarTint: String, CaseIterable, Sendable {
    case ember
    case blood
    case venom
    case wraith
    case nightshade

    /// 기본 tint — 잉걸불 오렌지. 기존 활성 아이콘 색을 잇는다.
    public static let `default`: MenuBarTint = .ember

    /// 신뢰 경계: 저장된 문자열은 첫 실행(nil)이거나 외부 조작(미지의 값)일 수 있다 —
    /// 유효하지 않으면 기본값으로 폴백한다(plist 변조·오타에도 안전).
    public init(storage value: String?) {
        self = value.flatMap(MenuBarTint.init(rawValue:)) ?? .default
    }
}
