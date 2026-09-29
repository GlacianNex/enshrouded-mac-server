// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "EnshroudedServerManager", platforms: [.macOS(.v14)], products: [
    .executable(name: "EnshroudedManager", targets: ["EnshroudedManager"])
], targets: [
    .target(name: "EnshroudedCore"),
    .executableTarget(name: "EnshroudedManager", dependencies: ["EnshroudedCore"]),
    .testTarget(name: "EnshroudedCoreTests", dependencies: ["EnshroudedCore"])
])
