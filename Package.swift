// swift-tools-version: 6.0
import PackageDescription

// No dependencies, by design: see docs/PRINCIPLES.md.
let package = Package(
    name: "XrayBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "XrayBar",
            resources: [.copy("Resources/xraybar-session.sh"), .copy("Resources/xraybar-install.sh")]
        ),
        // Root side, installed once as a LaunchDaemon (docs/DECISIONS.md D28).
        .executableTarget(name: "XrayBarHelper"),
        .testTarget(name: "XrayBarTests", dependencies: ["XrayBar"]),
    ]
)
