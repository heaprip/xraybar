// swift-tools-version: 6.0
import PackageDescription

// No dependencies, by design: see docs/PRINCIPLES.md.
let package = Package(
    name: "XrayBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "XrayBar",
            resources: [.copy("Resources/xraybar-session.sh")]
        ),
        .testTarget(name: "XrayBarTests", dependencies: ["XrayBar"]),
    ]
)
