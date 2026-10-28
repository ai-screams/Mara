import SwiftUI

/// Night Watch 설정 창의 재사용 컴포넌트 — 카드 컨테이너와 행(row)들.
/// 색·타이포는 전부 MaraTheme에서 온다.

/// 설정 행의 공통 치수. 하위 항목 들여쓰기는 아이콘 폭 + 간격에서 계산해 라벨 글자 위치와 항상 맞는다.
enum SettingsLayout {
    static let iconWidth: CGFloat = 18
    static let rowSpacing: CGFloat = 9
    /// 토글 하위 항목(상태 줄·목록·추가 버튼)의 들여쓰기.
    static let childIndent = iconWidth + rowSpacing
}

/// 상단 소제목 + 어두운 라운드 컨테이너.
struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.bold))
                .kerning(1.4)
                .foregroundStyle(MaraTheme.muted)
                .padding(.leading, 2)
            VStack(alignment: .leading, spacing: 11) { content }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MaraTheme.card, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// 아이콘 + 라벨 + 오렌지 스위치.
struct SettingsToggleRow: View {
    let symbol: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: SettingsLayout.rowSpacing) {
            SettingsIcon(symbol)
            Text(title).font(.callout).foregroundStyle(.white)
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// 아이콘 + 라벨 + 현재값(%) + 스테퍼.
struct SettingsStepperRow: View {
    let symbol: String
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    /// 이 값이면 숫자 대신 "Off"를 보인다(예: 저배터리 임계값 0 = 끔). nil이면 항상 숫자.
    var offValue: Int? = nil
    @Environment(\.accentTint) private var accent

    // 텍스트 입력·스테퍼 모두 이 바인딩을 통해서만 값을 쓴다 → 범위 밖 입력(예: 250)이
    // prefs/Core로 새지 않는다(과도값이 배터리 자동종료 베토를 오작동시키는 것을 원천 차단).
    private var clamped: Binding<Int> {
        Binding(get: { value },
                set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }

    var body: some View {
        HStack(spacing: SettingsLayout.rowSpacing) {
            SettingsIcon(symbol)
            Text(title).font(.callout).foregroundStyle(.white)
            Spacer(minLength: 8)
            // 직접 입력 가능한 숫자 필드 + "%" — 편집 영역임을 은은한 박스로 표시(수동 bundle ID 필드와 동일 패턴).
            HStack(spacing: 1) {
                if value == offValue {
                    // 끔 상태는 입력 필드 대신 고정 라벨 — 스테퍼를 올리면 다시 숫자 필드가 된다.
                    Text("Off").font(.callout).foregroundStyle(accent)
                        .frame(width: 41, alignment: .trailing)
                } else {
                    TextField(title, value: clamped, format: .number)
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(accent)
                        .frame(width: 30)
                    Text("%").font(.callout).foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 6))
            Stepper(title, value: clamped, in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

/// 카드 안 보조 설명 텍스트.
struct SettingsCaption: View {
    private let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        // 창 높이는 NSHostingController가 콘텐츠 크기로 정한다. 세로 고정이 없으면 긴 문구가
        // 한 줄 높이에 갇혀 말줄임으로 잘린다(실사고: 저배터리 캡션의 100% 안내가 안 보임).
        Text(text).font(.caption).foregroundStyle(MaraTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 행 선두의 고정폭 어센트 심볼.
struct SettingsIcon: View {
    private let symbol: String
    @Environment(\.accentTint) private var accent
    init(_ symbol: String) { self.symbol = symbol }
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13))
            .foregroundStyle(accent)
            .frame(width: SettingsLayout.iconWidth)
            .accessibilityHidden(true)
    }
}

/// 트리거 진단 상태 한 줄 — 상태 점(활성=accent / 비활성=muted) + 캡션.
/// indent=true면 토글 라벨 텍스트와 정렬되도록 SettingsLayout.childIndent만큼 들여쓴다.
struct SettingsStatusRow: View {
    let active: Bool
    let text: String
    var indent: Bool = true
    @Environment(\.accentTint) private var accent

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? accent : MaraTheme.muted.opacity(0.6))
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(active ? accent : MaraTheme.muted)
                // SettingsCaption과 같은 이유로 세로 고정하되, 상태 문구는 bundle ID처럼 길이 제한 없는
                // 값을 담으므로 2줄에서 자른다 — 무제한이면 창이 화면보다 커질 수 있다.
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, indent ? SettingsLayout.childIndent : 0)
        .accessibilityElement(children: .combine)
    }
}

/// 감시 목록 행의 삭제 버튼. 접근성 라벨은 사람이 알아볼 이름으로 준다.
struct RemoveButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill").foregroundStyle(MaraTheme.muted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(label)")
    }
}

