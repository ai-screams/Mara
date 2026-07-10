import Foundation

/// 자동화(트리거) 설정. 순수 도메인 데이터 — 영속(UserDefaults 인코딩)은 App(PrefsStore)이 담당한다.
public struct TriggerConfig: Codable, Equatable {
    public var chargingEnabled: Bool
    public var externalDisplayEnabled: Bool
    public var appRunningEnabled: Bool
    public var watchedBundleIDs: [BundleIdentifier]
    public var networkEnabled: Bool
    public var watchedNetworks: [String]  // normalized gateway MAC strings

    public static let defaults = TriggerConfig(
        chargingEnabled: false,
        externalDisplayEnabled: false,
        appRunningEnabled: false,
        watchedBundleIDs: [],
        networkEnabled: false,
        watchedNetworks: []
    )

    // MARK: - Init

    public init(
        chargingEnabled: Bool,
        externalDisplayEnabled: Bool,
        appRunningEnabled: Bool,
        watchedBundleIDs: [BundleIdentifier],
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
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chargingEnabled         = try c.decodeIfPresent(Bool.self,     forKey: .chargingEnabled)         ?? false
        externalDisplayEnabled  = try c.decodeIfPresent(Bool.self,     forKey: .externalDisplayEnabled)  ?? false
        appRunningEnabled       = try c.decodeIfPresent(Bool.self,     forKey: .appRunningEnabled)       ?? false
        // [String]으로 받아 개별 검증 — 무효/중복 항목만 버리고 나머지는 보존한다
        // (BundleIdentifier 단독 디코드는 throw라 배열 통째 디코드는 wipe 위험).
        let rawIDs = try c.decodeIfPresent([String].self, forKey: .watchedBundleIDs) ?? []
        var seen = Set<BundleIdentifier>()
        watchedBundleIDs = rawIDs
            .compactMap { BundleIdentifier(validating: $0) }
            .filter { seen.insert($0).inserted }
        networkEnabled          = try c.decodeIfPresent(Bool.self,     forKey: .networkEnabled)          ?? false
        watchedNetworks         = try c.decodeIfPresent([String].self, forKey: .watchedNetworks)         ?? []
    }
}

/// 활성화된 트리거의 종류와 파라미터(순수 값). config → 어떤 트리거를 켤지의 **결정**만 표현하며,
/// 실제 OS 어댑터를 물린 evaluator 인스턴스화는 App 레이어가 담당한다(순수/불순 분리).
public enum TriggerSpec: Equatable {
    case charging
    case externalDisplay
    case appRunning(Set<String>)
    case network(Set<NetworkIdentity>)
}

public extension TriggerConfig {
    /// 이 설정이 활성화하는 트리거 목록. enable 플래그와 빈-목록 가드를 적용한 순수 결정.
    /// (appRunning/network는 감시 목록이 비어 있으면 제외 — 무의미한 항상-false 트리거 방지.)
    func activeSpecs() -> [TriggerSpec] {
        var specs: [TriggerSpec] = []
        if chargingEnabled { specs.append(.charging) }
        if externalDisplayEnabled { specs.append(.externalDisplay) }
        if appRunningEnabled && !watchedBundleIDs.isEmpty {
            specs.append(.appRunning(Set(watchedBundleIDs.map(\.rawValue))))
        }
        if networkEnabled && !watchedNetworks.isEmpty {
            specs.append(.network(Set(watchedNetworks.map { NetworkIdentity(gatewayMAC: $0) })))
        }
        return specs
    }
}

public extension TriggerConfig {
    /// 검증+중복 방지 추가. 무효 형식이거나 이미 있으면 no-op. 반환: 실제 추가 여부.
    @discardableResult
    mutating func addWatchedBundleID(_ raw: String) -> Bool {
        guard let id = BundleIdentifier(validating: raw), !watchedBundleIDs.contains(id) else { return false }
        watchedBundleIDs.append(id)
        return true
    }

    mutating func removeWatchedBundleID(_ id: BundleIdentifier) {
        watchedBundleIDs.removeAll { $0 == id }
    }
}
