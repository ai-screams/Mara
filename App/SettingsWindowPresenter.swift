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
        let window = self.window ?? Self.makeWindow(content: makeContent())
        self.window = window
        // 숨겨져 있던 창을 다시 보여 줄 때만: 마우스가 있는 화면(= 방금 메뉴 막대를 누른 화면) 가운데로 옮기고
        // 포커스를 비운다. 이미 떠 있는 창은 사용자가 둔 자리와 입력 중인 칸을 그대로 둔다.
        // 포커스를 비우지 않으면 AppKit이 첫 입력칸(저배터리 숫자)에 포커스를 줘서 다른 칸에 치려던 키가 그리로 간다.
        let reopening = !window.isVisible
        if reopening,
           let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
                ?? NSScreen.main {
            window.setFrameOrigin(Self.centeredOrigin(for: window.frame.size, in: screen.visibleFrame))
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        if reopening { window.makeFirstResponder(nil) }
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
        return window
    }

    /// 보이는 영역(메뉴 막대·Dock 제외) 가운데. 창이 그 영역보다 크면 제목 표시줄이 잘리지 않게 위쪽을 맞춘다.
    private static func centeredOrigin(for size: CGSize, in visible: CGRect) -> CGPoint {
        let centeredY = max(visible.minY, visible.midY - size.height / 2)
        return CGPoint(x: visible.midX - size.width / 2,
                       y: min(visible.maxY - size.height, centeredY))
    }
}
