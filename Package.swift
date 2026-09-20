// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "NativeBrowserEngine",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "BrowserEngine", targets: ["BrowserEngine"]),
    .library(name: "AetherHumanUI", targets: ["AetherHumanUI"]),
    .executable(name: "AetherApp", targets: ["AetherApp"]),
    .executable(name: "browserctl", targets: ["browserctl"]),
    .executable(name: "browserd", targets: ["browserd"]),
    .executable(name: "enginebench", targets: ["enginebench"]),
  ],
  targets: [
    .target(name: "AetherHumanUI", path: "Sources/BrowserUI/Sources/AetherHumanUI",
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(name: "AetherApp", dependencies: ["AetherHumanUI", "BrowserEngine", "EngineRuntime", "EngineCore", "AgentProtocol", "Graphics", "Display", "DOM", "Media", "ContentBlocker"], exclude: ["Resources"]),
    .testTarget(name: "AetherHumanUITests", dependencies: ["AetherHumanUI"], path: "Sources/BrowserUI/Tests/AetherHumanUITests", swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "HumanIntegrationTests", dependencies: ["AetherApp", "EngineRuntime", "EngineCore", "AetherHumanUI"]),
    .target(name: "EngineCore"),
    .target(name: "DOM", dependencies: ["EngineCore"]),
    .target(name: "HTML", dependencies: ["EngineCore", "DOM"]),
    .target(name: "CSS", dependencies: ["EngineCore"]),
    .target(name: "Style", dependencies: ["EngineCore", "DOM", "CSS"]),
    .target(name: "Text", dependencies: ["EngineCore"]),
    .target(name: "Layout", dependencies: ["EngineCore", "DOM", "Style", "Text"]),
    .target(
      name: "Display", dependencies: ["EngineCore", "DOM", "Layout", "Style", "CSS", "Images"]),
    .target(name: "Graphics", dependencies: ["EngineCore", "Display", "Images"]),
    .target(name: "AetherNetworkHardening", path: "Sources/EngineAdditions/Sources/AetherNetworkHardening"),
    .target(name: "Networking", dependencies: ["EngineCore", "AetherNetworkHardening", "ContentBlocker"]),
    .target(name: "Images", dependencies: ["EngineCore", "Networking"]),
    .target(name: "JavaScript", dependencies: ["EngineCore", "DOM", "Storage"]),
    .target(
      name: "WebAPI",
      dependencies: ["EngineCore", "DOM", "Networking", "JavaScript", "Storage", "Media"]),
    .target(name: "Storage", dependencies: ["EngineCore"]),
    .target(name: "Media", dependencies: ["EngineCore", "DOM"]),
    .target(name: "Persistence", dependencies: ["EngineCore"]),
    .target(name: "WebSecurity", dependencies: ["EngineCore"]),
    .target(name: "ContentBlocker"),
    .target(name: "Scheduler", dependencies: ["EngineCore"]),
    .target(name: "Diagnostics", dependencies: ["EngineCore"]),
    .target(
      name: "Navigation",
      dependencies: [
        "EngineCore", "Networking", "HTML", "DOM", "CSS", "Style", "Layout", "Display", "Graphics",
        "Storage", "JavaScript", "WebAPI", "Diagnostics", "Images", "WebSecurity",
        "AetherNetworkHardening", "ContentBlocker",
      ]),
    .target(name: "AgentProtocol", dependencies: ["EngineCore"]),
    .target(name: "AetherCapture", path: "Sources/NativeCapture/Sources/AetherCapture"),
    .target(
      name: "EngineRuntime",
      dependencies: [
        "EngineCore", "DOM", "Navigation", "Graphics", "Storage", "Scheduler", "Diagnostics",
        "Networking", "JavaScript", "Style", "Layout", "Display", "WebSecurity", "Persistence",
        "CSS", "WebAPI", "AetherCapture", "Media", "ContentBlocker",
      ]),
    .target(
      name: "BrowserEngine",
      dependencies: [
        "EngineCore", "DOM", "AgentProtocol", "EngineRuntime", "Graphics", "Diagnostics",
        "AetherCapture", "Media",
      ]),
    .executableTarget(
      name: "browserctl",
      dependencies: ["BrowserEngine", "AgentProtocol", "EngineRuntime", "AetherCapture"]),
    .executableTarget(name: "browserd", dependencies: ["BrowserEngine", "AgentProtocol"]),
    .executableTarget(
      name: "enginebench",
      dependencies: ["BrowserEngine", "HTML", "CSS", "Style", "Layout", "Text"],
      path: "Benchmarks/enginebench"),
    .testTarget(name: "HTMLTests", dependencies: ["HTML", "DOM"]),
    .testTarget(name: "CSSTests", dependencies: ["CSS", "DOM", "HTML", "Style"]),
    .testTarget(name: "DOMTests", dependencies: ["DOM"]),
    .testTarget(
      name: "LayoutTests", dependencies: ["HTML", "CSS", "Style", "Layout", "Text", "DOM"]),
    .testTarget(
      name: "RenderingTests",
      dependencies: [
        "HTML", "CSS", "Style", "Layout", "Text", "Display", "Graphics", "DOM", "Images",
      ]),
    .testTarget(name: "NetworkTests", dependencies: ["Networking"]),
    .testTarget(name: "NetworkHardeningIntegrationTests", dependencies: ["AetherNetworkHardening"]),
    .testTarget(
      name: "AgentTests",
      dependencies: [
        "BrowserEngine", "AgentProtocol", "EngineCore", "EngineRuntime", "DOM", "AetherCapture",
      ]),
    .testTarget(
      name: "PerformanceTests", dependencies: ["HTML", "CSS", "Style", "Layout", "Text", "DOM"]),
    .testTarget(name: "JavaScriptTests", dependencies: ["JavaScript", "HTML", "DOM", "Storage"]),
    .testTarget(name: "MediaTests", dependencies: ["Media", "EngineCore", "DOM", "HTML"]),
    .testTarget(name: "WebAPITests", dependencies: ["WebAPI", "JavaScript", "Networking"]),
    .testTarget(name: "StorageTests", dependencies: ["Storage", "EngineCore"]),
    .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
    .testTarget(name: "SecurityTests", dependencies: ["WebSecurity"]),
    .testTarget(
      name: "BlockerTests",
      dependencies: ["ContentBlocker", "Navigation", "Networking", "EngineCore", "HTML", "DOM", "CSS", "Style", "Diagnostics"]),
    .testTarget(
      name: "AetherCaptureTests",
      dependencies: ["AetherCapture"],
      path: "Sources/NativeCapture/Tests/AetherCaptureTests"),
  ],
  swiftLanguageModes: [.v6]
)
