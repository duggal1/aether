// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AetherHumanUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AetherHumanUI", targets: ["AetherHumanUI"]),
        .executable(name: "AetherHumanPreview", targets: ["AetherHumanPreview"])
    ],
    targets: [
        .target(name: "AetherHumanUI", path: "Sources/AetherHumanUI"),
        .executableTarget(name: "AetherHumanPreview", dependencies: ["AetherHumanUI"]),
        .testTarget(name: "AetherHumanUITests", dependencies: ["AetherHumanUI"])
    ],
    swiftLanguageModes: [.v5]
)
