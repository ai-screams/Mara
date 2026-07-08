import AppKit

// AppKit 진입점. 순수 SwiftUI MenuBarExtra 앱은 이 환경(macOS 26/Xcode 26)에서 실행 직후
// 스스로 종료된다(격리 실험으로 확인: bare MenuBarExtra=GONE, AppKit NSStatusItem=ALIVE).
// AppDelegate가 NSStatusItem으로 메뉴바에 상주하고, SwiftUI 뷰(SettingsView)는 NSHostingController로 호스팅한다.
// main.swift 최상위 코드는 앱 시작 시 메인 스레드에서 실행되므로 assumeIsolated로 @MainActor
// AppDelegate를 안전하게 생성한다. delegate는 NSApp.delegate(weak)를 대신해 강하게 붙든다.
let delegate = MainActor.assumeIsolated { AppDelegate() }
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
