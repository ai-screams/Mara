import XCTest
@testable import MaraCore

final class MenuBarTintTests: XCTestCase {
    func testDefaultIsEmber() {
        XCTAssertEqual(MenuBarTint.default, .ember)
    }

    /// 팔레트 결정 고정 — case를 실수로 빼거나 더하면 여기서 깨진다(사용자 확정: 5색).
    func testAllCasesAreTheFivePalette() {
        XCTAssertEqual(MenuBarTint.allCases.count, 5)
        XCTAssertEqual(MenuBarTint.allCases, [.ember, .blood, .venom, .wraith, .nightshade])
    }

    /// 저장 문자열은 rawValue다 — 왕복이 안정적이어야 설정이 유지된다.
    func testRawValueRoundTripForAllCases() {
        for tint in MenuBarTint.allCases {
            XCTAssertEqual(MenuBarTint(rawValue: tint.rawValue), tint)
            XCTAssertEqual(MenuBarTint(storage: tint.rawValue), tint)
        }
    }

    func testStorageNilFallsBackToDefault() {
        XCTAssertEqual(MenuBarTint(storage: nil), .default)
    }

    func testStorageUnknownOrEmptyFallsBackToDefault() {
        XCTAssertEqual(MenuBarTint(storage: "chartreuse-of-doom"), .default)
        XCTAssertEqual(MenuBarTint(storage: ""), .default)
        XCTAssertEqual(MenuBarTint(storage: "Ember"), .default)   // 대소문자 구분 — rawValue는 소문자
    }

    func testStorageKnownValueDecodes() {
        XCTAssertEqual(MenuBarTint(storage: "blood"), .blood)
        XCTAssertEqual(MenuBarTint(storage: "nightshade"), .nightshade)
    }
}
