import AppIntents
import MaraCore

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
        try commander.startKeepAwake(duration: seconds).get()
        return .result()
    }
}

struct StopKeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Keep Awake"
    static let description = IntentDescription("Turn off keep-awake.")
    @Dependency private var commander: SessionCommander

    @MainActor
    func perform() async throws -> some IntentResult {
        try commander.stopKeepAwake().get()
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
