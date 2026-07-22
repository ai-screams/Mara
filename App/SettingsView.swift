import SwiftUI
import MaraCore

/// "Night Watch" 설정 창 — 항상 다크(MaraTheme), 눈 아이콘 glow 헤더 + 카드형 섹션.
/// 카드/행 컴포넌트는 SettingsComponents.swift, 창 크롬은 SettingsWindowPresenter 담당.
struct SettingsView: View {
    @ObservedObject var prefs: PrefsStore
    @ObservedObject var session: SessionManager
    @ObservedObject var triggers: TriggerEngine
    let currentNetwork: () -> NetworkIdentity?
    var checkForUpdates: () -> Void = {}
    var requestNotificationAuth: () async -> Bool = { false }
    @State private var appPicker: AppPickerPayload?
    @State private var manualBundleID = ""

    /// sheet(item:)용 페이로드 — isPresented+별도 @State 조합은 첫 표시가 낡은(빈) 상태를
    /// 캡처하는 SwiftUI 함정이 있다(실사고: 빈 피커). 데이터가 곧 표시 트리거가 되게 한다.
    private struct AppPickerPayload: Identifiable {
        let id = UUID()
        let apps: [RunningAppItem]
    }

    /// 앱 accent = 선택된 메뉴바 tint. SettingsView 자기 참조엔 직접 사용한다 —
    /// `.maraAccent`가 자식엔 `\.accentTint`를 주입하지만 자기 뷰의 @Environment는 부모값을 읽으므로.
    private var accent: Color { prefs.menuBarTint.accentColor }

