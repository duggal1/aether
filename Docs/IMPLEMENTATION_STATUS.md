# Implementation Status

This file prevents architectural progress from being confused with web-platform completeness.

| Area | Current state |
| --- | --- |
| Engine core | Implemented foundation |
| HTTP networking | Implemented basic HTTP/HTTPS path with cookies/cache |
| HTML | Streaming tokenizer/tree builder; incomplete WHATWG edge-case coverage |
| DOM | Mutable generational tree, selectors, snapshots, mutation journal |
| CSS | Tokenizer/parser/cascade/basic selector and computed-style coverage |
| Layout | Block/inline/basic flex/grid/positioning/form intrinsic sizing |
| Text | CoreText path on Apple plus deterministic fallback measurement/rendering |
| Images | Concurrent discovery/load; ImageIO decoding on Apple; display-list/offscreen compositing |
| Display | Rect/text/image/clip commands with dirty-region representation |
| Metal | Native macOS foundation; not yet production compositor parity |
| JavaScript | Custom interpreter with functions/closures/classes/modules/promises/microtasks/typed arrays/BigInt/RegExp/JSON; DOM/events/localStorage; setTimeout/setInterval/fetch/Headers/Request/Response wired through host-provided timer and network bridges; far from ECMAScript-complete |
| Timers/fetch | Deterministic timer pump and promise-based fetch with text/json/arrayBuffer bodies; page scripts execute on navigation with timers pumped; no streaming bodies, workers, WebSockets, or Canvas yet |
| Forms | Basic values, checkbox/radio behavior, GET/POST submission |
| Navigation | Load, reload, history back/forward, resizing |
| Durable state | Per-context SQLite profile (cookies, history, permissions, localStorage, cache metadata, checkpoints) with content-addressed disk blobs; hot paths stay in memory |
| Agent runtime | Context/page lifecycle with active/background/suspended/frozen/discarded states, fleet sweep, loadHTML headless path, inspect/query/snapshot/wait/mutations, hover/focus/blur/scroll/hit-testing/keyboard/select/fill/submit, history/console/network-log/frames, cookies/storage/permissions/dialogs/downloads/sessions, profile persistence via SQLite + content-addressed blobs |
| Headless | Implemented through same page/runtime model |
| Native capture | Engine-native page capture (AetherCapture target) over isolated contexts: natural scroll passes, scrolled-viewport software raster tiles, live-DOM HTML/CSSOM snapshot with selector/role/bounds/computed styles, cache-only asset bytes, privacy redaction, manifest warnings; exposed as page.capture and browserctl capture; WebP subject to ImageIO encoder availability with JPEG fallback |
| Process isolation | Not implemented |
| Production sandbox | Not implemented |
| Canvas/WebAssembly/workers | Not implemented |
| WebGL/WebGPU | Not implemented |
| Media/WebRTC/DRM | Not implemented |
| Service workers | Not implemented |
| Full accessibility/IME | Not implemented |

The correct next move is to deepen standards, isolation, invalidation, and compositor correctness without replacing the architecture with Chromium/WebKit wrappers.
