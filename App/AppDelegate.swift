import AppKit
import MaraCore
import Sparkle

/// 조립 전용 진입점: 환경·Sparkle 업데이터·상태바를 만들고 서로 배선한다.
/// 레거시판은 메뉴 전용이라 창(Settings·First Run Guide·Custom SwiftUI)이 없다 — Custom은 NSAlert.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private let env = AppEnvironment()

    /// Sparkle 자동 업데이트. `self`를 delegate로 넘기려면 lazy여야 하고, 옛 `setFeedURL` 흔적을 지운 **뒤에**
    /// 시작해야 하므로 `startingUpdater: false`로 만든 다음 `applicationDidFinishLaunching`에서 시작한다.
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
    )

    private lazy var statusBar = StatusBarController(env: env)
    private let customKeepAwake = CustomKeepAwakeAlert()

    /// 알림 경로(10.15+). 저장 프로퍼티의 타입은 가용성으로 가릴 수 없으므로 `Any?` 하나만 둔다.
    private var notificationBox: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // accessory 앱엔 기본 메인 메뉴가 없어 Cmd+Q 등이 안 걸린다 — 최소 표준 메뉴 설치.
        MainMenu.install(appName: "Mara")

        _ = updaterController.updater.clearFeedURLFromUserDefaults()
        updaterController.startUpdater()

        statusBar.onOpenCustomKeepAwake = { [weak self] in self?.runCustomKeepAwake() }
        statusBar.checkForUpdates = (
            target: updaterController,
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        )
        if #available(macOS 10.15, *) {
            let box = NotificationBox(env: env)
            notificationBox = box
            statusBar.requestNotificationAuth = { [weak box] completion in box?.requestAuthorization(completion) }
        }
        statusBar.install()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 순서 고정: 알림 구독을 먼저 끊고(트리거 세션 종료 알림이 앱 종료 직후 뜨지 않게) 그다음 정리.
        statusBar.requestNotificationAuth = nil   // box를 붙잡는 다른 참조가 없게
        notificationBox = nil
        env.shutdown()
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        LegacySupport.feedURL   // 본판 최소 OS 이상 → 본판 피드(이주), 미만 → 레거시 피드
    }

    // MARK: - Custom

    private func runCustomKeepAwake() {
        customKeepAwake.run { [env] duration in
            let result = env.session.start(
                SessionConfig(scope: env.prefs.defaultScope, duration: duration, origin: .manual)
            )
            // 성공한 duration만 MRU에 기록 — 실패한 입력과 절대시각(until)은 기록하지 않는다.
            if case .success = result, case let .duration(seconds) = duration {
                env.prefs.rememberCustomDuration(seconds)
            }
            return result
        }
    }
}

/// 알림 서비스 + 세션 알림 구독을 함께 강하게 보유하는 10.15+ 상자.
@available(macOS 10.15, *)
@MainActor
private final class NotificationBox {
    private let service = NotificationService()
    private let notifier: SessionNotifier

    init(env: AppEnvironment) {
        notifier = SessionNotifier(
            session: env.session,
            isEnabled: { [env] in env.prefs.notifyAutoSessionChanges },
            service: service
        )
    }

    /// 메뉴 토글이 켜질 때만 부른다(권한은 선요청하지 않는다). 결과는 main에서 전달한다.
    func requestAuthorization(_ completion: @escaping @MainActor (Bool) -> Void) {
        let service = self.service
        Task { @MainActor in completion(await service.requestAuthorization()) }
    }
}
