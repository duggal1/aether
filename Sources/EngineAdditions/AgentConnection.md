# AgentConnection: connect the additions to the CURRENT Aether repository

> **Current repository status (September 19, 2026):** This document describes the original add-on integration candidates. The real, reviewed implementation and macOS verification results are now in `Docs/ADDITIONS_INTEGRATION.md` at the repository root. Existing runtime, persistence, capture, fleet and graphics owners remain authoritative. Only non-duplicative network hardening was adopted as an active new module; do not install remaining add-on modules just to inflate integration statistics.

## First: read this accurately

This ZIP is an additive Swift source drop, not a patched copy of the current Aether repository. The only repository archive available during generation was the older Engine 0 ZIP; the later four-agent source changes were described in messages but were not supplied as files. There are no edits to your current `EngineRuntime`, `NavigationPipeline`, `Package.swift`, `CookieJar`, JavaScript runtime, or coworker-owned modules here. Do not blindly overwrite those files. Build and test the current Aether repo first, then integrate one small boundary at a time.

`Package.swift` in THIS ZIP exists only to build the additions in isolation. **Do not replace Aether's own Package.swift with it.** Copy `Sources/Aether*` modules into Aether's `Sources/`, add their targets/dependencies to Aether's existing manifest, and merge test files into a new `AetherAdditionsTests` target. This leaves all existing modules intact.

## The ownership and wiring contract

| New module | Read existing work first | Actual integration point | Do not replace |
|---|---|---|---|
| AetherResourceControl | Agent 4 `Scheduler/FleetScheduler.swift`, Agent 2 `Graphics/ResourceBudget.swift` and `Display/ImageMemoryPolicy.swift` | Translate live page estimates into `FleetPage`; use `FleetPolicy.plan` as advisory and apply changes via `EngineRuntime`'s real lifecycle functions; use `ConcurrencyGate` for heavy independent jobs; use `ResourceLedger` only for resources that have no existing owner | Existing fleet state machine, GPU budget ledger |
| AetherAgentInfrastructure | Agent 4 `EngineRuntime`, `BrowserEngine/AgentCommandDispatcher.swift`, `AgentProtocol`, `browserd`, CLI | Put session ownership validation at the external request boundary. Explicitly map actual supported method strings to `CommandAccessPolicy`. Call `AgentGateway.execute` with a closure that delegates to the existing dispatcher. Emit real operation events to `EventJournal`. | Existing AgentMethod enum or command dispatcher |
| AetherNetworkHardening | Agent 1 `WebSecurity`, `Navigation/NavigationPipeline.swift`, `Networking` | Apply HSTS before request and redirect dispatch; use HTTP freshness for cache validation; use `ResponseContentGuard` for script/style responses; apply `ReferrerPolicy` when constructing requests; sanitize download filenames before persistence | Agent 1 CSP/CORS/origin policy, cookie jar, existing cache storage |
| AetherWebPrimitives | Agent 3 JS/event loop/Fetch/workers/streams | Use `BoundedByteStream` for bounded streaming body handoff; call `MicrotaskCheckpoint.run()` at the existing event-loop microtask checkpoint only if Agent 3 has not already implemented a compliant job queue; use `MessageChannel` as an internal transport, not a substitute for standards structured clone | Agent 3 JS interpreter, promise machinery or worker APIs |
| AetherRenderInfrastructure | Agent 2 Layout/Display/Graphics/Diagnostics | Use `PageCapturePlan` in a real headless capture operation, scrolling the same live page and collecting output; populate manifest from actual resource outcomes; `RenderFrameJournal` can expose real frame revisions to agents | Existing compositor, tile caches, frame scheduler |
| AetherMetalBackend | Agent 2 Metal renderer and display-list path | Convert existing display commands into `MetalQuad` for narrow offscreen tests; use `MetalOffscreenRenderer` only where it improves the existing renderer; profile and replace shader runtime compilation with an offline metallib once supported by deployment | Agent 2 production compositor / UI renderer |

