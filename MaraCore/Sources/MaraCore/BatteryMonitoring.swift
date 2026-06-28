import Foundation
import IOKit.ps

public struct BatterySnapshot: Equatable {
    public let percentage: Int   // 0-100, AC 데스크탑이면 100
    public let isOnAC: Bool
    public init(percentage: Int, isOnAC: Bool) { self.percentage = percentage; self.isOnAC = isOnAC }
}

public protocol BatteryMonitoring: AnyObject {
    var snapshot: BatterySnapshot { get }
    var onChange: ((BatterySnapshot) -> Void)? { get set }
}

public final class IOKitBatteryMonitor: BatteryMonitoring {
    public var onChange: ((BatterySnapshot) -> Void)?
    private var runLoopSource: CFRunLoopSource?

    public init() { start() }

    public var snapshot: BatterySnapshot { Self.read() }

    private func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<IOKitBatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            me.onChange?(IOKitBatteryMonitor.read())
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
        if let s = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .defaultMode) }
    }
}
