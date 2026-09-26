import AppKit
import OpenCombine
import OpenCombineDispatch
import MaraCore

@MainActor
final class AppEnvironment {
    let session: SessionManager
    let prefs = PrefsStore()

    // OS 어댑터는 앱 수명 동안 1회만 생성 (수동 관찰 → config 무관, churn 제거)
    private let battery = IOKitBatteryMonitor()
    private let screens = NSScreenCounter()
    private let apps = NSWorkspaceAppsObserver()
    private let networkProvider = RoutingTableNetworkProvider()

    let triggerEngine: TriggerEngine
    private var cancellables = Set<AnyCancellable>()
    private var isShutDown = false

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
        prefs.$lowBatteryThreshold
            .dropFirst()   // 초기값 재방출 무시 (init에서 이미 반영)
            .sink { [weak self] v in unsafeAssumeMainActor { self?.session.lowBatteryThreshold = v } }
            .store(in: &cancellables)
        reconcileTriggers(prefs.triggerConfig)
        prefs.$triggerConfig
            .dropFirst()   // 초기값 재방출 무시 (위에서 한 번 반영함)
            // 메뉴 토글이 연달아 바뀔 때 평가기 전체 재구성이 매번 돌지 않게 잠깐 모은다.
            // OpenCombine: SDK에 Combine이 있으면 DispatchQueue 자체는 스케줄러가 아니다 — `.ocombine`.
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main.ocombine)
            .sink { [weak self] cfg in unsafeAssumeMainActor { self?.reconcileTriggers(cfg) } }
            .store(in: &cancellables)
    }

    /// 저장 설정에서 Mara 자신의 감시 ID를 뺀 값 — 트리거 생성·상태 줄·메뉴가 모두 이 값을 쓴다.
    var effectiveTriggerConfig: TriggerConfig {
        LegacyMenuPolicy.effectiveConfig(prefs.triggerConfig, selfBundleID: Bundle.main.bundleIdentifier)
    }

    private func reconcileTriggers(_ cfg: TriggerConfig) {
        // 결정(어떤 트리거를 켤지)은 순수 activeSpecs()가, 인스턴스화만 여기서 담당.
        let effective = LegacyMenuPolicy.effectiveConfig(cfg, selfBundleID: Bundle.main.bundleIdentifier)
        triggerEngine.updateEvaluators(effective.activeSpecs().map(makeEvaluator))
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

    /// 앱 종료 정리(1회). 알림 구독은 AppDelegate가 **이보다 먼저** 끊는다 — 여기서 트리거 세션이
    /// `.triggerCleared`로 끝나며 종료 직후 알림이 뜨지 않게. 이 함수는 알림을 모른다.
    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        cancellables.removeAll()
        triggerEngine.stop()
        if session.state.isActive { _ = session.stop(reason: .manual) }   // assertion·타이머 해제
        networkProvider.stop()
        apps.stop()
        screens.stop()
        battery.stop()
    }
}
