import Foundation
import MaraCore
import ServiceManagement

enum LaunchAtLogin {
    private struct MainApp: LoginItemRegistering {
        var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
        func register() throws { try SMAppService.mainApp.register() }
        func unregister() throws { try SMAppService.mainApp.unregister() }
    }

    static var isEnabled: Bool { MainApp().isEnabled }

    /// 시도 뒤의 실제 상태를 돌려준다. 호출부는 이 값으로 토글을 다시 맞춘다(실패 시 원래대로).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let result = SystemSettingSync.setLoginItem(enabled, on: MainApp())
        if let error = result.error {
            NSLog("LaunchAtLogin toggle failed: \(error)")
        }
        return result.isEnabled
    }
}
