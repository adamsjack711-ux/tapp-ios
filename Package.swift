// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PocketAgentCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PocketAgentCore", targets: ["PocketAgentCore"])
    ],
    targets: [
        .target(name: "PocketAgentCore"),
        .testTarget(
            name: "PocketAgentCoreTests",
            dependencies: ["PocketAgentCore"]
        )
    ]
)
