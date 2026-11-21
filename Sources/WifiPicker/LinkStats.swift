import CoreWLAN
import Foundation
import SystemConfiguration

struct LinkStats: Sendable, Equatable {
    var rssi: Int
    var noise: Int
    var channel: Int?
    var band: String?
    var width: String?
    var standard: String?
    var txRate: Double
    var ipv4: String?
    var router: String?

    var snr: Int { rssi - noise }
}

extension LinkStats {
    static func read(from interface: CWInterface) -> LinkStats? {
        guard interface.powerOn(), interface.ssid() != nil else { return nil }
        let channel = interface.wlanChannel()
        let name = interface.interfaceName ?? "en0"
        return LinkStats(
            rssi: interface.rssiValue(),
            noise: interface.noiseMeasurement(),
            channel: channel.map { $0.channelNumber },
            band: channel.flatMap { bandLabel($0.channelBand) },
            width: channel.flatMap { widthLabel($0.channelWidth) },
            standard: standardLabel(interface.activePHYMode()),
            txRate: interface.transmitRate(),
            ipv4: ipv4Address(interface: name),
            router: router(interface: name)
        )
    }

    private static let bands: [CWChannelBand: String] = [.band2GHz: "2.4 GHz", .band5GHz: "5 GHz", .band6GHz: "6 GHz"]
    private static let widths: [CWChannelWidth: String] = [
        .width20MHz: "20 MHz", .width40MHz: "40 MHz", .width80MHz: "80 MHz", .width160MHz: "160 MHz",
    ]
    private static let standards: [CWPHYMode: String] = [
        .mode11a: "802.11a", .mode11b: "802.11b", .mode11g: "802.11g", .mode11n: "Wi-Fi 4",
        .mode11ac: "Wi-Fi 5", .mode11ax: "Wi-Fi 6", .mode11be: "Wi-Fi 7",
    ]

    private static func bandLabel(_ band: CWChannelBand) -> String? { bands[band] }
    private static func widthLabel(_ width: CWChannelWidth) -> String? { widths[width] }
    private static func standardLabel(_ mode: CWPHYMode) -> String? { standards[mode] }

    private static func ipv4Address(interface: String) -> String? {
        let value = storeValue("State:/Network/Interface/\(interface)/IPv4")
        return (value?["Addresses"] as? [String])?.first
    }

    private static func router(interface: String) -> String? {
        let value = storeValue("State:/Network/Interface/\(interface)/IPv4")
        if let router = value?["Router"] as? String { return router }
        let global = storeValue("State:/Network/Global/IPv4")
        guard global?["PrimaryInterface"] as? String == interface else { return nil }
        return global?["Router"] as? String
    }

    private static func storeValue(_ key: String) -> [String: Any]? {
        guard let store = SCDynamicStoreCreate(nil, "wifi-picker" as CFString, nil, nil) else { return nil }
        return SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
    }
}
