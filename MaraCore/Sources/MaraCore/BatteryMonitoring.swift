import Foundation
import Combine
import IOKit.ps

public enum BatterySnapshot: Equatable, Sendable {
    case battery(percentage: Int, isOnAC: Bool)
    case desktop
    case unavailable

    /// 테스트·외부 adapter 호환용. 입력은 실제 배터리 관측값으로 취급한다.
    public init(percentage: Int, isOnAC: Bool) {
        self = .battery(percentage: min(max(percentage, 0), 100), isOnAC: isOnAC)
    }

    public var isOnAC: Bool {
        switch self {
        case .battery(_, let isOnAC): return isOnAC
        case .desktop: return true
        case .unavailable: return false
        }
    }
}

@MainActor
public protocol BatteryMonitoring: AnyObject {
    var snapshot: BatterySnapshot { get }
    var snapshots: AnyPublisher<BatterySnapshot, Never> { get }
}

@MainActor
public final class IOKitBatteryMonitor: BatteryMonitoring {
    private let subject: CurrentValueSubject<BatterySnapshot, Never>
    private var runLoopSource: CFRunLoopSource?

    public init() {
        subject = CurrentValueSubject(IOKitBatteryMonitor.read())
        if !start() {
            subject.send(.unavailable)
        }
    }

    public var snapshot: BatterySnapshot { subject.value }
    public var snapshots: AnyPublisher<BatterySnapshot, Never> { subject.eraseToAnyPublisher() }

    private func start() -> Bool {
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
            MainActor.assumeIsolated {
                let me = Unmanaged<IOKitBatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
                me.subject.send(IOKitBatteryMonitor.read())
            }
        }, context)?.takeRetainedValue() else { return false }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        return true
    }

    static func read() -> BatterySnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return .unavailable }
        guard let source = list.first else { return .desktop }
        guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                as? [String: Any],
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let maximum = description[kIOPSMaxCapacityKey] as? Int,
              maximum > 0,
              let state = description[kIOPSPowerSourceStateKey] as? String
        else { return .unavailable }
        let percentage = min(max(Int(Double(current) / Double(maximum) * 100.0), 0), 100)
        return .battery(percentage: percentage, isOnAC: state == kIOPSACPowerValue)
    }

    deinit {
        MainActor.assumeIsolated {
            // 제거 후 무효화: 콜백과 정리를 같은 main actor에 직렬화해 raw context가
            // 해제 후 호출되는 틈을 막는다.
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
                CFRunLoopSourceInvalidate(source)
            }
        }
    }
}
