import Foundation
import Combine
import MaraCore

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
    var defaultScope: KeepAwakeScope { KeepAwakeScope(keepDisplay: defaultKeepDisplayAwake) }
    private enum Keys {
        static let defaultKeepDisplayAwake = "defaultKeepDisplayAwake"
        static let lowBatteryThreshold = "lowBatteryThreshold"
        static let triggerConfig = "triggerConfig"
    }
    init() {
        let d = UserDefaults.standard
        d.register(defaults: [Keys.defaultKeepDisplayAwake: true, Keys.lowBatteryThreshold: 20])
        defaultKeepDisplayAwake = d.bool(forKey: Keys.defaultKeepDisplayAwake)
        lowBatteryThreshold = d.integer(forKey: Keys.lowBatteryThreshold)
        if let data = d.data(forKey: Keys.triggerConfig),
           let cfg = try? JSONDecoder().decode(TriggerConfig.self, from: data) {
            triggerConfig = cfg
        } else {
            triggerConfig = .defaults
        }
    }
}
