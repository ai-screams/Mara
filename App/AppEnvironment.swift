import SwiftUI
import Combine
import MaraCore

@MainActor
final class AppEnvironment: ObservableObject {
    let session: SessionManager
    let prefs = PrefsStore()
    private var hotkey: HotkeyManager?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let engine = SleepEngine(provider: IOKitPowerAssertionProvider())
        session = SessionManager(
            engine: engine,
            scheduler: DispatchScheduler(queue: .main),
            clock: SystemClock(),
            battery: IOKitBatteryMonitor(),
            lowBatteryThreshold: prefs.lowBatteryThreshold
        )
        prefs.$lowBatteryThreshold
            .sink { [weak self] newValue in self?.session.lowBatteryThreshold = newValue }
            .store(in: &cancellables)
        installHotkey()
    }

    private func installHotkey() {
        let hk = HotkeyManager(onToggle: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let scope: KeepAwakeScope = self.prefs.defaultKeepDisplayAwake ? .displayAndSystem : .systemOnly
                self.session.toggle(SessionConfig(scope: scope, duration: .indefinite, origin: .manual))
            }
        })
        hk.register()
        hotkey = hk
    }
}
