import SwiftUI
import Combine
import MaraCore

@MainActor
final class AppEnvironment: ObservableObject {
    let session: SessionManager
    let prefs = PrefsStore()
    private let battery = IOKitBatteryMonitor()
    private var triggerEngine: TriggerEngine?
    // 글로벌 핫키 기능 보류(비활성화) — 코드는 보존, 재활성화 시 주석 해제.
    // private var hotkey: HotkeyManager?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let engine = SleepEngine(provider: IOKitPowerAssertionProvider())
        session = SessionManager(
            engine: engine,
            scheduler: DispatchScheduler(queue: .main),
            clock: SystemClock(),
            battery: battery,
            lowBatteryThreshold: prefs.lowBatteryThreshold
        )
        prefs.$lowBatteryThreshold
            .sink { [weak self] newValue in self?.session.lowBatteryThreshold = newValue }
            .store(in: &cancellables)
        rebuildTriggers(prefs.triggerConfig)
        prefs.$triggerConfig
            .sink { [weak self] cfg in self?.rebuildTriggers(cfg) }
            .store(in: &cancellables)
        // installHotkey()  // 글로벌 핫키 보류
    }

    private func rebuildTriggers(_ cfg: TriggerConfig) {
        triggerEngine?.stop()
        var evaluators: [TriggerEvaluator] = []
        if cfg.chargingEnabled { evaluators.append(ChargingTrigger(battery: battery)) }
        if cfg.externalDisplayEnabled { evaluators.append(ExternalDisplayTrigger(screens: NSScreenCounter())) }
        if cfg.appRunningEnabled && !cfg.watchedBundleIDs.isEmpty {
            evaluators.append(AppRunningTrigger(apps: NSWorkspaceAppsObserver(),
                                                watched: Set(cfg.watchedBundleIDs)))
        }
        guard !evaluators.isEmpty else {
            if case let .active(cfg, _) = session.state, cfg.origin == .trigger {
                session.stop()
            }
            triggerEngine = nil
            return
        }
        let scope: KeepAwakeScope = prefs.defaultKeepDisplayAwake ? .displayAndSystem : .systemOnly
        let te = TriggerEngine(session: session, evaluators: evaluators, scope: scope)
        te.start()
        triggerEngine = te
    }

    // 글로벌 핫키 기능 보류(비활성화). 삭제하지 않고 보존 — 재활성화하려면 위 호출과
    // 아래 메서드, 그리고 `hotkey` 프로퍼티 주석을 해제하면 된다. HotkeyManager.swift는 그대로 유지.
    // private func installHotkey() {
    //     let hk = HotkeyManager(onToggle: { [weak self] in
    //         Task { @MainActor in
    //             guard let self else { return }
    //             let scope: KeepAwakeScope = self.prefs.defaultKeepDisplayAwake ? .displayAndSystem : .systemOnly
    //             self.session.toggle(SessionConfig(scope: scope, duration: .indefinite, origin: .manual))
    //         }
    //     })
    //     hk.register()
    //     hotkey = hk
    // }
}
