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
            // Settings의 TextEditor가 키 입력마다 triggerConfig를 재할당하므로, 평가기
            // 전체 재구성이 타이핑마다 돌지 않게 잠깐 모아서 반영한다(main 스케줄러 → 격리 유지).
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] cfg in MainActor.assumeIsolated { self?.reconcileTriggers(cfg) } }
            .store(in: &cancellables)
        // installHotkey()  // 글로벌 핫키 보류
    }

    private func reconcileTriggers(_ cfg: TriggerConfig) {
        // 결정(어떤 트리거를 켤지)은 순수 activeSpecs()가, 인스턴스화만 여기서 담당.
        triggerEngine.updateEvaluators(cfg.activeSpecs().map(makeEvaluator))
    }

    /// TriggerSpec(순수 결정) → 실제 OS 어댑터를 물린 evaluator. 불순한 인스턴스화만 담당.
    private func makeEvaluator(for spec: TriggerSpec) -> TriggerEvaluator {
        switch spec {
        case .charging:            return ChargingTrigger(battery: battery)
        case .externalDisplay:     return ExternalDisplayTrigger(screens: screens)
        case .appRunning(let ids): return AppRunningTrigger(apps: apps, watched: ids)
        case .network(let ids):    return NetworkTrigger(network: networkProvider, watched: ids)
        }
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
