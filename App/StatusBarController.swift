import AppKit
import OpenCombine
import MaraCore

/// 메뉴바 상태 아이템 + 네이티브 메뉴 담당. 아이콘은 실제 세션 상태를 반영하고,
/// 메뉴는 열릴 때마다 `menuNeedsUpdate`로 라이브 재구성한다. (창/업데이터는 소유하지 않는다 —
/// Settings 열기와 Check for Updates는 조립자(AppDelegate)가 주입한다.)
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let env: AppEnvironment
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    /// 카운트다운 갱신 타이머. sink가 세션 변화마다 재설정하며,
    /// 만료는 SessionManager 타이머가 stop → sink 경유로 invalidate된다.
    private var countdownTimer: Timer?
    /// Launch-at-Login 상태 캐시. `SMAppService.status`는 launchd 조회라 메뉴 열기마다
    /// 부르지 않는다 — 앱 내 토글이 갱신하고, 외부(System Settings) 변경은
    /// didBecomeActive에서 재동기화한다(install 참조).
    /// 레거시: 13 미만은 nil(항목 자체가 없다).
    private var launchAtLoginEnabled: Bool?

    /// 알림 권한 요청 — 10.15+에서만 AppDelegate가 주입한다(nil이면 알림 토글을 숨긴다).
    var requestNotificationAuth: ((@escaping @MainActor (Bool) -> Void) -> Void)?
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
        refreshStatusButton(env.session.state, tint: env.prefs.menuBarTint)
        item.isVisible = true         // 콘텐츠를 채운 뒤 마지막에 표시(기본값이 항상 true가 아님)

        // 세션 상태(@Published, main에서만 변이)를 구독해 아이콘/지속시간 라벨을 갱신.
        // @Published는 willSet에서 발화하므로 방출된 state를 그대로 넘겨야 한다(재-read 시 이전 값).
        env.session.$state
            .sink { [weak self] state in
                unsafeAssumeMainActor {
                    guard let self else { return }
                    self.refreshStatusButton(state, tint: self.env.prefs.menuBarTint)
                }
            }
            .store(in: &cancellables)

        // 메뉴바 tint 변경 시 활성 아이콘을 즉시 다시 굽는다. @Published는 willSet 발화라
        // 방출된 tint를 그대로 써야 한다(sink에서 prefs.menuBarTint 재-read 시 이전 값).
        env.prefs.$menuBarTint
            .dropFirst()   // 초기값 재방출 무시 (위 초기 refresh에서 이미 반영)
            .sink { [weak self] tint in
                unsafeAssumeMainActor {
                    guard let self else { return }
                    self.refreshStatusButton(self.env.session.state, tint: tint)
                }
            }
            .store(in: &cancellables)

        // 외부(System Settings) Launch-at-Login 변경을 다음 활성화 시 캐시에 반영한다(13+만).
        if #available(macOS 13.0, *) {
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.launchAtLoginEnabled = LaunchAtLogin.isEnabled }   // 13+ 블록 안이라 원본
            }
        }
    }

    // MARK: - Status button (eye icon + countdown)

    private func refreshStatusButton(_ state: SessionState, tint: MenuBarTint) {
        // 항상 기존 카운트다운 타이머를 먼저 취소한다.
        // sink가 세션 변화마다 재설정하며, 만료는 SessionManager 타이머가 stop → sink 경유로 invalidate된다.
        countdownTimer?.invalidate()
        countdownTimer = nil

        guard let button = statusItem?.button else { return }
        button.image = statusIcon(active: state.isActive, tint: tint)
        button.imagePosition = .imageLeading
        button.title = durationLabel(for: state).map { " " + $0 } ?? ""

        // expiresAt이 있는 활성 세션: 다음 라벨 전환 시각에 non-repeating 타이머를 건다.
        if case let .active(_, expiresAt) = state, let expiry = expiresAt {
            let remaining = expiry.timeIntervalSinceNow
            let interval = CountdownFormat.nextTick(remaining: remaining)
            let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
                guard let self else { return }
                // 발화 시 현재 state·tint를 다시 읽어 최신 상태로 재귀 예약한다(라벨 틱만이라 tint는 안 바뀜).
                unsafeAssumeMainActor {
                    self.refreshStatusButton(self.env.session.state, tint: self.env.prefs.menuBarTint)
                }
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

    /// 활성: 뜬 눈(사용자 선택 tint) / 비활성: 감은 눈(template — 메뉴바 톤 자동 적응).
    /// tint는 비트맵에 직접 굽는다(sourceAtop + non-template). NSStatusBarButton은
    /// contentTintColor를 무시하고, template 이미지·팔레트 심볼 구성도 단색으로 렌더한다
    /// (macOS 26 실기 관측 — 스크린샷으로 확인된 사실). 그래서 색은 미리 구워 넣는다.
    /// 색은 오직 "활성"만 의미하므로 비활성은 tint와 무관한 단일 template 이미지.
    /// tint별 활성 이미지는 1회만 합성해 캐시한다(카운트다운 틱마다 재합성 방지, tint당 1개).
    private func statusIcon(active: Bool, tint: MenuBarTint) -> NSImage {
        guard active else { return Self.inactiveIcon }
        if let cached = activeIconCache[tint] { return cached }
        let icon = Self.makeActiveIcon(color: tint.color)
        activeIconCache[tint] = icon
        return icon
    }

    /// tint별 활성 아이콘 캐시. 인스턴스 프로퍼티(@MainActor 격리)라 동시성 안전.
    private var activeIconCache: [MenuBarTint: NSImage] = [:]
    private static let inactiveIcon: NSImage = makeInactiveIcon()

    private static func makeInactiveIcon() -> NSImage {
        // 11 미만은 SF Symbol이 없다 — nil이면 상태 아이템 폭이 0이 되므로 직접 그린 눈으로 대체한다.
        let base = NSImage.symbol(MaraSymbol.resting, accessibilityDescription: "Mara — inactive")
            ?? LegacyStatusIcon.eye(open: false)
        base.isTemplate = true              // 메뉴바 톤에 자동 적응(흑백)
        return base
    }

    private static func makeActiveIcon(color: NSColor) -> NSImage {
        let description = "Mara — keep-awake active"
        let base = NSImage.symbol(MaraSymbol.awake, accessibilityDescription: description)
            ?? LegacyStatusIcon.eye(open: true)
        let tinted = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            color.set()
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
        menu.addItem(automationMenuItem())
        menu.addItem(lowBatteryMenuItem())
        if requestNotificationAuth != nil { menu.addItem(notifyMenuItem()) }
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
            durMenu.addItem(Self.sectionHeader("Recent"))
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

        if LegacySupport.launchAtLogin, let enabled = launchAtLoginEnabled {
            let login = addItem(to: menu, title: "Launch at Login",
                                action: #selector(toggleLaunchAtLogin), symbol: "play.circle")
            login.state = enabled ? .on : .off
        }

        menu.addItem(iconColorMenuItem())
    }

    /// "Icon Color" 서브메뉴 — 활성 아이콘 tint 선택(라디오식 체크 + 색 스와치).
    private func iconColorMenuItem() -> NSMenuItem {
        let sub = NSMenu()
        let current = env.prefs.menuBarTint
        for tint in MenuBarTint.allCases {
            let item = NSMenuItem(title: tint.displayName,
                                  action: #selector(setMenuBarTint(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tint
            item.state = (tint == current) ? .on : .off
            item.image = Self.swatch(tint.color)
            sub.addItem(item)
        }
        let parent = NSMenuItem(title: "Icon Color", action: nil, keyEquivalent: "")
        parent.image = Self.menuSymbol("paintpalette")
        parent.submenu = sub
        return parent
    }

    /// 메뉴 항목용 색 스와치 — 작은 원형 채움. non-template이라 색 그대로 렌더된다.
    private static func swatch(_ color: NSColor, diameter: CGFloat = 12) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func addFooterItems(to menu: NSMenu) {
        menu.addItem(supportMenuItem())

        if let (target, action) = checkForUpdates {
            // 타깃이 updaterController여야 Sparkle이 canCheckForUpdates로 활성/비활성을 자동 관리한다.
            menu.addItem(versionFooterItem())
            let update = NSMenuItem(title: "Check for Updates…", action: action, keyEquivalent: "")
            update.target = target
            update.image = Self.menuSymbol("arrow.triangle.2.circlepath")
            menu.addItem(update)
        }

        addItem(to: menu, title: "Quit Mara", action: #selector(quit), key: "q", symbol: "power")
    }

    /// "Support Mara" 서브메뉴 — 후원처를 `SponsorLink.allCases` 그대로 렌더한다.
    /// 최상위를 어지럽히지 않도록 Icon Color와 같은 서브메뉴 형태를 쓴다.
    private func supportMenuItem() -> NSMenuItem {
        let sub = NSMenu()
        for link in SponsorLink.allCases {
            let item = NSMenuItem(title: link.title,
                                  action: #selector(openSponsorLink(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = link
            item.image = Self.menuSymbol(link.symbol)
            sub.addItem(item)
        }
        let parent = NSMenuItem(title: "Support Mara", action: nil, keyEquivalent: "")
        parent.image = Self.menuSymbol(SponsorLink.containerSymbol)
        parent.submenu = sub
        return parent
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
        NSImage.symbol(name)   // 11 미만 nil — 장식이라 글자만 남는다
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
        guard #available(macOS 13.0, *), let enabled = launchAtLoginEnabled else { return }
        LaunchAtLogin.setEnabled(!enabled)
        launchAtLoginEnabled = LaunchAtLogin.isEnabled   // 실제 결과로 재동기화(토글 실패 시에도 정확)
    }

    @objc private func setMenuBarTint(_ sender: NSMenuItem) {
        guard let tint = sender.representedObject as? MenuBarTint else { return }
        env.prefs.menuBarTint = tint   // didSet 저장 + @Published → tint sink가 아이콘을 다시 굽는다
    }

    @objc private func openSponsorLink(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? SponsorLink else { return }
        link.open()
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

// MARK: - Legacy (menu-only): 본판 Settings 창의 조작을 서브메뉴로 옮긴 것.
// 무엇이 보이고 체크되는지는 Core `LegacyMenuPolicy`(테스트됨)가 정하고, 여기서는 NSMenuItem으로 옮기기만 한다.

extension StatusBarController {
    /// 14 미만의 `NSMenuItem.sectionHeader` 대체 — 비활성 제목 항목.
    fileprivate static func sectionHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return .sectionHeader(title: title) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    fileprivate static func disabledLine(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.indentationLevel = 1
        return item
    }

    fileprivate func versionFooterItem() -> NSMenuItem {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let item = NSMenuItem(title: LegacyMenuPolicy.versionFooter(shortVersion: short, build: build),
                              action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: Automation

    fileprivate func automationMenuItem() -> NSMenuItem {
        let sub = NSMenu()
        let cfg = env.effectiveTriggerConfig
        let snapshot = env.triggerEngine.snapshot
        if snapshot.isSuppressed {
            sub.addItem(Self.disabledLine("Paused — turned off manually; resumes after all triggers clear"))
            sub.addItem(.separator())
        }
        let rows: [(TriggerKind, String, Bool, String)] = [
            (.charging, "Keep awake while charging", cfg.chargingEnabled, "bolt.fill"),
            (.externalDisplay, "Keep awake with external display", cfg.externalDisplayEnabled, "display.2"),
            (.appRunning, "Keep awake while specific apps run", cfg.appRunningEnabled, "app.badge"),
            (.network, "Keep awake on specific networks", cfg.networkEnabled, "wifi"),
        ]
        for (kind, title, on, symbol) in rows {
            let item = NSMenuItem(title: title, action: #selector(toggleTrigger(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.state = on ? .on : .off
            item.image = Self.menuSymbol(symbol)
            sub.addItem(item)
            // 켜진 트리거마다 자기 상태 한 줄(본판 Settings와 같은 구조).
            if let text = TriggerStatusFormatter.text(kind, config: cfg, snapshot: snapshot) {
                sub.addItem(Self.disabledLine(text))
            }
            if kind == .appRunning, on { sub.addItem(watchedAppsMenuItem()) }
            if kind == .network, on { sub.addItem(networksMenuItem()) }
        }
        let parent = NSMenuItem(title: "Automation", action: nil, keyEquivalent: "")
        parent.image = Self.menuSymbol("bolt.circle")
        parent.submenu = sub
        return parent
    }

    fileprivate func watchedAppsMenuItem() -> NSMenuItem {
        let sub = NSMenu()
        let running = NSWorkspace.shared.runningApplications.map {
            LegacyMenuPolicy.RunningApp(bundleID: $0.bundleIdentifier, name: $0.localizedName,
                                        isProhibited: $0.activationPolicy == .prohibited,
                                        isRegular: $0.activationPolicy == .regular)
        }
        let items = LegacyMenuPolicy.watchedAppItems(running: running,
                                                     watched: env.prefs.triggerConfig.watchedBundleIDs,
                                                     selfBundleID: Bundle.main.bundleIdentifier)
        if items.isEmpty { sub.addItem(Self.disabledLine("No apps running")) }
        for app in items {
            let title = app.running ? app.title : "\(app.title) (not running)"
            let item = NSMenuItem(title: title, action: #selector(toggleWatchedApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.bundleID
            item.state = app.watched ? .on : .off
            sub.addItem(item)
        }
        let parent = NSMenuItem(title: "Watched Apps", action: nil, keyEquivalent: "")
        parent.indentationLevel = 1
        parent.submenu = sub
        return parent
    }

    fileprivate func networksMenuItem() -> NSMenuItem {
        let sub = NSMenu()
        let remember = NSMenuItem(title: "Remember Current Network", action: #selector(rememberNetwork),
                                  keyEquivalent: "")
        remember.target = self
        let current = env.currentNetwork?.gatewayMAC
        remember.isEnabled = current.map { !env.prefs.triggerConfig.watchedNetworks.contains($0) } ?? false
        sub.addItem(remember)
        let saved = env.prefs.triggerConfig.watchedNetworks
        if !saved.isEmpty {
            sub.addItem(.separator())
            sub.addItem(Self.sectionHeader("Remembered — click to forget"))
            for mac in saved {
                let item = NSMenuItem(title: mac == current ? "\(mac) (current)" : mac,
                                      action: #selector(forgetNetwork(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = mac
                sub.addItem(item)
            }
        }
        let parent = NSMenuItem(title: "Networks", action: nil, keyEquivalent: "")
        parent.indentationLevel = 1
        parent.submenu = sub
        return parent
    }

    // MARK: Low battery / notifications

    fileprivate func lowBatteryMenuItem() -> NSMenuItem {
        let sub = NSMenu()
        sub.addItem(Self.disabledLine("On battery, keep-awake won't start — and ends — at or below this level."))
        sub.addItem(.separator())
        for entry in LegacyMenuPolicy.lowBatteryItems(stored: env.prefs.lowBatteryThreshold) {
            var title = "\(entry.percent)%"
            if entry.isOffGrid { title += " (current)" }
            if entry.percent == 100 { title += " — never on battery" }
            let item = NSMenuItem(title: title, action: #selector(setLowBattery(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.percent
            item.state = entry.checked ? .on : .off
            sub.addItem(item)
        }
        let parent = NSMenuItem(title: "Low-Battery Auto-Off", action: nil, keyEquivalent: "")
        parent.image = Self.menuSymbol("battery.25")
        parent.submenu = sub
        return parent
    }

    fileprivate func notifyMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Notify on Automatic Start & End", action: #selector(toggleNotify),
                              keyEquivalent: "")
        item.target = self
        item.state = env.prefs.notifyAutoSessionChanges ? .on : .off
        item.image = Self.menuSymbol("bell.badge")
        return item
    }

    // MARK: Actions

    @objc fileprivate func toggleTrigger(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = TriggerKind(rawValue: raw) else { return }
        switch kind {
        case .charging:        env.prefs.triggerConfig.chargingEnabled.toggle()
        case .externalDisplay: env.prefs.triggerConfig.externalDisplayEnabled.toggle()
        case .appRunning:      env.prefs.triggerConfig.appRunningEnabled.toggle()
        case .network:         env.prefs.triggerConfig.networkEnabled.toggle()
        }
    }

    @objc fileprivate func toggleWatchedApp(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        if let id = env.prefs.triggerConfig.watchedBundleIDs.first(where: { $0.rawValue == raw }) {
            env.prefs.triggerConfig.removeWatchedBundleID(id)
        } else {
            env.prefs.triggerConfig.addWatchedBundleID(raw)
        }
    }

    @objc fileprivate func rememberNetwork() {
        guard let mac = env.currentNetwork?.gatewayMAC,
              !env.prefs.triggerConfig.watchedNetworks.contains(mac) else { return }
        env.prefs.triggerConfig.watchedNetworks.append(mac)
    }

    @objc fileprivate func forgetNetwork(_ sender: NSMenuItem) {
        guard let mac = sender.representedObject as? String else { return }
        let alert = NSAlert()
        alert.messageText = "Forget network \(mac)?"
        alert.informativeText = "Mara will no longer keep your Mac awake on this network."
        alert.addButton(withTitle: "Forget")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        env.prefs.triggerConfig.watchedNetworks.removeAll { $0 == mac }
    }

    @objc fileprivate func setLowBattery(_ sender: NSMenuItem) {
        guard let percent = sender.representedObject as? Int else { return }
        env.prefs.lowBatteryThreshold = percent
    }

    @objc fileprivate func toggleNotify() {
        if env.prefs.notifyAutoSessionChanges {
            env.prefs.notifyAutoSessionChanges = false
            return
        }
        // 켤 때만 권한을 요청한다(시스템 프롬프트는 최초 1회). 거부되면 켜지 않는다(강요 금지).
        requestNotificationAuth? { [weak self] granted in
            self?.env.prefs.notifyAutoSessionChanges = granted
        }
    }
}
