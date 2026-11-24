import CoreWLAN
import Foundation
import SystemConfiguration
import WifiPickerCore

final class LinkStatsReader {
    private lazy var store: SCDynamicStore? = SCDynamicStoreCreate(nil, "wifi-picker" as CFString, nil, nil)

    func read(from interface: CWInterface) -> LinkStats? {
        guard interface.powerOn(), interface.ssid() != nil else { return nil }
        let channel = interface.wlanChannel()
        let name = interface.interfaceName ?? "en0"
        let ipv4Dict = storeValue("State:/Network/Interface/\(name)/IPv4")
        let ipv4 = (ipv4Dict?["Addresses"] as? [String])?.first
        let router = resolveRouter(interface: name, interfaceIPv4: ipv4Dict)
        return LinkStats(
            rssi: interface.rssiValue(),
            noise: interface.noiseMeasurement(),
            channel: channel.map { $0.channelNumber },
            band: channel.flatMap { Self.bands[$0.channelBand] },
            width: channel.flatMap { Self.widths[$0.channelWidth] },
            standard: Self.standards[interface.activePHYMode()],
            txRate: interface.transmitRate(),
            ipv4: ipv4,
            router: router
        )
    }

    private static let bands: [CWChannelBand: String] = [
        .band2GHz: "2.4 GHz", .band5GHz: "5 GHz", .band6GHz: "6 GHz",
    ]
    private static let widths: [CWChannelWidth: String] = [
        .width20MHz: "20 MHz", .width40MHz: "40 MHz", .width80MHz: "80 MHz", .width160MHz: "160 MHz",
    ]
    private static let standards: [CWPHYMode: String] = [
        .mode11a: "802.11a", .mode11b: "802.11b", .mode11g: "802.11g", .mode11n: "Wi-Fi 4",
        .mode11ac: "Wi-Fi 5", .mode11ax: "Wi-Fi 6", .mode11be: "Wi-Fi 7",
    ]

    private func resolveRouter(interface: String, interfaceIPv4: [String: Any]?) -> String? {
        if let router = interfaceIPv4?["Router"] as? String { return router }
        let global = storeValue("State:/Network/Global/IPv4")
        guard global?["PrimaryInterface"] as? String == interface else { return nil }
        return global?["Router"] as? String
    }

    private func storeValue(_ key: String) -> [String: Any]? {
        guard let store else { return nil }
        return SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
    }
}
