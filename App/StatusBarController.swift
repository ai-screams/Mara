import AppKit
import Combine
import MaraCore

/// 메뉴바 상태 아이템 + 네이티브 메뉴 담당. 아이콘은 실제 세션 상태를 반영하고,
/// 메뉴는 열릴 때마다 `menuNeedsUpdate`로 라이브 재구성한다. (창/업데이터는 소유하지 않는다 —
/// Settings 열기와 Check for Updates는 조립자(AppDelegate)가 주입한다.)
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let env: AppEnvironment
    private var statusItem: NSStatusItem?
    /// 첫 실행 안내 팝오버의 앵커 — install() 이후에만 non-nil. 읽기 전용 노출.
    var statusButton: NSStatusBarButton? { statusItem?.button }
    private var cancellables = Set<AnyCancellable>()
    /// 카운트다운 갱신 타이머. sink가 세션 변화마다 재설정하며,
    /// 만료는 SessionManager 타이머가 stop → sink 경유로 invalidate된다.
    private var countdownTimer: Timer?
    /// Launch-at-Login 상태 캐시. `SMAppService.status`는 launchd 조회라 메뉴 열기마다
    /// 부르지 않는다 — 앱 내 토글이 갱신하고, 외부(System Settings) 변경은
    /// didBecomeActive에서 재동기화한다(install 참조).
    private var launchAtLoginEnabled = LaunchAtLogin.isEnabled

    /// Settings 창 열기 — 창 소유자(AppDelegate)가 주입.
    var onOpenSettings: (() -> Void)?
    /// 커스텀 타이머 다이얼로그 열기 — 창 소유자(AppDelegate)가 주입.
    var onOpenCustomKeepAwake: (() -> Void)?
    /// Sparkle "Check for Updates…" 메뉴 항목의 (타깃, 셀렉터). Sparkle import를
    /// 이 파일로 끌어오지 않으려고 제네릭 타깃/셀렉터로 받는다.
    var checkForUpdates: (target: AnyObject, action: Selector)?

    private static let durationPresets: [(title: String, seconds: TimeInterval)] = [
        ("15 minutes", 15 * 60),
        ("1 hour", 60 * 60),
        ("2 hours", 2 * 60 * 60),
        ("5 hours", 5 * 60 * 60),
    ]

    init(env: AppEnvironment) {
        self.env = env
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // autosave 이름을 명시해야 한다. 기본 이름 "Item-0"은 macOS 26 메뉴바 관리(Control Center)의
        // 숨김 상태("NSStatusItem Visible Item-0" = 0)와 충돌해 아이템이 메뉴바에 그려지지 않는다.
        item.autosaveName = "Mara"
        let menu = NSMenu()
        menu.delegate = self          // 열릴 때마다 menuNeedsUpdate로 라이브 상태 반영
        item.menu = menu
        statusItem = item
        // 숫자 폭 흔들림 방지: 모노스페이스 숫자 폰트로 라벨 너비를 안정화한다.
        item.button?.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        refreshStatusButton(env.session.state)
        item.isVisible = true         // 콘텐츠를 채운 뒤 마지막에 표시(기본값이 항상 true가 아님)

        // 세션 상태(@Published, main에서만 변이)를 구독해 아이콘/지속시간 라벨을 갱신.
        // @Published는 willSet에서 발화하므로 방출된 state를 그대로 넘겨야 한다(재-read 시 이전 값).
        env.session.$state
            .sink { [weak self] state in MainActor.assumeIsolated { self?.refreshStatusButton(state) } }
            .store(in: &cancellables)

        // 외부(System Settings) Launch-at-Login 변경을 다음 활성화 시 캐시에 반영한다.
        // (액세서리 앱이라 자주 발화하진 않지만, 발화하면 메뉴 체크 표시가 정확해진다.)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.launchAtLoginEnabled = LaunchAtLogin.isEnabled }
        }
    }

    // MARK: - Status button (eye icon + countdown)

    private func refreshStatusButton(_ state: SessionState) {
        // 항상 기존 카운트다운 타이머를 먼저 취소한다.
        // sink가 세션 변화마다 재설정하며, 만료는 SessionManager 타이머가 stop → sink 경유로 invalidate된다.
        countdownTimer?.invalidate()
        countdownTimer = nil

        guard let button = statusItem?.button else { return }
        button.image = Self.statusIcon(active: state.isActive)
        button.imagePosition = .imageLeading
        button.title = durationLabel(for: state).map { " " + $0 } ?? ""

        // expiresAt이 있는 활성 세션: 다음 라벨 전환 시각에 non-repeating 타이머를 건다.
        if case let .active(_, expiresAt) = state, let expiry = expiresAt {
            let remaining = expiry.timeIntervalSinceNow
            let interval = CountdownFormat.nextTick(remaining: remaining)
            let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
                guard let self else { return }
                // 발화 시 현재 state를 다시 읽어 최신 상태로 재귀 예약한다.
                MainActor.assumeIsolated { self.refreshStatusButton(self.env.session.state) }
            }
            timer.tolerance = 1.0   // 에너지 배려: 1초 오차 허용
            RunLoop.main.add(timer, forMode: .common)
            countdownTimer = timer
        }
    }

    /// 활성 세션의 라벨: expiresAt 기반 카운트다운(4h55m → … → 1m) 또는 무한(∞). 비활성이면 nil.
    private func durationLabel(for state: SessionState) -> String? {
        guard case let .active(_, expiresAt) = state else { return nil }
        guard let expiry = expiresAt else { return "∞" }
        return CountdownFormat.label(remaining: expiry.timeIntervalSinceNow)
    }

    /// 활성: 뜬 눈(오렌지) / 비활성: 감은 눈(template — 메뉴바 톤 자동 적응).
    /// 오렌지는 비트맵에 직접 굽는다(sourceAtop + non-template). NSStatusBarButton은
    /// contentTintColor를 무시하고, template 이미지·팔레트 심볼 구성도 단색으로 렌더한다
    /// (macOS 26 실기 관측 — 스크린샷으로 확인된 사실).
    /// active는 Bool뿐이므로 두 이미지를 1회만 만들어 캐시한다(카운트다운 틱마다 재합성 방지).
    static func statusIcon(active: Bool) -> NSImage { active ? activeIcon : inactiveIcon }

    private static let activeIcon: NSImage = makeStatusIcon(active: true)
    private static let inactiveIcon: NSImage = makeStatusIcon(active: false)

    private static func makeStatusIcon(active: Bool) -> NSImage {
        let description = active ? "Mara — keep-awake active" : "Mara — inactive"
        let symbol = active ? MaraSymbol.awake : MaraSymbol.resting
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: description) ?? NSImage()
        guard active else {
            base.isTemplate = true
            return base
        }
        let tinted = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.systemOrange.set()
            rect.fill(using: .sourceAtop)   // 글리프 알파 위에만 색을 얹는다
            return true
        }
        tinted.isTemplate = false           // 구운 색 그대로 렌더
        tinted.accessibilityDescription = description
        return tinted
    }

    // MARK: - Menu (rebuilt on open for live state)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = env.session.state

        addSessionHeaderItems(to: menu, state: state)
        addTriggerStatusItem(to: menu, state: state)

        menu.addItem(.separator())
        menu.addItem(durationMenuItem())
        addPreferenceItems(to: menu)
        menu.addItem(.separator())
        addFooterItems(to: menu)
    }

    private func addSessionHeaderItems(to menu: NSMenu, state: SessionState) {
        // representedObject = 메뉴가 그려진 시점의 활성 여부(사용자 의도). 메뉴가 열린 사이
        // 세션이 끝나도(타이머 만료·저전력 종료) "Turn Off" 클릭이 새 세션을 시작하지 않게 한다.
        let awakeItem = addItem(to: menu, title: state.isActive ? "Turn Off" : "Keep Awake",
                                action: #selector(toggleKeepAwake(_:)),
                                symbol: state.isActive ? MaraSymbol.resting : MaraSymbol.awake)
        awakeItem.representedObject = state.isActive

        if let failure = env.session.lastFailure {
            let errorItem = NSMenuItem(
                title: "Last operation failed — \(SessionFailureText.describe(failure))",
                action: nil,
                keyEquivalent: ""
            )
            errorItem.isEnabled = false
            errorItem.image = Self.menuSymbol("exclamationmark.triangle.fill")
            menu.addItem(errorItem)
        }
    }

    private func addTriggerStatusItem(to menu: NSMenu, state: SessionState) {
        if case let .active(cfg, _) = state, cfg.origin == .trigger {
            let t = NSMenuItem(title: "Auto-activated (trigger)", action: nil, keyEquivalent: "")
            t.isEnabled = false
            t.image = Self.menuSymbol("bolt.fill")
            menu.addItem(t)
        }
    }

    private func durationMenuItem() -> NSMenuItem {
        // 서브메뉴도 메인 메뉴와 같은 디자인 언어: 전 항목 SF Symbol + "Recent" 섹션 헤더.
        let durMenu = NSMenu()
        for preset in Self.durationPresets {
            durMenu.addItem(durationItem(preset.title, preset.seconds))
        }
        // 최근 커스텀 duration(MRU 최대 3) — 원클릭 재사용. Until은 기록되지 않는다.
        let recentDurations = env.prefs.recentCustomDurations.filter { seconds in
            !Self.durationPresets.contains { $0.seconds == seconds }
        }
        if !recentDurations.isEmpty {
            durMenu.addItem(.separator())
            durMenu.addItem(.sectionHeader(title: "Recent"))
            for seconds in recentDurations {
                durMenu.addItem(durationItem(DurationFormat.compact(seconds), seconds,
                                             symbol: "clock.arrow.circlepath"))
            }
            let clear = NSMenuItem(title: "Clear Recent", action: #selector(clearRecentDurations), keyEquivalent: "")
            clear.target = self
            clear.image = Self.menuSymbol("xmark.circle")
            durMenu.addItem(clear)
        }
        durMenu.addItem(.separator())
        let custom = NSMenuItem(title: "Custom…", action: #selector(openCustomKeepAwake), keyEquivalent: "")
        custom.target = self
        custom.image = Self.menuSymbol("slider.horizontal.3")
        durMenu.addItem(custom)
        let durParent = NSMenuItem(title: "Keep awake for…", action: nil, keyEquivalent: "")
        durParent.image = Self.menuSymbol("timer")
        durParent.submenu = durMenu
        return durParent
    }

    private func addPreferenceItems(to menu: NSMenu) {
        let display = addItem(to: menu, title: "Keep display awake",
                              action: #selector(toggleDisplay), symbol: "display")
        display.state = currentKeepDisplay ? .on : .off

        let login = addItem(to: menu, title: "Launch at Login",
                            action: #selector(toggleLaunchAtLogin), symbol: "play.circle")
        login.state = launchAtLoginEnabled ? .on : .off
    }

    private func addFooterItems(to menu: NSMenu) {
        if let (target, action) = checkForUpdates {
            // 타깃이 updaterController여야 Sparkle이 canCheckForUpdates로 활성/비활성을 자동 관리한다.
            let update = NSMenuItem(title: "Check for Updates…", action: action, keyEquivalent: "")
            update.target = target
            update.image = Self.menuSymbol("arrow.triangle.2.circlepath")
            menu.addItem(update)
        }

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

    private func durationItem(_ title: String, _ seconds: TimeInterval,
                              symbol: String = "clock") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(startTimed(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = seconds
        item.image = Self.menuSymbol(symbol)
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
            report(env.session.stop())   // 이미 꺼져 있으면 no-op
        } else {
            report(env.session.start(
                SessionConfig(scope: env.prefs.defaultScope, duration: .indefinite, origin: .manual)
            ))
        }
    }

    @objc private func startTimed(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        report(env.session.start(
            SessionConfig(scope: env.prefs.defaultScope, duration: .duration(seconds), origin: .manual)
        ))
    }

    @objc private func toggleDisplay() {
        let newValue = !currentKeepDisplay
        let result = env.session.updateScope(KeepAwakeScope(keepDisplay: newValue))
        guard case .success = result else {
            report(result)
            return
        }
        env.prefs.defaultKeepDisplayAwake = newValue
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.setEnabled(!launchAtLoginEnabled)
        launchAtLoginEnabled = LaunchAtLogin.isEnabled   // 실제 결과로 재동기화(토글 실패 시에도 정확)
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func clearRecentDurations() {
        env.prefs.clearRecentCustomDurations()
    }

    @objc private func openCustomKeepAwake() {
        onOpenCustomKeepAwake?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func report(_ result: Result<Void, SessionFailure>) {
        if case .failure = result { NSSound.beep() }
    }
}
