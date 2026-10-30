import Foundation
import XCTest
@testable import MaraCore

@MainActor
final class RoutingTableNetworkProviderTests: XCTestCase {
    func test_refresh_retriesUntilGatewayMACBecomesAvailable() async {
        let expected = NetworkIdentity(gatewayMAC: "00:10:db:ff:10:02")
        let reader = SequenceIdentityReader([nil, nil, expected])
        let provider = RoutingTableNetworkProvider(
            readIdentity: { reader.read() },
            retryDelays: [.zero, .zero]
        )

        await provider.refreshForTesting()

        XCTAssertEqual(provider.current, expected)
        XCTAssertEqual(reader.currentReadCount, 3)
    }

    func test_refresh_succeedsOnFirstAttempt_withoutRetry() async {
        let expected = NetworkIdentity(gatewayMAC: "aa:bb:cc:dd:ee:ff")
        let reader = SequenceIdentityReader([expected])
        let provider = RoutingTableNetworkProvider(
            readIdentity: { reader.read() },
            retryDelays: [.zero, .zero]
        )

        await provider.refreshForTesting()

        XCTAssertEqual(provider.current, expected)
        XCTAssertEqual(reader.currentReadCount, 1)   // 첫 read 성공 → sleep/재시도 경로 안 탐
    }

    func test_refresh_stopsAfterBoundedAttempts() async {
        let reader = SequenceIdentityReader([nil, nil, nil, nil])
        let provider = RoutingTableNetworkProvider(
            readIdentity: { reader.read() },
            retryDelays: [.zero, .zero]
        )

        await provider.refreshForTesting()

        XCTAssertNil(provider.current)
        XCTAssertEqual(reader.currentReadCount, 3)
    }

    // 경로가 다시 바뀌면 재시도 대기 중이던 이전 refresh는 nil을 내보내지 않고 끝나야 한다.
    // 이것을 실패시키는 것: 재시도 sleep의 `catch { return }`을 `break`로 바꾸면 취소된 refresh가
    // 루프 끝의 send(nil)에 닿아 published 값에 nil이 하나 더 붙는다.
    func test_pathChange_supersedesPendingRetry_withoutPublishingNil() async {
        let expected = NetworkIdentity(gatewayMAC: "00:10:db:ff:10:02")
        let reader = SequenceIdentityReader([nil, expected])
        let sleeper = SleepProbe()
        let provider = RoutingTableNetworkProvider(
            readIdentity: { reader.read() },
            retryDelays: [.seconds(60)],
            sleep: { try await sleeper.sleep($0) }
        )
        var published: [NetworkIdentity?] = []
        let subscription = provider.changes.sink { published.append($0) }
        defer { subscription.cancel() }

        let first = provider.pathDidChangeForTesting()
        while sleeper.currentEntered < 1 { await Task.yield() }   // 첫 refresh가 재시도 대기에 들어간 뒤 취소한다
        let second = provider.pathDidChangeForTesting()
        await first?.value
        await second?.value

        XCTAssertEqual(provider.current, expected)
        XCTAssertEqual(published, [nil, expected])
    }

    // 이것을 실패시키는 것: guard에서 MAC 조건을 빼거나 경로 없이도 MAC을 묻게 바꾸는 것.
    func test_gatewayIdentity_needsBothRouteAndMAC() {
        let route = RoutingTableParser.GatewayRoute(address: 0x0101_A8C0, interfaceIndex: 4)
        var askedFor: [RoutingTableParser.GatewayRoute] = []

        XCTAssertNil(RoutingTableNetworkProvider.gatewayIdentity(gateway: nil) { askedFor.append($0); return "aa:bb:cc:dd:ee:ff" })
        XCTAssertTrue(askedFor.isEmpty)   // 경로가 없으면 ARP를 묻지도 않는다
        XCTAssertNil(RoutingTableNetworkProvider.gatewayIdentity(gateway: route) { _ in nil })
        XCTAssertEqual(
            RoutingTableNetworkProvider.gatewayIdentity(gateway: route) { askedFor.append($0); return "AA:BB:CC:DD:EE:FF" },
            NetworkIdentity(gatewayMAC: "aa:bb:cc:dd:ee:ff")
        )
        XCTAssertEqual(askedFor, [route])
    }
}

private final class SleepProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var entered = 0

    var currentEntered: Int {
        lock.withLock { entered }
    }

    func sleep(_ duration: Duration) async throws {
        lock.withLock { entered += 1 }
        try await Task.sleep(for: duration)
    }
}

private final class SequenceIdentityReader: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [NetworkIdentity?]
    private var readCount = 0

    var currentReadCount: Int {
        lock.withLock { readCount }
    }

    init(_ values: [NetworkIdentity?]) {
        self.values = values
    }

    func read() -> NetworkIdentity? {
        lock.withLock {
            readCount += 1
            return values.isEmpty ? nil : values.removeFirst()
        }
    }
}
