import SwiftUI
import MaraCore

/// Mara 브랜드 팔레트 — 랜딩 페이지(docs/index.html)의 CSS 변수와 동일한 값.
/// Settings 창은 시스템 모드와 무관하게 항상 이 다크 테마("Night Watch")로 렌더한다.
enum MaraTheme {
    static let bg      = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x1A / 255)
    static let card    = Color(red: 0x22 / 255, green: 0x22 / 255, blue: 0x27 / 255)
    static let accent  = Color(red: 0xFF / 255, green: 0x95 / 255, blue: 0x00 / 255)
    static let textMid = Color(red: 0xC4 / 255, green: 0xC4 / 255, blue: 0xCC / 255)
    static let muted   = Color(red: 0x8B / 255, green: 0x8B / 255, blue: 0x95 / 255)

    static let bgNSColor = NSColor(red: 0x17 / 255, green: 0x17 / 255, blue: 0x1A / 255, alpha: 1)
}

/// 브랜드 아이콘의 단일 출처 — 활성=뜬 눈 / 비활성=감은 눈 의미를 여기서만 정의한다.
/// (메뉴바 아이콘·Settings 헤더는 현재 상태를, "Keep Awake/Turn Off" 메뉴 항목은
/// 클릭 후 도달할 다음 상태를 반전해 사용한다.)
enum MaraSymbol {
    static let awake = "eye.fill"
    static let resting = "eye.slash.fill"
}

/// 메뉴바 tint의 App-side 매핑 — 실제 색과 표시 이름. Core `MenuBarTint`는 case·기본값만
/// 알고(OS-free), 색(AppKit)과 UI 문자열은 여기서만 정의한다. switch는 exhaustive라 Core에
/// case를 더하면 App이 컴파일 실패로 잡아준다(팔레트 = 사용자 확정 5색).
extension MenuBarTint {
    /// 팔레트 단일 출처(0–255 sRGB, "The colors of the mara"). color·accentColor가 여기서 파생된다.
    private var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .ember:      return (0xF2, 0x64, 0x19)
        case .blood:      return (0xD7, 0x26, 0x3D)
        case .venom:      return (0x6D, 0xD4, 0x00)
        case .wraith:     return (0x35, 0xC9, 0xC2)
        case .nightshade: return (0xA2, 0x4B, 0xE0)
        }
    }

    /// 메뉴바 활성 아이콘에 굽는 색(AppKit).
    var color: NSColor { NSColor(red: rgb.r / 255, green: rgb.g / 255, blue: rgb.b / 255, alpha: 1) }

    /// 앱 UI(Settings 등)의 accent — 선택한 tint를 따라간다(SwiftUI).
    var accentColor: Color { Color(red: rgb.r / 255, green: rgb.g / 255, blue: rgb.b / 255) }

    /// 메뉴에 보일 이름 (UI 문자열 — App 전용).
    var displayName: String {
        switch self {
        case .ember:      return "Ember"
        case .blood:      return "Blood"
        case .venom:      return "Venom"
        case .wraith:     return "Wraith"
        case .nightshade: return "Nightshade"
        }
    }
}

/// 앱 UI accent — 선택된 `MenuBarTint`를 따라간다. 각 창 루트가 `.maraAccent(_:)`로 주입하고,
/// 자식 뷰는 `@Environment(\.accentTint)`로 읽는다. 배경(bg/card)은 다크 "Night Watch" 유지 —
/// 바뀌는 건 강조색뿐(컨트롤·아이콘·glow). 기본값은 실제 기본 tint(ember) — 주입 안 된
/// 표면이 생겨도 팔레트에 없는 색이 아니라 진짜 기본색으로 폴백한다(기본 tint가 바뀌면 자동 추종).
///
/// 주의: `.maraAccent`를 뷰 body 안에서 걸면 **자식**에만 적용된다 — 그 뷰 자신의 `@Environment`는
/// 부모값을 읽으므로, prefs를 가진 루트(SettingsView·CustomKeepAwakeView)는 자기 참조엔
/// `prefs.menuBarTint.accentColor`를 직접 쓰고 자식 구조체만 `\.accentTint`로 읽는다.
private struct AccentTintKey: EnvironmentKey {
    static let defaultValue: Color = MenuBarTint.default.accentColor
}

extension EnvironmentValues {
    var accentTint: Color {
        get { self[AccentTintKey.self] }
        set { self[AccentTintKey.self] = newValue }
    }
}

extension View {
    /// 선택 tint를 앱 accent로 흘려보낸다 — 네이티브 컨트롤 `.tint` + 자식이 읽을 `\.accentTint`.
    func maraAccent(_ tint: MenuBarTint) -> some View {
        self.tint(tint.accentColor).environment(\.accentTint, tint.accentColor)
    }
}
