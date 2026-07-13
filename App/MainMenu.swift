import AppKit

/// 최소 표준 메인 메뉴 — LSUIElement(accessory) 앱이라 기본 메뉴가 없어서, 창을 띄웠을 때
/// Cmd+W(닫기)·Cmd+C/V/X/A(텍스트 편집)·Cmd+Q가 아무 메뉴에도 안 걸려 동작하지 않던 문제를 해결한다.
/// 항목은 target=nil(first responder)로 두어 표준 셀렉터가 응답자 체인으로 흘러가게 한다.
/// 메뉴 막대는 accessory 앱 특성상 앱이 활성(창 포커스)일 때만 보이고 평소엔 숨는다.
@MainActor
enum MainMenu {
    static func install(appName: String) {
        let main = NSMenu()

        // App 메뉴 — 첫 항목은 제목과 무관하게 시스템이 앱 메뉴로 취급한다.
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit \(appName)",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit 메뉴 — 텍스트 필드 표준 편집(감시 앱 bundle ID 수동 입력 등).
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Window 메뉴 — Cmd+W(닫기)·Cmd+M(최소화). performClose/Miniaturize는 key window로 전달된다.
        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close",
                           action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu   // 표준 Window 메뉴로 지정 → 열린 창 목록 자동 관리
    }
}