    var body: some View {
        VStack(spacing: 18) {
            header
            generalCard
            automationCard
            footer
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
        .padding(.top, 30)          // 투명 titlebar(신호등 버튼) 아래로 헤더가 깔리지 않게
        .frame(width: 400)
        .background(MaraTheme.bg)
        .preferredColorScheme(.dark)
        .maraAccent(prefs.menuBarTint)
    }

    // MARK: - Cards

    private var generalCard: some View {
        SettingsCard(title: "GENERAL") {
            SettingsToggleRow(symbol: "display", title: "Keep display awake by default",
                              isOn: $prefs.defaultKeepDisplayAwake)
            SettingsStepperRow(symbol: "battery.25", title: "Low-battery auto-off",
                               value: $prefs.lowBatteryThreshold,
                               range: SessionManager.batteryThresholdRange, step: 5)
            SettingsCaption("On battery power, a session won't start—and a running session ends—when the level is at or below the threshold. At 100%, keep-awake never runs on battery.")
            SettingsToggleRow(symbol: "bell.badge", title: "Notify on automatic start & end",
                              isOn: $prefs.notifyAutoSessionChanges)
                .onChange(of: prefs.notifyAutoSessionChanges) { _, enabled in
                    guard enabled else { return }
                    // 연타 시 Task가 중복 enqueue될 수 있으나 requestAuthorization은 최초 프롬프트 후 멱등(캐시 상태 반환)이라 무해.
                    Task { @MainActor in
                        // 시스템 프롬프트는 최초 1회. 거부 상태면 토글을 되돌린다(강요 금지).
                        if await requestNotificationAuth() == false {
                            prefs.notifyAutoSessionChanges = false
                        }
                    }
                }
            if let last = session.recentEvents.last {
                SettingsCaption("Last: \(Self.eventLine(last))")
            }
            if let failure = session.lastFailure {
                SettingsCaption("Error: \(SessionFailureText.describe(failure))")
            }
        }
    }

    private var automationCard: some View {
        SettingsCard(title: "AUTOMATION") {
            SettingsToggleRow(symbol: "bolt.fill", title: "Keep awake while charging",
                              isOn: $prefs.triggerConfig.chargingEnabled)
            statusRow(for: .charging)
            SettingsToggleRow(symbol: "display.2", title: "Keep awake with external display",
                              isOn: $prefs.triggerConfig.externalDisplayEnabled)
            statusRow(for: .externalDisplay)
            SettingsToggleRow(symbol: "app.badge", title: "Keep awake while specific apps run",
                              isOn: $prefs.triggerConfig.appRunningEnabled)
            statusRow(for: .appRunning)
            if prefs.triggerConfig.appRunningEnabled {
                watchedAppsList
            }
            SettingsToggleRow(symbol: "wifi", title: "Keep awake on specific networks",
                              isOn: $prefs.triggerConfig.networkEnabled)
            statusRow(for: .network)
            if prefs.triggerConfig.networkEnabled {
                networkList
            }
            if triggers.snapshot.isSuppressed {
                // 카드 레벨 안내 — 특정 트리거 소속이 아니므로 들여쓰지 않는다.
                SettingsStatusRow(active: false,
                                  text: "Paused — turned off manually; resumes after all triggers clear",
                                  indent: false)
            }
        }
    }

    /// 켜진 트리거에만 진단 상태 행을 렌더한다 (꺼진 트리거는 행 없음).
    @ViewBuilder
    private func statusRow(for kind: TriggerKind) -> some View {
        if let status = Self.triggerStatus(kind, config: prefs.triggerConfig, snapshot: triggers.snapshot) {
            SettingsStatusRow(active: status.active, text: status.text)
        }
    }

    // MARK: - Header / Footer

    /// 눈 = 실제 세션 상태 표시기 — 메뉴바 아이콘과 같은 의미(활성: 뜬 눈+glow / 비활성: 감은 눈).
    private var header: some View {
        let active = session.state.isActive
        return VStack(spacing: 5) {
            Image(systemName: active ? MaraSymbol.awake : MaraSymbol.resting)
                .font(.system(size: 32))
                .foregroundStyle(active ? accent : MaraTheme.muted)
                .shadow(color: active ? accent.opacity(0.55) : .clear, radius: 14)
                .accessibilityHidden(true)
            Text("Mara")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .kerning(5)
                .foregroundStyle(.white)
            Text(active ? "Keeping your Mac awake" : "The eye is resting — your Mac may sleep")
                .font(.caption)
                .foregroundStyle(active ? accent : MaraTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.25), value: active)
    }

    private var footer: some View {
        // 2줄 구성: 후원(중앙) 위 / 버전·업데이트 아래. VStack 기본 정렬(.center)이 곧 중앙정렬이다.
        VStack(spacing: 8) {
            supportMenu
            HStack(spacing: 6) {
                Text("v\(Self.version)")
                    .font(.caption)
                    .foregroundStyle(MaraTheme.muted)
                Text("·").font(.caption).foregroundStyle(MaraTheme.muted)
                Button("Check for Updates…", action: checkForUpdates)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(accent)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 후원 링크 — 메뉴바 "Support Mara" 서브메뉴와 같은 목록(`SponsorLink.allCases`)을 쓴다.
    /// 후원처를 나열하지 않고 드롭다운 하나로 접어, footer가 기능 항목보다 튀지 않게 한다.
    private var supportMenu: some View {
        Menu {
            ForEach(SponsorLink.allCases, id: \.self) { link in
                Button {
                    link.open()
                } label: {
                    Label(link.title, systemImage: link.symbol)
                }
            }
        } label: {
            Label("Support", systemImage: SponsorLink.containerSymbol)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .font(.caption)
        .foregroundStyle(accent)
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    // MARK: - Trigger inputs

    private var watchedAppsList: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                // 여는 순간 1회 스냅샷으로 고정 — 시트가 떠 있는 동안 부모 재렌더(진단 갱신 등)마다
                // NSWorkspace를 재열거하지 않고, 추가한 행이 목록에서 사라지는 대신 체크로 남는다.
                appPicker = AppPickerPayload(apps: RunningAppSnapshot.fetch(
                    excluding: Set(prefs.triggerConfig.watchedBundleIDs.map(\.rawValue))))
            } label: {
                Label("Add Running App…", systemImage: "plus.circle.fill")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(accent)
            .sheet(item: $appPicker) { payload in
                RunningAppPickerView(
                    apps: payload.apps,
                    onAdd: { prefs.triggerConfig.addWatchedBundleID($0) }
                )
            }

            ForEach(prefs.triggerConfig.watchedBundleIDs, id: \.self) { id in
                RemovableChipRow(text: id.rawValue) {
                    prefs.triggerConfig.removeWatchedBundleID(id)
                }
            }

            // Advanced: 검증된 수동 입력 — 제출 시에만 반영, 성공 시에만 비운다.
            HStack(spacing: 6) {
                TextField("Add bundle ID manually", text: $manualBundleID)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(MaraTheme.textMid)
                    .onSubmit(submitManualBundleID)
                Button("Add", action: submitManualBundleID)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(accent)
                    .disabled(manualBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(6)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func submitManualBundleID() {
        // 무효 형식/중복이면 필드를 비우지 않는다 — 사용자가 고칠 수 있게 남긴다.
        if prefs.triggerConfig.addWatchedBundleID(manualBundleID) {
            manualBundleID = ""
        }
    }

    private var networkList: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                if let mac = currentNetwork()?.gatewayMAC,
                   !prefs.triggerConfig.watchedNetworks.contains(mac) {
                    prefs.triggerConfig.watchedNetworks.append(mac)
                }
            } label: {
                Label("Remember current network", systemImage: "plus.circle.fill")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(accent)
            .disabled(currentNetwork() == nil)

            ForEach(prefs.triggerConfig.watchedNetworks, id: \.self) { mac in
                RemovableChipRow(text: mac) {
                    prefs.triggerConfig.watchedNetworks.removeAll { $0 == mac }
                }
            }
        }
    }

    // MARK: - Trigger diagnostics formatter

    /// Core `TriggerStatusText` 결정 → 표시 문구(영어) 매핑. 토글 OFF면 nil(행 숨김).
    /// 분기 로직은 Core(`TriggerStatusText.evaluate`, 테스트됨)에 있고, 이 함수는 문구 렌더링만 맡는다.
    static func triggerStatus(_ kind: TriggerKind, config: TriggerConfig, snapshot: TriggerEngineSnapshot)
        -> (active: Bool, text: String)? {
        guard let status = TriggerStatusText.evaluate(kind, config: config, snapshot: snapshot) else { return nil }
        switch status {
        case .needsWatchList(.appRunning):
            return (false, "Add app bundle IDs below to activate")
        case .needsWatchList(.network):
            return (false, "Remember a network below to activate")
        case .needsWatchList:
            return (false, "Add entries below to activate")   // 도달 불가(appRunning/network만) — 망라성용
        case .checking:
            return (false, "Checking…")
        case .charging(let active, let onAC):
            return (active, onAC ? "Active — on AC power" : "Inactive — on battery")
        case .batteryUnavailable:
            return (false, "Unavailable — can't read power source")
        case .externalDisplay(let active, let count):
            return externalDisplayStatus(active: active, count: count)
        case .appRunningSingle(let active, let id):
            return (active, "Active — \(id) running")
        case .appRunningMultiple(let count):
            return (true, "Active — \(count) watched apps running")
        case .appRunningNone(let watched):
            return appRunningNoneStatus(watched: watched)
        case .network(let active, let mac, let matched):
            return networkStatus(active: active, mac: mac, matched: matched)
        case .plain(let active):
            return (active, active ? "Active" : "Inactive")
        }
    }

    private static func externalDisplayStatus(active: Bool, count: Int) -> (active: Bool, text: String) {
        (active, active
            ? "Active — \(count) \(count == 1 ? "display" : "displays")"
            : "Inactive — built-in display only")
    }

    private static func appRunningNoneStatus(watched: Int) -> (active: Bool, text: String) {
        // 감시 개수를 함께 표기 — 오타 가능성 vs 앱 미실행으로 가설을 좁힐 수 있게 한다.
        (false, "Inactive — \(watched) \(watched == 1 ? "app" : "apps") watched, none running")
    }

    private static func networkStatus(active: Bool, mac: String?, matched: Bool)
        -> (active: Bool, text: String) {
        guard let mac else { return (active, "Inactive — can't resolve gateway") }
        return (active, matched ? "Active — \(mac)" : "Inactive — different network")
    }

    // MARK: - Event formatter

    /// 최근 이벤트 한 줄 요약(영어) — 메뉴를 로그 뷰어로 만들지 않는다는 원칙에 따라 1개만.
    static func eventLine(_ event: SessionEvent) -> String {
        let time = event.at.formatted(date: .omitted, time: .shortened)
        switch event.kind {
        case .started(let cfg):
            return cfg.origin == .trigger ? "started by trigger · \(time)" : "started · \(time)"
        case .stopped(.manual):               return "turned off · \(time)"
        case .stopped(.timerExpired):         return "timer expired · \(time)"
        case .stopped(.lowBattery(let p)):    return "ended — low battery \(p)% · \(time)"
        case .stopped(.triggerCleared):       return "ended — trigger cleared · \(time)"
        case .stopped(.replacedByNewSession): return "restarted · \(time)"
        case .scopeChanged:                   return "scope changed · \(time)"
        case .startRejected(_, .lowBattery(let p)): return "didn't start — low battery \(p)% · \(time)"
        case .startRejected:                  return "didn't start · \(time)"
        }
    }
}
