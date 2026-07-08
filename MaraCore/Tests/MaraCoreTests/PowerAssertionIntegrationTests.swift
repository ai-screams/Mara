import XCTest
import IOKit.pwr_mgt
@testable import MaraCore

/// 통합 테스트: Mock이 아니라 실제 `IOKitPowerAssertionProvider`/`SleepEngine`이
/// OS 전원 관리에 어서션을 실제로 등록/해제하는지 `IOPMCopyAssertionsByProcess`로 교차검증한다.
/// 비권한 API. 고유 이름으로 필터해 이 프로세스의 무관한 어서션과 격리하고, defer로 항상 정리한다.
final class PowerAssertionIntegrationTests: XCTestCase {

    private let systemType = kIOPMAssertionTypePreventUserIdleSystemSleep as String
    private let displayType = kIOPMAssertionTypePreventUserIdleDisplaySleep as String

    /// 이 프로세스가 보유한, 주어진 이름의 어서션들의 타입 목록(실제 OS 상태).
    private func assertionTypes(named name: String) -> [String] {
        var dict: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&dict) == kIOReturnSuccess,
              let byPid = dict?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }
        let pid = NSNumber(value: ProcessInfo.processInfo.processIdentifier)
        return (byPid[pid] ?? [])
            .filter { ($0[kIOPMAssertionNameKey] as? String) == name }
            .compactMap { $0[kIOPMAssertionTypeKey] as? String }
    }

    func test_provider_createRegistersRealAssertion_releaseRemovesIt() {
        let name = "MaraIT.provider.\(UUID().uuidString)"
        let provider = IOKitPowerAssertionProvider()

        let token = provider.create(type: .preventSystemSleep, name: name)
        defer { if let token { provider.release(token) } }
        XCTAssertNotNil(token, "IOKit create should succeed (unprivileged)")

        let held = assertionTypes(named: name)
        XCTAssertEqual(held, [systemType], "one real system-sleep assertion should be registered with the OS")

        if let token { provider.release(token) }
        XCTAssertEqual(assertionTypes(named: name), [], "assertion should be gone after release")
    }

    func test_sleepEngine_applyHoldsBothTypes_releaseAllClears() {
        let name = "MaraIT.engine.\(UUID().uuidString)"
        let engine = SleepEngine(provider: IOKitPowerAssertionProvider(), name: name)
        defer { engine.releaseAll() }

        engine.apply(display: true, system: true)
        let held = Set(assertionTypes(named: name))
        XCTAssertEqual(held, [systemType, displayType], "both real assertions should be registered with the OS")

        engine.releaseAll()
        XCTAssertEqual(assertionTypes(named: name), [], "all assertions should be gone after releaseAll")
    }

    func test_sleepEngine_reapplyIsIdempotent_noDuplicateAssertions() {
        let name = "MaraIT.idem.\(UUID().uuidString)"
        let engine = SleepEngine(provider: IOKitPowerAssertionProvider(), name: name)
        defer { engine.releaseAll() }

        engine.apply(display: true, system: true)
        engine.apply(display: true, system: true)   // 재적용: 이미 보유 → 재생성 금지
        XCTAssertEqual(assertionTypes(named: name).count, 2, "reapply must not create duplicate OS assertions")
    }

    func test_sleepEngine_systemOnly_holdsOnlySystemAssertion() {
        let name = "MaraIT.sysonly.\(UUID().uuidString)"
        let engine = SleepEngine(provider: IOKitPowerAssertionProvider(), name: name)
        defer { engine.releaseAll() }

        engine.apply(display: false, system: true)
        XCTAssertEqual(assertionTypes(named: name), [systemType],
                       "systemOnly scope must not hold a display-sleep assertion")
    }
}
