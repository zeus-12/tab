// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tab",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tab",
            path: "Sources/Tab"
        )
    ],
    swiftLanguageModes: [.v5]
)
