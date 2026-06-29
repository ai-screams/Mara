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
