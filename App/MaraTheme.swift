import AppKit
import MaraCore

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
