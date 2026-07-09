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
    private lazy var settingsPresenter = SettingsWindowPresenter { [env, updaterController] in
        SettingsView(
            prefs: env.prefs,
            session: env.session,
            currentNetwork: { env.currentNetwork },
            checkForUpdates: { updaterController.checkForUpdates(nil) }
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBar.onOpenSettings = { [weak self] in self?.settingsPresenter.show() }
        statusBar.checkForUpdates = (
            target: updaterController,
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        )
        statusBar.install()
    }
}
