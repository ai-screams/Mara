import Foundation

/// 자동화(트리거) 설정. 순수 도메인 데이터 — 영속(UserDefaults 인코딩)은 App(PrefsStore)이 담당한다.
public struct TriggerConfig: Codable, Equatable, Sendable {
    public var chargingEnabled: Bool
    public var externalDisplayEnabled: Bool
    public var appRunningEnabled: Bool
    public var watchedBundleIDs: [BundleIdentifier]
    public var networkEnabled: Bool
    /// 정규화된 게이트웨이 MAC 문자열. 쓰기는 add/removeWatchedNetwork로만 — 이름과 함께 정리돼야 한다.
    public internal(set) var watchedNetworks: [String]
    /// 감시 네트워크의 표시 이름(정규화된 MAC → 이름). 식별·트리거 판단에는 쓰지 않는다(표시 전용).
    /// watchedNetworks와 별도 사전인 이유: 배열 원소를 구조체로 바꾸면 저장 형식이 바뀌어 옛 버전이 디코드하지 못한다.
    /// 알려진 제약: 옛 버전은 이 키를 모르므로, 다운그레이드한 뒤 트리거 설정을 바꿔 저장하면 이름이 사라진다.
    public internal(set) var networkNames: [String: String]

    public static let defaults = TriggerConfig(
        chargingEnabled: false,
        externalDisplayEnabled: false,
        appRunningEnabled: false,
        watchedBundleIDs: [],
        networkEnabled: false,
        watchedNetworks: [],
        networkNames: [:]
    )

    // MARK: - Init

    public init(
        chargingEnabled: Bool,
        externalDisplayEnabled: Bool,
        appRunningEnabled: Bool,
        watchedBundleIDs: [BundleIdentifier],
        networkEnabled: Bool,
        watchedNetworks: [String],
        networkNames: [String: String] = [:]
    ) {
        self.chargingEnabled        = chargingEnabled
        self.externalDisplayEnabled = externalDisplayEnabled
        self.appRunningEnabled      = appRunningEnabled
        self.watchedBundleIDs       = watchedBundleIDs
        self.networkEnabled         = networkEnabled
        self.watchedNetworks        = watchedNetworks
        self.networkNames           = networkNames
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case chargingEnabled
        case externalDisplayEnabled
        case appRunningEnabled
        case watchedBundleIDs
        case networkEnabled
        case watchedNetworks
        case networkNames
    }

    /// 하위호환 디코드: 기존에 영속된 JSON엔 새로 추가된 키가 없을 수 있다.
    /// decodeIfPresent + 폴백 기본값으로 업그레이드 시 throw(및 데이터 wipe)를 막는다.
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
        // 정규화 + 순서 유지 중복 제거 — 밖에서 고친 plist의 대문자·한 자리 옥텟이 이름 키와 어긋나지 않게 한다.
        let rawNetworks = try c.decodeIfPresent([String].self, forKey: .watchedNetworks) ?? []
        var seenMACs = Set<String>()
        watchedNetworks = rawNetworks
            .map(NetworkIdentity.normalize)
            .filter { seenMACs.insert($0).inserted }
        // 이 필드만 관대하게 디코드한다 — 타입이 틀린 값 때문에 throw하면 PrefsStore가 트리거 설정 전체를 기본값으로 되돌린다.
        let rawNames = (try? c.decodeIfPresent([String: String].self, forKey: .networkNames)) ?? [:]
        networkNames = Self.normalizedNetworkNames(rawNames, watched: seenMACs)
    }

    /// 키 정규화 → 감시 목록에 있는 것만 → 이름 정리. 두 키가 같은 MAC으로 접히면 이미 정규형이던 키가 이긴다
    /// (그다음은 키 정렬 순서 — 사전 순회 순서에 기대지 않는 결정적 규칙).
    private static func normalizedNetworkNames(_ raw: [String: String], watched: Set<String>) -> [String: String] {
        var result: [String: String] = [:]
        for key in raw.keys.sorted() {
            let mac = NetworkIdentity.normalize(key)
            guard watched.contains(mac), let name = raw[key].flatMap(sanitizeNetworkName) else { continue }
            // 사전 키는 유일하므로 정규형 키는 많아야 하나 — 그 키면 앞서 들어온 값을 덮는다.
            if result[mac] == nil || key == mac { result[mac] = name }
        }
        return result
    }
}

