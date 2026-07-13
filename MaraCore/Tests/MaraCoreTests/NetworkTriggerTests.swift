import XCTest
import Combine
@testable import MaraCore

@MainActor
final class NetworkTriggerTests: XCTestCase {
    func test_identity_normalizesMAC() {
        // 대문자/축약 옥텟이 소문자 2자리로 정규화되어 동등 비교된다.
        XCTAssertEqual(NetworkIdentity(gatewayMAC: "0:10:DB:ff:10:2"),
                       NetworkIdentity(gatewayMAC: "00:10:db:ff:10:02"))
    }

    func test_trigger_satisfiedWhenCurrentInWatched() {
        let home = NetworkIdentity(gatewayMAC: "00:10:db:ff:10:02")
        let net = MockNetwork(nil)
        let t = NetworkTrigger(network: net, watched: [home])
        XCTAssertFalse(t.isSatisfied)               // 오프라인
        var received: [Bool] = []
        let c = t.satisfied.sink { received.append($0) }
        net.set(home)                               // 집 네트워크 접속
        net.set(NetworkIdentity(gatewayMAC: "aa:bb:cc:dd:ee:ff"))  // 다른 네트워크
        net.set(nil)                                // 오프라인
        c.cancel()
        XCTAssertEqual(received, [false, true, false])
        XCTAssertFalse(t.isSatisfied)
    }
}
