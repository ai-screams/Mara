import Foundation
import Combine
import MaraCore

// @MainActor: @Published 프로퍼티가 main에서만 변이됨을 컴파일러가 강제한다.
// AppEnvironment의 두 sink는 이 delivery가 main임을 전제로 assumeIsolated한다.
@MainActor
final class PrefsStore: ObservableObject {
    @Published var defaultKeepDisplayAwake: Bool {
        didSet { UserDefaults.standard.set(defaultKeepDisplayAwake, forKey: Keys.defaultKeepDisplayAwake) }
    }
    @Published var lowBatteryThreshold: Int {
        didSet { UserDefaults.standard.set(lowBatteryThreshold, forKey: Keys.lowBatteryThreshold) }
    }
    @Published var triggerConfig: TriggerConfig {
        didSet {
            if let data = try? JSONEncoder().encode(triggerConfig) {
                UserDefaults.standard.set(data, forKey: Keys.triggerConfig)
            }
        }
    }
    @Published var notifyAutoSessionChanges: Bool {
        didSet { UserDefaults.standard.set(notifyAutoSessionChanges, forKey: Keys.notifyAutoSessionChanges) }
    }
    /// 커스텀 타이머 최근 사용값(초), 최신순 최대 3개. Until(절대시각)은 기록하지 않는다.
    @Published var recentCustomDurations: [TimeInterval] {
        didSet { UserDefaults.standard.set(recentCustomDurations, forKey: Keys.recentCustomDurations) }
    }
    var defaultScope: KeepAwakeScope { KeepAwakeScope(keepDisplay: defaultKeepDisplayAwake) }
    private enum Keys {
        static let defaultKeepDisplayAwake = "defaultKeepDisplayAwake"
        static let lowBatteryThreshold = "lowBatteryThreshold"
        static let triggerConfig = "triggerConfig"
        static let notifyAutoSessionChanges = "notifyAutoSessionChanges"
        static let recentCustomDurations = "recentCustomDurations"
    }
    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Keys.defaultKeepDisplayAwake: true,
            Keys.lowBatteryThreshold: 20,
            Keys.notifyAutoSessionChanges: false,
            Keys.recentCustomDurations: [TimeInterval](),
        ])
        defaultKeepDisplayAwake = d.bool(forKey: Keys.defaultKeepDisplayAwake)
        lowBatteryThreshold = d.integer(forKey: Keys.lowBatteryThreshold)
        notifyAutoSessionChanges = d.bool(forKey: Keys.notifyAutoSessionChanges)
        // 신뢰 경계: plist는 외부에서 조작될 수 있다 — 비유한·비양수 값과 초과 길이를 로드 시 걸러낸다.
        let loaded = (d.array(forKey: Keys.recentCustomDurations) as? [TimeInterval]) ?? []
        recentCustomDurations = Array(loaded.filter { $0.isFinite && $0 > 0 }.prefix(3))
        if let data = d.data(forKey: Keys.triggerConfig),
           let cfg = try? JSONDecoder().decode(TriggerConfig.self, from: data) {
            triggerConfig = cfg
        } else {
            triggerConfig = .defaults
        }
    }
    /// 최근 커스텀 duration 전체 삭제 (메뉴 "Clear Recent").
    func clearRecentCustomDurations() {
        recentCustomDurations = []
    }

    /// MRU 갱신: 같은 값은 앞으로 끌어올리고, 3개 초과분은 버린다.
    func rememberCustomDuration(_ seconds: TimeInterval) {
        guard seconds.isFinite && seconds > 0 else { return }   // 쓰기 경로도 가드 — 로드 필터와 대칭(2계층 완결)
        var list = recentCustomDurations.filter { $0 != seconds }
        list.insert(seconds, at: 0)
        recentCustomDurations = Array(list.prefix(3))
    }
}
