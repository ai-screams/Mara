import XCTest
@testable import SleeplessCore

final class PowerAssertionContractTests: XCTestCase {
    func test_create_thenRelease_leavesNoLiveAssertions() {
        let p = MockPowerAssertionProvider()
        let t = p.create(type: .preventSystemSleep, name: "x")
        XCTAssertNotNil(t)
        XCTAssertEqual(p.live.count, 1)
        p.release(t!)
        XCTAssertEqual(p.live.count, 0)
    }
}

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
}
