import AppKit
import MaraCore
import Sparkle

/// 조립 전용 진입점: 환경·Sparkle 업데이터·상태바·설정 창을 만들고 서로 배선한다.
/// 상태바/메뉴는 StatusBarController, 설정 창 크롬은 SettingsWindowPresenter가 담당한다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let env = AppEnvironment()

    /// Sparkle 자동 업데이트. startingUpdater: true → 피드(appcast) 주기 확인을 즉시 시작하고,
    /// 자동 확인 동의는 Sparkle 표준(둘째 실행 시 프롬프트)에 맡긴다. "Check for Updates…"
    /// 메뉴 항목의 타깃이 되며 canCheckForUpdates에 따라 자동 활성/비활성된다.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    private lazy var statusBar = StatusBarController(env: env)
    // init은 UNUserNotificationCenter.current() 획득/delegate 설정만 — 권한 프롬프트는 Settings 토글에서만 발생.
    private let notificationService = NotificationService()
    private lazy var customKeepAwakePresenter = CustomKeepAwakePresenter { [env] duration in
        // duration 모드만 MRU에 기록 — 절대시각(until)은 재사용 의미가 없다.
        if case let .duration(seconds) = duration { env.prefs.rememberCustomDuration(seconds) }
        env.session.start(SessionConfig(scope: env.prefs.defaultScope, duration: duration, origin: .manual))
    }
    private lazy var settingsPresenter = SettingsWindowPresenter { [env, updaterController, notificationService] in
        SettingsView(
            prefs: env.prefs,
            session: env.session,
            triggers: env.triggerEngine,
            currentNetwork: { env.currentNetwork },
            checkForUpdates: { updaterController.checkForUpdates(nil) },
            requestNotificationAuth: { await notificationService.requestAuthorization() }
        )
    }
    private var sessionNotifier: SessionNotifier?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBar.onOpenSettings = { [weak self] in self?.settingsPresenter.show() }
        statusBar.onOpenCustomKeepAwake = { [weak self] in self?.customKeepAwakePresenter.show() }
        statusBar.checkForUpdates = (
            target: updaterController,
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        )
        statusBar.install()
        sessionNotifier = SessionNotifier(
            session: env.session,
            isEnabled: { [env] in env.prefs.notifyAutoSessionChanges },
            service: notificationService
        )
    }
}
