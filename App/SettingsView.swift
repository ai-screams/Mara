import SwiftUI
import MaraCore

struct SettingsView: View {
    @ObservedObject var prefs: PrefsStore
    let currentNetwork: () -> NetworkIdentity?

    var body: some View {
        Form {
            Toggle("Keep display awake by default", isOn: $prefs.defaultKeepDisplayAwake)
            Stepper("Low-battery auto-off: \(prefs.lowBatteryThreshold)%",
                    value: $prefs.lowBatteryThreshold, in: 5...50, step: 5)
            Text("배터리(AC 미연결) 잔량이 임계 이하로 떨어지면 세션을 안전하게 종료합니다.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()
            Text("자동화 (트리거)").font(.headline)
            Toggle("충전(AC) 연결 시 자동 활성", isOn: $prefs.triggerConfig.chargingEnabled)
            Toggle("외장 디스플레이 연결 시 자동 활성", isOn: $prefs.triggerConfig.externalDisplayEnabled)
            Toggle("특정 앱 실행 중 자동 활성", isOn: $prefs.triggerConfig.appRunningEnabled)
            if prefs.triggerConfig.appRunningEnabled {
                Text("감시할 앱 Bundle ID (줄바꿈으로 구분)")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: bundleIDsBinding)
                    .frame(height: 80)
                    .font(.system(.body, design: .monospaced))
                    .border(.secondary)
            }
            Toggle("특정 네트워크에서 자동 활성", isOn: $prefs.triggerConfig.networkEnabled)
            if prefs.triggerConfig.networkEnabled {
                Button("현재 네트워크 기억") {
                    if let mac = currentNetwork()?.gatewayMAC,
                       !prefs.triggerConfig.watchedNetworks.contains(mac) {
                        prefs.triggerConfig.watchedNetworks.append(mac)
                    }
                }
                .disabled(currentNetwork() == nil)
                ForEach(prefs.triggerConfig.watchedNetworks, id: \.self) { mac in
                    HStack {
                        Text(mac).font(.system(.caption, design: .monospaced))
                        Spacer()
                        Button("삭제") {
                            prefs.triggerConfig.watchedNetworks.removeAll { $0 == mac }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 380)
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
