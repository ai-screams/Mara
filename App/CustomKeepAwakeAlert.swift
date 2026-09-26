import AppKit
import MaraCore

/// 레거시 "Custom…" — 본판 SwiftUI 다이얼로그(CustomKeepAwakeView) 대신 `NSAlert` + accessory 뷰.
/// Duration(시·분, 최대 24h)과 Until(시각, 지난 시각은 내일)을 고른다. 계약은 본판과 같다:
/// 시작이 **실패하면 닫지 않는다** — 입력값과 실패 문구를 보존한 채 같은 alert를 다시 띄운다. 취소하면 끝.
@MainActor
final class CustomKeepAwakeAlert {
    private enum Mode: Int { case duration = 0, until = 1 }

    // 다시 열어도 마지막 입력을 유지한다(본판 캐시 창과 같은 관례). Until 시각만 열 때마다 현재+1h로.
    private var mode = Mode.duration
    private var hours = 1
    private var minutes = 0

    /// `start`는 세션 시작 결과를 돌려준다(실패 = 저배터리 veto·duration 해석 실패·assertion 적용 실패).
    func run(start: (SessionDuration) -> Result<Void, SessionFailure>) {
        var untilTime = Date().addingTimeInterval(3600)
        var message: String?
        while true {
            let alert = NSAlert()
            alert.messageText = "Keep awake…"
            alert.informativeText = message ?? "Duration up to 24 hours, or until a time of day (past times roll over to tomorrow)."
            alert.addButton(withTitle: "Keep Awake")
            alert.addButton(withTitle: "Cancel")

            let modePopup = popup(["Duration", "Until"], selected: mode.rawValue)
            let hoursPopup = popup((0...24).map { "\($0) h" }, selected: hours)
            let minutesPopup = popup(stride(from: 0, through: 55, by: 5).map { "\($0) m" }, selected: minutes / 5)
            let untilPicker = NSDatePicker()
            untilPicker.datePickerElements = .hourMinute
            untilPicker.datePickerStyle = .textFieldAndStepper
            untilPicker.dateValue = untilTime
            untilPicker.sizeToFit()
            alert.accessoryView = accessory(rows: [[modePopup], [hoursPopup, minutesPopup], [untilPicker]])

            NSApp.activate(ignoringOtherApps: true)   // 액세서리 앱 — alert를 전면으로(10.13에서도 동작)
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            mode = Mode(rawValue: modePopup.indexOfSelectedItem) ?? .duration
            hours = hoursPopup.indexOfSelectedItem
            minutes = hours == 24 ? 0 : minutesPopup.indexOfSelectedItem * 5   // 최대 24h — 24h에 분을 얹지 않는다
            untilTime = untilPicker.dateValue

            let duration: SessionDuration
            switch mode {
            case .duration:
                let seconds = TimeInterval(hours * 3600 + minutes * 60)
                guard seconds > 0 else { message = "Pick a duration."; continue }
                duration = .duration(seconds)
            case .until:
                duration = .until(UntilResolver.resolve(timeOfDay: untilTime, now: Date()))
            }
            switch start(duration) {
            case .success: return
            case .failure(let failure):
                NSSound.beep()
                message = "Couldn't start — \(SessionFailureText.describe(failure)). Adjust and try again."
            }
        }
    }

    private func popup(_ titles: [String], selected: Int) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.addItems(withTitles: titles)
        button.selectItem(at: selected)
        button.sizeToFit()
        return button
    }

    /// 행 단위 수직 배치(NSStackView는 10.9+). alert가 accessory 크기를 frame으로 읽으므로 fittingSize로 맞춘다.
    private func accessory(rows: [[NSView]]) -> NSView {
        let stack = NSStackView(views: rows.map { views -> NSView in
            let row = NSStackView(views: views)
            row.orientation = .horizontal
            row.spacing = 8
            return row
        })
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        return stack
    }
}
