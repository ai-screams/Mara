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

    let triggerEngine: TriggerEngine
    let sessionCommander: SessionCommander
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
        self.sessionCommander = SessionCommander(session: session, scope: { prefs.defaultScope }, clock: SystemClock())

        // PrefsStore(@Published)는 main에서만 변이되므로 두 sink 모두 main에서 delivery된다.
        // assumeIsolated로 @MainActor 코어(session/reconcileTriggers) 호출을 격리 보장한다.
        prefs.$lowBatteryThreshold
            .dropFirst()   // 초기값 재방출 무시 (init에서 이미 반영)
            .sink { [weak self] v in MainActor.assumeIsolated { self?.session.lowBatteryThreshold = v } }
            .store(in: &cancellables)
        reconcileTriggers(prefs.triggerConfig.activeSpecs())
        // 평가기는 activeSpecs()가 바뀔 때만 다시 만든다. 네트워크 이름처럼 표시만 바뀌는 편집은 키 입력마다
        // config를 바꾸지만 specs는 그대로라 여기서 걸러진다. removeDuplicates를 dropFirst보다 앞에 둬야
        // 위에서 반영한 초기 specs가 비교 기준이 된다(뒤에 두면 첫 편집이 평가기를 한 번 다시 만든다).
        prefs.$triggerConfig
            .map { $0.activeSpecs() }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] specs in MainActor.assumeIsolated { self?.reconcileTriggers(specs) } }
            .store(in: &cancellables)
        // installHotkey()  // 글로벌 핫키 보류
    }

    private func reconcileTriggers(_ specs: [TriggerSpec]) {
        // 결정(어떤 트리거를 켤지)은 순수 activeSpecs()가, 인스턴스화만 여기서 담당.
        triggerEngine.updateEvaluators(specs.map(makeEvaluator))
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

    /// 현재 네트워크(게이트웨이) — CurrentValueSubject라 구독 즉시 현재값을 재방출한다. delivery는 main.
    var networkChanges: AnyPublisher<NetworkIdentity?, Never> { networkProvider.changes }

    // 글로벌 핫키 기능 보류(비활성화). 삭제하지 않고 보존 — 재활성화하려면 위 호출과
    // 아래 메서드, 그리고 `hotkey` 프로퍼티 주석을 해제하면 된다. HotkeyManager.swift는 그대로 유지.
    // 다시 켤 때는 아래처럼 SessionConfig를 직접 만들지 말고 sessionCommander(수동 시작·끄기의 단일 경로)를 쓴다.
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
