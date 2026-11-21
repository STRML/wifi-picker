import WifiPickerCore

// Fake networks for `--demo`, used for screenshots so no real location leaks.
enum DemoNetworks {
    static let current = "The LAN Before Time"

    static let stats = LinkStats(
        rssi: -44, noise: -93, channel: 149, band: "5 GHz", width: "80 MHz", standard: "Wi-Fi 6",
        txRate: 1201, ipv4: "10.0.0.42", router: "10.0.0.1"
    )

    static let samples: [ScanSample] = [
        sample("Dave's iPhone 47", rssi: -58, known: true),
        sample("Grandma's Galaxy Fold", rssi: -71),
        sample("Hotspot of Last Resort", rssi: -80),
        sample(current, rssi: -44, known: true),
        sample("Pretty Fly for a Wi-Fi", rssi: -61, known: true),
        sample("Bill Wi the Science Fi", rssi: -67, known: true),
        sample("Wu-Tang LAN", rssi: -74, known: true),
        sample("FBI Surveillance Van 3", rssi: -52),
        sample("Abraham Linksys", rssi: -63),
        sample("It Hurts When IP", rssi: -66),
        sample("Silence of the LANs", rssi: -70),
        sample("Get Off My LAN", rssi: -73),
        sample("Router? I Hardly Know Her", rssi: -77),
        sample("Free Public WiFi (Trust Me)", rssi: -79, secure: false),
        sample("404 Network Unavailable", rssi: -85),
    ]

    private static func sample(_ ssid: String, rssi: Int, known: Bool = false, secure: Bool = true) -> ScanSample {
        ScanSample(ssid: ssid, bssid: "", rssi: rssi, band: .ghz5, secure: secure, known: known)
    }
}
