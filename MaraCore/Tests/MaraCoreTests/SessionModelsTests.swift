import XCTest
@testable import MaraCore

final class SessionModelsTests: XCTestCase {
    func test_scope_displayAndSystem_keepsDisplayAwake() {
        XCTAssertTrue(KeepAwakeScope.displayAndSystem.keepsDisplayAwake)
        XCTAssertFalse(KeepAwakeScope.systemOnly.keepsDisplayAwake)
    }
    func test_state_isActive() {
        XCTAssertFalse(SessionState.inactive.isActive)
        let cfg = SessionConfig(scope: .systemOnly, duration: .indefinite, origin: .manual)
        XCTAssertTrue(SessionState.active(cfg, expiresAt: nil).isActive)
    }
}
