// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudePill",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudePill", targets: ["ClaudePill"]),
    ],
    targets: [
        .target(name: "ClaudePillCore"),
        .executableTarget(
            name: "ClaudePill",
            dependencies: ["ClaudePillCore"]
        ),
        .testTarget(
            name: "ClaudePillCoreTests",
            dependencies: ["ClaudePillCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
