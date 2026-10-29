import XCTest
@testable import MaraCore

/// 손으로 만든 PF_ROUTE 바이트 배열로 파서의 오프셋 워크를 검증한다. 실기 테이블 테스트(`RoutingTableParserTests`)는
/// 게이트웨이가 없거나 macOS 27처럼 ARP 표가 가려지면 아무것도 확인하지 않으므로, 형식이 틀린 입력은 여기서만 다룬다.
final class RoutingTableBufferTests: XCTestCase {

    // MARK: - Fixture builders

    private static let headerSize = MemoryLayout<rt_msghdr>.size
    private static let rtaDst: Int32 = 1 << 0
    private static let rtaGateway: Int32 = 1 << 1

    private func ip(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> in_addr_t {
        in_addr_t(bigEndian: UInt32(a) << 24 | UInt32(b) << 16 | UInt32(c) << 8 | UInt32(d))
    }

    /// sockaddr_in 16바이트. `declaredLength`로 sa_len만 속일 수 있다(실제 바이트 수는 그대로).
    private func sockaddrIn(_ addr: in_addr_t, declaredLength: UInt8 = 16) -> [UInt8] {
        var sin = sockaddr_in()
        sin.sin_len = declaredLength
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_addr.s_addr = addr
        return withUnsafeBytes(of: &sin) { Array($0) }
    }

    /// sockaddr_dl: 8바이트 고정 머리 + 인터페이스 이름 + 링크 주소, 최소 20바이트(구조체 크기)로 채운다.
    /// `index`는 sdl_index(호스트 바이트 순서 u_short)다.
    private func sockaddrDL(mac: [UInt8], name: String = "", index: UInt16 = 1) -> [UInt8] {
        let nameBytes = Array(name.utf8)
        var bytes: [UInt8] = [0, UInt8(AF_LINK)] + withUnsafeBytes(of: index) { Array($0) }
            + [6, UInt8(nameBytes.count), UInt8(mac.count), 0]
        bytes += nameBytes + mac
        let size = max(bytes.count, MemoryLayout<sockaddr_dl>.size)
        bytes += [UInt8](repeating: 0, count: (size + 3) / 4 * 4 - bytes.count)
        bytes[0] = UInt8(size)
        return bytes
    }

    /// rt_msghdr + sockaddr 목록. `declaredLength`로 rtm_msglen만 속일 수 있다.
    private func message(flags: Int32 = 0, index: UInt16 = 0, addrs: Int32, _ sockaddrs: [[UInt8]],
                         declaredLength: Int? = nil) -> [UInt8] {
        let body = sockaddrs.flatMap { $0 }
        var header = rt_msghdr()
        header.rtm_msglen = UInt16(declaredLength ?? Self.headerSize + body.count)
        header.rtm_flags = flags
        header.rtm_index = index
        header.rtm_addrs = addrs
        return withUnsafeBytes(of: &header) { Array($0) } + body
    }

    private func route(dst: in_addr_t, gateway: in_addr_t, flags: Int32 = RTF_GATEWAY, index: UInt16 = 0) -> [UInt8] {
        message(flags: flags, index: index, addrs: Self.rtaDst | Self.rtaGateway, [sockaddrIn(dst), sockaddrIn(gateway)])
    }

    private func arpEntry(_ addr: in_addr_t, mac: [UInt8], name: String = "", index: UInt16 = 1) -> [UInt8] {
        message(addrs: Self.rtaDst | Self.rtaGateway, [sockaddrIn(addr), sockaddrDL(mac: mac, name: name, index: index)])
    }

    /// 인터페이스 1의 게이트웨이. 기존 MAC 조회 테스트는 ARP 항목도 인터페이스 1이라 주소만으로 정해진다.
    private func gateway(_ address: in_addr_t, interface: UInt16 = 1) -> RoutingTableParser.GatewayRoute {
        .init(address: address, interfaceIndex: interface)
    }

    private let gatewayMAC: [UInt8] = [0x74, 0x29, 0x72, 0xb3, 0xe0, 0x80]

    // MARK: - Default gateway

    func test_gateway_skipsNonDefaultRoutes() {
        // 이것을 실패시키는 것: 목적지 0.0.0.0 검사를 빼면 앞의 10.0.0.0 경로의 게이트웨이가 나온다.
        let buf = route(dst: ip(10, 0, 0, 0), gateway: ip(10, 0, 0, 1))
            + route(dst: 0, gateway: ip(192, 168, 0, 1))
        XCTAssertEqual(RoutingTableParser.defaultGateway(in: buf)?.address, ip(192, 168, 0, 1))
    }

    func test_gateway_ignoresDefaultRouteWithoutGatewayFlag() {
        // 이것을 실패시키는 것: RTF_GATEWAY 검사를 빼면 플래그 없는 경로의 주소가 게이트웨이로 나온다.
        let buf = route(dst: 0, gateway: ip(192, 168, 0, 1), flags: 0)
        XCTAssertNil(RoutingTableParser.defaultGateway(in: buf))
    }

    func test_gateway_ignoresSockaddrWhoseDeclaredLengthIsTooShort() {
        // 목적지 sockaddr가 sa_len 8로 8바이트만 차지하고, 바로 뒤에 게이트웨이가 온다.
        // 이것을 실패시키는 것: sa_len >= sizeof(sockaddr_in) 검사를 빼면 8바이트짜리를 16바이트로 읽어
        // 목적지 0.0.0.0을 받아들이고 경로를 기본 경로로 본다.
        let buf = message(flags: RTF_GATEWAY, addrs: Self.rtaDst | Self.rtaGateway,
                          [Array(sockaddrIn(0, declaredLength: 8).prefix(8)),
                           sockaddrIn(ip(192, 168, 0, 1))])
        XCTAssertNil(RoutingTableParser.defaultGateway(in: buf))
    }

    func test_gateway_stopsAtMessageLongerThanBuffer() {
        // 이것을 실패시키는 것: offset + msgLen <= buf.count 검사를 빼면 잘린 메시지를 읽다 범위를 벗어난다.
        let full = route(dst: 0, gateway: ip(192, 168, 0, 1))
        let truncated = message(flags: RTF_GATEWAY, addrs: Self.rtaDst | Self.rtaGateway,
                                [sockaddrIn(0), sockaddrIn(ip(192, 168, 0, 1))],
                                declaredLength: full.count + 64)
        XCTAssertNil(RoutingTableParser.defaultGateway(in: truncated))
    }

    func test_gateway_stopsAtMessageShorterThanHeader() {
        // 이것을 실패시키는 것: msgLen >= sizeof(rt_msghdr) 검사를 빼면 길이 0 메시지에서 같은 자리를 끝없이 돈다.
        let zeroLength = message(addrs: 0, [], declaredLength: 0)
        let buf = zeroLength + route(dst: 0, gateway: ip(192, 168, 0, 1))
        XCTAssertNil(RoutingTableParser.defaultGateway(in: buf))
    }

    func test_gateway_emptyAndShortBuffers() {
        // 이것을 실패시키는 것: 루프 조건을 offset < buf.count로 넓히면 머리보다 짧은 버퍼에서 범위 밖을 읽는다.
        XCTAssertNil(RoutingTableParser.defaultGateway(in: []))
        XCTAssertNil(RoutingTableParser.defaultGateway(in: [UInt8](repeating: 0, count: Self.headerSize - 1)))
    }

    func test_gateway_keepsTheDefaultRouteInterface() {
        // 이것을 실패시키는 것: rtm_index 대신 0을 넣으면 인터페이스 16이 사라진다.
        let buf = route(dst: 0, gateway: ip(192, 168, 0, 1), index: 16)
        XCTAssertEqual(RoutingTableParser.defaultGateway(in: buf), gateway(ip(192, 168, 0, 1), interface: 16))
    }

    // MARK: - MAC lookup

    func test_mac_returnsLinkAddressOfMatchingEntry() {
        // 이것을 실패시키는 것: RTA_DST 일치 검사를 빼면 첫 항목(192.168.0.7)의 MAC이 나온다.
        let buf = arpEntry(ip(192, 168, 0, 7), mac: [1, 2, 3, 4, 5, 6])
            + arpEntry(ip(192, 168, 0, 1), mac: gatewayMAC)
        XCTAssertEqual(RoutingTableParser.mac(for: gateway(ip(192, 168, 0, 1)), in: buf), "74:29:72:b3:e0:80")
        XCTAssertNil(RoutingTableParser.mac(for: gateway(ip(192, 168, 0, 9)), in: buf))
    }

    func test_mac_skipsInterfaceNameBeforeLinkAddress() {
        // 이것을 실패시키는 것: sdl_nlen을 더하지 않으면 "en0" 바이트부터 읽어 MAC이 어긋난다.
        let buf = arpEntry(ip(192, 168, 0, 1), mac: gatewayMAC, name: "en0")
        XCTAssertEqual(RoutingTableParser.mac(for: gateway(ip(192, 168, 0, 1)), in: buf), "74:29:72:b3:e0:80")
    }

    func test_mac_rejectsLinkAddressThatIsNotSixBytes() {
        // 이것을 실패시키는 것: alen == 6 검사를 빼면 8바이트 주소에서 앞 8옥텟이 MAC으로 나온다.
        let buf = arpEntry(ip(192, 168, 0, 1), mac: gatewayMAC + [0, 0])
        XCTAssertNil(RoutingTableParser.mac(for: gateway(ip(192, 168, 0, 1)), in: buf))
    }

    func test_mac_rejectsLinkAddressRunningPastMessageEnd() {
        // 이름이 길어 링크 주소가 메시지 끝을 넘는다. 뒤 메시지 바이트를 MAC으로 읽으면 안 된다.
        // 이것을 실패시키는 것: macStart + alen <= msgEnd 검사를 빼면 다음 메시지 머리를 MAC으로 읽는다.
        var dl = sockaddrDL(mac: [], name: "abcdefghijkl")    // 8 + 12 = 20바이트, 링크 주소 자리 없음
        dl[6] = 6                                             // alen만 6으로 속인다
        let buf = message(addrs: Self.rtaDst | Self.rtaGateway, [sockaddrIn(ip(192, 168, 0, 1)), dl])
            + arpEntry(ip(10, 0, 0, 1), mac: gatewayMAC)
        XCTAssertNil(RoutingTableParser.mac(for: gateway(ip(192, 168, 0, 1)), in: buf))
    }

    func test_mac_prefersEntryOnTheDefaultRouteInterface() {
        // Wi-Fi(인터페이스 5)와 유선(16)이 서로 다른 공유기에 붙었고 둘 다 게이트웨이가 192.168.0.1이다.
        // 기본 경로가 유선이면 유선 쪽 MAC이어야 한다.
        // 이것을 실패시키는 것: 인터페이스 비교를 빼면 앞에 온 Wi-Fi 항목의 MAC(01:02:…)이 나온다.
        let buf = arpEntry(ip(192, 168, 0, 1), mac: [1, 2, 3, 4, 5, 6], index: 5)
            + arpEntry(ip(192, 168, 0, 1), mac: gatewayMAC, index: 16)
        XCTAssertEqual(RoutingTableParser.mac(for: gateway(ip(192, 168, 0, 1), interface: 16), in: buf),
                       "74:29:72:b3:e0:80")
    }

    func test_mac_fallsBackToAddressMatchWhenNoEntryIsOnTheInterface() {
        // 커널이 인터페이스 번호를 예상과 다르게 채워도 공유기 하나짜리 네트워크는 지금처럼 알아봐야 한다.
        // 이것을 실패시키는 것: 인터페이스가 맞는 항목만 받으면(물러남 제거) nil이 된다.
        let buf = arpEntry(ip(192, 168, 0, 1), mac: gatewayMAC, index: 5)
            + arpEntry(ip(192, 168, 0, 1), mac: [1, 2, 3, 4, 5, 6], index: 7)
        XCTAssertEqual(RoutingTableParser.mac(for: gateway(ip(192, 168, 0, 1), interface: 16), in: buf),
                       "74:29:72:b3:e0:80")
    }
}
