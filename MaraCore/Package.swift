// swift-tools-version: 5.9
import PackageDescription

let openCombine: [Target.Dependency] = [
    .product(name: "OpenCombine", package: "OpenCombine"),
    .product(name: "OpenCombineFoundation", package: "OpenCombine"),
    .product(name: "OpenCombineDispatch", package: "OpenCombine")
]

let package = Package(
    name: "MaraCore",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "MaraCore", targets: ["MaraCore"])
    ],
    // 레거시(10.13): Combine(10.15+) 대신 OpenCombine. 불변 revision은 Package.resolved가 고정한다.
    dependencies: [
        .package(url: "https://github.com/OpenCombine/OpenCombine", exact: "0.14.0")
    ],
    targets: [
        .target(
            name: "MaraCore",
            dependencies: openCombine,
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "MaraCoreTests",
            dependencies: ["MaraCore"] + openCombine,
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        )
    ]
)
