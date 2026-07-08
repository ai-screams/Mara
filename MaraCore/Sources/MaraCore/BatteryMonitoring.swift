import Foundation
import Combine
import IOKit.ps

public struct BatterySnapshot: Equatable {
    public let percentage: Int   // 0-100, AC 데스크탑이면 100
    public let isOnAC: Bool
    public init(percentage: Int, isOnAC: Bool) { self.percentage = percentage; self.isOnAC = isOnAC }
}

public protocol BatteryMonitoring: AnyObject {
    var snapshot: BatterySnapshot { get }
    var snapshots: AnyPublisher<BatterySnapshot, Never> { get }
}

public final class IOKitBatteryMonitor: BatteryMonitoring {
    private let subject: CurrentValueSubject<BatterySnapshot, Never>
    private var runLoopSource: CFRunLoopSource?

    public init() {
        subject = CurrentValueSubject(IOKitBatteryMonitor.read())
        start()
    }

    public var snapshot: BatterySnapshot { subject.value }
    public var snapshots: AnyPublisher<BatterySnapshot, Never> { subject.eraseToAnyPublisher() }

    private func start() {
        // context = passUnretained(self)가 이 패턴의 정석이다. IOPSNotificationCreateRunLoopSource는
        // context를 raw void*로 저장할 뿐 CFRetain하지 않으므로, passRetained(self)로 잡으면 아무도
        // 해제하지 않는 self의 +1이 남아 **누수**가 되고 deinit이 영원히 호출되지 않는다(실증 확인 —
        // source가 context를 retain하지 않으니 retain cycle이 아니라 unbalanced retain이다).
        // 대신 안전은 수명 불변식으로 보장된다: self는 main-actor 소유자(AppEnvironment·SessionManager)가
        // 보유하므로 최종 해제가 메인에서 일어나고, IOPS 콜백과 deinit이 모두 메인 런루프에서 실행되어
        // deinit의 무효화·제거 후 in-flight 콜백이 없다.
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<IOKitBatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            me.subject.send(IOKitBatteryMonitor.read())
        }, context)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    static func read() -> BatterySnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let ps = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any]
        else {
            return BatterySnapshot(percentage: 100, isOnAC: true)  // 배터리 없음 = 데스크탑
        }
        let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
        let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
        let state = desc[kIOPSPowerSourceStateKey] as? String ?? kIOPSACPowerValue
        let pct = max > 0 ? Int(Double(current) / Double(max) * 100.0) : 100
        return BatterySnapshot(percentage: pct, isOnAC: state == kIOPSACPowerValue)
    }

    deinit {
        // 제거 후 무효화(방어적): invalidate는 source가 등록된 모든 런루프에서 제거하고
        // 무효 표시하여, 어떤 참조가 남아도 콜백이 다시 발화하지 않도록 보장한다.
        if let s = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .defaultMode)
            CFRunLoopSourceInvalidate(s)
        }
    }
}
