public enum JoinOutcome: Sendable, Equatable {
    case connected
    case needsPassword
    case wrongPassword
    case failed(String)
}

public enum JoinPolicy {
    static let authenticationCodes: Set<Int> = [-3905, -3906, -3909, -3912, -3924, -3925]

    public static func needsPasswordUpFront(secure: Bool, known: Bool) -> Bool {
        secure && !known
    }

    public static func outcome(forErrorCode code: Int, message: String, hadPassword: Bool, secure: Bool) -> JoinOutcome {
        if !hadPassword && secure { return .needsPassword }
        if hadPassword && authenticationCodes.contains(code) { return .wrongPassword }
        return .failed(message)
    }
}
