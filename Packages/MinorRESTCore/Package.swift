// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MinorRESTCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MinorRESTCore", targets: ["MinorRESTCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
    ],
    targets: [
        .target(name: "MinorRESTCore", dependencies: ["Yams"]),
        .testTarget(name: "MinorRESTCoreTests", dependencies: ["MinorRESTCore"]),
    ]
)
