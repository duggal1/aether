# Roadmap

## Engine 0: implemented foundation

The repository currently implements the complete architectural path needed to continue as an independent engine: core identifiers and geometry, DOM storage, streaming HTML tokenization/tree construction, CSS parsing and style computation, block/inline/basic flex/grid layout, form-control intrinsic sizing, display lists, offscreen rendering, an initial Metal path, image decoding/loading, networking, cache/cookies, contexts, navigation/history/forms, a compact JavaScript runtime, DOM/event/localStorage bindings, structured agent inspection/control, local socket transport, CLI, diagnostics, tests, fixtures, and benchmarks.

## Engine 1: standards and incremental correctness

- WHATWG-compatible HTML insertion modes, foster parenting, templates, foreign content, encoding behavior, and adversarial parser fixtures
- Broader selectors, pseudo-classes/elements, specificity edge cases, cascade layers, custom properties, modern color/value syntax, media/container queries
- Stronger intrinsic sizing, full flex/grid algorithms, tables, replaced elements, floats, fragmentation, sticky positioning, scrolling and overflow behavior
- Substantially broader ECMAScript syntax/semantics, garbage collection, modules, promises/microtasks, typed arrays, streams, fetch bindings, mutation observers, richer DOM/event APIs
- Incremental style, layout, paint, resource, and compositor invalidation using the existing mutation/version boundaries
- Better image sizing/decoding lifecycle, responsive images, fonts, form controls, focus/selection, clipboard, file upload, downloads, permissions, CSP, CORS, and origin enforcement

## Engine 2: production runtime and accelerated compositor

- Renderer-process isolation and macOS sandbox profiles before hostile-content claims
- GPU tiles, texture atlases, image textures, glyph atlases, clip/transform stacks, async upload, damage-driven Metal compositing, GPU scrolling and animations
- Page freezing/discard/restore and bounded renderer pools for large agent fleets
- Canvas 2D, WebAssembly, workers, WebSockets, service workers, media, hardware video decode, WebAudio, WebGL/WebGPU
- Persistent cache/storage, certificate policy, downloads, accessibility tree depth, automation-safe file/permission handoff

## Engine 3: compatibility tail

- Web-platform conformance suites at scale
- Advanced typography, international text, IME, printing, accessibility parity, WebRTC, DRM integration where legally/platform-available
- Exploit containment, fuzzing, security review, renderer crash recovery, production lifecycle management
- Compatibility and performance qualification against representative modern web applications

No phase requires adding a browser chatbot or cloud control plane. AI agents remain external decision-makers controlling the engine through native local primitives.
