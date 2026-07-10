import XCTest
@testable import MaraCore

final class CountdownFormatTests: XCTestCase {

    // MARK: - label: 정확한 남은 시간(분 반올림) — 올림 아님

    func testLabel_exactBoundary5h() {
        // 정확 경계: 18000초 → compact(18000) = 300분 → "5h"
        XCTAssertEqual(CountdownFormat.label(remaining: 5 * 3600), "5h")
    }

    func testLabel_justAfterBoundary5h() {
        // 경계 직후: 4h59m59s = 17999초 → 분 반올림 = 300분 → "5h" (틱 사이 오차는 반올림이 흡수)
        XCTAssertEqual(CountdownFormat.label(remaining: 4 * 3600 + 59 * 60 + 59), "5h")
    }

    func testLabel_next5minBoundary() {
        // 4h55m 경계: 17700초 → 295분 → "4h55m"
        XCTAssertEqual(CountdownFormat.label(remaining: 4 * 3600 + 55 * 60), "4h55m")
    }

    func testLabel_6min_exact() {
        // 정확 라벨: 6분은 "6m" — 올림("10m")이었다면 5분 배수가 아닌 세션이 과대 표시된다
        XCTAssertEqual(CountdownFormat.label(remaining: 6 * 60), "6m")
    }

    func testLabel_47min_honestStart() {
        // 커스텀 47m 세션 시작 직후: "47m" (과대 표시 없음). 이후 틱은 45m 경계에 정렬된다.
        XCTAssertEqual(CountdownFormat.label(remaining: 47 * 60), "47m")
    }

    func testLabel_exactBoundary5m() {
        // 300초 → 5분 → "5m"
        XCTAssertEqual(CountdownFormat.label(remaining: 5 * 60), "5m")
    }

    func testLabel_4min30sec_roundsToNearest() {
        // 분 반올림: 4m30s = 270초 → round(4.5) = 5 → "5m"
        XCTAssertEqual(CountdownFormat.label(remaining: 4 * 60 + 30), "5m")
    }

    func testLabel_3min_fine() {
        XCTAssertEqual(CountdownFormat.label(remaining: 3 * 60), "3m")
    }

    func testLabel_subMinute_floorsAtOneMinute() {
        // 활성 세션의 마지막 1분은 "0m" 대신 "1m" 바닥 처리 (만료 알림은 SessionManager 몫)
        XCTAssertEqual(CountdownFormat.label(remaining: 59), "1m")
        XCTAssertEqual(CountdownFormat.label(remaining: 29), "1m")
    }

    func testLabel_zero() {
        XCTAssertEqual(CountdownFormat.label(remaining: 0), "0m")
    }

    func testLabel_negative() {
        XCTAssertEqual(CountdownFormat.label(remaining: -5), "0m")
    }

    func testLabel_nan() {
        XCTAssertEqual(CountdownFormat.label(remaining: .nan), "0m")
    }

    // MARK: - nextTick: 경계 정렬

    func testNextTick_exactBoundary5h() {
        // 정확 경계 → next = (60-1)*300 = 17700 → tick = 18000-17700 = 300
        XCTAssertEqual(CountdownFormat.nextTick(remaining: 5 * 3600), 300, accuracy: 0.001)
    }

    func testNextTick_4h57min() {
        // 4h57m = 17820초 → g=300 → ceil(17820/300)=60 → next=(60-1)*300=17700 → tick=17820-17700=120
        XCTAssertEqual(CountdownFormat.nextTick(remaining: 4 * 3600 + 57 * 60), 120, accuracy: 0.001)
    }

    func testNextTick_exactBoundary5m() {
        // 300초(경계, fine 영역) → g=60 → ceil(300/60)=5 → next=(5-1)*60=240 → tick=300-240=60
        XCTAssertEqual(CountdownFormat.nextTick(remaining: 5 * 60), 60, accuracy: 0.001)
    }

    func testNextTick_3min30sec() {
        // 3m30s = 210초 → g=60 → ceil(210/60)=4 → next=(4-1)*60=180 → tick=210-180=30
        XCTAssertEqual(CountdownFormat.nextTick(remaining: 3 * 60 + 30), 30, accuracy: 0.001)
    }

    func testNextTick_zeroOrNegative() {
        // 비정상 입력 → fine(60) 반환
        XCTAssertEqual(CountdownFormat.nextTick(remaining: 0), 60, accuracy: 0.001)
        XCTAssertEqual(CountdownFormat.nextTick(remaining: -1), 60, accuracy: 0.001)
    }
}
