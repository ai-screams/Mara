import XCTest
import Combine
@testable import MaraCore

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
}
