import Foundation
import Network
import SystemConfiguration

/// 네트워크 경로 변화 감지 경계. 저장 프로퍼티의 타입은 가용성으로 가릴 수 없으므로(`NWPathMonitor`는 10.14+),
/// provider는 10.13에서도 존재하는 이 프로토콜만 저장하고 구현을 OS별로 고른다.
///
/// 계약: `onChange`는 **비격리 클로저**이며 구현은 반드시 main 큐에서 호출한다(호출부가
/// `unsafeAssumeMainActor`로 진입한다). `stop()`은 멱등이다.
@MainActor
public protocol NetworkChangeMonitoring: AnyObject {
    func start(onChange: @escaping () -> Void)
    func stop()
}

/// 10.14+: `NWPathMonitor`(queue `.main`).
@available(macOS 10.14, *)
@MainActor
public final class NWPathChangeMonitor: NetworkChangeMonitoring {
    private var monitor: NWPathMonitor?

    public init() {}

    public func start(onChange: @escaping () -> Void) {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { _ in onChange() }
        monitor.start(queue: .main)
        self.monitor = monitor
    }

    public func stop() {
        monitor?.cancel()
        monitor = nil
    }
}

/// 10.13: `SCDynamicStore`의 전역 IPv4/IPv6 상태 키 알림(queue `.main`).
///
/// context에는 self가 아니라 콜백만 든 작은 box를 넘기고 그 box만 +1로 잡는다 — store가 self를
/// 붙잡는 순환이 생기지 않고, `stop()`이 box를 정확히 한 번 놓는다.
@MainActor
public final class SCDynamicStoreChangeMonitor: NetworkChangeMonitoring {
    private final class CallbackBox {
        let onChange: () -> Void
        init(_ onChange: @escaping () -> Void) { self.onChange = onChange }
    }

    private static let watchedKeys = ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"]

    private var store: SCDynamicStore?
    private var box: Unmanaged<CallbackBox>?

    public init() {}

    public func start(onChange: @escaping () -> Void) {
        guard store == nil else { return }
        let box = Unmanaged.passRetained(CallbackBox(onChange))
        var context = SCDynamicStoreContext(version: 0, info: box.toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "com.aiscream.Mara.network" as CFString, { _, _, info in
            guard let info else { return }
            Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue().onChange()
        }, &context) else {
            box.release()
            return
        }
        SCDynamicStoreSetNotificationKeys(store, Self.watchedKeys as CFArray, nil)
        SCDynamicStoreSetDispatchQueue(store, .main)
        self.store = store
        self.box = box
    }

    public func stop() {
        if let store {
            SCDynamicStoreSetDispatchQueue(store, nil)
        }
        store = nil
        box?.release()
        box = nil
    }
}
