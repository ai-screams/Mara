import MaraCore

enum SessionFailureText {
    static func describe(_ failure: SessionFailure) -> String {
        switch failure {
        case .lowBattery(let percent):
            return "can't start — battery at \(percent)% is at or below your limit"
        case .invalidDuration:
            return "invalid duration"
        case .invalidUntilDate:
            return "invalid end time"
        case .power(let engineFailure):
            guard let first = engineFailure.failures.first else {
                return "unknown power-management error"
            }
            switch first {
            case .creationFailed(let type, let code):
                return "couldn't create \(name(of: type)) assertion (\(code))"
            case .releaseFailed(_, let code):
                return "couldn't release power assertion (\(code))"
            }
        }
    }

    private static func name(of type: PowerAssertionType) -> String {
        switch type {
        case .preventDisplaySleep: return "display-sleep"
        case .preventSystemSleep: return "system-sleep"
        }
    }
}
