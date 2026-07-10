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

    var body: some View {
        HStack(spacing: 9) {
            SettingsIcon(symbol)
            Text(title).font(.callout).foregroundStyle(.white)
            Spacer(minLength: 8)
            Text("\(value)%")
                .font(.callout.monospacedDigit())
                .foregroundStyle(MaraTheme.accent)
            Stepper(title, value: $value, in: range, step: step)
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
    init(_ symbol: String) { self.symbol = symbol }
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13))
            .foregroundStyle(MaraTheme.accent)
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

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? MaraTheme.accent : MaraTheme.muted.opacity(0.6))
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(active ? MaraTheme.accent : MaraTheme.muted)
        }
        .padding(.leading, indent ? 27 : 0)
        .accessibilityElement(children: .combine)
    }
}
