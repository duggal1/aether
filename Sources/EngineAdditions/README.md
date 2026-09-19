# Aether Engine Additions

An additive Swift 6.2 source drop for the custom Aether browser engine. No Chromium, WebKit, Tauri, Rust, frontend, or inference provider. No existing Aether source file is copied or overwritten.

Read `AgentConnection.md` before moving source files. Read `AgentHandoff.md` before claiming completion.

The Package.swift here exists only to independently build and test these additions. Do NOT replace the main Aether Package.swift with it. The Mac-only Metal implementation is conditionally compiled, and has not been verified on macOS in this environment.

```bash
swift build -c release
swift test
```

Copy only new Sources/Aether* directories and desired Tests/AetherAdditionsTests files into the live repository, merge their target declarations into its manifest, and connect the real runtime using `AgentConnection.md`. Do not blindly copy its Package.swift.

This drop is useful tested code and a handoff, not completion of full ECMAScript, browser security isolation, the production compositor, or Web Platform APIs.
