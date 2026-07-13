import Foundation
import XCTest
@testable import MaraCore

@MainActor
final class AdapterContractTests: XCTestCase {
    func test_dispatchScheduler_deliversOnMainThread() async {
        let delivered = expectation(description: "scheduled action delivered")
        let scheduler = DispatchScheduler()

        _ = scheduler.schedule(after: 0) {
            XCTAssertTrue(Thread.isMainThread)
            delivered.fulfill()
        }

        await fulfillment(of: [delivered], timeout: 1)
    }

    func test_batterySnapshot_distinguishesDesktopBatteryAndUnavailable() {
        XCTAssertTrue(BatterySnapshot.desktop.isOnAC)
        XCTAssertFalse(BatterySnapshot.unavailable.isOnAC)
        XCTAssertEqual(BatterySnapshot(percentage: 120, isOnAC: false),
                       .battery(percentage: 100, isOnAC: false))
        XCTAssertEqual(BatterySnapshot(percentage: -10, isOnAC: true),
                       .battery(percentage: 0, isOnAC: true))
    }

    func test_screenSnapshot_clampsImpossibleCounts() {
        XCTAssertEqual(ScreenSnapshot(totalCount: -1, externalCount: 3),
                       ScreenSnapshot(totalCount: 0, externalCount: 0))
        XCTAssertEqual(ScreenSnapshot(totalCount: 1, externalCount: 3),
                       ScreenSnapshot(totalCount: 1, externalCount: 1))
    }
}
