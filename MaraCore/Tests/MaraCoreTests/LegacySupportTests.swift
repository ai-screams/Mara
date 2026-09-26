import XCTest
@testable import MaraCore

@MainActor
final class LegacySupportTests: XCTestCase {
    private struct Boom: Error {}

    func test_unsafeAssumeMainActor_returnsBodyValue_onMain() {
        XCTAssertEqual(unsafeAssumeMainActor { 42 }, 42)
    }

    func test_unsafeAssumeMainActor_rethrows() {
        XCTAssertThrowsError(try unsafeAssumeMainActor { () throws -> Int in throw Boom() })
    }
}

/// 두 변화 감지 구현은 OS 어댑터라 콜백을 결정적으로 일으킬 수는 없다(실기에서 확인). 여기서는
/// 시작·중지가 멱등이고 반복해도 자원이 꼬이지 않는다는 계약만 고정한다(헤드리스 CI에서도 돈다).
@MainActor
final class NetworkChangeMonitoringTests: XCTestCase {
    private func exercise(_ monitor: NetworkChangeMonitoring) {
        monitor.start { }
        monitor.start { }      // 두 번째 start는 무시
        monitor.stop()
        monitor.stop()         // 두 번째 stop도 안전
        monitor.start { }      // 멈춘 뒤 다시 시작 가능
        monitor.stop()
    }

    func test_scDynamicStoreMonitor_startStop_isIdempotent() {
        exercise(SCDynamicStoreChangeMonitor())
    }

    func test_nwPathMonitor_startStop_isIdempotent() {
        exercise(NWPathChangeMonitor())
    }
}

@MainActor
final class RoutingTableNetworkProviderStopTests: XCTestCase {
    /// stop()은 세대를 올려 진행 중인 새로고침 결과를 버린다(종료 중 늦게 도착한 값이 방출되지 않는다).
    func test_stop_discardsInFlightRefresh() {
        let id = NetworkIdentity(gatewayMAC: "cc:cc:cc:cc:cc:cc")
        let provider = RoutingTableNetworkProvider(readIdentity: { id }, retryDelays: [])
        var finished = false
        provider.onRefreshFinishedForTesting = { finished = true }
        provider.startRefresh()
        provider.stop()
        provider.stop()        // 멱등
        let drained = expectation(description: "read and main hop drained")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { DispatchQueue.main.async { drained.fulfill() } }
        wait(for: [drained], timeout: 5)
        XCTAssertFalse(finished)
        XCTAssertNil(provider.current)
    }
}
