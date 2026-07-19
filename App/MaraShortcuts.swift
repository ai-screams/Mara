import AppIntents
import Foundation
import MaraCore

/// Shortcuts가 사용자에게 보여줄 읽을 수 있는 오류. Core의 SessionFailure는 LocalizedError를
/// 채택하지 않아 raw로 던지면 "The operation couldn't be completed…"만 뜬다 — App 문구로 감싼다.
/// (UI 문자열은 App 레이어에만, SessionFailureText 재사용 — 기존 규칙.)
private struct KeepAwakeIntentError: LocalizedError {
    let errorDescription: String?
    init(_ failure: SessionFailure) { errorDescription = SessionFailureText.describe(failure) }
}

// duration은 옵셔널 네이티브 파라미터(nil=무기한). 상한 클램프는 Core(SessionCommander)가 담당.
struct StartKeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Keep Awake"
    static let description = IntentDescription("Keep your Mac awake, optionally for a set duration.")

    @Parameter(title: "Duration")
    var duration: Measurement<UnitDuration>?

    @Dependency private var commander: SessionCommander

    @MainActor
    func perform() async throws -> some IntentResult {
        let seconds = duration?.converted(to: .seconds).value
        do {
            try commander.startKeepAwake(duration: seconds).get()
        } catch {
            // .get()은 typed throws로 SessionFailure를 던진다 — error가 이미 그 타입.
            throw KeepAwakeIntentError(error)
        }
        return .result()
    }
}

struct StopKeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Keep Awake"
    static let description = IntentDescription("Turn off keep-awake.")
    @Dependency private var commander: SessionCommander

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            try commander.stopKeepAwake().get()
        } catch {
            // .get()은 typed throws로 SessionFailure를 던진다 — error가 이미 그 타입.
            throw KeepAwakeIntentError(error)
        }
        return .result()
    }
}

struct GetKeepAwakeStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Keep Awake Status"
    static let description = IntentDescription("Check whether Mara is keeping your Mac awake.")
    @Dependency private var commander: SessionCommander

    @MainActor
    func perform() async throws -> some ReturnsValue<Bool> & ProvidesDialog {
        let status = commander.status()
        let dialog: IntentDialog
        if status.isActive {
            let remaining = status.remaining.map { " for \(DurationFormat.compact($0))" } ?? ""
            let via = status.isTriggered ? " (by automation)" : ""
            dialog = IntentDialog("Mara is keeping your Mac awake\(remaining)\(via).")
        } else {
            dialog = IntentDialog("Mara is not keeping your Mac awake.")
        }
        return .result(value: status.isActive, dialog: dialog)
    }
}
