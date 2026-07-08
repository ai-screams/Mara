import SwiftUI
import Combine
import MaraCore

@MainActor
final class AppEnvironment: ObservableObject {
    let session: SessionManager
    let prefs = PrefsStore()

    // OS 어댑터는 앱 수명 동안 1회만 생성 (수동 관찰 → config 무관, churn 제거)
    private let battery = IOKitBatteryMonitor()
    private let screens = NSScreenCounter()
    private let apps = NSWorkspaceAppsObserver()
    private let networkProvider = RoutingTableNetworkProvider()

    private let triggerEngine: TriggerEngine
    // 글로벌 핫키 기능 보류(비활성화) — 코드는 보존, 재활성화 시 주석 해제.
    // private var hotkey: HotkeyManager?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let engine = SleepEngine(provider: IOKitPowerAssertionProvider())
        let session = SessionManager(
            engine: engine,
            scheduler: DispatchScheduler(),
            clock: SystemClock(),
            battery: battery,
            lowBatteryThreshold: prefs.lowBatteryThreshold
        )
        self.session = session
        // 트리거 엔진은 1회 생성(durable) — suppression이 config 변경에도 유지됨
        let prefs = self.prefs
        self.triggerEngine = TriggerEngine(session: session, scope: { prefs.defaultScope })

        // PrefsStore(@Published)는 main에서만 변이되므로 두 sink 모두 main에서 delivery된다.
        // assumeIsolated로 @MainActor 코어(session/reconcileTriggers) 호출을 격리 보장한다.
        prefs.$lowBatteryThreshold
            .dropFirst()   // 초기값 재방출 무시 (init에서 이미 반영)
            .sink { [weak self] v in MainActor.assumeIsolated { self?.session.lowBatteryThreshold = v } }
            .store(in: &cancellables)
        reconcileTriggers(prefs.triggerConfig)
        prefs.$triggerConfig
            .dropFirst()   // 초기값 재방출 무시 (위에서 한 번 반영함)
            .sink { [weak self] cfg in MainActor.assumeIsolated { self?.reconcileTriggers(cfg) } }
            .store(in: &cancellables)
        // installHotkey()  // 글로벌 핫키 보류
    }

    private func reconcileTriggers(_ cfg: TriggerConfig) {
        var evaluators: [TriggerEvaluator] = []
        if cfg.chargingEnabled { evaluators.append(ChargingTrigger(battery: battery)) }
        if cfg.externalDisplayEnabled { evaluators.append(ExternalDisplayTrigger(screens: screens)) }
        if cfg.appRunningEnabled && !cfg.watchedBundleIDs.isEmpty {
            evaluators.append(AppRunningTrigger(apps: apps, watched: Set(cfg.watchedBundleIDs)))
        }
        if cfg.networkEnabled && !cfg.watchedNetworks.isEmpty {
            let watched = Set(cfg.watchedNetworks.map { NetworkIdentity(gatewayMAC: $0) })
            evaluators.append(NetworkTrigger(network: networkProvider, watched: watched))
        }
        triggerEngine.updateEvaluators(evaluators)
    }

    var currentNetwork: NetworkIdentity? { networkProvider.current }

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
