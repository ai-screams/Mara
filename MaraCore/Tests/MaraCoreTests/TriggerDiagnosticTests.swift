import XCTest
import Combine
@testable import MaraCore

/// 각 평가기의 TriggerDiagnosing conformance — 현재값과 변화 방출을 검증한다.
@MainActor
final class TriggerDiagnosticTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Charging

    func test_charging_diagnosticReflectsACState() {
        let battery = MockBattery(percentage: 80, isOnAC: false)
        let t = ChargingTrigger(battery: battery)
        XCTAssertEqual(t.diagnostic, .charging(onAC: false))
        battery.emit(percentage: 80, isOnAC: true)
        XCTAssertEqual(t.diagnostic, .charging(onAC: true))
    }

    func test_charging_diagnosticsPublishesOnChange_andDeduplicates() {
        let battery = MockBattery(percentage: 80, isOnAC: false)
        let t = ChargingTrigger(battery: battery)
        var received: [TriggerDiagnostic] = []
        t.diagnostics.sink { received.append($0) }.store(in: &cancellables)
        XCTAssertEqual(received, [.charging(onAC: false)])   // CurrentValueSubject replay
        battery.emit(percentage: 50, isOnAC: false)          // AC 동일 → dedup, 방출 없음
        battery.emit(percentage: 50, isOnAC: true)
        XCTAssertEqual(received, [.charging(onAC: false), .charging(onAC: true)])
    }

    func test_charging_diagnosticsPublishesUnavailable() {
        // 변경 알림 경로도 지금 값 경로(TriggerEvaluatorTests)와 같은 매핑을 쓰는지 고정한다.
        // 이것을 실패시키는 것: 진단 매핑에서 .unavailable 분기를 빼면 .charging(onAC: false)가 나온다.
        let battery = MockBattery(percentage: 80, isOnAC: true)
        let t = ChargingTrigger(battery: battery)
        var received: [TriggerDiagnostic] = []
        t.diagnostics.sink { received.append($0) }.store(in: &cancellables)
        battery.emitUnavailable()
        XCTAssertEqual(received, [.charging(onAC: true), .batteryUnavailable])
    }

    // MARK: - External display

    func test_externalDisplay_diagnosticReflectsScreenCount() {
        let screens = MockScreens(count: 1)
        let t = ExternalDisplayTrigger(screens: screens)
        XCTAssertEqual(t.diagnostic, .externalDisplay(screenCount: 1))
        screens.set(3)
        XCTAssertEqual(t.diagnostic, .externalDisplay(screenCount: 3))
    }

    func test_externalDisplay_diagnosticsPublishesDetailChange_evenWhenSatisfiedUnchanged() {
        // satisfied(Bool)는 2→3에서 변하지 않지만 진단은 변해야 한다 — 이 publisher의 존재 이유.
        let screens = MockScreens(count: 2)
        let t = ExternalDisplayTrigger(screens: screens)
        var received: [TriggerDiagnostic] = []
        t.diagnostics.sink { received.append($0) }.store(in: &cancellables)
        screens.set(3)
        XCTAssertEqual(received, [.externalDisplay(screenCount: 2), .externalDisplay(screenCount: 3)])
    }

    // MARK: - App running

    func test_appRunning_diagnosticExposesOnlyMatchedIDs() {
        let apps = MockApps(["com.apple.dt.Xcode", "com.tinyspeck.slackmacgap"])
        let t = AppRunningTrigger(apps: apps, watched: ["com.tinyspeck.slackmacgap"])
        // 감시 목록과의 교집합만 — 무관한 실행 앱(Xcode)은 노출 금지.
        XCTAssertEqual(t.diagnostic, .appRunning(matched: ["com.tinyspeck.slackmacgap"]))
        apps.set(["com.apple.dt.Xcode"])
        XCTAssertEqual(t.diagnostic, .appRunning(matched: []))
    }

    func test_appRunning_diagnosticsDeduplicates_whenUnwatchedAppsChange() {
        let apps = MockApps(["com.tinyspeck.slackmacgap"])
        let t = AppRunningTrigger(apps: apps, watched: ["com.tinyspeck.slackmacgap"])
        var received: [TriggerDiagnostic] = []
        t.diagnostics.sink { received.append($0) }.store(in: &cancellables)
        apps.set(["com.tinyspeck.slackmacgap", "com.apple.dt.Xcode"])   // matched 불변 → dedup
        XCTAssertEqual(received, [.appRunning(matched: ["com.tinyspeck.slackmacgap"])])
    }

    func test_appRunning_diagnosticsPublishesWhenWatchedAppQuits() {
        let apps = MockApps(["com.tinyspeck.slackmacgap"])
        let t = AppRunningTrigger(apps: apps, watched: ["com.tinyspeck.slackmacgap"])
        var received: [TriggerDiagnostic] = []
        t.diagnostics.sink { received.append($0) }.store(in: &cancellables)
        apps.set([])   // 감시 앱 종료 → matched 변화가 방출되어야 한다
        XCTAssertEqual(received, [
            .appRunning(matched: ["com.tinyspeck.slackmacgap"]),
            .appRunning(matched: []),
        ])
    }

    // MARK: - Network

    func test_network_diagnosticCoversNilCurrentAndMatch() {
        let watched = NetworkIdentity(gatewayMAC: "00:10:db:ff:10:02")
        let net = MockNetwork(nil)
        let t = NetworkTrigger(network: net, watched: [watched])
        XCTAssertEqual(t.diagnostic, .network(current: nil, matched: false))
        net.set(watched)
        XCTAssertEqual(t.diagnostic, .network(current: watched, matched: true))
        let other = NetworkIdentity(gatewayMAC: "aa:bb:cc:dd:ee:ff")
        net.set(other)
        XCTAssertEqual(t.diagnostic, .network(current: other, matched: false))
    }

    func test_network_diagnosticsPublishesTransitions() {
        let watched = NetworkIdentity(gatewayMAC: "00:10:db:ff:10:02")
        let net = MockNetwork(nil)
        let t = NetworkTrigger(network: net, watched: [watched])
        var received: [TriggerDiagnostic] = []
        t.diagnostics.sink { received.append($0) }.store(in: &cancellables)
        net.set(watched)
        let other = NetworkIdentity(gatewayMAC: "aa:bb:cc:dd:ee:ff")
        net.set(other)
        // 이것을 실패시키는 것: 일치 판정이 감시 목록을 보지 않으면 마지막 항목이 matched: true가 된다.
        XCTAssertEqual(received, [
            .network(current: nil, matched: false),
            .network(current: watched, matched: true),
            .network(current: other, matched: false),
        ])
    }

    // MARK: - Snapshot 모델

    func test_engineSnapshot_lookupByKind() {
        let snap = TriggerEngineSnapshot(
            triggers: [
                TriggerSnapshot(kind: .charging, isSatisfied: true, diagnostic: .charging(onAC: true)),
                TriggerSnapshot(kind: .network, isSatisfied: false, diagnostic: nil),
            ],
            isSuppressed: false
        )
        XCTAssertEqual(snap.trigger(.charging)?.isSatisfied, true)
        XCTAssertEqual(snap.trigger(.network)?.diagnostic, nil)
        XCTAssertNil(snap.trigger(.externalDisplay))
        XCTAssertEqual(TriggerEngineSnapshot.empty, TriggerEngineSnapshot(triggers: [], isSuppressed: false))
    }
}
