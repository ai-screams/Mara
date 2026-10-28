import XCTest
@testable import MaraCore

/// 감시 네트워크 표시 이름(networkNames). 식별은 MAC 그대로이고 이름은 표시 전용이다.
final class NetworkNameTests: XCTestCase {

    private func decode(_ json: String) throws -> TriggerConfig {
        try JSONDecoder().decode(TriggerConfig.self, from: Data(json.utf8))
    }

    private let mac = "74:29:72:b3:e0:80"

    private func config(watching macs: [String]) -> TriggerConfig {
        TriggerConfig(chargingEnabled: false, externalDisplayEnabled: false, appRunningEnabled: false,
                      watchedBundleIDs: [], networkEnabled: true, watchedNetworks: macs)
    }

    // MARK: - 저장 호환

    // 이것을 실패시키는 것: networkNames를 decodeIfPresent가 아닌 decode로 읽는 것(옛 JSON에서 throw).
    func test_decode_legacyJSONWithoutNames_keepsNetworksAndEmptyNames() throws {
        let cfg = try decode(#"{"networkEnabled":true,"watchedNetworks":["74:29:72:b3:e0:80"]}"#)
        XCTAssertEqual(cfg.watchedNetworks, [mac])
        XCTAssertEqual(cfg.networkNames, [:])
    }

    // 이것을 실패시키는 것: CodingKeys에서 networkNames를 빼는 것(인코드에서 사라짐).
    func test_encodeDecode_roundTripsNames() throws {
        var original = config(watching: [mac])
        original.setNetworkName("Home", for: mac)
        let restored = try JSONDecoder().decode(TriggerConfig.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.networkNames, [mac: "Home"])
    }

    // 이것을 실패시키는 것: networkNames 디코드에서 try?를 빼는 것(타입 오류가 throw → PrefsStore가 전체를 기본값으로).
    func test_decode_malformedNames_doesNotWipeOtherSettings() throws {
        for names in [#""bad""#, #"{"74:29:72:b3:e0:80": 5}"#, "[1,2]"] {
            let cfg = try decode(#"{"chargingEnabled":true,"networkEnabled":true,"watchedNetworks":["74:29:72:b3:e0:80"],"networkNames":"# + names + "}")
            XCTAssertTrue(cfg.chargingEnabled, names)
            XCTAssertEqual(cfg.watchedNetworks, [mac], names)
            XCTAssertEqual(cfg.networkNames, [:], names)
        }
    }

    // MARK: - MAC 정규화

    // 이것을 실패시키는 것: watchedNetworks 디코드에서 정규화나 중복 제거를 빼는 것.
    func test_decode_normalizesAndDedupesWatchedNetworks_preservingOrder() throws {
        let cfg = try decode(#"{"watchedNetworks":["0:10:DB:ff:10:2","74:29:72:b3:e0:80","00:10:db:ff:10:02"]}"#)
        XCTAssertEqual(cfg.watchedNetworks, ["00:10:db:ff:10:02", mac])
    }

    // 이것을 실패시키는 것: 이름 키 정규화를 빼는 것(대문자 키의 이름이 버려짐).
    func test_decode_normalizesNameKeys() throws {
        let cfg = try decode(#"{"watchedNetworks":["0:10:DB:ff:10:2"],"networkNames":{"0:10:DB:FF:10:2":"Office"}}"#)
        XCTAssertEqual(cfg.networkNames, ["00:10:db:ff:10:02": "Office"])
    }

    // 이것을 실패시키는 것: 감시 목록 필터를 빼는 것.
    func test_decode_dropsNamesForUnwatchedNetworks() throws {
        let cfg = try decode(#"{"watchedNetworks":["74:29:72:b3:e0:80"],"networkNames":{"aa:bb:cc:dd:ee:ff":"Gone","74:29:72:b3:e0:80":"Home"}}"#)
        XCTAssertEqual(cfg.networkNames, [mac: "Home"])
    }

    // 이것을 실패시키는 것: 충돌 시 정규형 키 우선 규칙을 빼는 것. 대문자 키("00:10:DB…")가 정렬상 정규형보다
    // 앞서므로, 규칙이 없으면 먼저 처리된 "Legacy"가 남는다.
    func test_decode_nameKeyCollision_prefersCanonicalKey() throws {
        let cfg = try decode(#"{"watchedNetworks":["00:10:db:ff:10:02"],"networkNames":{"00:10:DB:FF:10:02":"Legacy","00:10:db:ff:10:02":"Canonical"}}"#)
        XCTAssertEqual(cfg.networkNames, ["00:10:db:ff:10:02": "Canonical"])
    }

    // MARK: - 변경 API

    // 이것을 실패시키는 것: setNetworkName의 감시 목록 가드를 빼는 것.
    func test_setName_ignoresUnwatchedMAC() {
        var cfg = config(watching: [mac])
        cfg.setNetworkName("Ghost", for: "aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(cfg.networkNames, [:])
    }

    // 이것을 실패시키는 것: 인자 정규화를 빼는 것.
    func test_setName_normalizesMACArgument() {
        var cfg = config(watching: [mac])
        cfg.setNetworkName("Home", for: "74:29:72:B3:E0:80")
        XCTAssertEqual(cfg.networkDisplayName("74:29:72:B3:E0:80"), "Home")
        XCTAssertEqual(cfg.networkNames, [mac: "Home"])
    }

    // 이것을 실패시키는 것: 빈 이름을 저장하는 것(nil 대신 "").
    func test_setName_blankClearsName() {
        var cfg = config(watching: [mac])
        cfg.setNetworkName("Home", for: mac)
        cfg.setNetworkName("   ", for: mac)
        XCTAssertNil(cfg.networkDisplayName(mac))
        XCTAssertEqual(cfg.networkNames, [:])
    }

    // 이것을 실패시키는 것: removeWatchedNetwork에서 이름 삭제 줄을 빼는 것.
    func test_remove_alsoRemovesName() {
        var cfg = config(watching: [mac])
        cfg.setNetworkName("Home", for: mac)
        cfg.removeWatchedNetwork(mac)
        XCTAssertEqual(cfg.watchedNetworks, [])
        XCTAssertEqual(cfg.networkNames, [:])
    }

    // 이것을 실패시키는 것: addWatchedNetwork의 중복 가드를 빼는 것.
    func test_add_rejectsDuplicate() {
        var cfg = config(watching: [])
        XCTAssertTrue(cfg.addWatchedNetwork(NetworkIdentity(gatewayMAC: "74:29:72:B3:E0:80")))
        XCTAssertFalse(cfg.addWatchedNetwork(NetworkIdentity(gatewayMAC: mac)))
        XCTAssertEqual(cfg.watchedNetworks, [mac])
    }

    // 이름은 트리거 판단에 관여하지 않는다 — App이 activeSpecs 중복 제거로 이름 변경 시 평가기 재구성을 건너뛰는 전제.
    // 이것을 실패시키는 것: activeSpecs()가 networkNames를 읽게 하는 것(지금 코드에는 그런 경로가 없어 처음부터 GREEN).
    func test_activeSpecs_unaffectedByNames() {
        var cfg = config(watching: [mac])
        let before = cfg.activeSpecs()
        cfg.setNetworkName("Home", for: mac)
        XCTAssertEqual(cfg.activeSpecs(), before)
    }

    // MARK: - 이름 정리

    private func clean(_ s: String) -> String? { TriggerConfig.sanitizeNetworkName(s) }

    // 이것을 실패시키는 것: 공백 축약이나 trim을 빼는 것.
    func test_sanitize_collapsesWhitespaceAndControls() {
        XCTAssertEqual(clean("  Home \n\t Wi-Fi \u{2028} 5G  "), "Home Wi-Fi 5G")
        XCTAssertEqual(clean("a\u{0007}b"), "a b")      // C0 제어문자
        XCTAssertEqual(clean("a\u{0085}b"), "a b")      // C1(NEL)
        XCTAssertNil(clean(" \n\t "))
    }

    // 이것을 실패시키는 것: "보이는 글자" 검사를 isEmpty로 바꾸는 것(ZWJ+VS만 남은 이름이 저장됨).
    func test_sanitize_invisibleOnlyIsNil() {
        XCTAssertNil(clean("\u{200B}\u{FEFF}\u{2060}"))
        XCTAssertNil(clean("\u{200D}\u{FE0F}"))
    }

    // 이것을 실패시키는 것: isDefaultIgnorableCodePoint 제거 분기를 빼거나 손으로 나열한 목록으로 되돌리는 것.
    func test_sanitize_stripsBidiControlsAndDefaultIgnorables() {
        XCTAssertEqual(clean("\u{202E}emoH"), "emoH")             // RLO
        XCTAssertEqual(clean("\u{2067}Home\u{2069}"), "Home")      // RLI…PDI
        XCTAssertEqual(clean("Ho\u{200F}me"), "Home")              // RLM
        XCTAssertEqual(clean("Ho\u{061C}me"), "Home")                 // ARABIC LETTER MARK
        XCTAssertEqual(clean("\u{206A}Home\u{206F}"), "Home")         // 옛 bidi 제어
        XCTAssertEqual(clean("Ho\u{034F}me"), "Home")                 // COMBINING GRAPHEME JOINER
        XCTAssertNil(clean("\u{3164}\u{115F}"))                       // 한글 채움 문자만
    }

    // 이것을 실패시키는 것: 보이는 글자 판정에서 무시 문자를 빼지 않는 것(태그만 있는 이름이 저장됨).
    func test_sanitize_tagOnlyIsNil_butFlagSequenceSurvives() {
        XCTAssertNil(clean("\u{E0067}\u{E0062}\u{E007F}"))
        let england = "🏴\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        XCTAssertEqual(clean("\(england) Office"), "\(england) Office")
    }

    // 이것을 실패시키는 것: 제거 조건에서 keepsIgnorable 예외를 빼는 것(ZWJ가 지워져 가족 이모지가 쪼개짐).
    func test_sanitize_keepsEmojiAndCombiningMarks() {
        let family = "👨\u{200D}👩\u{200D}👧"
        XCTAssertEqual(clean("\(family) Home"), "\(family) Home")
        XCTAssertEqual(clean("Cafe\u{0301}"), "Cafe\u{0301}")
        XCTAssertEqual(clean("집 와이파이"), "집 와이파이")
    }

    // 이것을 실패시키는 것: 글자 수 상한을 빼는 것. ASCII라 바이트 상한(120)보다 글자 상한(40)이 먼저 걸린다.
    func test_sanitize_capsAt40Characters() {
        let long = String(repeating: "a", count: 60)
        XCTAssertEqual(clean(long)?.count, TriggerConfig.networkNameMaxCharacters)
    }

    // 이것을 실패시키는 것: UTF-8 바이트 상한을 빼는 것(결합 문자 수천 개짜리 한 글자가 통과).
    func test_sanitize_boundsPathologicalGraphemes() {
        let zalgo = "a" + String(repeating: "\u{0301}", count: 5_000)
        XCTAssertNil(clean(zalgo))
        let name = clean("Home " + zalgo)
        XCTAssertEqual(name, "Home")
    }
}
