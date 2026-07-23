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
        guard !list.isEmpty else { return .desktop }
        let descriptions = list.compactMap {
            IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any]
        }
        guard let description = select(descriptions) else { return .unavailable }
        return parse(description)
    }

    /// 여러 전원 소스 중 저배터리 정책의 기준이 될 description을 고른다.
    ///
    /// IOPSCopyPowerSourcesList는 **정렬을 계약하지 않는데** 예전 코드는 `list.first`를 썼다.
    /// SDK의 IOPSKeys.h가 kIOPSTypeKey의 유효 값으로 InternalBattery와 UPS 둘을 명시하므로,
    /// 노트북에 UPS를 물리면 어느 쪽이 기준이 될지 배열 순서에 매달렸다 — 내부 배터리가 위험한데
    /// UPS가 넉넉하다고 세션을 유지하거나, 그 반대로 오거부할 수 있었다. 순서가 아니라 type을 본다.
    ///
    /// 정책: **내부 배터리 우선**. Mara의 "Low-battery auto-off"는 Mac 자체를 보호하는 기능이라
    /// 기준 소스는 Mac의 배터리다. 내부 배터리가 없으면(데스크톱 + UPS) 첫 유효 소스로 폴백한다.
    ///
    /// 의도된 엣지: 내부 배터리 description이 **키가 모자라** parse에 실패하는 경우, 그걸 고른 채
    /// `.unavailable`을 낸다 — UPS 잔량으로 대체하지 않는다. UPS %를 Mac 배터리인 양 보고하면
    /// 잘못된 자동 종료를 부르기 때문이다. `.unavailable`은 batteryFloorBreach가 `case .battery`
    /// 패턴 매칭이라 veto를 걸지 않으므로(기존 규칙) 세션 시작을 막지도 않는다 — 모른다는 사실에
    /// 정직한 fail-open.
    ///
    /// 위 규칙이 닿지 않는 갈래가 하나 있다(정확히 적어 둔다): description을 **아예 읽지 못한**
    /// 소스(`IOPSGetPowerSourceDescription`이 nil이거나 `[String: Any]` 캐스트 실패)는 read()의
    /// compactMap이 떨어뜨려 이 함수에 보이지도 않는다 — 그 소스가 내부 배터리였다면 위 "UPS로
    /// 대체하지 않는다"가 적용되지 않고 다음 소스로 폴백한다. IOPS는 실제 CFDictionary를 돌려주므로
    /// 실기 도달 경로가 없어 그대로 둔다(막으려면 read()가 원시 소스 핸들을 넘겨야 해서 이 함수가
    /// IOKit에 다시 묶인다 — 테스트 가능성을 잃는 대가가 도달 불가 경로보다 크다).
    ///
    /// IOKit 호출과 분리한 순수 함수 — 하드웨어 없이(헤드리스 CI 포함) 순서 permutation을 테스트한다.
    static func select(_ descriptions: [[String: Any]]) -> [String: Any]? {
        descriptions.first { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }
            ?? descriptions.first
    }

    /// IOPS 전원 소스 description → BatterySnapshot 순수 변환.
    /// IOKit 호출과 분리해 두어 하드웨어 없이(헤드리스 CI 포함) 유닛테스트가 가능하다.
    static func parse(_ description: [String: Any]) -> BatterySnapshot {
        guard let current = description[kIOPSCurrentCapacityKey] as? Int,
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
