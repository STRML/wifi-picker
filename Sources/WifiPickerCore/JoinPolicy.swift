import Foundation

public enum JoinOutcome: Sendable, Equatable {
    case connected
    case needsPassword
    case wrongPassword
    case failed(String)
}

public enum JoinPolicy {
    /// CoreWLAN CWErr codes that indicate bad credentials when a password was supplied.
    static let authenticationCodes: Set<Int> = [-3905, -3906, -3909, -3912, -3924, -3925]

    public static func needsPasswordUpFront(secure: Bool, known: Bool) -> Bool {
        secure && !known
    }

    public static func outcome(
        forErrorCode code: Int,
        fallbackMessage: String? = nil,
        hadPassword: Bool,
        secure: Bool
    ) -> JoinOutcome {
        if !hadPassword && secure { return .needsPassword }
        if hadPassword && authenticationCodes.contains(code) { return .wrongPassword }
        return .failed(localizedErrorMessage(forErrorCode: code, fallback: fallbackMessage))
    }

    public static func localizedErrorMessage(forErrorCode code: Int, fallback: String? = nil) -> String {
        if let mapped = coreWLANMessages[code] {
            return mapped
        }
        if let fallback = fallback?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty,
           !isGenericFoundationError(fallback)
        {
            return fallback
        }
        return String(localized: "Couldn’t join network")
    }

    private static func isGenericFoundationError(_ message: String) -> Bool {
        message.contains("operation couldn’t be completed")
            || message.contains("operation couldn't be completed")
    }

    private static let coreWLANMessages: [Int: String] = [
        1: String(localized: "Enterprise authentication failed"),
        -3900: String(localized: "Invalid Wi-Fi request"),
        -3901: String(localized: "Out of memory"),
        -3902: String(localized: "Couldn’t join network"),
        -3903: String(localized: "Network not supported"),
        -3904: String(localized: "Invalid network response"),
        -3905: String(localized: "Connection timed out"),
        -3906: String(localized: "Association failed"),
        -3907: String(localized: "Unsupported network capabilities"),
        -3908: String(localized: "Reassociation denied"),
        -3909: String(localized: "Network denied connection"),
        -3910: String(localized: "Unsupported authentication"),
        -3911: String(localized: "Authentication failed"),
        -3912: String(localized: "Authentication challenge failed"),
        -3913: String(localized: "Access point is full"),
        -3914: String(localized: "Incompatible Wi-Fi rates"),
        -3915: String(localized: "Incompatible Wi-Fi settings"),
        -3916: String(localized: "Incompatible Wi-Fi settings"),
        -3917: String(localized: "Invalid network response"),
        -3918: String(localized: "Unsupported encryption"),
        -3919: String(localized: "Unsupported encryption"),
        -3920: String(localized: "Unsupported security mode"),
        -3921: String(localized: "Unsupported WPA version"),
        -3922: String(localized: "Invalid security settings"),
        -3923: String(localized: "Security cipher rejected"),
        -3924: String(localized: "Invalid network key"),
        -3925: String(localized: "WPA handshake timed out"),
        -3926: String(localized: "Incompatible Wi-Fi mode"),
        -3927: String(localized: "Incompatible Wi-Fi mode"),
        -3928: String(localized: "Wi-Fi interface unavailable"),
        -3929: String(localized: "Wi-Fi service busy"),
        -3930: String(localized: "Operation not permitted"),
        -3931: String(localized: "Couldn’t join network"),
    ]
}
