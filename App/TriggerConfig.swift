import Foundation

struct TriggerConfig: Codable, Equatable {
    var chargingEnabled: Bool
    var externalDisplayEnabled: Bool
    var appRunningEnabled: Bool
    var watchedBundleIDs: [String]
    var networkEnabled: Bool
    var watchedNetworks: [String]  // normalized gateway MAC strings

    static let defaults = TriggerConfig(
        chargingEnabled: false,
        externalDisplayEnabled: false,
        appRunningEnabled: false,
        watchedBundleIDs: [],
        networkEnabled: false,
        watchedNetworks: []
    )

    // MARK: - Init

    init(
        chargingEnabled: Bool,
        externalDisplayEnabled: Bool,
        appRunningEnabled: Bool,
        watchedBundleIDs: [String],
        networkEnabled: Bool,
        watchedNetworks: [String]
    ) {
        self.chargingEnabled        = chargingEnabled
        self.externalDisplayEnabled = externalDisplayEnabled
        self.appRunningEnabled      = appRunningEnabled
        self.watchedBundleIDs       = watchedBundleIDs
        self.networkEnabled         = networkEnabled
        self.watchedNetworks        = watchedNetworks
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case chargingEnabled
        case externalDisplayEnabled
        case appRunningEnabled
        case watchedBundleIDs
        case networkEnabled
        case watchedNetworks
    }

    /// Backward-compatible decode: existing persisted JSON may be missing newer keys.
    /// Using decodeIfPresent + fallback defaults prevents a throw (and data wipe) on upgrade.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chargingEnabled         = try c.decodeIfPresent(Bool.self,     forKey: .chargingEnabled)         ?? false
        externalDisplayEnabled  = try c.decodeIfPresent(Bool.self,     forKey: .externalDisplayEnabled)  ?? false
        appRunningEnabled       = try c.decodeIfPresent(Bool.self,     forKey: .appRunningEnabled)       ?? false
        watchedBundleIDs        = try c.decodeIfPresent([String].self, forKey: .watchedBundleIDs)        ?? []
        networkEnabled          = try c.decodeIfPresent(Bool.self,     forKey: .networkEnabled)          ?? false
        watchedNetworks         = try c.decodeIfPresent([String].self, forKey: .watchedNetworks)         ?? []
    }
}
