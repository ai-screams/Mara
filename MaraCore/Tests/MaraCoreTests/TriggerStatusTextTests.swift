import XCTest
@testable import MaraCore

final class TriggerStatusTextTests: XCTestCase {
    private func snapshot(_ snaps: [TriggerSnapshot]) -> TriggerEngineSnapshot {
        TriggerEngineSnapshot(triggers: snaps, isSuppressed: false)
    }

    private func config(charging: Bool = false, extDisplay: Bool = false,
                        appRunning: Bool = false, bundleIDs: [String] = [],
                        network: Bool = false, networks: [String] = []) -> TriggerConfig {
        var c = TriggerConfig.defaults
        c.chargingEnabled = charging
        c.externalDisplayEnabled = extDisplay
        c.appRunningEnabled = appRunning
        c.networkEnabled = network
        c.watchedNetworks = networks
        for id in bundleIDs { _ = c.addWatchedBundleID(id) }
        return c
    }

    // MARK: guards

    func testDisabledReturnsNil() {
        XCTAssertNil(TriggerStatusText.evaluate(.charging, config: config(charging: false), snapshot: snapshot([])))
        XCTAssertNil(TriggerStatusText.evaluate(.network, config: config(network: false), snapshot: snapshot([])))
    }

    func testAppRunningEmptyListNeedsWatchList() {
        XCTAssertEqual(TriggerStatusText.evaluate(.appRunning, config: config(appRunning: true, bundleIDs: []),
                                                  snapshot: snapshot([])), .needsWatchList(.appRunning))
    }

    func testNetworkEmptyListNeedsWatchList() {
        XCTAssertEqual(TriggerStatusText.evaluate(.network, config: config(network: true, networks: []),
                                                  snapshot: snapshot([])), .needsWatchList(.network))
    }

    func testSnapshotMissingIsChecking() {
        XCTAssertEqual(TriggerStatusText.evaluate(.charging, config: config(charging: true),
                                                  snapshot: snapshot([])), .checking)
    }

    // MARK: diagnostics

    func testChargingOnACActive() {
        let snap = TriggerSnapshot(kind: .charging, isSatisfied: true, diagnostic: .charging(onAC: true))
        XCTAssertEqual(TriggerStatusText.evaluate(.charging, config: config(charging: true), snapshot: snapshot([snap])),
                       .charging(active: true, onAC: true))
    }

    func testChargingOnBatteryInactive() {
        let snap = TriggerSnapshot(kind: .charging, isSatisfied: false, diagnostic: .charging(onAC: false))
        XCTAssertEqual(TriggerStatusText.evaluate(.charging, config: config(charging: true), snapshot: snapshot([snap])),
                       .charging(active: false, onAC: false))
    }

    func testExternalDisplayActive() {
        let snap = TriggerSnapshot(kind: .externalDisplay, isSatisfied: true, diagnostic: .externalDisplay(screenCount: 2))
        XCTAssertEqual(TriggerStatusText.evaluate(.externalDisplay, config: config(extDisplay: true), snapshot: snapshot([snap])),
                       .externalDisplay(active: true, count: 2))
    }

    func testAppRunningSingleMatch() {
        let snap = TriggerSnapshot(kind: .appRunning, isSatisfied: true, diagnostic: .appRunning(matched: ["com.a"]))
        XCTAssertEqual(TriggerStatusText.evaluate(.appRunning, config: config(appRunning: true, bundleIDs: ["com.a", "com.b"]),
                                                  snapshot: snapshot([snap])), .appRunningSingle(active: true, id: "com.a"))
    }

    func testAppRunningMultipleMatch() {
        let snap = TriggerSnapshot(kind: .appRunning, isSatisfied: true, diagnostic: .appRunning(matched: ["com.a", "com.b"]))
        XCTAssertEqual(TriggerStatusText.evaluate(.appRunning, config: config(appRunning: true, bundleIDs: ["com.a", "com.b"]),
                                                  snapshot: snapshot([snap])), .appRunningMultiple(count: 2))
    }

    func testAppRunningNoneReportsWatchedCount() {
        let snap = TriggerSnapshot(kind: .appRunning, isSatisfied: false, diagnostic: .appRunning(matched: []))
        XCTAssertEqual(TriggerStatusText.evaluate(.appRunning, config: config(appRunning: true, bundleIDs: ["com.a", "com.b", "com.c"]),
                                                  snapshot: snapshot([snap])), .appRunningNone(watched: 3))
    }

    func testNetworkMatched() {
        let id = NetworkIdentity(gatewayMAC: "00:11:22:33:44:55")
        let snap = TriggerSnapshot(kind: .network, isSatisfied: true, diagnostic: .network(current: id, matched: true))
        XCTAssertEqual(TriggerStatusText.evaluate(.network, config: config(network: true, networks: ["00:11:22:33:44:55"]),
                                                  snapshot: snapshot([snap])), .network(active: true, gatewayMAC: id.gatewayMAC, matched: true))
    }

    func testNetworkUnresolvedGateway() {
        let snap = TriggerSnapshot(kind: .network, isSatisfied: false, diagnostic: .network(current: nil, matched: false))
        XCTAssertEqual(TriggerStatusText.evaluate(.network, config: config(network: true, networks: ["00:11:22:33:44:55"]),
                                                  snapshot: snapshot([snap])), .network(active: false, gatewayMAC: nil, matched: false))
    }

    func testPlainWhenNoDiagnostic() {
        let snap = TriggerSnapshot(kind: .charging, isSatisfied: true, diagnostic: nil)
        XCTAssertEqual(TriggerStatusText.evaluate(.charging, config: config(charging: true), snapshot: snapshot([snap])),
                       .plain(active: true))
    }
}

extension TriggerStatusTextTests {
    func testChargingUnavailableIsExplicit() {
        let config = TriggerConfig(
            chargingEnabled: true,
            externalDisplayEnabled: false,
            appRunningEnabled: false,
            watchedBundleIDs: [],
            networkEnabled: false,
            watchedNetworks: []
        )
        let snapshot = TriggerEngineSnapshot(
            triggers: [TriggerSnapshot(
                kind: .charging,
                isSatisfied: false,
                diagnostic: .batteryUnavailable
            )],
            isSuppressed: false
        )

        XCTAssertEqual(
            TriggerStatusText.evaluate(.charging, config: config, snapshot: snapshot),
            .batteryUnavailable
        )
    }
}
