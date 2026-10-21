// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PoochiAnalytics",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PoochiCore", targets: ["PoochiCore"]),
        .executable(name: "PoochiAnalytics", targets: ["PoochiAnalytics"])
    ],
    targets: [
        .target(name: "PoochiCore"),
        .executableTarget(name: "PoochiAnalytics", dependencies: ["PoochiCore"]),
        .testTarget(name: "PoochiCoreTests", dependencies: ["PoochiCore"])
    ]
)
