// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MaraCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MaraCore", targets: ["MaraCore"])
    ],
    targets: [
        .target(
            name: "MaraCore",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "MaraCoreTests",
            dependencies: ["MaraCore"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        )
    ]
)
