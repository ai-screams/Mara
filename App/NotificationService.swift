import Foundation
import MaraCore
import UserNotifications

/// UNUserNotificationCenter 어댑터. 권한은 여기서 절대 선요청하지 않는다 —
/// Settings 토글을 켜는 순간에만 requestAuthorization이 불린다(권한 0 원칙의 opt-in 예외).
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self   // 앱이 포그라운드여도 배너를 표시(아래 willPresent)
    }

    /// true = 허용. 최초 1회만 시스템 프롬프트가 뜨고 이후엔 저장된 상태를 돌려준다.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert])) ?? false
    }

    /// 현재 권한. 프롬프트를 띄우지 않는다(조회만). 인스턴스 상태가 필요 없어 static으로 둔다 —
    /// MainActor에서 non-Sendable 인스턴스를 async 경계 너머로 보내지 않게 한다.
    static func permission() async -> SystemSettingSync.NotificationPermission {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // trigger: nil → 즉시 전달. 권한이 없으면 여기서 조용히 실패하므로 로그로만 남긴다.
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
            if let error { NSLog("Notification delivery failed: \(error)") }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
