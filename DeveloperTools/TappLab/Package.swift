// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "TappMotion", platforms: [.macOS(.v14)], targets: [
    .target(name: "TappMotion"),
    .testTarget(name: "TappMotionTests", dependencies: ["TappMotion"])
])
