// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SleeplessCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SleeplessCore", targets: ["SleeplessCore"])
    ],
    targets: [
        .target(name: "SleeplessCore"),
        .testTarget(name: "SleeplessCoreTests", dependencies: ["SleeplessCore"])
    ]
)
