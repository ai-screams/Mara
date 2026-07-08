import XCTest
@testable import MaraCore

/// 실제 커널 라우팅/ARP 테이블에 대해 파서를 구동한다(권한 불필요).
/// 특정 값이 아니라 **형태**(nil 또는 정규화된 MAC)를 검증하므로, 게이트웨이 유무와
/// 무관하게 CI에서 견고하다. 목적: 오프셋 워크가 실기 커널 데이터에서 트랩 없이
/// 동작하고 well-formed 값을 내는지 실제 코드 경로로 확인(스크래치 복사본이 아님).
final class RoutingTableParserTests: XCTestCase {
    private let macPattern = "^([0-9a-f]{2}:){5}[0-9a-f]{2}$"

    func test_defaultGatewayIP_doesNotTrap_andMACIsWellFormedWhenPresent() {
        // 게이트웨이가 없으면 nil(정상). 있으면 MAC은 nil 또는 소문자 콜론-헥사 6옥텟.
        guard let gwIP = RoutingTableParser.defaultGatewayIP() else { return }
        guard let mac = RoutingTableParser.macForIP(gwIP) else { return }
        XCTAssertNotNil(mac.range(of: macPattern, options: .regularExpression),
                        "MAC must be lowercase colon-hex 6 octets, got \(mac)")
    }

    func test_macForIP_unknownAddress_returnsNil() {
        // 라우팅 테이블에 없을 IP(0.0.0.0)는 매칭되지 않아 nil이어야 한다(트랩 없음).
        XCTAssertNil(RoutingTableParser.macForIP(in_addr_t(0)))
    }
}
