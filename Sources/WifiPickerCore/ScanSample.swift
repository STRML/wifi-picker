import Foundation

public enum Band: Int, Sendable, Equatable {
    case unknown
    case ghz2
    case ghz5
    case ghz6
}

public struct ScanSample: Sendable, Equatable {
    public var ssid: String
    public var bssid: String
    public var rssi: Int
    public var band: Band
    public var secure: Bool
    public var known: Bool

    public init(
        ssid: String,
        bssid: String,
        rssi: Int,
        band: Band = .ghz5,
        secure: Bool = true,
        known: Bool = false
    ) {
        self.ssid = ssid
        self.bssid = bssid
        self.rssi = rssi
        self.band = band
        self.secure = secure
        self.known = known
    }
}
