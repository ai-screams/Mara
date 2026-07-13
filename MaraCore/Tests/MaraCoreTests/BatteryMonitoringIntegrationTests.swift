import Combine
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
}
