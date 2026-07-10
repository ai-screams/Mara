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
        .tint(MaraTheme.accent)
    }

    // MARK: - Cards

    private var generalCard: some View {
        SettingsCard(title: "GENERAL") {
            SettingsToggleRow(symbol: "display", title: "Keep display awake by default",
                              isOn: $prefs.defaultKeepDisplayAwake)
            SettingsStepperRow(symbol: "battery.25", title: "Low-battery auto-off",
                               value: $prefs.lowBatteryThreshold, range: 5...50, step: 5)
            SettingsCaption("Ends the session safely when battery level (on battery power) drops below the threshold.")
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
                SettingsCaption("App bundle IDs to watch (one per line)")
                bundleIDsEditor
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
                .foregroundStyle(active ? MaraTheme.accent : MaraTheme.muted)
                .shadow(color: active ? MaraTheme.accent.opacity(0.55) : .clear, radius: 14)
                .accessibilityHidden(true)
            Text("Mara")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .kerning(5)
                .foregroundStyle(.white)
            Text(active ? "Keeping your Mac awake" : "The eye is resting — your Mac may sleep")
                .font(.caption)
                .foregroundStyle(active ? MaraTheme.accent : MaraTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.25), value: active)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("v\(Self.version)")
                .font(.caption)
                .foregroundStyle(MaraTheme.muted)
            Text("·").font(.caption).foregroundStyle(MaraTheme.muted)
            Button("Check for Updates…", action: checkForUpdates)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(MaraTheme.accent)
        }
        .frame(maxWidth: .infinity)
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    // MARK: - Trigger inputs

    private var bundleIDsEditor: some View {
        TextEditor(text: bundleIDsBinding)
            .frame(height: 72)
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(MaraTheme.textMid)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 6))
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
            .foregroundStyle(MaraTheme.accent)
            .disabled(currentNetwork() == nil)

            ForEach(prefs.triggerConfig.watchedNetworks, id: \.self) { mac in
                HStack {
                    Text(mac)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(MaraTheme.textMid)
                    Spacer()
                    Button {
                        prefs.triggerConfig.watchedNetworks.removeAll { $0 == mac }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MaraTheme.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(mac)")
                }
            }
        }
    }

    private var bundleIDsBinding: Binding<String> {
        Binding(
            get: { prefs.triggerConfig.watchedBundleIDs.joined(separator: "\n") },
            set: { text in
                prefs.triggerConfig.watchedBundleIDs = text
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    // MARK: - Trigger diagnostics formatter

    /// Core 진단 값 → 표시 문구(영어) 매핑. 토글 OFF면 nil(행 숨김).
    /// enabled인데 감시 목록이 비면 armed되지 않으므로(activeSpecs 제외) 안내 문구를 반환한다.
    static func triggerStatus(_ kind: TriggerKind, config: TriggerConfig, snapshot: TriggerEngineSnapshot)
        -> (active: Bool, text: String)? {
        switch kind {
        case .charging:
            guard config.chargingEnabled else { return nil }
        case .externalDisplay:
            guard config.externalDisplayEnabled else { return nil }
        case .appRunning:
            guard config.appRunningEnabled else { return nil }
            guard !config.watchedBundleIDs.isEmpty else {
                return (false, "Add app bundle IDs below to activate")
            }
        case .network:
            guard config.networkEnabled else { return nil }
            guard !config.watchedNetworks.isEmpty else {
                return (false, "Remember a network below to activate")
            }
        }
        // 설정 반영은 300ms debounce — 재조정 전엔 스냅샷에 아직 없을 수 있다(일시 상태).
        guard let snap = snapshot.trigger(kind) else { return (false, "Checking…") }
        let active = snap.isSatisfied
        switch snap.diagnostic {
        case .charging(let onAC):
            return (active, onAC ? "Active — on AC power" : "Inactive — on battery")
        case .externalDisplay(let count):
            return (active, active ? "Active — \(count) displays" : "Inactive — built-in display only")
        case .appRunning(let matched):
            if matched.count == 1, let id = matched.first {
                return (active, "Active — \(id) running")
            }
            return (active, active ? "Active — \(matched.count) watched apps running"
                                   : "Inactive — no watched app running")
        case .network(let current, let matched):
            guard let current else { return (active, "Inactive — can't resolve gateway") }
            return (active, matched ? "Active — \(current.gatewayMAC)"
                                    : "Inactive — different network")
        case nil:
            return (active, active ? "Active" : "Inactive")
        }
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
        }
    }
}
