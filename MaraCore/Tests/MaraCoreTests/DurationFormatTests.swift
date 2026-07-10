import XCTest
@testable import MaraCore

final class DurationFormatTests: XCTestCase {
    func test_minutesUnderAnHour() {
        XCTAssertEqual(DurationFormat.compact(15 * 60), "15m")
        XCTAssertEqual(DurationFormat.compact(59 * 60), "59m")
    }
    func test_zeroAndSubMinute_roundToNearestMinute() {
        XCTAssertEqual(DurationFormat.compact(0), "0m")
        XCTAssertEqual(DurationFormat.compact(29), "0m")    // .rounded() 반내림
        XCTAssertEqual(DurationFormat.compact(30), "1m")    // .rounded() 반올림
        XCTAssertEqual(DurationFormat.compact(90), "2m")
    }
    func test_wholeHours() {
        XCTAssertEqual(DurationFormat.compact(3600), "1h")
        XCTAssertEqual(DurationFormat.compact(2 * 3600), "2h")
        XCTAssertEqual(DurationFormat.compact(24 * 3600), "24h")
    }
    func test_hoursWithMinutes() {
        XCTAssertEqual(DurationFormat.compact(90 * 60), "1h30m")
        XCTAssertEqual(DurationFormat.compact(3600 + 5 * 60), "1h5m")
    }
    func test_boundary_59point5MinutesRoundsToOneHour() {
        XCTAssertEqual(DurationFormat.compact(59.5 * 60), "1h")   // 60분으로 반올림 → "1h"
    }
    func test_hostileInputs_degradeSafely() {
        XCTAssertEqual(DurationFormat.compact(.nan), "0m")
        XCTAssertEqual(DurationFormat.compact(.infinity), "0m")
        XCTAssertEqual(DurationFormat.compact(-600), "0m")
        XCTAssertEqual(DurationFormat.compact(1e30), "24h")   // 상한 클램프
        XCTAssertEqual(DurationFormat.compact(0), "0m")       // 클램프 하한 경계
    }
}
