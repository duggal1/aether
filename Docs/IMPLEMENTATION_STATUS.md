# Implementation Status

This file prevents architectural progress from being confused with web-platform completeness.

Classification: **wired** = implemented and exercised in the live root-package path with tests; **incomplete** = implemented but with known gaps; **source-only** = source exists but is excluded from the live root package or unused by callers; **unsupported** = not implemented. Nothing in the engine is qualified as "tested on real sites"; the only real-network evidence is smoke-level navigation and evaluation against trivial public pages.

| Area | Classification | Current state |
| --- | --- | --- |
| Engine core | wired (incomplete) | Identifiers, geometry, buffers, dirty regions; foundation exercised by every pipeline test |
| HTTP networking | wired (incomplete) | Basic HTTP/HTTPS via URLSession with hardened cache freshness, cookies, HSTS-on-navigation; no conditional revalidation, variant keys, or full redirect-policy coverage |
| HTML | wired (incomplete) | Streaming tokenizer/tree builder with raw text, implicit closes, foster parenting, templates; not WHATWG-complete, no adversarial conformance corpus |
| DOM | wired (incomplete) | Mutable generational tree, selectors, snapshots, mutation journal; no shadow trees, no ranges |
| CSS | wired (incomplete) | Tokenizer/parser/cascade/basic selectors and computed styles; no pseudo-elements, container queries, custom-property full resolution |
| Layout | wired (incomplete) | Block/inline/basic flex/grid/positioning/form intrinsic sizing; no tables, floats, fragmentation, sticky |
| Text | wired (incomplete) | CoreText on Apple plus deterministic fallback; no shaping-intensive scripts |
| Images | wired (incomplete) | Concurrent discovery/load, ImageIO decode on Apple; display-list/offscreen compositing |
| Display | wired (incomplete) | Rect/text/image/clip commands with dirty regions; retained-tile and chunk invalidation primitives exist but are not the live repaint path |
| Metal | wired (minimal) | Foundation exists; the live render path is `SoftwareRenderer`, and `MetalRenderer` is not production compositor parity |
| JavaScript | wired (incomplete) | Custom interpreter: functions/closures/classes/modules/promises/microtasks/typed arrays/BigInt/RegExp/JSON, DOM/events/localStorage bindings, timers/fetch bridges. This pass fixed: unary minus never negating, top-level lexical declarations not persisting across evaluations, microtask checkpoints around evaluation, and Int64-range overflow traps in number→string/BigInt comparisons. Still far from ECMAScript-complete; no GC specification beyond reference lifetime, no streams/workers |
| Timers/fetch | wired (incomplete) | Deterministic timer pump and promise-based fetch with text/json/arrayBuffer bodies; no streaming bodies, AbortController, WebSocket, workers |
| Forms | wired (incomplete) | Basic values, checkbox/radio behavior, GET/POST submission |
| Navigation | wired (incomplete) | Load, reload, history back/forward, resizing, scheme/mixed-content/CORS guards; hostile-navigation hardening is partial |
| Durable state | wired (incomplete) | Per-context SQLite profile (cookies, history, permissions, localStorage, cache metadata, checkpoints) with content-addressed disk blobs; recovery under corruption/real workloads unproven |
| Agent runtime | wired (incomplete) | 76-method dispatcher over Unix socket, context/page lifecycle with active/background/suspended/frozen/discarded states, fleet sweep, inspect/query/snapshot/wait/mutations, hover/focus/blur/scroll/hit-testing/keyboard/select/fill/submit, history/console/network-log/frames, cookies/storage/permissions/dialogs/downloads/sessions, profile persistence. This pass fixed: null results now serialize as `"result": null` on the wire (they previously vanished), and responses round-trip losslessly through `browserctl`. `page.workers` returns an empty list by design until workers exist. No authenticated multi-owner IPC yet |
| Headless | wired (incomplete) | Same page/runtime model, loadHTML path, offscreen rendering |
| Native capture | wired (incomplete) | Engine-native page capture (AetherCapture) over isolated contexts: scroll passes, scrolled-viewport software raster tiles, live-DOM/CSSOM snapshot, cache-only assets, privacy redaction, manifest warnings; WebP subject to ImageIO encoder availability with JPEG fallback. Real-site visual parity unproven |
| `Sources/EngineAdditions` | source-only | Only `AetherNetworkHardening` is a live root-package target; the other addition modules deliberately remain uninstalled (see `Docs/ADDITIONS_INTEGRATION.md`) |
| Process isolation | unsupported | Not implemented |
| Production sandbox | unsupported | Not implemented |
| Canvas/WebAssembly/workers | unsupported | Not implemented |
| WebGL/WebGPU | unsupported | Not implemented |
| Media/WebRTC/DRM | unsupported | No integrated video pipeline or content-blocking target |
| Service workers | unsupported | Not implemented |
| Full accessibility/IME | unsupported | Not implemented |

The correct next move is to deepen standards, isolation, invalidation, and compositor correctness without replacing the architecture with Chromium/WebKit wrappers.
