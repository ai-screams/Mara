import Foundation
import IOKit.pwr_mgt

public enum PowerAssertionType {
    case preventDisplaySleep
    case preventSystemSleep

    var ioKitName: CFString {
        switch self {
        case .preventDisplaySleep: return kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        case .preventSystemSleep:  return kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        }
    }
}

public struct PowerAssertionToken: Hashable {
    public let id: UInt32
    public init(id: UInt32) { self.id = id }
}

public protocol PowerAssertionProviding {
    func create(type: PowerAssertionType, name: String) -> PowerAssertionToken?
    func release(_ token: PowerAssertionToken)
}

public final class IOKitPowerAssertionProvider: PowerAssertionProviding {
    public init() {}

    public func create(type: PowerAssertionType, name: String) -> PowerAssertionToken? {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type.ioKitName,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return nil }
        return PowerAssertionToken(id: id)
    }

    public func release(_ token: PowerAssertionToken) {
        _ = IOPMAssertionRelease(IOPMAssertionID(token.id))
    }
}
