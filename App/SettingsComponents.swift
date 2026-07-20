import SwiftUI

/// Night Watch 설정 창의 재사용 컴포넌트 — 카드 컨테이너와 행(row)들.
/// 색·타이포는 전부 MaraTheme에서 온다.

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
        HStack(spacing: 9) {
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
    @Environment(\.accentTint) private var accent

    // 텍스트 입력·스테퍼 모두 이 바인딩을 통해서만 값을 쓴다 → 범위 밖 입력(예: 250)이
    // prefs/Core로 새지 않는다(과도값이 배터리 자동종료 베토를 오작동시키는 것을 원천 차단).
    private var clamped: Binding<Int> {
        Binding(get: { value },
                set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }

    var body: some View {
        HStack(spacing: 9) {
            SettingsIcon(symbol)
            Text(title).font(.callout).foregroundStyle(.white)
            Spacer(minLength: 8)
            // 직접 입력 가능한 숫자 필드 + "%" — 편집 영역임을 은은한 박스로 표시(수동 bundle ID 필드와 동일 패턴).
            HStack(spacing: 1) {
                TextField(title, value: clamped, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(accent)
                    .frame(width: 30)
                Text("%").font(.callout).foregroundStyle(accent)
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
        Text(text).font(.caption).foregroundStyle(MaraTheme.muted)
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
            .frame(width: 18)
            .accessibilityHidden(true)
    }
}

/// 트리거 진단 상태 한 줄 — 상태 점(활성=accent / 비활성=muted) + 캡션.
/// indent=true면 토글 라벨 텍스트와 정렬되도록 아이콘 폭(18)+간격(9)만큼 들여쓴다.
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
        }
        .padding(.leading, indent ? 27 : 0)
        .accessibilityElement(children: .combine)
    }
}

/// 감시 목록(앱·네트워크)의 삭제 가능한 항목 행 — 모노스페이스 라벨 + 우측 삭제 버튼.
struct RemovableChipRow: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(MaraTheme.textMid)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(MaraTheme.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(text)")
        }
    }
}
