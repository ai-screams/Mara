import XCTest
import Combine
@testable import MaraCore

@MainActor
final class TriggerEvaluatorTests: XCTestCase {
    func test_mockTrigger_publishesChanges() {
        let t = MockTrigger(kind: .charging, satisfied: false)
        var received: [Bool] = []
        let c = t.satisfied.sink { received.append($0) }
        t.set(true); t.set(false)
        c.cancel()
        XCTAssertEqual(received, [false, true, false])
        XCTAssertEqual(t.kind, .charging)
    }
}

extension TriggerEvaluatorTests {
    func test_externalDisplayTrigger_satisfiedWhenMoreThanOneScreen() {
        let screens = MockScreens(count: 1)
        let t = ExternalDisplayTrigger(screens: screens)
        XCTAssertFalse(t.isSatisfied)
        var received: [Bool] = []
        let c = t.satisfied.sink { received.append($0) }
        screens.set(2)   // 외장 연결
        screens.set(1)   // 분리
        c.cancel()
        XCTAssertEqual(received, [false, true, false])
    }

    func test_externalDisplayTrigger_singleExternalScreen_isSatisfied() {
        let screens = MockScreens(count: 1, externalCount: 1)
        let trigger = ExternalDisplayTrigger(screens: screens)

        XCTAssertTrue(trigger.isSatisfied, "single-monitor desktops and clamshell mode are external")
    }
}

extension TriggerEvaluatorTests {
    func test_appRunningTrigger_satisfiedWhenWatchedAppRuns() {
        let apps = MockApps(["com.apple.Safari"])
        let t = AppRunningTrigger(apps: apps, watched: ["com.foo.bar"])
        XCTAssertFalse(t.isSatisfied)
        var received: [Bool] = []
        let c = t.satisfied.sink { received.append($0) }
        apps.set(["com.apple.Safari", "com.foo.bar"])  // 감시 앱 실행
        apps.set(["com.apple.Safari"])                  // 종료
        c.cancel()
        XCTAssertEqual(received, [false, true, false])
    }
}

extension TriggerEvaluatorTests {
    func test_chargingTrigger_followsACState() {
        let bat = MockBattery(percentage: 80, isOnAC: false)
        let t = ChargingTrigger(battery: bat)
        XCTAssertFalse(t.isSatisfied)
        var received: [Bool] = []
        let c = t.satisfied.sink { received.append($0) }
        bat.emit(percentage: 80, isOnAC: true)   // 충전 연결
        bat.emit(percentage: 81, isOnAC: true)   // 퍼센트만 변화 → isOnAC 불변, 중복 방출 없어야
        bat.emit(percentage: 81, isOnAC: false)  // 분리
        c.cancel()
        XCTAssertEqual(received, [false, true, false])
        XCTAssertFalse(t.isSatisfied)
    }

    func test_chargingTrigger_unavailableDoesNotActivate() {
        let battery = MockBattery(percentage: 80, isOnAC: true)
        let trigger = ChargingTrigger(battery: battery)
        battery.emitUnavailable()

        XCTAssertFalse(trigger.isSatisfied)
        XCTAssertEqual(trigger.diagnostic, .batteryUnavailable)
    }
}
