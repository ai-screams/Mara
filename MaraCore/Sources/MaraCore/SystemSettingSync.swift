import Foundation

/// 로그인 항목 등록 경계. App의 `SMAppService.mainApp` 래퍼가 채택한다.
public protocol LoginItemRegistering {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

/// 시스템 설정이 진실의 출처인 두 토글(로그인 시 실행, 알림)을 실제 상태에 맞추는 규칙.
/// 저장·OS 호출은 App이 맡고, "무엇을 보여 줄 것인가"라는 결정만 여기(Core, 테스트 가능)에 둔다.
public enum SystemSettingSync {
    /// 로그인 항목을 원하는 상태로 바꾸고, 시도 뒤의 실제 상태를 돌려준다.
    /// 실패해도 토글은 실제 상태로 돌아가야 하므로 오류는 함께 돌려주기만 하고 상태는 다시 읽는다.
    /// 이미 원하는 상태면 OS를 부르지 않는다 — 되돌린 토글의 onChange가 다시 들어와도 no-op이 된다.
    public static func setLoginItem(_ enabled: Bool,
                                    on item: LoginItemRegistering) -> (isEnabled: Bool, error: Error?) {
        guard item.isEnabled != enabled else { return (enabled, nil) }
        do {
            if enabled { try item.register() } else { try item.unregister() }
            return (item.isEnabled, nil)
        } catch {
            return (item.isEnabled, error)
        }
    }

    /// 알림 권한을 앱이 이해하는 세 갈래로 줄인 값.
    public enum NotificationPermission: Sendable, Equatable {
        case notDetermined, denied, allowed
    }

    /// 알림 토글을 유지할지. System Settings에서 거부(`denied`)됐으면 켜져 있어도 `center.add`가
    /// 조용히 실패하므로 끈다. 다시 켜면 권한 요청부터 다시 한다.
    /// `notDetermined`는 끄지 않는다 — 토글을 처음 켤 때 권한 프롬프트가 떠 있는 동안 앱이 다시
    /// 활성화되면 아직 이 상태라서, 끄면 사용자가 허용하는 흐름 한가운데서 토글이 꺼진다.
    /// (`tccutil reset` 뒤처럼 켜진 채 `notDetermined`인 경우는 남지만, 드물고 배달 실패가 로그에 남는다.)
    public static func keepsNotifications(_ enabled: Bool, permission: NotificationPermission) -> Bool {
        enabled && permission != .denied
    }
}