/// 감시 목록(앱·네트워크) 행의 공통 모양: [선두 장식] 제목 / 작은 모노스페이스 식별자 · 삭제.
struct WatchedItemRow<Leading: View, Title: View>: View {
    let subtitle: String
    let removeLabel: String
    let onRemove: () -> Void
    @ViewBuilder var leading: Leading
    @ViewBuilder var title: Title

    var body: some View {
        HStack(spacing: 8) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                title
                Text(subtitle)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(MaraTheme.muted)
            }
            Spacer()
            RemoveButton(label: removeLabel, action: onRemove)
        }
    }
}

/// 이름을 알 수 없는 항목(설치되지 않은 앱 ID)의 한 줄 — 모노스페이스 라벨 + 삭제.
struct RemovableChipRow: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(MaraTheme.textMid)
            Spacer()
            RemoveButton(label: text, action: onRemove)
        }
    }
}

/// 감시 앱 한 줄: 설치돼 있으면 아이콘·이름 + 작은 bundle ID, 아니면 ID만.
struct WatchedAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        if let app = InstalledAppInfo.lookup(bundleID) {
            WatchedItemRow(subtitle: app.id, removeLabel: app.name, onRemove: onRemove) {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable().frame(width: SettingsLayout.iconWidth,
                                                           height: SettingsLayout.iconWidth)
                }
            } title: {
                Text(app.name).font(.callout).foregroundStyle(.white)
            }
        } else {
            RemovableChipRow(text: bundleID, onRemove: onRemove)
        }
    }
}

/// 감시 네트워크 한 줄: 이름 입력칸 + 작은 MAC + 삭제. 식별은 MAC이고 이름은 표시 전용이다.
/// 입력은 키마다 저장한다 — 설정 창은 닫아도 숨겨질 뿐이라, Return·포커스 이탈에만 저장하면 그대로 앱을 끌 때 사라진다.
/// 입력 중에는 초안을 그대로 두고(공백이 지워지지 않게), Return이나 포커스를 잃으면 정리된 저장값으로 맞춘다 —
/// 그러지 않으면 40자를 넘긴 입력이나 공백뿐인 입력이 칸에 남아 저장값과 다르게 보인다.
struct WatchedNetworkRow: View {
    let mac: String
    let savedName: String?
    let onRename: (String) -> Void
    let onRemove: () -> Void
    @State private var draft: String
    @FocusState private var focused: Bool

    init(mac: String, savedName: String?, onRename: @escaping (String) -> Void, onRemove: @escaping () -> Void) {
        self.mac = mac
        self.savedName = savedName
        self.onRename = onRename
        self.onRemove = onRemove
        _draft = State(initialValue: savedName ?? "")
    }

    var body: some View {
        WatchedItemRow(subtitle: mac, removeLabel: savedName ?? mac, onRemove: onRemove) {
            EmptyView()
        } title: {
            // placeholder를 muted로 — 흰 글자면 이름을 붙인 행과 구분되지 않는다.
            TextField("Name", text: $draft,
                      prompt: Text("Name (e.g. Home)").foregroundStyle(MaraTheme.muted))
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.white)
                .focused($focused)
                .accessibilityLabel("Name for network \(mac)")
                .onChange(of: draft) { _, newValue in onRename(newValue) }
                .onSubmit(syncDraftToSaved)
                .onChange(of: focused) { _, isFocused in if !isFocused { syncDraftToSaved() } }
        }
    }

    private func syncDraftToSaved() {
        draft = savedName ?? ""
    }
}
