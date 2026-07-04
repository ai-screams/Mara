import SwiftUI
import MaraCore

struct MenuBarView: View {
    @ObservedObject var session: SessionManager
    @ObservedObject var prefs: PrefsStore

    private var defaultConfig: SessionConfig {
        let scope = prefs.defaultScope
        return SessionConfig(scope: scope, duration: .indefinite, origin: .manual)
    }

    var body: some View {
        Button(session.state.isActive ? "Turn Off" : "Keep Awake") {
            session.toggle(defaultConfig)
        }
        if case let .active(cfg, _) = session.state, cfg.origin == .trigger {
            Text("자동 활성 (트리거)").font(.caption).foregroundStyle(.secondary)
        }
        Divider()
        Menu("Keep awake for…") {
            durationButton("15 minutes", 15 * 60)
            durationButton("1 hour", 60 * 60)
            durationButton("2 hours", 2 * 60 * 60)
            durationButton("5 hours", 5 * 60 * 60)
        }
        Toggle("Keep display awake", isOn: displayBinding)
        Toggle("Launch at Login", isOn: Binding(
            get: { LaunchAtLogin.isEnabled },
            set: { LaunchAtLogin.setEnabled($0) }
        ))
        Divider()
        Button("Quit Mara") { NSApplication.shared.terminate(nil) }
    }

    private func durationButton(_ title: String, _ seconds: TimeInterval) -> some View {
        let scope = prefs.defaultScope
        return Button(title) {
            session.start(SessionConfig(scope: scope, duration: .duration(seconds), origin: .manual))
        }
    }

    private var displayBinding: Binding<Bool> {
        Binding(
            get: {
                if case let .active(cfg, _) = session.state { return cfg.scope.keepsDisplayAwake }
                return true
            },
            set: { keepDisplay in
                let scope: KeepAwakeScope = keepDisplay ? .displayAndSystem : .systemOnly
                session.start(SessionConfig(scope: scope, duration: .indefinite, origin: .manual))
            }
        )
    }
}
