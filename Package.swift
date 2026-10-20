// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MACWIN",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ScrubCore"),
        .executableTarget(name: "MACWIN", dependencies: ["ScrubCore"]),
        .executableTarget(name: "macwin-cli", dependencies: ["ScrubCore"]),
    ]
)
