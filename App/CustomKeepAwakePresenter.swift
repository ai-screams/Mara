import AppKit
import SwiftUI
import MaraCore

/// 커스텀 타이머 다이얼로그 창의 생성·표시(창 크롬은 `MaraTheme.makeWindow`). 창은 1회 생성 후 캐시(닫아도 해제 안 함).
@MainActor
final class CustomKeepAwakePresenter {
    private var window: NSWindow?
    private let prefs: PrefsStore
    private let onStart: (SessionDuration) -> Bool

    init(prefs: PrefsStore, onStart: @escaping (SessionDuration) -> Bool) {
        self.prefs = prefs
        self.onStart = onStart
    }

    func show() {
        if window == nil { window = makeWindow() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = CustomKeepAwakeView(
            prefs: prefs,
            onStart: onStart,
            dismiss: { [weak self] in self?.window?.close() }
        )
        let window = MaraTheme.makeWindow(title: "Keep Awake", content: view)
        window.center()
        return window
    }
}