/// 활성화된 트리거의 종류와 파라미터(순수 값). config → 어떤 트리거를 켤지의 **결정**만 표현하며,
/// 실제 OS 어댑터를 물린 evaluator 인스턴스화는 App 레이어가 담당한다(순수/불순 분리).
public enum TriggerSpec: Equatable, Sendable {
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

// MARK: - 감시 네트워크 이름

extension TriggerConfig {
    /// 표시 이름 상한. 40은 보이는 글자(grapheme) 수, 120은 결합 문자를 수천 개 붙인 한 글자 같은 입력의 저장 상한.
    static let networkNameMaxCharacters = 40
    static let networkNameMaxUTF8Bytes = 120

    /// 표시 이름 정리. 결과가 비면 nil(= 이름 없음, MAC으로 표시).
    /// - 제어문자(C0/C1)·공백류·줄/문단 구분자 → 공백 하나로 축약, 앞뒤 공백 제거
    /// - 기본 무시 문자(Default_Ignorable_Code_Point, bidi 제어 포함)는 속성으로 판정해 제거 — 표시 순서를 뒤집거나
    ///   빈 이름처럼 보이게 한다
    /// - 단 이모지에 필요한 ZWJ·이형 선택자·태그 문자(지역 국기 시퀀스)는 유지
    static func sanitizeNetworkName(_ raw: String) -> String? {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            if scalar.properties.isDefaultIgnorableCodePoint && !keepsIgnorable(scalar) { continue }
            let isBreak = scalar.properties.generalCategory == .control || scalar.properties.isWhitespace
            scalars.append(isBreak ? " " : scalar)
        }
        let collapsed = String(scalars).split(separator: " ").joined(separator: " ")
        var name = ""
        for character in collapsed {
            guard name.count < networkNameMaxCharacters,
                  name.utf8.count + character.utf8.count <= networkNameMaxUTF8Bytes else { break }
            name.append(character)
        }
        name = name.trimmingCharacters(in: .whitespaces)
        // 남겨 둔 무시 문자(ZWJ·이형 선택자·태그)만 있으면 보이지 않는 이름이다.
        let visible = name.unicodeScalars.contains { !$0.properties.isDefaultIgnorableCodePoint }
        return visible ? name : nil
    }

    /// 기본 무시 문자 중 이모지 표시에 필요해 남기는 것: ZWJ, 이형 선택자 두 영역, 태그 문자(🏴 지역 국기).
    private static func keepsIgnorable(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200D, 0xFE00...0xFE0F, 0xE0100...0xE01EF, 0xE0020...0xE007F: return true
        default: return false
        }
    }
}

public extension TriggerConfig {
    /// 중복이면 false. 이름은 비어 있는 채로 추가된다.
    @discardableResult
    mutating func addWatchedNetwork(_ identity: NetworkIdentity) -> Bool {
        guard !watchedNetworks.contains(identity.gatewayMAC) else { return false }
        watchedNetworks.append(identity.gatewayMAC)
        return true
    }

    /// 목록과 이름을 함께 지운다 — 이름만 고아로 남지 않게.
    mutating func removeWatchedNetwork(_ mac: String) {
        let key = NetworkIdentity.normalize(mac)
        watchedNetworks.removeAll { $0 == key }
        networkNames[key] = nil
    }

    /// 감시 목록에 없는 MAC이면 no-op. 정리 결과가 비면 이름을 지운다.
    mutating func setNetworkName(_ raw: String, for mac: String) {
        let key = NetworkIdentity.normalize(mac)
        guard watchedNetworks.contains(key) else { return }
        networkNames[key] = Self.sanitizeNetworkName(raw)
    }

    /// 이름이 없으면 nil — 호출부가 MAC으로 대체한다.
    func networkDisplayName(_ mac: String) -> String? {
        networkNames[NetworkIdentity.normalize(mac)]
    }
}
