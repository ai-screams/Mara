import SwiftUI
import SleeplessCore

@MainActor
final class AppEnvironment: ObservableObject {
    let session: SessionManager
    private var hotkey: HotkeyManager?

    init() {
        let engine = SleepEngine(provider: IOKitPowerAssertionProvider())
        session = SessionManager(
            engine: engine,
            scheduler: DispatchScheduler(queue: .main),
            clock: SystemClock(),
            battery: IOKitBatteryMonitor(),
            lowBatteryThreshold: 20
        )
        installHotkey()
    }

    func installHotkey() {
        let cfg = SessionConfig(scope: .displayAndSystem, duration: .indefinite, origin: .manual)
        let hk = HotkeyManager(onToggle: { [weak self] in
            Task { @MainActor in self?.session.toggle(cfg) }
        })
        hk.register()
        hotkey = hk
    }
}
