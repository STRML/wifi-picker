import Foundation

public enum HotspotClassifier {
    private static let keywords = [
        "iphone", "ipad", "galaxy", "pixel", "androidap", "android", "oneplus", "redmi", "xiaomi",
        "hotspot", "mifi", "jetpack",
    ]

    public static func isHotspot(_ ssid: String) -> Bool {
        containsKeyword(ssid) || startsMotoWord(ssid) || isPossessive(ssid)
    }

    private static func containsKeyword(_ ssid: String) -> Bool {
        keywords.contains { ssid.range(of: $0, options: .caseInsensitive) != nil }
    }

    private static func startsMotoWord(_ ssid: String) -> Bool {
        ssid.contains(/(?i)(^|[^\p{L}])moto/)
    }

    private static func isPossessive(_ ssid: String) -> Bool {
        ssid.contains(/^[^'’]+['’][sS]\s+\S/)
    }
}
