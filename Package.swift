// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WifiPicker",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WifiPicker", targets: ["WifiPicker"]),
    ],
    targets: [
        .target(name: "WifiPickerCore"),
        .executableTarget(
            name: "WifiPicker",
            dependencies: ["WifiPickerCore"]
        ),
        .testTarget(
            name: "WifiPickerCoreTests",
            dependencies: ["WifiPickerCore"]
        ),
    ]
)
