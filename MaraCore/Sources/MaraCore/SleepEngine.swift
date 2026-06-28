public final class SleepEngine {
    private let provider: PowerAssertionProviding
    private let name: String
    private var displayToken: PowerAssertionToken?
    private var systemToken: PowerAssertionToken?

    public init(provider: PowerAssertionProviding, name: String = "Mara") {
        self.provider = provider
        self.name = name
    }

    public var isDisplayHeld: Bool { displayToken != nil }
    public var isSystemHeld: Bool { systemToken != nil }

    /// 멱등: 원하는 상태로 reconcile. 이미 보유 중이면 재생성하지 않고, 불필요하면 해제.
    public func apply(display: Bool, system: Bool) {
        reconcile(want: display, token: &displayToken, type: .preventDisplaySleep)
        reconcile(want: system, token: &systemToken, type: .preventSystemSleep)
    }

    public func releaseAll() {
        apply(display: false, system: false)
    }

    private func reconcile(want: Bool, token: inout PowerAssertionToken?, type: PowerAssertionType) {
        if want, token == nil {
            token = provider.create(type: type, name: name)
        } else if !want, let live = token {
            provider.release(live)
            token = nil
        }
    }

    deinit { releaseAll() }
}
