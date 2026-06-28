import XCTest
@testable import MaraCore

final class SmokeTests: XCTestCase {
    func test_packageBuildsAndTestsRun() {
        XCTAssertEqual(MaraCore.version, "0.1.0")
    }
}
