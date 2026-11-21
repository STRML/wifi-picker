import Testing
@testable import WifiPickerCore

@Suite struct HotspotClassifierTests {
    @Test(arguments: [
        "iPhone", "Sam’s iPhone", "iPad Pro", "Galaxy S10719e", "Pixel 7", "AndroidAP_1234", "Android_6A3F",
        "OnePlus 9", "Redmi Note 11", "Xiaomi 13", "Moto G Power", "MyHotspot", "Verizon MiFi 8800L", "Jetpack 4412",
        "IPHONE", "galaxy a52", "HOTSPOT-77",
    ])
    func phoneAndHotspotNamesAreHotspots(name: String) {
        #expect(HotspotClassifier.isHotspot(name), "\(name)")
    }

    @Test(arguments: ["Sam's Phone", "Sam’s Pixel", "Alex's S23", "Maria’s Phone"])
    func possessiveFormsWithStraightOrCurlyApostrophesAreHotspots(name: String) {
        #expect(HotspotClassifier.isHotspot(name), "\(name)")
    }

    @Test(arguments: [
        "Free Airport WIFI", "Unitedwifi.com", "cowadlwifi12", "skyfi_secure", "@NRadio-5AB2", "016airport",
        "Remote Office", "Samotop", "Starbucks", "NETGEAR42", "xfinitywifi", "Sam's", "'s home", "",
    ])
    func ordinaryNetworksAreNotHotspots(name: String) {
        #expect(HotspotClassifier.isHotspot(name) == false, "\(name)")
    }
}
