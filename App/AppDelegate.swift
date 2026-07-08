import AppKit
import Combine
import SwiftUI
import MaraCore

/// 메뉴바 상주 앱의 AppKit 진입점. NSStatusItem으로 눈 아이콘을 띄우고, 네이티브 NSMenu로
/// 세션을 조작하며, 설정 창은 기존 SwiftUI `SettingsView`를 NSHostingController로 호스팅한다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let env = AppEnvironment()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true         // 명시 필요: 기본값이 항상 true가 아니며(false로 시작 관측됨),
                                      // false면 상태아이템 창이 화면 밖에 파킹돼 메뉴바에 나타나지 않는다.
        let menu = NSMenu()
        menu.delegate = self          // 열릴 때마다 menuNeedsUpdate로 라이브 상태 반영
        item.menu = menu
        statusItem = item
        refreshStatusButton(env.session.state)

        // 세션 상태(@Published, main에서만 변이)를 구독해 아이콘/지속시간 라벨을 갱신.
        // @Published는 willSet에서 발화하므로 방출된 state를 그대로 넘겨야 한다(재-read 시 이전 값).
        env.session.$state
            .sink { [weak self] state in MainActor.assumeIsolated { self?.refreshStatusButton(state) } }
            .store(in: &cancellables)
    }

    // MARK: - Status button (eye icon + duration)

    private func refreshStatusButton(_ state: SessionState) {
        guard let button = statusItem?.button else { return }
        button.image = Self.statusIcon(active: state.isActive)
        button.imagePosition = .imageLeading
        button.title = durationLabel(for: state).map { " " + $0 } ?? ""
    }

    /// 활성 세션의 지속시간 라벨(15m / 1h / ∞). 비활성이면 nil.
    private func durationLabel(for state: SessionState) -> String? {
        guard case let .active(config, _) = state else { return nil }
        switch config.duration {
        case .indefinite:      return "∞"
        case .duration(let t): return Self.durationText(t)
        case .until(let date): return Self.durationText(max(0, date.timeIntervalSinceNow))
        }
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }

    /// 활성: 뜬 눈 + 주황(색상 유지) / 비활성: 감은 눈 + template(라이트·다크 자동 적응).
    static func statusIcon(active: Bool) -> NSImage {
        let symbol = active ? "eye.fill" : "eye.slash.fill"
        let description = active ? "Mara — keep-awake 활성" : "Mara — 비활성"
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: description) ?? NSImage()
        guard active else {
            base.isTemplate = true
            return base
        }
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
        let colored = base.withSymbolConfiguration(config) ?? base
        colored.isTemplate = false
        return colored
    }

    // MARK: - Menu (rebuilt on open for live state)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = env.session.state

        addItem(to: menu, title: state.isActive ? "Turn Off" : "Keep Awake", action: #selector(toggleKeepAwake))

        if case let .active(cfg, _) = state, cfg.origin == .trigger {
            let t = NSMenuItem(title: "자동 활성 (트리거)", action: nil, keyEquivalent: "")
            t.isEnabled = false
            menu.addItem(t)
        }

        menu.addItem(.separator())

        let durMenu = NSMenu()
        durMenu.addItem(durationItem("15 minutes", 15 * 60))
        durMenu.addItem(durationItem("1 hour", 60 * 60))
        durMenu.addItem(durationItem("2 hours", 2 * 60 * 60))
        durMenu.addItem(durationItem("5 hours", 5 * 60 * 60))
        let durParent = NSMenuItem(title: "Keep awake for…", action: nil, keyEquivalent: "")
        durParent.submenu = durMenu
        menu.addItem(durParent)

        let display = addItem(to: menu, title: "Keep display awake", action: #selector(toggleDisplay))
        display.state = currentKeepDisplay ? .on : .off

        let login = addItem(to: menu, title: "Launch at Login", action: #selector(toggleLaunchAtLogin))
        login.state = LaunchAtLogin.isEnabled ? .on : .off

        menu.addItem(.separator())
        addItem(to: menu, title: "Settings…", action: #selector(openSettings), key: ",")
        addItem(to: menu, title: "Quit Mara", action: #selector(quit), key: "q")
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func durationItem(_ title: String, _ seconds: TimeInterval) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(startTimed(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = seconds
        return item
    }

    /// 화면-유지 현재값: 활성 세션이면 그 scope, 아니면 사용자 기본값.
    private var currentKeepDisplay: Bool {
        if case let .active(cfg, _) = env.session.state { return cfg.scope.keepsDisplayAwake }
        return env.prefs.defaultKeepDisplayAwake
    }

    // MARK: - Actions

    @objc private func toggleKeepAwake() {
        env.session.toggle(SessionConfig(scope: env.prefs.defaultScope, duration: .indefinite, origin: .manual))
    }

    @objc private func startTimed(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        env.session.start(SessionConfig(scope: env.prefs.defaultScope, duration: .duration(seconds), origin: .manual))
    }

    @objc private func toggleDisplay() {
        let newValue = !currentKeepDisplay
        env.prefs.defaultKeepDisplayAwake = newValue              // 기본값 영속
        env.session.updateScope(KeepAwakeScope(keepDisplay: newValue))  // 활성이면 라이브 반영
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(
                rootView: SettingsView(prefs: env.prefs, currentNetwork: { [env] in env.currentNetwork })
            )
            let window = NSWindow(contentViewController: host)
            window.title = "Mara Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
