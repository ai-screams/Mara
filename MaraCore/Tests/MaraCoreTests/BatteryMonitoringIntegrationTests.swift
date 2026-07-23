import Combine
import IOKit.ps
import XCTest
@testable import MaraCore

@MainActor
final class BatteryMonitoringIntegrationTests: XCTestCase {
    func test_iokitMonitorPublishesCoherentInitialSnapshot() {
        var monitor: IOKitBatteryMonitor? = IOKitBatteryMonitor()
        var received: [BatterySnapshot] = []
        let cancellable = monitor?.snapshots.sink { received.append($0) }

        guard let snapshot = monitor?.snapshot else {
            return XCTFail("monitor unexpectedly missing")
        }
        XCTAssertEqual(received, [snapshot])
        if case .battery(let percentage, _) = snapshot {
            XCTAssertTrue((0...100).contains(percentage))
        }

        cancellable?.cancel()
        monitor = nil   // main-actor deinit must remove and invalidate the CFRunLoop source safely
    }

    // MARK: - parse: 하드웨어 비의존 순수 변환 (헤드리스 CI에서도 커버됨)

    func test_parse_acPower_reportsOnAC() {
        let snapshot = IOKitBatteryMonitor.parse([
            kIOPSCurrentCapacityKey: 80,
            kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        ])
        XCTAssertEqual(snapshot, .battery(percentage: 80, isOnAC: true))
    }

    func test_parse_batteryPower_reportsOffAC() {
        let snapshot = IOKitBatteryMonitor.parse([
            kIOPSCurrentCapacityKey: 30,
            kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
        ])
        XCTAssertEqual(snapshot, .battery(percentage: 30, isOnAC: false))
    }

    func test_parse_computesRatioWhenMaxNot100() {
        let snapshot = IOKitBatteryMonitor.parse([
            kIOPSCurrentCapacityKey: 25,
            kIOPSMaxCapacityKey: 50,
            kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
        ])
        XCTAssertEqual(snapshot, .battery(percentage: 50, isOnAC: false))
    }

    func test_parse_clampsAbove100() {
        let snapshot = IOKitBatteryMonitor.parse([
            kIOPSCurrentCapacityKey: 120,
            kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
        ])
        XCTAssertEqual(snapshot, .battery(percentage: 100, isOnAC: false))
    }

    func test_parse_missingCurrentCapacity_isUnavailable() {
        let snapshot = IOKitBatteryMonitor.parse([
            kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        ])
        XCTAssertEqual(snapshot, .unavailable)
    }

    func test_parse_nonPositiveMaxCapacity_isUnavailable() {
        let snapshot = IOKitBatteryMonitor.parse([
            kIOPSCurrentCapacityKey: 50,
            kIOPSMaxCapacityKey: 0,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        ])
        XCTAssertEqual(snapshot, .unavailable)
    }

    func test_parse_missingState_isUnavailable() {
        let snapshot = IOKitBatteryMonitor.parse([
            kIOPSCurrentCapacityKey: 50,
            kIOPSMaxCapacityKey: 100,
        ])
        XCTAssertEqual(snapshot, .unavailable)
    }

    // MARK: - select: 전원 소스 선택 정책 (순서가 아니라 type으로 고른다)
    //
    // IOPSCopyPowerSourcesList는 정렬을 계약하지 않으므로 순서 permutation을 고정한다.
    // 실제 UPS 하드웨어 없이 dictionary fixture로 계약을 못박는 자리다.

    private func internalBattery(_ percent: Int) -> [String: Any] {
        [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: percent,
            kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
        ]
    }

    private func ups(_ percent: Int) -> [String: Any] {
        [
            kIOPSTypeKey: kIOPSUPSType,
            kIOPSCurrentCapacityKey: percent,
            kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        ]
    }

    func test_select_prefersInternalBattery_whenUPSComesFirst() {
        let chosen = IOKitBatteryMonitor.select([ups(90), internalBattery(15)])
        XCTAssertEqual(IOKitBatteryMonitor.parse(chosen ?? [:]), .battery(percentage: 15, isOnAC: false))
    }

    func test_select_prefersInternalBattery_whenInternalComesFirst() {
        let chosen = IOKitBatteryMonitor.select([internalBattery(15), ups(90)])
        XCTAssertEqual(IOKitBatteryMonitor.parse(chosen ?? [:]), .battery(percentage: 15, isOnAC: false))
    }

    /// 핵심 회귀 가드: 배열 순서를 뒤집어도 결과가 같아야 한다(예전 `list.first`는 여기서 갈렸다).
    func test_select_isOrderIndependent() {
        let forward = IOKitBatteryMonitor.select([ups(90), internalBattery(15)])
        let reversed = IOKitBatteryMonitor.select([internalBattery(15), ups(90)])
        XCTAssertEqual(IOKitBatteryMonitor.parse(forward ?? [:]), IOKitBatteryMonitor.parse(reversed ?? [:]))
    }

    /// 데스크톱 + UPS: 내부 배터리가 없으면 첫 유효 소스로 폴백한다.
    func test_select_fallsBackToFirstSource_whenNoInternalBattery() {
        let chosen = IOKitBatteryMonitor.select([ups(90)])
        XCTAssertEqual(IOKitBatteryMonitor.parse(chosen ?? [:]), .battery(percentage: 90, isOnAC: true))
    }

    /// description을 하나도 못 읽으면 nil → read()가 .unavailable로 매핑한다.
    /// (소스가 0개인 데스크톱의 .desktop과 의미가 섞이지 않아야 한다 — 그 분기는 read()가 담당.)
    func test_select_emptyDescriptions_isNil() {
        XCTAssertNil(IOKitBatteryMonitor.select([]))
    }

    /// 내부 배터리가 malformed여도 UPS 잔량으로 대체하지 않는다 — UPS %를 Mac 배터리인 양
    /// 보고하면 잘못된 자동 종료를 부른다. 모른다는 사실에 정직하게 .unavailable.
    func test_select_malformedInternalBattery_doesNotFallBackToUPS() {
        let malformed: [String: Any] = [kIOPSTypeKey: kIOPSInternalBatteryType]
        let chosen = IOKitBatteryMonitor.select([ups(90), malformed])
        XCTAssertEqual(IOKitBatteryMonitor.parse(chosen ?? [:]), .unavailable)
    }

    /// type 키가 없는 소스만 있으면(알 수 없는 어댑터) 첫 유효 소스로 폴백한다.
    func test_select_untypedSources_fallBackToFirst() {
        let untyped: [String: Any] = [
            kIOPSCurrentCapacityKey: 42,
            kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
        ]
        let chosen = IOKitBatteryMonitor.select([untyped, ups(90)])
        XCTAssertEqual(IOKitBatteryMonitor.parse(chosen ?? [:]), .battery(percentage: 42, isOnAC: false))
    }
}
