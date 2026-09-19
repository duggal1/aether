# AgentHandoff: truthful implementation report for the next coding agent

> **Updated after the integration:** Read `Docs/ADDITIONS_INTEGRATION.md` first. The original handoff below documents the ZIP as initially generated; the repository has since integrated network hardening into the real SwiftPM graph, corrected capture and disk-cache defects and validated a native macOS release build, targeted network tests and benchmark. The full suite still has 14 existing JavaScript-runtime issues. No production renderer sandbox or complete P0–P2 browser engine has been built.

I created a source-only add-on package that compiles independently under Swift 6.2, with targeted tests and explicit connection instructions. I did NOT finish the entire P0–P2 browser-engine plan, did NOT integrate into the unretrieved four-agent working tree, and did NOT verify macOS Metal or sandbox/process isolation. Do not tell the user otherwise.

## Implemented in this add-on

- `AetherResourceControl`: bounded resource reservations; concurrency admission with cancellation; a policy planner for fleet memory pressure, preserving pinned/pending pages.
- `AetherAgentInfrastructure`: owner-scoped session grants/generation rotation; bounded sequenced event replay; idempotent request recognition; operation state transitions; bounded task mailbox; fail-closed, owner-checked agent command gateway.
- `AetherNetworkHardening`: HTTP cache directives, conditional request headers, dynamic HTTPS HSTS rules, single/multiple byte ranges, download filename sanitation, referrer policies, and no-sniff script/style validation.
- `AetherWebPrimitives`: bounded asynchronous byte stream with backpressure and cancellation; internal message channel; main-actor microtask checkpoint hook. They are integration primitives, NOT a complete Fetch/Streams/Workers/WebSocket/ECMAScript platform.
- `AetherRenderInfrastructure`: bounded full-page screenshot scroll/crop planner, frame revision journal, explicit design extraction manifest that records missing assets and warnings. This is NOT an image encoder, a website parser, or a screenshot implementation.
- `AetherMetalBackend`: custom Metal offscreen textured/color quad raster path under `#if canImport(Metal)`; clear, clip, tint and output raw RGBA. It is NOT a production retained compositor or renderer isolation layer. The Metal-specific code has not been compiled or tested on macOS in this environment.
- 28 independent Swift unit tests passed on Linux using Swift 6.2.1. The macOS Metal branch was excluded by conditional compilation. These tests do not prove end-to-end compatibility with the updated Aether repository.

## Your mandatory first tasks

1. Read `AgentConnection.md` and the actual CURRENT source tree, especially the Agent 1–4 changes. Stop if the current source is missing; request it rather than invent integration APIs.
2. Build the real current repository. Repair existing integration breakages without reverting valid coworker work. Add the new targets only where needed; do not overwrite Aether's `Package.swift`.
3. Review every new module for redundant overlap. Favor the existing coworkers' implementations and delete unnecessary add-ons.
4. Add verified authorization at Unix-socket peer / local capability boundary. A JSON owner field is not proof of identity. Existing browser permission/security policies must still apply to agent requests.
5. Connect networking policies before sending requests and after redirects; test all relevant redirects, cookie rules and content restrictions. HSTS must eventually persist and include preload semantics.
6. Wire the EXISTING Agent 2 rendering pipeline to live pages; use this ZIP's Metal path only for narrow offscreen tests or when performance profiling shows it helps. Test on macOS and fix platform compilation errors.
7. Hook the byte stream/microtask primitives only if Agent 3 does not already have correct equivalents. The complete JS/Web API implementation is still an independent large project.
8. Add actual full-page captures and design extraction on top of live headless navigation, not just a manifest and scroll planner.
9. Run standards, integration, security, memory pressure and macOS GPU tests. Measure before declaring performance improvements.

## Large remaining engine work, deliberately not disguised as done

P0: real sandboxed renderer processes and origin isolation; browser-complete JS parser/runtime/GC/promises/modules/DOM bindings; fully integrated Metal tiles/glyph/image compositor and incremental invalidation; verified combined build and real-site testing.

P1: major WHATWG HTML/CSS/layout conformance, full Fetch/CORS/CSP/cache semantics, standards Streams/WebSocket/workers/IndexedDB, Canvas 2D, media playback, real WASM execution, accessibility, IME, real offscreen/headless execution, drag/drop, uploads/downloads, macOS profile persistence and recovery validation.

P2: WebGL/WebGPU, WebRTC, robust modern-site compatibility, bounded multi-agent load and meaningful low-memory/latency benchmarks on Apple Silicon.

The remaining work above is not something a few standalone Swift files can safely replace. Aether is still an Engine 0 project and must not be described as a Chrome-class replacement. The objective remains a minimal native Swift + Metal browser, for humans and external terminal agents, with one shared engine, not a chatbot or a browser wrapper.
