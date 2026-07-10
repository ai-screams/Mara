import XCTest
@testable import MaraCore

final class BundleIdentifierTests: XCTestCase {
    // MARK: - 검증

    func test_valid_typicalReverseDNS() {
        XCTAssertEqual(BundleIdentifier(validating: "com.apple.Safari")?.rawValue, "com.apple.Safari")
        XCTAssertEqual(BundleIdentifier(validating: "com.tiny-speck.slackmacgap2")?.rawValue,
                       "com.tiny-speck.slackmacgap2")
    }

    func test_valid_trimsSurroundingWhitespace() {
        XCTAssertEqual(BundleIdentifier(validating: "  com.foo.Bar\n")?.rawValue, "com.foo.Bar")
    }

    func test_invalid_emptyOrWhitespaceOnly() {
        XCTAssertNil(BundleIdentifier(validating: ""))
        XCTAssertNil(BundleIdentifier(validating: "   \n"))
    }

    func test_invalid_internalWhitespaceOrControl() {
        XCTAssertNil(BundleIdentifier(validating: "com foo"))          // 내부 공백 — 오타 차단이 검증의 목적
        XCTAssertNil(BundleIdentifier(validating: "com.a\nb"))         // 내부 개행
        XCTAssertNil(BundleIdentifier(validating: "com.a\u{0000}b"))   // 제어문자
    }

    func test_valid_beyondAppleRecommendedCharset() {
        // Apple 권고([A-Za-z0-9-.])보다 넓게 허용 — 언더스코어 포함 실존 앱(Electron 계열)과
        // 구버전 자유 입력으로 저장된 항목의 업그레이드 생존을 위해 (Codex 감사 반영).
        XCTAssertEqual(BundleIdentifier(validating: "com.foo_bar")?.rawValue, "com.foo_bar")
        XCTAssertEqual(BundleIdentifier(validating: "com.한글.app")?.rawValue, "com.한글.app")
    }

    func test_caseIsPreserved_matchingIsExact() {
        // 정규화하지 않는다 — 피커가 OS의 정확한 표기를 제공한다.
        let a = BundleIdentifier(validating: "com.Foo")
        let b = BundleIdentifier(validating: "com.foo")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Codable (기존 [String] JSON과 호환)

    func test_decode_fromPlainJSONString() throws {
        let decoded = try JSONDecoder().decode([BundleIdentifier].self,
                                               from: Data(#"["com.apple.Safari"]"#.utf8))
        XCTAssertEqual(decoded.map(\.rawValue), ["com.apple.Safari"])
    }

    func test_encode_producesPlainJSONString() throws {
        let ids = [BundleIdentifier(validating: "com.foo.Bar")!]
        let json = String(data: try JSONEncoder().encode(ids), encoding: .utf8)
        XCTAssertEqual(json, #"["com.foo.Bar"]"#)
    }

    func test_decode_invalidString_throws() {
        // 단독 디코드는 throw — 목록 레벨 안전 필터는 TriggerConfig가 담당(그쪽 테스트 참조).
        XCTAssertThrowsError(try JSONDecoder().decode(BundleIdentifier.self,
                                                      from: Data(#""bad id""#.utf8)))
    }
}
