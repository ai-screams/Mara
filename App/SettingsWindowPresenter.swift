import AppKit
import SwiftUI

/// Night Watch 설정 창의 생성·크롬·표시 담당. 창은 1회 생성 후 캐시한다(닫아도 해제 안 함).
@MainActor
final class SettingsWindowPresenter {
    private var window: NSWindow?
    private let makeContent: () -> SettingsView

    init(makeContent: @escaping () -> SettingsView) {
        self.makeContent = makeContent
    }

    func show() {
        if window == nil { window = Self.makeWindow(content: makeContent()) }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private static func makeWindow(content: SettingsView) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = "Mara Settings"
        // "Night Watch" 크롬: 콘텐츠가 titlebar까지 차도록 투명 처리하고 창 배경을
        // 테마 색으로 고정 — 뷰의 preferredColorScheme(.dark)와 함께 항상-다크를 완성한다.
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = MaraTheme.bgNSColor
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
