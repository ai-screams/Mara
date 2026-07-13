import XCTest
import IOKit.pwr_mgt
@testable import MaraCore

final class PowerAssertionTypeMappingTests: XCTestCase {
    func test_ioKitName_isNotSwapped() {
        XCTAssertEqual(PowerAssertionType.preventDisplaySleep.ioKitName, kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString)
        XCTAssertEqual(PowerAssertionType.preventSystemSleep.ioKitName, kIOPMAssertionTypePreventUserIdleSystemSleep as CFString)
    }
}

@MainActor
final class PowerAssertionContractTests: XCTestCase {
    func test_create_thenRelease_leavesNoLiveAssertions() {
        let p = MockPowerAssertionProvider()
        let t = try? p.create(type: .preventSystemSleep, name: "x").get()
        XCTAssertNotNil(t)
        XCTAssertEqual(p.live.count, 1)
        _ = p.release(t!)
        XCTAssertEqual(p.live.count, 0)
    }
}

@MainActor
final class SleepEngineTests: XCTestCase {
    func test_apply_system_acquiresOnlySystemAssertion() {
        let p = MockPowerAssertionProvider()
        let engine = SleepEngine(provider: p)
        engine.apply(display: false, system: true)
        XCTAssertTrue(engine.isSystemHeld)
        XCTAssertFalse(engine.isDisplayHeld)
        XCTAssertEqual(p.live.values.filter { $0 == .preventSystemSleep }.count, 1)
        XCTAssertEqual(p.live.values.filter { $0 == .preventDisplaySleep }.count, 0)
    }

    func test_apply_isIdempotent_noDuplicateAssertions() {
        let p = MockPowerAssertionProvider()
        let engine = SleepEngine(provider: p)
        engine.apply(display: true, system: true)
        engine.apply(display: true, system: true)
        XCTAssertEqual(p.live.count, 2)
    }

    func test_apply_reconcilesDown_releasesDisplayWhenNoLongerWanted() {
        let p = MockPowerAssertionProvider()
        let engine = SleepEngine(provider: p)
        engine.apply(display: true, system: true)
        engine.apply(display: false, system: true)
        XCTAssertFalse(engine.isDisplayHeld)
        XCTAssertTrue(engine.isSystemHeld)
        XCTAssertEqual(p.live.count, 1)
    }

    func test_releaseAll_clearsEverything() {
        let p = MockPowerAssertionProvider()
        let engine = SleepEngine(provider: p)
        engine.apply(display: true, system: true)
        engine.releaseAll()
        XCTAssertFalse(engine.isDisplayHeld)
        XCTAssertFalse(engine.isSystemHeld)
        XCTAssertEqual(p.live.count, 0)
    }

    func test_apply_displayFailure_rollsBackNewSystemAssertion() {
        let p = MockPowerAssertionProvider()
        p.failingCreateTypes = [.preventDisplaySleep]
        let engine = SleepEngine(provider: p)

        let result = engine.apply(display: true, system: true)

        guard case .failure(let failure) = result else {
            return XCTFail("expected display assertion failure")
        }
        XCTAssertEqual(failure.failures, [
            .creationFailed(type: .preventDisplaySleep, code: -1),
        ])
        XCTAssertFalse(engine.isDisplayHeld)
        XCTAssertFalse(engine.isSystemHeld)
        XCTAssertTrue(p.live.isEmpty, "new system token must be rolled back")
    }

    func test_releaseFailure_keepsTokenForRetry() {
        let p = MockPowerAssertionProvider()
        let engine = SleepEngine(provider: p)
        engine.apply(display: false, system: true)
        p.failNextRelease = true

        guard case .failure = engine.releaseAll() else {
            return XCTFail("expected release failure")
        }
        XCTAssertTrue(engine.isSystemHeld)
        XCTAssertEqual(p.live.count, 1)

        XCTAssertNoThrow(try engine.releaseAll().get())
        XCTAssertFalse(engine.isSystemHeld)
        XCTAssertTrue(p.live.isEmpty)
    }

    func test_rollbackReleaseFailure_keepsCreatedTokenForRetry() {
        let p = MockPowerAssertionProvider()
        p.failingCreateTypes = [.preventDisplaySleep]
        p.failNextRelease = true
        let engine = SleepEngine(provider: p)

        guard case .failure(let failure) = engine.apply(display: true, system: true) else {
            return XCTFail("expected create and rollback failure")
        }
        XCTAssertEqual(failure.failures.count, 2)
        XCTAssertTrue(engine.isSystemHeld)
        XCTAssertEqual(p.live.count, 1)

        XCTAssertNoThrow(try engine.releaseAll().get())
        XCTAssertFalse(engine.isSystemHeld)
        XCTAssertTrue(p.live.isEmpty)
    }
}
