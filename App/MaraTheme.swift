import SwiftUI

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
