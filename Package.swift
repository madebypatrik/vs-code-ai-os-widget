// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentPill",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentPill", targets: ["AgentPill"]),
    ],
    targets: [
        .target(name: "AgentPillCore"),
        .executableTarget(
            name: "AgentPill",
            dependencies: ["AgentPillCore"]
        ),
        .testTarget(
            name: "AgentPillCoreTests",
            dependencies: ["AgentPillCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
