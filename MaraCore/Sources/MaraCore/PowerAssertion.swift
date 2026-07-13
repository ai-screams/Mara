import Foundation
import IOKit.pwr_mgt

public enum PowerAssertionType: Hashable, Sendable {
    case preventDisplaySleep
    case preventSystemSleep

    var ioKitName: CFString {
        switch self {
        case .preventDisplaySleep: return kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        case .preventSystemSleep:  return kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        }
    }
}

public struct PowerAssertionToken: Hashable, Sendable {
    public let id: UInt32
    public init(id: UInt32) { self.id = id }
}

public enum PowerAssertionFailure: Error, Equatable, Sendable {
    case creationFailed(type: PowerAssertionType, code: Int32)
    case releaseFailed(token: PowerAssertionToken, code: Int32)
}

@MainActor
public protocol PowerAssertionProviding {
    func create(type: PowerAssertionType, name: String) -> Result<PowerAssertionToken, PowerAssertionFailure>
    func release(_ token: PowerAssertionToken) -> Result<Void, PowerAssertionFailure>
}

@MainActor
public final class IOKitPowerAssertionProvider: PowerAssertionProviding {
    public init() {}

    public func create(type: PowerAssertionType,
                       name: String) -> Result<PowerAssertionToken, PowerAssertionFailure> {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type.ioKitName,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            return .failure(.creationFailed(type: type, code: result))
        }
        return .success(PowerAssertionToken(id: id))
    }

    public func release(_ token: PowerAssertionToken) -> Result<Void, PowerAssertionFailure> {
        let result = IOPMAssertionRelease(IOPMAssertionID(token.id))
        guard result == kIOReturnSuccess else {
            return .failure(.releaseFailed(token: token, code: result))
        }
        return .success(())
    }
}
