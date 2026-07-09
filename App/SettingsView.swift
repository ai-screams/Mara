import SwiftUI
import MaraCore

/// "Night Watch" 설정 창 — 항상 다크(MaraTheme), 눈 아이콘 glow 헤더 + 카드형 섹션.
/// 창 크롬(투명 titlebar·배경색)은 AppDelegate.openSettings가 맞춰준다.
struct SettingsView: View {
    @ObservedObject var prefs: PrefsStore
    @ObservedObject var session: SessionManager
    let currentNetwork: () -> NetworkIdentity?
    var checkForUpdates: () -> Void = {}

    var body: some View {
        VStack(spacing: 18) {
            header

            card("GENERAL") {
                toggleRow("display", "Keep display awake by default",
                          isOn: $prefs.defaultKeepDisplayAwake)
                stepperRow("battery.25", "Low-battery auto-off",
                           value: $prefs.lowBatteryThreshold, in: 5...50, step: 5)
                caption("Ends the session safely when battery level (on battery power) drops below the threshold.")
            }

            card("AUTOMATION") {
                toggleRow("bolt.fill", "Keep awake while charging",
                          isOn: $prefs.triggerConfig.chargingEnabled)
                toggleRow("display.2", "Keep awake with external display",
                          isOn: $prefs.triggerConfig.externalDisplayEnabled)
                toggleRow("app.badge", "Keep awake while specific apps run",
                          isOn: $prefs.triggerConfig.appRunningEnabled)
                if prefs.triggerConfig.appRunningEnabled {
                    caption("App bundle IDs to watch (one per line)")
                    TextEditor(text: bundleIDsBinding)
                        .frame(height: 72)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(MaraTheme.textMid)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 6))
                }
                toggleRow("wifi", "Keep awake on specific networks",
                          isOn: $prefs.triggerConfig.networkEnabled)
                if prefs.triggerConfig.networkEnabled {
                    networkList
                }
            }

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

    // MARK: - Header / Footer

    /// 눈 = 실제 세션 상태 표시기 — 메뉴바 아이콘과 같은 의미(활성: 뜬 눈+glow / 비활성: 감은 눈).
    private var header: some View {
        let active = session.state.isActive
        return VStack(spacing: 5) {
            Image(systemName: active ? "eye.fill" : "eye.slash.fill")
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

    // MARK: - Card & rows

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.bold))
                .kerning(1.4)
                .foregroundStyle(MaraTheme.muted)
                .padding(.leading, 2)
            VStack(alignment: .leading, spacing: 11) { content() }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MaraTheme.card, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func toggleRow(_ symbol: String, _ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 9) {
            icon(symbol)
            Text(title).font(.callout).foregroundStyle(.white)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private func stepperRow(_ symbol: String, _ title: String,
                            value: Binding<Int>, in range: ClosedRange<Int>, step: Int) -> some View {
        HStack(spacing: 9) {
            icon(symbol)
            Text(title).font(.callout).foregroundStyle(.white)
            Spacer(minLength: 8)
            Text("\(value.wrappedValue)%")
                .font(.callout.monospacedDigit())
                .foregroundStyle(MaraTheme.accent)
            Stepper(title, value: value, in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
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

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13))
            .foregroundStyle(MaraTheme.accent)
            .frame(width: 18)
            .accessibilityHidden(true)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(MaraTheme.muted)
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
}
