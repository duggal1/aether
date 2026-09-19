// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AetherNativeCapture",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AetherCapture", targets: ["AetherCapture"])],
    targets: [
        .target(name: "AetherCapture"),
        .testTarget(name: "AetherCaptureTests", dependencies: ["AetherCapture"])
    ]
)
