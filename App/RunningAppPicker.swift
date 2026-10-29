import SwiftUI
import AppKit
import MaraCore

/// 실행 중인 앱 1개의 표시 항목 — 시트를 여는 순간의 스냅샷.
struct RunningAppItem: Identifiable {
    let id: String          // bundle ID (스냅샷 dedup 키)
    let name: String
    let icon: NSImage?
}

enum RunningAppSnapshot {
    /// 피커에 보여줄 실행 앱 목록. 옵저버(NSWorkspace didLaunch/didTerminate 알림)가
    /// 추적할 수 없는 백그라운드 전용(.prohibited) 프로세스는 제외한다 —
    /// 보여주면 "추가했는데 트리거가 반응 안 하는" 앱이 생긴다.
    static func fetch(excluding watched: Set<String>) -> [RunningAppItem] {
        var seen = Set<String>()
        let selfID = Bundle.main.bundleIdentifier   // 루프 불변식 — 체인 밖에서 1회만 읽는다
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .compactMap { app -> (item: RunningAppItem, regular: Bool)? in
                guard let id = app.bundleIdentifier,
                      id != selfID,   // 자기 자신 제외 — "Mara 실행 중" 트리거는 항상-참이라 무의미
                      !watched.contains(id),
                      seen.insert(id).inserted else { return nil }
                return (RunningAppItem(id: id, name: app.localizedName ?? id, icon: app.icon),
                        app.activationPolicy == .regular)
            }
            .sorted {
                if $0.regular != $1.regular { return $0.regular }   // 독 앱 먼저
                return $0.item.name.localizedCaseInsensitiveCompare($1.item.name) == .orderedAscending
            }
            .map(\.item)
    }
}

/// Night Watch 스타일 실행 앱 피커 시트. 행 클릭 → 추가(onAdd), 추가된 행은 체크로 남고 다시 누르면 뺀다(onRemove).
struct RunningAppPickerView: View {
    let apps: [RunningAppItem]
    /// 실제 추가 성공 여부를 반환해야 한다 — 체크마크는 성공에만 게이트된다
    /// (검증 실패가 체크로 표시되는 거짓 성공 방지, Codex 감사 High 반영).
    let onAdd: (String) -> Bool
    let onRemove: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accentTint) private var accent   // 부모(SettingsView)가 시트로 흘려보낸 tint
    @State private var added: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ADD RUNNING APP")
                .font(.caption2.weight(.bold))
                .kerning(1.4)
                .foregroundStyle(MaraTheme.muted)
            if apps.isEmpty {
                SettingsCaption("No new running apps to add.")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(apps) { app in appRow(app) }
                    }
                }
                .frame(maxHeight: 320)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(MaraTheme.bg)
        .preferredColorScheme(.dark)
        .tint(accent)
    }

    @ViewBuilder
    private func appRow(_ app: RunningAppItem) -> some View {
        let isAdded = added.contains(app.id)
        Button {
            if isAdded {
                onRemove(app.id)
                added.remove(app.id)
            } else if onAdd(app.id) {
                added.insert(app.id)
            }
        } label: {
            HStack(spacing: 9) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app.dashed")
                        .frame(width: 20, height: 20)
                        .foregroundStyle(MaraTheme.muted)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.callout).foregroundStyle(.white)
                    Text(app.id)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(MaraTheme.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isAdded ? MaraTheme.muted : accent)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.001))   // hover/클릭 히트영역 보정
    }
}

/// 감시 목록의 bundle ID → 설치된 앱의 이름·아이콘. 설치되지 않은 ID(직접 입력·삭제한 앱)는 nil.
/// 캐시하지 않는다 — 감시 앱은 몇 개뿐이고, 캐시하면 앱 이름 변경·삭제 뒤에도 옛 표시가 남는다.
@MainActor
enum InstalledAppInfo {
    static func lookup(_ bundleID: String) -> RunningAppItem? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return RunningAppItem(id: bundleID, name: localizedName(bundleID: bundleID, url: url),
                              icon: NSWorkspace.shared.icon(forFile: url.path))
    }

    /// 피커(`NSRunningApplication.localizedName`)와 같은 사용자 언어 이름.
    /// `FileManager.displayName`은 문서와 달리 호출 앱(영어 전용 Mara)의 언어를 따라 "카카오톡" 대신
    /// "KakaoTalk"을 준다(실측, macOS 27). 실행 중이 아닌 앱은 그 번들의 InfoPlist 테이블(.strings·
    /// .loctable)을 사용자 언어로 읽는다 — 그 API가 15.4+라 그 전에는 파일 표시 이름으로 돌아간다.
    private static func localizedName(bundleID: String, url: URL) -> String {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName {
            return running
        }
        if #available(macOS 15.4, *), let bundle = Bundle(url: url) {
            let languages = Bundle.preferredLocalizations(from: bundle.localizations,
                                                          forPreferences: Locale.preferredLanguages)
                .map { Locale.Language(identifier: $0) }
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                // 번역이 없으면 key를 그대로 돌려준다(value: nil).
                let name = bundle.localizedString(forKey: key, value: nil, table: "InfoPlist", localizations: languages)
                if name != key { return name }
            }
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "", options: [.anchored, .backwards])
    }
}
