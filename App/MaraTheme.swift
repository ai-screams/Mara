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
