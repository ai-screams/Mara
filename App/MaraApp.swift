import SwiftUI
import AppKit
import MaraCore

@main
struct MaraApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(session: env.session, prefs: env.prefs)
        } label: {
            // SessionManager를 직접 관찰하는 뷰로 분리해야 상태 변경 시 아이콘이 다시 그려진다.
            // (Scene body는 env만 관찰하므로 중첩된 session.state 변경은 자동 감지되지 않는다.)
            MenuBarLabel(session: env.session)
        }
        .menuBarExtraStyle(.menu)
        Settings {
            SettingsView(prefs: env.prefs, currentNetwork: { env.currentNetwork })
        }
    }
}

/// 메뉴바 아이콘: keep-awake 상태를 직접 관찰해 토글 시 즉시 갱신된다.
private struct MenuBarLabel: View {
    @ObservedObject var session: SessionManager

    var body: some View {
        HStack(spacing: 2) {
            Image(nsImage: MenuBarLabel.statusIcon(active: session.state.isActive))
            // 활성 시 아이콘 오른쪽에 지속시간 표기 (15m / 1h / ∞).
            if let label = durationLabel {
                Text(label).font(.system(size: 12, weight: .medium))
            }
        }
    }

    /// 활성 세션의 지속시간 라벨. 비활성이면 nil(표기 없음).
    private var durationLabel: String? {
        guard case let .active(config, _) = session.state else { return nil }
        switch config.duration {
        case .indefinite:        return "∞"
        case .duration(let t):   return MenuBarLabel.durationText(t)
        case .until(let date):   return MenuBarLabel.durationText(max(0, date.timeIntervalSinceNow))
        }
    }

    /// 초 → "15m" / "1h" / "1h30m" 형태의 짧은 라벨.
    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }

    /// - active: 채워진 컵 + 주황(non-template, 색상 유지)
    /// - inactive: 빈 컵 + template(라이트/다크 자동 적응)
    static func statusIcon(active: Bool) -> NSImage {
        let symbol = active ? "cup.and.saucer.fill" : "cup.and.saucer"
        let description = active ? "Mara — keep-awake 활성" : "Mara — 비활성"
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
            ?? NSImage()
        guard active else {
            base.isTemplate = true
            return base
        }
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
        let colored = base.withSymbolConfiguration(config) ?? base
        colored.isTemplate = false   // 색상 유지(메뉴바 template 렌더 회피)
        return colored
    }
}
