import AppKit
import SwiftUI

/// Night Watch 설정 창의 생성·위치·표시 담당(창 크롬은 `MaraTheme.makeWindow`). 창은 1회 생성 후 캐시한다(닫아도 해제 안 함).
@MainActor
final class SettingsWindowPresenter {
    private var window: NSWindow?
    private let makeContent: () -> SettingsView

    init(makeContent: @escaping () -> SettingsView) {
        self.makeContent = makeContent
    }

    func show() {
        let window = self.window ?? MaraTheme.makeWindow(title: "Mara Settings", content: makeContent())
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

    /// 보이는 영역(메뉴 막대·Dock 제외) 가운데. 창이 그 영역보다 크면 제목 표시줄이 잘리지 않게 위쪽을 맞춘다.
    private static func centeredOrigin(for size: CGSize, in visible: CGRect) -> CGPoint {
        let centeredY = max(visible.minY, visible.midY - size.height / 2)
        return CGPoint(x: visible.midX - size.width / 2,
                       y: min(visible.maxY - size.height, centeredY))
    }
}
