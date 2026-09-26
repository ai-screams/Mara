import ServiceManagement

/// 레거시: `SMAppService`(13+) — 13 미만은 메뉴 항목 자체가 없다(`LegacySupport.launchAtLogin`).
@available(macOS 13.0, *)
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("LaunchAtLogin toggle failed: \(error)")
        }
    }
}
