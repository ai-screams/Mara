import SwiftUI
import Combine
import MaraCore

/// "Night Watch" 설정 창 — 항상 다크(MaraTheme), 눈 아이콘 glow 헤더 + 카드형 섹션.
/// 카드/행 컴포넌트는 SettingsComponents.swift, 창 크롬은 SettingsWindowPresenter 담당.
struct SettingsView: View {
    @ObservedObject var prefs: PrefsStore
    @ObservedObject var session: SessionManager
    @ObservedObject var triggers: TriggerEngine
    /// 네트워크는 비동기로 늦게 알려지고, 감시 목록이 비면 네트워크 트리거가 없어 진단 갱신도 없다.
    /// 그래서 클로저로 읽지 않고 직접 구독한다 — 아니면 버튼·안내가 첫 등록 전에 낡은 채 남는다.
    let networkChanges: AnyPublisher<NetworkIdentity?, Never>
    var checkForUpdates: () -> Void = {}
    var requestNotificationAuth: () async -> Bool = { false }
    @State private var appPicker: AppPickerPayload?
    @State private var manualBundleID = ""
    @State private var currentNetwork: NetworkIdentity?

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
        // 투명 titlebar(신호등 버튼) 아래로 헤더가 깔리지 않게 위를 비운다. titlebar safe area(32pt)는 창 쪽에서
        // 끄고(SettingsWindowPresenter) 그만큼을 이 여백에 합쳤다.
        .padding(.top, 62)
        .frame(width: 400)
        .background(MaraTheme.bg)
        .preferredColorScheme(.dark)
        .maraAccent(prefs.menuBarTint)
        .onReceive(networkChanges) { currentNetwork = $0 }
    }

    /// 메뉴 "Keep display awake"와 같은 경로(`PrefsStore.setKeepDisplayAwake`) — 켜진 세션에도 바로 적용한다.
    /// 적용에 실패하면 기본값이 바뀌지 않으므로 토글이 이전 값으로 돌아가고 Error 줄이 이유를 보인다.
    private var keepDisplayBinding: Binding<Bool> {
        Binding(get: { prefs.defaultKeepDisplayAwake },
                set: { prefs.setKeepDisplayAwake($0, applyingTo: session) })
    }

    // MARK: - Cards

    private var generalCard: some View {
        SettingsCard(title: "GENERAL") {
            SettingsToggleRow(symbol: "display", title: "Keep display awake by default",
                              isOn: keepDisplayBinding)
            SettingsStepperRow(symbol: "battery.25", title: "Low-battery auto-off",
                               value: $prefs.lowBatteryThreshold,
                               range: SessionManager.batteryThresholdRange, step: 5,
                               offValue: SessionManager.batteryAutoOffDisabled)
            if prefs.lowBatteryThreshold == SessionManager.batteryAutoOffDisabled {
                SettingsCaption("Off — keep-awake runs at any battery level.")
            } else {
                SettingsCaption("On battery power, a session won't start—and a running session ends—when the level is at or below the threshold. At 100%, keep-awake never runs on battery. Step below 5% to turn it off.")
            }
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
        if let status = SettingsText.triggerStatus(kind, config: prefs.triggerConfig, snapshot: triggers.snapshot) {
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
                // 감은 눈(eye.slash)이 뜬 눈보다 키가 커서, 상태가 바뀔 때마다 머리글 아래 전체가 밀렸다.
                // 두 심볼을 같은 높이의 자리에 둔다.
                .frame(height: 40)
                // 애니메이션은 눈에만 건다. 머리글 전체에 걸면 폭이 다른 상태 문구가 바뀌는 동안 글자가 미끄러진다.
                .animation(.easeInOut(duration: 0.25), value: active)
                .accessibilityHidden(true)
            Text("Mara")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .kerning(5)
                .foregroundStyle(.white)
            Text(active ? "Keeping your Mac awake" : "The eye is resting — your Mac may sleep")
                .font(.caption)
                .foregroundStyle(active ? accent : MaraTheme.muted)
            // 마지막 세션 이벤트는 세션 상태 문구 바로 밑에 둔다 — 알림 토글 밑에 두면 알림 기록처럼 읽힌다.
            if let last = session.recentEvents.last {
                Text(SettingsText.eventLine(last))
                    .font(.caption)
                    .foregroundStyle(MaraTheme.muted)
            }
        }
        .frame(maxWidth: .infinity)
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
        // soft-deprecated(SDK: deprecated 100000.0 센티넬 — 현재 경고 없음). Apple이 실제 버전을 배정하면
        // SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 빌드가 깨진다. 대체는 `.menuStyle(.button).buttonStyle(.borderless)`
        // 인데 렌더가 달라져 눈 확인 필요 — 블라인드 스왑 금지. CI가 이 줄로 깨지면 그때 교체+스크린샷.
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

    /// 감시 앱 목록. 순서는 목록 → 추가 → 직접 입력(편집 목록의 흔한 형태), 들여쓰기는 토글 라벨 글자 위치에 맞춘다.
    private var watchedAppsList: some View {
        VStack(alignment: .leading, spacing: 7) {
            WatchedRows(count: prefs.triggerConfig.watchedBundleIDs.count) {
                ForEach(prefs.triggerConfig.watchedBundleIDs, id: \.self) { id in
                    WatchedAppRow(bundleID: id.rawValue) {
                        prefs.triggerConfig.removeWatchedBundleID(id)
                    }
                }
            }

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
        .padding(.leading, SettingsLayout.childIndent)
    }

    private func submitManualBundleID() {
        // 무효 형식/중복이면 필드를 비우지 않는다 — 사용자가 고칠 수 있게 남긴다.
        if prefs.triggerConfig.addWatchedBundleID(manualBundleID) {
            manualBundleID = ""
        }
    }

    /// 감시 네트워크 목록. 앱 목록과 같은 형태(목록 → 추가)와 들여쓰기. 네트워크를 못 알아볼 때의 이유는 위 상태 줄이 말한다.
    private var networkList: some View {
        VStack(alignment: .leading, spacing: 7) {
            WatchedRows(count: prefs.triggerConfig.watchedNetworks.count) {
                ForEach(prefs.triggerConfig.watchedNetworks, id: \.self) { mac in
                    WatchedNetworkRow(mac: mac,
                                      savedName: prefs.triggerConfig.networkDisplayName(mac),
                                      onRename: { prefs.triggerConfig.setNetworkName($0, for: mac) },
                                      onRemove: { prefs.triggerConfig.removeWatchedNetwork(mac) })
                }
            }

            Button {
                if let identity = currentNetwork {
                    prefs.triggerConfig.addWatchedNetwork(identity)
                }
            } label: {
                Label("Remember current network", systemImage: "plus.circle.fill")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            // 색을 직접 지정하면 비활성이어도 흐려지지 않는다 — 비활성일 땐 muted로 바꿔 상태와 모양을 맞춘다.
            .foregroundStyle(currentNetwork == nil ? MaraTheme.muted : accent)
            .disabled(currentNetwork == nil)
        }
        .padding(.leading, SettingsLayout.childIndent)
    }
}
