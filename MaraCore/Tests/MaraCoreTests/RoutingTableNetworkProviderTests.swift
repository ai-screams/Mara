import Foundation
import XCTest
@testable import MaraCore

@MainActor
final class RoutingTableNetworkProviderTests: XCTestCase {
    /// 한 번의 새로고침(재시도 포함)이 값을 방출할 때까지 기다린다.
    private func refresh(_ provider: RoutingTableNetworkProvider) {
        let done = expectation(description: "refresh finished")
        provider.onRefreshFinishedForTesting = { done.fulfill() }
        provider.startRefresh()
        wait(for: [done], timeout: 5)
    }

    func test_refresh_retriesUntilGatewayMACBecomesAvailable() {
        let expected = NetworkIdentity(gatewayMAC: "00:10:db:ff:10:02")
        let reader = SequenceIdentityReader([nil, nil, expected])
        let provider = RoutingTableNetworkProvider(readIdentity: { reader.read() }, retryDelays: [0, 0])

        refresh(provider)

        XCTAssertEqual(provider.current, expected)
        XCTAssertEqual(reader.currentReadCount, 3)
    }

    func test_refresh_succeedsOnFirstAttempt_withoutRetry() {
        let expected = NetworkIdentity(gatewayMAC: "aa:bb:cc:dd:ee:ff")
        let reader = SequenceIdentityReader([expected])
        let provider = RoutingTableNetworkProvider(readIdentity: { reader.read() }, retryDelays: [0, 0])

        refresh(provider)

        XCTAssertEqual(provider.current, expected)
        XCTAssertEqual(reader.currentReadCount, 1)   // 첫 read 성공 → 재시도 경로 안 탐
    }

    func test_refresh_stopsAfterBoundedAttempts() {
        let reader = SequenceIdentityReader([nil, nil, nil, nil])
        let provider = RoutingTableNetworkProvider(readIdentity: { reader.read() }, retryDelays: [0, 0])

        refresh(provider)

        XCTAssertNil(provider.current)
        XCTAssertEqual(reader.currentReadCount, 3)
    }

    /// 빠른 A→B 전환: 먼저 시작한 새로고침이 늦게 끝나도 더 새로운 세대의 값을 덮지 못한다.
    func test_newerRefresh_winsOverSlowerOlderRead() {
        let a = NetworkIdentity(gatewayMAC: "aa:aa:aa:aa:aa:aa")
        let b = NetworkIdentity(gatewayMAC: "bb:bb:bb:bb:bb:bb")
        let reader = GatedIdentityReader(first: a, then: b)
        let provider = RoutingTableNetworkProvider(readIdentity: { reader.read() }, retryDelays: [])
        var emitted: [NetworkIdentity?] = []
        let cancellable = provider.changes.dropFirst().sink { emitted.append($0) }

        provider.startRefresh()          // 세대 1: 느린 읽기(A)가 게이트에서 대기
        reader.waitUntilFirstReadStarted()
        refresh(provider)                // 세대 2: 빠른 읽기(B)가 먼저 끝나 방출
        reader.releaseFirstRead()        // 세대 1의 A가 뒤늦게 돌아옴 → 버려져야 한다
        let drained = expectation(description: "main queue drained")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            DispatchQueue.main.async { drained.fulfill() }
        }
        wait(for: [drained], timeout: 5)

        XCTAssertEqual(provider.current, b)
        XCTAssertEqual(emitted, [b])
        cancellable.cancel()
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

/// 첫 읽기는 게이트가 열릴 때까지 막고, 이후 읽기는 즉시 돌려준다.
private final class GatedIdentityReader: @unchecked Sendable {
    private let lock = NSLock()
    private let first: NetworkIdentity
    private let then: NetworkIdentity
    private var reads = 0
    private let started = DispatchSemaphore(value: 0)
    private let gate = DispatchSemaphore(value: 0)

    init(first: NetworkIdentity, then: NetworkIdentity) {
        self.first = first
        self.then = then
    }

    func read() -> NetworkIdentity? {
        let isFirst = lock.withLock { () -> Bool in reads += 1; return reads == 1 }
        guard isFirst else { return then }
        started.signal()
        gate.wait()
        return first
    }

    func waitUntilFirstReadStarted() { started.wait() }
    func releaseFirstRead() { gate.signal() }
}
