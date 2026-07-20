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
        didSet {
            let sanitized = Self.sanitizeBatteryThreshold(lowBatteryThreshold)
            if sanitized != lowBatteryThreshold { lowBatteryThreshold = sanitized }
            UserDefaults.standard.set(sanitized, forKey: Keys.lowBatteryThreshold)
        }
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
    /// 첫 실행 안내 팝오버 표시 여부 — 표시 시점에 즉시 true로 기록해 1회성을 보장한다.
    @Published var hasShownFirstRunGuide: Bool {
        didSet { UserDefaults.standard.set(hasShownFirstRunGuide, forKey: Keys.hasShownFirstRunGuide) }
    }
    /// 메뉴바 활성 아이콘 색. rawValue(문자열)로 저장한다. 색↔이름 매핑은 App(MaraTheme).
    @Published var menuBarTint: MenuBarTint {
        didSet { UserDefaults.standard.set(menuBarTint.rawValue, forKey: Keys.menuBarTint) }
    }
    var defaultScope: KeepAwakeScope { KeepAwakeScope(keepDisplay: defaultKeepDisplayAwake) }
    private enum Keys {
        static let defaultKeepDisplayAwake = "defaultKeepDisplayAwake"
        static let lowBatteryThreshold = "lowBatteryThreshold"
        static let triggerConfig = "triggerConfig"
        static let notifyAutoSessionChanges = "notifyAutoSessionChanges"
        static let recentCustomDurations = "recentCustomDurations"
        static let hasShownFirstRunGuide = "hasShownFirstRunGuide"
        static let menuBarTint = "menuBarTint"
    }
    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Keys.defaultKeepDisplayAwake: true,
            Keys.lowBatteryThreshold: 50,
            Keys.notifyAutoSessionChanges: false,
            Keys.recentCustomDurations: [TimeInterval](),
            Keys.hasShownFirstRunGuide: false,
            Keys.menuBarTint: MenuBarTint.default.rawValue,
        ])
        defaultKeepDisplayAwake = d.bool(forKey: Keys.defaultKeepDisplayAwake)
        lowBatteryThreshold = Self.sanitizeBatteryThreshold(d.integer(forKey: Keys.lowBatteryThreshold))
        notifyAutoSessionChanges = d.bool(forKey: Keys.notifyAutoSessionChanges)
        hasShownFirstRunGuide = d.bool(forKey: Keys.hasShownFirstRunGuide)
        // 신뢰 경계: 저장 문자열이 nil/미지 값이면 Core가 기본값(ember)으로 폴백한다.
        menuBarTint = MenuBarTint(storage: d.string(forKey: Keys.menuBarTint))
        // 신뢰 경계: plist는 외부에서 조작될 수 있다 — 비유한·비양수 값과 초과 길이를 로드 시 걸러낸다(Core).
        let loaded = (d.array(forKey: Keys.recentCustomDurations) as? [TimeInterval]) ?? []
        recentCustomDurations = CustomDurationMRU.sanitizing(loaded)
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
    /// 순수 로직(중복 제거·cap)은 Core `CustomDurationMRU.inserting`이 담당(테스트됨).
    /// 무효 입력은 여기서 완전 no-op으로 조기 반환한다 — 같은 값 재대입 시 @Published/didSet이
    /// 재발화해 UserDefaults를 불필요하게 다시 쓰는 것을 막는다(원본 동작 보존).
    func rememberCustomDuration(_ seconds: TimeInterval) {
        guard seconds.isFinite && seconds > 0 else { return }
        recentCustomDurations = CustomDurationMRU.inserting(seconds, into: recentCustomDurations)
    }

    private static func sanitizeBatteryThreshold(_ value: Int) -> Int {
        let range = SessionManager.batteryThresholdRange
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
