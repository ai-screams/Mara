import Foundation

struct TriggerConfig: Codable, Equatable {
    var chargingEnabled: Bool
    var externalDisplayEnabled: Bool
    var appRunningEnabled: Bool
    var watchedBundleIDs: [String]

    static let defaults = TriggerConfig(
        chargingEnabled: false,
        externalDisplayEnabled: false,
        appRunningEnabled: false,
        watchedBundleIDs: []
    )
}
