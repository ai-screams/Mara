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
        // 숨겨진 창을 다시 보여 줄 때만, 마우스가 있는 화면 가운데로 옮긴다. 메뉴 막대에서 Settings…를 누른 직후라
        // 그 화면이 곧 사용자가 보고 있는 화면이다. 이미 떠 있는 창은 사용자가 둔 자리에서 옮기지 않는다.
        // (예전엔 만들 때 한 번 center()만 해서, 앱을 켠 뒤 처음 열면 보고 있지 않은 주 디스플레이에 떴다.)
        if let window, !window.isVisible,
           let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
                ?? NSScreen.main {
            window.setFrameOrigin(Self.centeredOrigin(for: window.frame.size, in: screen.visibleFrame))
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // 열 때 포커스를 비운다 — 그대로 두면 AppKit이 첫 입력칸(저배터리 숫자)에 포커스를 줘서, 네트워크 이름을
        // 치려던 키가 그 칸에 들어간다(실사고: "Low-l"). 사용자가 클릭한 칸에서만 입력이 시작되게 한다.
        window?.makeFirstResponder(nil)
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
    static func centeredOrigin(for size: CGSize, in visible: CGRect) -> CGPoint {
        let centeredY = max(visible.minY, visible.midY - size.height / 2)
        return CGPoint(x: visible.midX - size.width / 2,
                       y: min(visible.maxY - size.height, centeredY))
    }
}
