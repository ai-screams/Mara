import AppKit
import OpenCombine

// 레거시판(macOS 10.13–13)의 App 쪽 OS 차이 흡수는 이 파일 하나에서만 한다(Core 쪽은 MaraCore/LegacySupport.swift).

/// 레거시에서 OS가 지원하지 않는 기능의 판정.
enum LegacySupport {
    /// 로그인 자동 실행(`SMAppService`, 13+). 13 미만은 메뉴 항목을 숨긴다(헬퍼 번들 방식은 기각).
    static var launchAtLogin: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    /// 자동 시작·종료 알림(`UNUserNotificationCenter` 10.14 + 권한 요청 async 10.15).
    static var notifications: Bool {
        if #available(macOS 10.15, *) { return true }
        return false
    }

    /// 본판(main) 최소 OS. 이 이상이면 본판 appcast로 옮겨 가 본판으로 이주한다.
    ///
    /// 주의 — 이 값을 낮출 때(본판이 최소 OS를 내릴 때)는 bridge 절차가 필수다: 새 값을 compile한 레거시
    /// bridge build를 **기존 appcast 상한**으로 먼저 게시 → adoption 확인 → 그 뒤에만 본판 deployment target과
    /// 레거시 appcast `maximumSystemVersion`을 함께 낮춘다(이 값은 각 레거시 binary에 compile된다).
    static let mainMinimumOS = OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)

    static let mainFeedURL = "https://github.com/ai-screams/Mara/releases/latest/download/appcast.xml"
    static let legacyFeedURL = "https://github.com/ai-screams/Mara/releases/download/legacy-feed/appcast.xml"

    /// Sparkle `feedURLString(for:)`의 결정 — 두 분기 모두 non-nil.
    static var feedURL: String {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(mainMinimumOS) ? mainFeedURL : legacyFeedURL
    }
}

extension NSImage {
    /// SF Symbol(11+). 11 미만은 nil — 메뉴 항목 아이콘은 장식이라 글자만 남는다.
    /// (메뉴바 아이콘은 nil이면 상태 아이템 폭이 0이 되므로 `LegacyStatusIcon`으로 따로 대체한다.)
    static func symbol(_ name: String, accessibilityDescription: String? = nil) -> NSImage? {
        if #available(macOS 11.0, *) {
            return NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
        }
        return nil
    }
}

// 새 SDK의 Foundation이 Combine의 이름을 함께 노출해 OpenCombine과 모호해진다 — 이 모듈 안에서 OpenCombine으로 고정.
typealias Published = OpenCombine.Published
typealias ObservableObject = OpenCombine.ObservableObject
