// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AetherHumanUI",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "AetherHumanUI", targets: ["AetherHumanUI"]),
        .executable(name: "AetherHumanPreview", targets: ["AetherHumanPreview"])
    ],
    targets: [
        .target(name: "AetherHumanUI", path: "Sources",
                exclude: ["AetherHumanUI/Resources", "AetherHumanPreview"],
                sources: ["AetherHumanUI", "icons"],
                resources: [.copy("AetherHumanUI/Resources/Fonts")]),
        .executableTarget(name: "AetherHumanPreview", dependencies: ["AetherHumanUI"]),
        .testTarget(name: "AetherHumanUITests", dependencies: ["AetherHumanUI"])
    ],
    swiftLanguageModes: [.v5]
)
