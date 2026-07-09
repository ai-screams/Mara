import AppKit
import Combine
import SwiftUI
import MaraCore
import Sparkle

/// 메뉴바 상주 앱의 AppKit 진입점. NSStatusItem으로 눈 아이콘을 띄우고, 네이티브 NSMenu로
/// 세션을 조작하며, 설정 창은 기존 SwiftUI `SettingsView`를 NSHostingController로 호스팅한다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let env = AppEnvironment()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    /// Sparkle 자동 업데이트. startingUpdater: true → 피드(appcast) 주기 확인을 즉시 시작하고,
    /// 자동 확인 동의는 Sparkle 표준(둘째 실행 시 프롬프트)에 맡긴다. "Check for Updates…"
    /// 메뉴 항목의 타깃이 되며 canCheckForUpdates에 따라 자동 활성/비활성된다.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // autosave 이름을 명시해야 한다. 기본 이름 "Item-0"은 macOS 26 메뉴바 관리(Control Center)의
        // 숨김 상태("NSStatusItem Visible Item-0" = 0)와 충돌해 아이템이 메뉴바에 그려지지 않는다.
        item.autosaveName = "Mara"
        let menu = NSMenu()
        menu.delegate = self          // 열릴 때마다 menuNeedsUpdate로 라이브 상태 반영
        item.menu = menu
        statusItem = item
        refreshStatusButton(env.session.state)
        item.isVisible = true         // 콘텐츠를 채운 뒤 마지막에 표시(기본값이 항상 true가 아님)

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
        // 색은 contentTintColor로 입힌다 — 팔레트 컬러 non-template 이미지는 메뉴바에서
        // 단색으로 렌더된다(macOS 26 관측). template + tint가 정석이고 다크/라이트에도 안전.
        button.contentTintColor = state.isActive ? .systemOrange : nil
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

    /// 활성: 뜬 눈 / 비활성: 감은 눈. 둘 다 template — 색은 refreshStatusButton의
    /// contentTintColor가 입힌다(활성=오렌지, 비활성=메뉴바 톤 자동 적응).
    static func statusIcon(active: Bool) -> NSImage {
        let symbol = active ? "eye.fill" : "eye.slash.fill"
        let description = active ? "Mara — keep-awake active" : "Mara — inactive"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description) ?? NSImage()
        image.isTemplate = true
        return image
    }

    // MARK: - Menu (rebuilt on open for live state)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = env.session.state

        // representedObject = 메뉴가 그려진 시점의 활성 여부(사용자 의도). 메뉴가 열린 사이
        // 세션이 끝나도(타이머 만료·저전력 종료) "Turn Off" 클릭이 새 세션을 시작하지 않게 한다.
        let awakeItem = addItem(to: menu, title: state.isActive ? "Turn Off" : "Keep Awake",
                                action: #selector(toggleKeepAwake(_:)),
                                symbol: state.isActive ? "eye.slash.fill" : "eye.fill")
        awakeItem.representedObject = state.isActive

        if case let .active(cfg, _) = state, cfg.origin == .trigger {
            let t = NSMenuItem(title: "Auto-activated (trigger)", action: nil, keyEquivalent: "")
            t.isEnabled = false
            t.image = Self.menuSymbol("bolt.fill")
            menu.addItem(t)
        }

        menu.addItem(.separator())

        let durMenu = NSMenu()
        durMenu.addItem(durationItem("15 minutes", 15 * 60))
        durMenu.addItem(durationItem("1 hour", 60 * 60))
        durMenu.addItem(durationItem("2 hours", 2 * 60 * 60))
        durMenu.addItem(durationItem("5 hours", 5 * 60 * 60))
        let durParent = NSMenuItem(title: "Keep awake for…", action: nil, keyEquivalent: "")
        durParent.image = Self.menuSymbol("timer")
        durParent.submenu = durMenu
        menu.addItem(durParent)

        let display = addItem(to: menu, title: "Keep display awake",
                              action: #selector(toggleDisplay), symbol: "display")
        display.state = currentKeepDisplay ? .on : .off

        let login = addItem(to: menu, title: "Launch at Login",
                            action: #selector(toggleLaunchAtLogin), symbol: "play.circle")
        login.state = LaunchAtLogin.isEnabled ? .on : .off

        menu.addItem(.separator())

        // addItem 헬퍼는 target=self 고정이라 직접 생성 — 타깃이 updaterController여야
        // Sparkle이 canCheckForUpdates로 활성/비활성을 자동 관리한다.
        let update = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        update.target = updaterController
        update.image = Self.menuSymbol("arrow.triangle.2.circlepath")
        menu.addItem(update)

        addItem(to: menu, title: "Settings…", action: #selector(openSettings), key: ",",
                symbol: "gearshape")
        addItem(to: menu, title: "Quit Mara", action: #selector(quit), key: "q", symbol: "power")
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String = "",
                         symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = symbol.flatMap(Self.menuSymbol)
        menu.addItem(item)
        return item
    }

    /// 메뉴 항목용 템플릿 심볼 — 시스템이 메뉴 톤(라이트/다크·비활성)에 맞춰 자동 렌더한다.
    private static func menuSymbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
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

    @objc private func toggleKeepAwake(_ sender: NSMenuItem) {
        // 의도 기반 분기: 메뉴가 그려질 때 활성이었다면 사용자의 의도는 '끄기'다.
        // 열린 메뉴가 낡아 상태가 이미 바뀌었어도 반대 동작(재시작)을 하지 않는다.
        let intendedOff = sender.representedObject as? Bool ?? env.session.state.isActive
        if intendedOff {
            env.session.stop()   // 이미 꺼져 있으면 no-op
        } else {
            env.session.start(SessionConfig(scope: env.prefs.defaultScope, duration: .indefinite, origin: .manual))
        }
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
                rootView: SettingsView(
                    prefs: env.prefs,
                    session: env.session,
                    currentNetwork: { [env] in env.currentNetwork },
                    checkForUpdates: { [updaterController] in updaterController.checkForUpdates(nil) }
                )
            )
            let window = NSWindow(contentViewController: host)
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
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
