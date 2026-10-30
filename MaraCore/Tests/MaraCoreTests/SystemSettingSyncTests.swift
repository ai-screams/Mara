import XCTest
@testable import MaraCore

final class SystemSettingSyncTests: XCTestCase {
    private struct Failure: Error {}

    private final class FakeLoginItem: LoginItemRegistering {
        var isEnabled: Bool
        var failNext = false
        private(set) var calls: [String] = []

        init(enabled: Bool) { isEnabled = enabled }

        func register() throws {
            calls.append("register")
            if failNext { throw Failure() }
            isEnabled = true
        }

        func unregister() throws {
            calls.append("unregister")
            if failNext { throw Failure() }
            isEnabled = false
        }
    }

    func test_setLoginItem_appliesTheRequestedState() {
        let item = FakeLoginItem(enabled: false)

        let on = SystemSettingSync.setLoginItem(true, on: item)
        XCTAssertTrue(on.isEnabled)
        XCTAssertNil(on.error)

        let off = SystemSettingSync.setLoginItem(false, on: item)
        XCTAssertFalse(off.isEnabled)
        XCTAssertEqual(item.calls, ["register", "unregister"])
    }

    // 실패하면 요청값이 아니라 실제 상태를 돌려줘야 토글이 되돌아간다.
    // 이것을 실패시키는 것: catch에서 `item.isEnabled` 대신 요청값 `enabled`를 돌려주는 것.
    func test_setLoginItem_failure_reportsTheActualState() {
        let item = FakeLoginItem(enabled: false)
        item.failNext = true

        let result = SystemSettingSync.setLoginItem(true, on: item)

        XCTAssertFalse(result.isEnabled)
        XCTAssertNotNil(result.error)
    }

    // 되돌린 토글의 onChange가 다시 불러도 OS를 다시 부르지 않는다.
    // 이것을 실패시키는 것: 첫 줄의 guard를 지우는 것(unregister가 한 번 더 불린다).
    func test_setLoginItem_alreadyInState_doesNotCallTheOS() {
        let item = FakeLoginItem(enabled: false)

        let result = SystemSettingSync.setLoginItem(false, on: item)

        XCTAssertFalse(result.isEnabled)
        XCTAssertNil(result.error)
        XCTAssertTrue(item.calls.isEmpty)
    }

    // 이것을 실패시키는 것: `!= .denied`를 `== .allowed`로 좁히는 것(프롬프트가 떠 있는 동안 토글이 꺼진다),
    // 또는 `enabled &&`를 빼는 것(꺼 둔 토글이 켜진다).
    func test_keepsNotifications_turnsOffOnlyWhenDenied() {
        XCTAssertTrue(SystemSettingSync.keepsNotifications(true, permission: .allowed))
        XCTAssertTrue(SystemSettingSync.keepsNotifications(true, permission: .notDetermined))
        XCTAssertFalse(SystemSettingSync.keepsNotifications(true, permission: .denied))
        XCTAssertFalse(SystemSettingSync.keepsNotifications(false, permission: .allowed))
    }
}
