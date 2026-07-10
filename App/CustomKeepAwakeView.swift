import SwiftUI
import MaraCore

/// Night Watch 미니 다이얼로그 — 임의 duration 또는 "특정 시각까지" keep-awake 시작.
/// 저장·세션 시작은 하지 않는다: 선택 결과를 onStart로 넘기고 닫기만 요청한다.
struct CustomKeepAwakeView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case duration = "Duration"
        case until = "Until"
        var id: String { rawValue }
    }

    let onStart: (SessionDuration) -> Void
    let dismiss: () -> Void

    @State private var mode: Mode = .duration
    @State private var hours = 1
    @State private var minutes = 0
    @State private var untilTime = Date().addingTimeInterval(3600)

    private var durationSeconds: TimeInterval { TimeInterval(hours * 3600 + minutes * 60) }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 5) {
                Image(systemName: MaraSymbol.awake)
                    .font(.system(size: 24))
                    .foregroundStyle(MaraTheme.accent)
                    .accessibilityHidden(true)
                Text("Keep awake…")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                if mode == .duration {
                    HStack(spacing: 12) {
                        stepperField(value: $hours, range: 0...24, unit: "h")
                        stepperField(value: $minutes, range: 0...55, unit: "m", step: 5)
                    }
                    // 최대 24h — 24h에서 분을 얹지 못하게 클램프
                    .onChange(of: hours) { _, h in if h == 24 { minutes = 0 } }
                    .onChange(of: minutes) { _, m in if hours == 24 && m > 0 { minutes = 0 } }   // 24h에서 분 직접 증가도 차단
                    Text(durationSeconds > 0 ? "Keeps your Mac awake for \(DurationFormat.compact(durationSeconds))." : "Pick a duration.")
                        .font(.caption).foregroundStyle(MaraTheme.muted)
                } else {
                    DatePicker("Until", selection: $untilTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                        .labelsHidden()
                    Text("Past times roll over to tomorrow.")
                        .font(.caption).foregroundStyle(MaraTheme.muted)
                }
            }
            .frame(height: 56)

            Button("Keep Awake") {
                onStart(selectedDuration())
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(mode == .duration && durationSeconds <= 0)
        }
        .padding(20)
        .frame(width: 260)
        .background(MaraTheme.bg)
        .preferredColorScheme(.dark)
        .tint(MaraTheme.accent)
        // 캐시된 창이라 @State가 살아남는다 — 열 때마다 기본 시각을 현재+1h로 리셋 (duration 입력은 관례상 유지)
        .onAppear { untilTime = Date().addingTimeInterval(3600) }
    }

    /// Until: 오늘의 해당 시각, 이미 지났으면 내일 — 알람의 표준 의미.
    private func selectedDuration() -> SessionDuration {
        switch mode {
        case .duration:
            return .duration(durationSeconds)
        case .until:
            let cal = Calendar.current
            let hm = cal.dateComponents([.hour, .minute], from: untilTime)
            var target = cal.nextDate(after: Date(), matching: hm, matchingPolicy: .nextTime) ?? untilTime
            // DST-safe rollover: 달력 기준 +1일 (24 * 3600 고정 대신)
            if target <= Date() { target = cal.date(byAdding: .day, value: 1, to: target) ?? target }
            return .until(target)
        }
    }

    private func stepperField(value: Binding<Int>, range: ClosedRange<Int>, unit: String, step: Int = 1) -> some View {
        HStack(spacing: 6) {
            Text("\(value.wrappedValue)")
                .font(.title3.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 34, alignment: .trailing)
            Text(unit).font(.callout).foregroundStyle(MaraTheme.muted)
            Stepper(unit, value: value, in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
                // F4: VoiceOver가 label+value를 두 번 읽지 않도록 명시적으로 지정
                .accessibilityLabel(unit == "h" ? "Hours" : "Minutes")
                .accessibilityValue("\(value.wrappedValue)")
        }
    }
}