## One-way target dependencies

```text
AetherResourceControl
AetherAgentInfrastructure -> AetherResourceControl
AetherNetworkHardening
AetherWebPrimitives
AetherRenderInfrastructure
AetherMetalBackend -> AetherRenderInfrastructure
```

Example *target entries* to merge inside the current `Package.swift` `targets` array:

```swift
.target(name: "AetherResourceControl"),
.target(name: "AetherAgentInfrastructure", dependencies: ["AetherResourceControl"]),
.target(name: "AetherNetworkHardening"),
.target(name: "AetherWebPrimitives"),
.target(name: "AetherRenderInfrastructure"),
.target(name: "AetherMetalBackend", dependencies: ["AetherRenderInfrastructure"]),
.testTarget(name: "AetherAdditionsTests", dependencies: [
    "AetherResourceControl", "AetherAgentInfrastructure", "AetherNetworkHardening",
    "AetherWebPrimitives", "AetherRenderInfrastructure"
]),
```

Then add only the dependencies each ORIGINAL target actually imports. Example: `BrowserEngine` may gain `AetherAgentInfrastructure`, `Navigation` may gain `AetherNetworkHardening`, and `Graphics` may gain `AetherMetalBackend`. **Do not create circular imports.** If `Graphics -> AetherMetalBackend -> AetherRenderInfrastructure`, do not import `Graphics` into either additions module.

## Security-critical ordering

1. Start with the existing session owner/context isolation gate. Never allow an agent session to implicitly inherit the human profile.
2. Validate the concrete method against `CommandAccessPolicy`; unknown commands fail closed.
3. Require matching session generation and owner at the IPC entry point. A caller-provided owner field is not authentication: bind identity to an OS-authenticated Unix-socket peer or an explicitly approved local capability, rather than accepting an arbitrary JSON owner string.
4. Apply existing origin/CSP/CORS/permissions restrictions to the same operation no matter whether the caller is a human, JS, or an agent. Agent APIs should not silently bypass website security boundaries.
5. Apply HSTS to redirects too. Respect preloaded and persisted HSTS once implemented. HSTSRegistry in this ZIP is a bounded dynamic rule store, not a complete RFC 6797 implementation.
6. Use existing persistence. No new SQLite actor or second profile database. Reuse the agent coworker's `SQLiteStore`, `ProfileStore` and content-addressed cache.

## Rendering integration

1. Run the current real navigation/render benchmarks before any switch.
2. Use Agent 2's `FramePipelineState`, `RetainedCompositor`, `FrameRecorder`, `TileCache` and budgets. The newly added frame journal is an OBSERVABILITY consumer, not a second compositor.
3. Do not run image decode or synchronous GPU readback on an interaction-critical path. `MetalOffscreenRenderer.render` waits for completion because it produces raw pixels for a headless output, not because that is suitable for normal presentation.
4. Render frames through existing layout/display list output. `PageCapturePlan` only computes scroll coordinates and image crops: it does not capture screenshots or load websites by itself.
5. Run macOS hardware integration, resource-pressure tests and visual reference tests on the actual Apple Silicon machine.

## Required integration checks

```bash
swift build -c release
swift test
swift run enginebench
```

Then run the *existing* browserd/browserctl commands in the actual repo. Verify real navigation, page JS, human/agent shared session, headless renders, cookies across profiles, CORS/CSP denial, network errors, downloads, and at least two concurrent agent owners. A green add-on package test is NOT proof of a working macOS web engine.

## Never create duplicate subsystems merely to consume this ZIP

If a coworker already built an equivalent scheduler, renderer memory ledger, script job queue, profile database, security policy or event journal, **integrate behavior into that code and delete the redundant new module/file rather than maintaining two live implementations**. The additions are candidates, not orders to replace objectively better existing work.
