// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AetherEngineAdditions",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AetherResourceControl", targets: ["AetherResourceControl"]),
        .library(name: "AetherAgentInfrastructure", targets: ["AetherAgentInfrastructure"]),
        .library(name: "AetherNetworkHardening", targets: ["AetherNetworkHardening"]),
        .library(name: "AetherWebPrimitives", targets: ["AetherWebPrimitives"]),
        .library(name: "AetherRenderInfrastructure", targets: ["AetherRenderInfrastructure"]),
        .library(name: "AetherMetalBackend", targets: ["AetherMetalBackend"])
    ],
    targets: [
        .target(name: "AetherResourceControl"),
        .target(name: "AetherAgentInfrastructure", dependencies: ["AetherResourceControl"]),
        .target(name: "AetherNetworkHardening"),
        .target(name: "AetherWebPrimitives"),
        .target(name: "AetherRenderInfrastructure"),
        .target(name: "AetherMetalBackend", dependencies: ["AetherRenderInfrastructure"]),
        .testTarget(name: "AetherAdditionsTests", dependencies: ["AetherResourceControl", "AetherAgentInfrastructure", "AetherNetworkHardening", "AetherWebPrimitives", "AetherRenderInfrastructure"])
    ],
    swiftLanguageModes: [.v6]
)
