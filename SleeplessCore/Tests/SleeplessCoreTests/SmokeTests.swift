import XCTest
@testable import SleeplessCore

final class SmokeTests: XCTestCase {
    func test_packageBuildsAndTestsRun() {
        XCTAssertEqual(SleeplessCore.version, "0.1.0")
    }
}
