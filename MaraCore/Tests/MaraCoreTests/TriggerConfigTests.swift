import XCTest
@testable import MaraCore

final class TriggerConfigTests: XCTestCase {

    // MARK: - Backward-compatible Codable

    private func decode(_ json: String) throws -> TriggerConfig {
        try JSONDecoder().decode(TriggerConfig.self, from: Data(json.utf8))
    }

    func test_decode_emptyObject_fallsBackToAllDefaults() throws {
        // 구버전/미래버전 JSON에 키가 없어도 throw/데이터 소실 없이 기본값으로 디코드.
        let cfg = try decode("{}")
        XCTAssertEqual(cfg, .defaults)
    }

    func test_decode_missingNewerKeys_usesFalseAndEmptyDefaults() throws {
        // 예전 스키마(charging만 존재)에서 업그레이드 시 나머지는 기본값으로 채워진다.
        let cfg = try decode(#"{"chargingEnabled": true}"#)
        XCTAssertTrue(cfg.chargingEnabled)
        XCTAssertFalse(cfg.externalDisplayEnabled)
        XCTAssertFalse(cfg.appRunningEnabled)
        XCTAssertEqual(cfg.watchedBundleIDs, [])
        XCTAssertFalse(cfg.networkEnabled)
        XCTAssertEqual(cfg.watchedNetworks, [])
    }

    func test_encodeDecode_roundTrips() throws {
        let original = TriggerConfig(
            chargingEnabled: true,
            externalDisplayEnabled: false,
            appRunningEnabled: true,
            watchedBundleIDs: ["com.apple.Safari", "com.foo.Bar"],
            networkEnabled: true,
            watchedNetworks: ["00:10:db:ff:10:02"]
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(TriggerConfig.self, from: data)
        XCTAssertEqual(restored, original)
    }

    func test_defaults_areAllDisabledAndEmpty() {
        let d = TriggerConfig.defaults
        XCTAssertFalse(d.chargingEnabled)
        XCTAssertFalse(d.externalDisplayEnabled)
        XCTAssertFalse(d.appRunningEnabled)
        XCTAssertFalse(d.networkEnabled)
        XCTAssertEqual(d.watchedBundleIDs, [])
        XCTAssertEqual(d.watchedNetworks, [])
    }
}

// MARK: - activeSpecs() 순수 결정 로직

extension TriggerConfigTests {
    private func config(
        charging: Bool = false, externalDisplay: Bool = false,
        appRunning: Bool = false, bundleIDs: [String] = [],
        network: Bool = false, networks: [String] = []
    ) -> TriggerConfig {
        TriggerConfig(
            chargingEnabled: charging, externalDisplayEnabled: externalDisplay,
            appRunningEnabled: appRunning, watchedBundleIDs: bundleIDs,
            networkEnabled: network, watchedNetworks: networks
        )
    }

    func test_activeSpecs_allDisabled_isEmpty() {
        XCTAssertEqual(config().activeSpecs(), [])
    }

    func test_activeSpecs_charging() {
        XCTAssertEqual(config(charging: true).activeSpecs(), [.charging])
    }

    func test_activeSpecs_externalDisplay() {
        XCTAssertEqual(config(externalDisplay: true).activeSpecs(), [.externalDisplay])
    }

    func test_activeSpecs_appRunning_withWatched() {
        XCTAssertEqual(
            config(appRunning: true, bundleIDs: ["com.apple.Safari"]).activeSpecs(),
            [.appRunning(["com.apple.Safari"])]
        )
    }

    func test_activeSpecs_appRunning_enabledButEmpty_isExcluded() {
        // enable 되어도 감시 목록이 비면 항상-false 트리거를 만들지 않는다.
        XCTAssertEqual(config(appRunning: true, bundleIDs: []).activeSpecs(), [])
    }

    func test_activeSpecs_appRunning_deduplicatesWatched() {
        // Set 변환으로 중복 bundle ID는 하나로 정규화된다.
        XCTAssertEqual(
            config(appRunning: true, bundleIDs: ["a", "a"]).activeSpecs(),
            [.appRunning(["a"])]
        )
    }

    func test_activeSpecs_network_withWatched_normalizesMAC() {
        // watchedNetworks 문자열이 NetworkIdentity로 정규화되어 spec에 담긴다.
        let specs = config(network: true, networks: ["0:10:db:ff:10:2"]).activeSpecs()
        XCTAssertEqual(specs, [.network([NetworkIdentity(gatewayMAC: "00:10:db:ff:10:02")])])
    }

    func test_activeSpecs_network_enabledButEmpty_isExcluded() {
        XCTAssertEqual(config(network: true, networks: []).activeSpecs(), [])
    }

    func test_activeSpecs_allEnabled_producesAllFour() {
        let specs = config(
            charging: true, externalDisplay: true,
            appRunning: true, bundleIDs: ["a"],
            network: true, networks: ["00:10:db:ff:10:02"]
        ).activeSpecs()
        XCTAssertEqual(specs.count, 4)
        XCTAssertTrue(specs.contains(.charging))
        XCTAssertTrue(specs.contains(.externalDisplay))
        XCTAssertTrue(specs.contains(.appRunning(["a"])))
        XCTAssertTrue(specs.contains(.network([NetworkIdentity(gatewayMAC: "00:10:db:ff:10:02")])))
    }
}
