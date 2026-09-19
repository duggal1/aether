# NativeBrowserEngine

NativeBrowserEngine is a Swift-first, Apple-native browser-engine foundation with no browser frontend. It owns the pipeline from network bytes to DOM, CSS, computed style, layout, display lists, image/text rasterization, navigation state, JavaScript execution, browser contexts, and structured local agent control.

The project deliberately does not use Chromium, WebKit, Tauri, Rust, React, Electron, or a webview. macOS builds use native Apple frameworks where they are the correct systems primitive: Metal for GPU rendering work, CoreText/CoreGraphics for text, ImageIO for image decoding, Foundation/Network system facilities for transport, and Swift concurrency for asynchronous orchestration.

This is a serious Engine 0 implementation, not a claim of Chrome- or Safari-class web-platform completeness.

## Build

Requires Swift 6.2 or newer. The package targets macOS 15 or newer for the native product path.

```bash
swift build -c release
swift test
```

Run the benchmark harness:

```bash
.build/release/enginebench
```

## Headless use

Render and inspect directly without a frontend:

```bash
.build/release/browserctl inspect https://example.com
.build/release/browserctl render https://example.com /tmp/example.png 1280 800
.build/release/browserctl eval https://example.com 'document.title'
.build/release/browserctl shell https://example.com
```

Run the persistent local agent daemon:

```bash
.build/release/browserd --socket /tmp/native-browser-engine.sock
```

Then create isolated contexts and pages through the same engine:

```bash
.build/release/browserctl --socket /tmp/native-browser-engine.sock context-create work
.build/release/browserctl --socket /tmp/native-browser-engine.sock page-open work https://example.com
```

The daemon speaks newline-delimited JSON over a Unix-domain socket. Agents operate on stable DOM node identifiers, semantic roles, values, bounds, mutations, snapshots, navigation history, JavaScript, storage-backed page state, and rendering rather than relying on screenshots and guessed coordinates.

## Implemented foundation

- Typed engine, context, page, navigation, document, request, and generational DOM identifiers
- Streaming HTML tokenization and tree construction with raw-text handling
- Compact mutable DOM with mutation journaling, snapshots, semantic inspection, and selector queries
- CSS tokenization/parsing, cascade, computed style, basic selectors, inheritance, and viewport-aware lengths
- Block, inline, basic flex, basic grid, positioning, overflow foundations, text measurement, and intrinsic form-control sizing
- Display lists with rectangles, text, clipping, decoded images, dirty regions, and z-ordering
- Deterministic offscreen rasterization and a native macOS Metal path
- Concurrent stylesheet/image loading, ordered script loading, cookies, bounded HTTP cache, and isolated network sessions
- ImageIO/CoreGraphics decoding on Apple platforms
- Basic JavaScript interpreter with functions, closures, arrays/objects, DOM bindings, events, bubbling, `preventDefault`, and origin-partitioned `localStorage`
- Navigation history, reload, forms, GET/POST submission, checkboxes/radios, links, typing, resizing, snapshots, waits, and mutation polling
- Browser contexts partitioning cookies, storage, pages, and future permission state
- Local agent protocol, persistent daemon, CLI, metrics, fixtures, tests, and benchmark harness

## Deliberate limits

Modern browsers represent decades of standards and security work. This repository does not pretend otherwise. Full WHATWG tree-construction behavior, complete ECMAScript, advanced CSS, process isolation, production sandboxing, composited text/image Metal rendering, media, Canvas, WebAssembly, workers, WebSockets, service workers, WebGL/WebGPU, WebRTC, DRM, accessibility depth, IME, and the compatibility tail remain continuation work.

Do not use the current Engine 0 to execute hostile web content as though it had production browser sandboxing. Read `SECURITY.md`, `Docs/ARCHITECTURE.md`, `Docs/IMPLEMENTATION_STATUS.md`, and `HANDOFF.md` before extending the engine.
