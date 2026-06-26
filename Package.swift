// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tab",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tab",
            path: "Sources/Tab",
            linkerSettings: [
                // Private framework that hosts the SLPS* window-focusing symbols.
                .unsafeFlags(["-F", "/System/Library/PrivateFrameworks", "-framework", "SkyLight"])
            ]
        ),
        .testTarget(
            name: "TabTests",
            dependencies: ["Tab"],
            path: "Tests/TabTests",
            linkerSettings: [
                .unsafeFlags(["-F", "/System/Library/PrivateFrameworks", "-framework", "SkyLight"])
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
