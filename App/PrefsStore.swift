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
    var defaultScope: KeepAwakeScope { KeepAwakeScope(keepDisplay: defaultKeepDisplayAwake) }
    private enum Keys {
        static let defaultKeepDisplayAwake = "defaultKeepDisplayAwake"
        static let lowBatteryThreshold = "lowBatteryThreshold"
        static let triggerConfig = "triggerConfig"
        static let notifyAutoSessionChanges = "notifyAutoSessionChanges"
    }
    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Keys.defaultKeepDisplayAwake: true,
            Keys.lowBatteryThreshold: 20,
            Keys.notifyAutoSessionChanges: false,
        ])
        defaultKeepDisplayAwake = d.bool(forKey: Keys.defaultKeepDisplayAwake)
        lowBatteryThreshold = d.integer(forKey: Keys.lowBatteryThreshold)
        notifyAutoSessionChanges = d.bool(forKey: Keys.notifyAutoSessionChanges)
        if let data = d.data(forKey: Keys.triggerConfig),
           let cfg = try? JSONDecoder().decode(TriggerConfig.self, from: data) {
            triggerConfig = cfg
        } else {
            triggerConfig = .defaults
        }
    }
}
