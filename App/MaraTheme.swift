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
    /// 활성 아이콘에 굽는 색("The colors of the mara" 팔레트, sRGB).
    var color: NSColor {
        switch self {
        case .ember:      return NSColor(red: 0xF2 / 255, green: 0x64 / 255, blue: 0x19 / 255, alpha: 1)
        case .blood:      return NSColor(red: 0xD7 / 255, green: 0x26 / 255, blue: 0x3D / 255, alpha: 1)
        case .venom:      return NSColor(red: 0x6D / 255, green: 0xD4 / 255, blue: 0x00 / 255, alpha: 1)
        case .wraith:     return NSColor(red: 0x35 / 255, green: 0xC9 / 255, blue: 0xC2 / 255, alpha: 1)
        case .nightshade: return NSColor(red: 0xA2 / 255, green: 0x4B / 255, blue: 0xE0 / 255, alpha: 1)
        }
    }

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
