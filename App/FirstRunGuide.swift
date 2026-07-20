import SwiftUI
import AppKit
import MaraCore

/// 첫 실행 안내 팝오버 콘텐츠 — Night Watch 톤. 권한 프롬프트처럼 보이지 않게
/// 시스템 다이얼로그 관용(앱 아이콘+허용/거부 배치)을 피하고 브랜드 헤더+행 안내로 구성한다.
struct FirstRunGuideView: View {
    let onDone: () -> Void
    @Environment(\.accentTint) private var accent   // presenter가 현재 tint를 주입
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 헤더 — Settings 헤더의 축소판(같은 시각 언어)
            VStack(spacing: 4) {
                Image(systemName: MaraSymbol.awake)
                    .font(.system(size: 26))
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.55), radius: 12)
                    .accessibilityHidden(true)
                Text("Mara lives in your menu bar")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 9) {
                guideRow(symbol: MaraSymbol.resting, tint: MaraTheme.muted,
                         text: "Closed eye — resting, your Mac may sleep")
                guideRow(symbol: MaraSymbol.awake, tint: accent,
                         text: "Open orange eye — keeping your Mac awake")
                guideRow(symbol: "gearshape", tint: MaraTheme.muted,
                         text: "Automation & trigger status live in Settings")
            }

            // Launch at Login — 원클릭. SMAppService 등록은 권한 프롬프트가 아니다.
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.callout)
                .foregroundStyle(.white)
                .tint(accent)
                .onChange(of: launchAtLogin) { _, enabled in
                    LaunchAtLogin.setEnabled(enabled)
                }

            Button(action: onDone) {
                Text("Got it")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .frame(width: 280)
        .background(MaraTheme.bg)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func guideRow(symbol: String, tint: Color, text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(MaraTheme.textMid)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 첫 실행 안내 팝오버 presenter — 상태바 버튼에 앵커해 1회 표시한다.
/// LSUIElement 앱에서 .transient의 바깥 클릭 dismiss는 앱이 활성일 때만 동작하므로
/// 표시 직전 activate하고, 명시적 "Got it" 버튼을 항상 제공한다.
@MainActor
final class FirstRunGuidePresenter: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?

    func show(relativeTo button: NSStatusBarButton, tint: MenuBarTint) {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.appearance = NSAppearance(named: .darkAqua)
        pop.delegate = self
        pop.contentViewController = NSHostingController(
            rootView: FirstRunGuideView(onDone: { [weak self] in self?.dismiss() }).maraAccent(tint)
        )
        popover = pop
        NSApp.activate()
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func dismiss() {
        popover?.performClose(nil)   // 해제는 popoverDidClose가 담당 (바깥 클릭 닫힘과 경로 통일)
    }

    // 닫힘 경로가 둘(Got it / transient 바깥 클릭)이라 delegate에서 한 번에 해제한다 —
    // 닫힌 팝오버가 앱 수명 동안 리테인되는 것 방지.
    func popoverDidClose(_ notification: Notification) {
        popover = nil
    }
}
