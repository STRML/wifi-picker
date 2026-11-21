import Foundation
@testable import WifiPickerCore

let t0 = Date(timeIntervalSince1970: 1_800_000_000)

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func sample(
    _ ssid: String,
    rssi: Int = -60,
    bssid: String? = nil,
    band: Band = .ghz5,
    secure: Bool = true,
    known: Bool = false
) -> ScanSample {
    ScanSample(
        ssid: ssid,
        bssid: bssid ?? "00:00:00:00:00:\(ssid.utf8.count)",
        rssi: rssi,
        band: band,
        secure: secure,
        known: known
    )
}

func store(_ samples: [ScanSample], at time: Date = t0) -> NetworkStore {
    var result = NetworkStore()
    result.ingest(samples, at: time)
    return result
}
