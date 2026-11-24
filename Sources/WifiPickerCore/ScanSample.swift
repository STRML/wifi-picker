import Foundation

public struct ScanSample: Sendable, Equatable {
    public var ssid: String
    public var bssid: String
    public var rssi: Int
    public var secure: Bool
    public var known: Bool

    public init(
        ssid: String,
        bssid: String,
        rssi: Int,
        secure: Bool = true,
        known: Bool = false
    ) {
        self.ssid = ssid
        self.bssid = bssid
        self.rssi = rssi
        self.secure = secure
        self.known = known
    }
}

public struct NetworkEntry: Sendable, Equatable {
    public var ssid: String
    public var rssi: Int
    public var secure: Bool
    public var known: Bool
    public var firstSeen: Date
    public var lastSeen: Date

    public var signal: Double { SignalLevel.value(forRSSI: rssi) }
}

public enum SignalLevel {
    static let weakest = -90.0
    static let strongest = -45.0

    public static func value(forRSSI rssi: Int) -> Double {
        min(1, max(0, (Double(rssi) - weakest) / (strongest - weakest)))
    }
}

public enum ColumnKind: Int, Sendable, CaseIterable {
    case hotspots
    case known
    case other

    static func classify(_ entry: NetworkEntry) -> ColumnKind {
        if HotspotClassifier.isHotspot(entry.ssid) { return .hotspots }
        return entry.known ? .known : .other
    }
}

public struct LayoutColumn: Sendable, Equatable {
    public let kind: ColumnKind
    public var slots: [String]

    public init(kind: ColumnKind, slots: [String]) {
        self.kind = kind
        self.slots = slots
    }
}

public struct LayoutCell: Sendable, Equatable {
    public let entry: NetworkEntry
    public let dimmed: Bool
}

public enum MoveDirection: Sendable, Equatable {
    case left
    case right
    case up
    case down
}

public enum PanelKey: Sendable, Equatable {
    case escape
    case confirm
    case arrow(MoveDirection)
}

public struct InterfaceState: Sendable, Equatable {
    public var powerOn: Bool
    public var ssid: String?
    public var rssi: Int?

    public init(powerOn: Bool, ssid: String?, rssi: Int?) {
        self.powerOn = powerOn
        self.ssid = ssid
        self.rssi = rssi
    }
}

public struct LinkStats: Sendable, Equatable {
    public var rssi: Int
    public var noise: Int
    public var channel: Int?
    public var band: String?
    public var width: String?
    public var standard: String?
    public var txRate: Double
    public var ipv4: String?
    public var router: String?

    public var snr: Int { rssi - noise }

    public init(
        rssi: Int,
        noise: Int,
        channel: Int?,
        band: String?,
        width: String?,
        standard: String?,
        txRate: Double,
        ipv4: String?,
        router: String?
    ) {
        self.rssi = rssi
        self.noise = noise
        self.channel = channel
        self.band = band
        self.width = width
        self.standard = standard
        self.txRate = txRate
        self.ipv4 = ipv4
        self.router = router
    }
}

public enum LocationAccess: Sendable, Equatable {
    case undetermined
    case granted
    case denied
}
