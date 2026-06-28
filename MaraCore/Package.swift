// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MaraCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MaraCore", targets: ["MaraCore"])
    ],
    targets: [
        .target(name: "MaraCore"),
        .testTarget(name: "MaraCoreTests", dependencies: ["MaraCore"])
    ]
)
