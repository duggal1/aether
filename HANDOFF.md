# Handoff to the next AI agent

I successfully built the Engine 0 implementation and the hard architectural skeleton. Do not restart this repository, replace it with a wrapper, or collapse it into a monolith. Continue the independent engine that already exists.

The repository already contains typed core identifiers, generational DOM storage, mutation journaling and snapshots, streaming HTML parsing with raw-text handling, CSS/style/layout separation, display lists, text/image offscreen rendering, a native Metal foundation, concurrent resource loading, networking/cookies/cache, navigation/history/forms, browser contexts, a custom JavaScript interpreter, DOM/event/localStorage bindings, diagnostics, local agent protocol, persistent Unix-socket daemon, CLI, fixtures, tests, and benchmarks.

The brutal work left is standards depth, incremental rendering, security isolation, and production GPU composition. Prioritize it in this order:

1. Run `swift test`, a release build, and `enginebench` before changing behavior. Preserve regressions as tests.
2. Expand HTML parsing toward the WHATWG tree-construction algorithm with insertion modes, malformed-markup fixtures, templates, foreign content, foster parenting, encodings, and conformance cases.
3. Deepen CSS selectors/cascade/custom properties and implement substantially more complete flex, grid, tables, positioning, intrinsic sizing, overflow, scrolling, and replaced-element behavior.
4. Turn the JavaScript interpreter into a substantially complete ECMAScript runtime. Add robust GC/runtime semantics, modules, promises/microtasks, typed arrays, and then deepen DOM/events/fetch/streams/Web APIs.
5. Replace broad recomputation after mutations with dependency-driven style invalidation, subtree layout invalidation, display-list damage, retained tiles, and compositor-only updates when possible.
6. Harden navigation, redirects, cookies, origin policy, CORS, CSP, permissions, storage partitioning, focus/selection, files, downloads, and form edge cases.
7. Build renderer-process isolation and a real macOS sandbox boundary before presenting hostile-web execution as safe.
8. Deepen Metal into the production renderer: tiles, texture residency/eviction, image textures, glyph atlases, clip/transform stacks, alpha blending, asynchronous uploads, damage tracking, scrolling, animation, and `CAMetalLayer` presentation for a future UI client.
9. Add page freezing/discard/restore and bounded renderer pools so agent fleets can own many logical pages without keeping every page hot in RAM.
10. Add Canvas, WebAssembly, workers, WebSockets, service workers, hardware media decode, WebAudio, WebGL/WebGPU, accessibility, IME, WebRTC, and other platform features only as clean modules with tests.
11. Continuously run standards fixtures, fuzz parsers/runtime boundaries, profile memory/latency/frame cost, and refuse compatibility claims that lack tests.

Do not add a chatbot, cloud control plane, Chromium, WebKit, Tauri, Rust, React, Electron, or browser UI. The external AI agent decides what to do. This engine is the local deterministic instrument it controls.

Keep `AGENTS.md` as the operating contract. Preserve small public APIs, one-way dependencies, bounded state, structured agent primitives, and truthful scope. The architecture is already here; your job is to do the ugly standards/security/performance work rather than invent another skeleton.
