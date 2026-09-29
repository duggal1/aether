# Architecture

> [!WARNING]
> **This document describes the original custom engine and is stale.** That engine is being retired in favour of system WebKit (`WKWebView`). The module layering below still describes the code that exists on disk, but the rendering path (`SoftwareRenderer`/`MetalRenderer`), the `JSRuntime`, and the headless rendering targets are **not** the current website-rendering path. Read `Docs/WEBKIT.md` for what actually renders pages, and `work/plan/backend/retire-custom-engine.md` for the migration status. Where the two disagree, the WebKit path is live.

NativeBrowserEngine is a frontend-independent engine. A future macOS browser shell, `browserctl`, `browserd`, tests, and local coding agents are clients of the same runtime rather than separate browser implementations.

## Dependency direction

The package keeps dependencies mostly one-way:

```text
EngineCore
├── DOM ── HTML
├── CSS ── Style
├── Text ── Layout
├── Networking ── Images
├── Storage
├── Persistence
├── JavaScript
├── WebSecurity
├── Scheduler
└── Diagnostics

DOM + Style + Layout + Images
            ↓
         Display
            ↓
         Graphics
            ↓
        Navigation
            ↓
       EngineRuntime
            ↓
       BrowserEngine
            ↓
   browserctl / browserd
```

`AgentProtocol` models transport messages only. It does not own browser state. `BrowserEngine` is the stable facade over `EngineRuntime`.

## Navigation and rendering

The primary path is:

```text
HTTPRequest
    ↓
NetworkSession
    ↓
HTML bytes
    ↓
HTMLTokenizer + HTMLTreeBuilder
    ↓
DOMDocument
    ↓
ResourceDiscovery
    ├── stylesheets ─┐
    ├── images ──────┼── concurrent resource loading
    └── scripts ─────┘   ordered execution semantics retained
    ↓
StyleResolver
    ↓
LayoutEngine
    ↓
DisplayListBuilder
    ↓
SoftwareRenderer / MetalRenderer
```

The DOM uses generational `NodeID` values backed by compact slot storage. Removing and reusing a slot invalidates stale identifiers rather than silently pointing them at unrelated nodes. Mutation versions and a bounded journal make structured incremental agent observation possible.

## JavaScript

`JSRuntime` is owned per loaded page. Document scripts execute against the same runtime that later receives agent evaluation and DOM events. DOM wrappers carry native node identifiers rather than translating through screen coordinates.

The current interpreter is intentionally compact and incomplete. Its boundary is explicit so bytecode, better garbage collection, JIT work, WebAssembly, and broader ECMAScript/Web API coverage can be added without coupling JavaScript to layout or browser UI.

## Browser contexts

A `BrowserContext` owns an isolated network session, cookie jar, HTTP cache, origin-partitioned storage, and pages. Pages own navigation history, loaded document state, JavaScript runtime, viewport, layout, and display state.

This gives human profiles and agent namespaces the same primitive without creating a second automation architecture.

## Agent control

Agents address contexts, pages, and DOM nodes directly. Core operations include inspection, snapshots, selector queries, navigation, history, waiting, mutation retrieval, input, click/default form behavior, JavaScript evaluation, rendering, resizing, and metrics.

Pixels remain available when visual reasoning is actually required. They are not the primary control protocol.

## Rendering targets

Headless and future visible rendering share display-list generation. The current offscreen renderer produces deterministic pixel buffers for tests and agents. macOS has a Metal renderer foundation for GPU raster/composition work. A future window target should attach Metal output to a `CAMetalLayer` without moving page state into AppKit or SwiftUI.

## Performance model

The preferred optimization order is: avoid work, reuse work, invalidate narrowly, parallelize independent work, then move appropriate raster/compositing work to the GPU. Parser/layout state stays on CPU where dependency-heavy branchy work belongs.

The current engine already tracks DOM mutation versions and display dirty regions, but production incremental style/layout/paint/compositor invalidation is still continuation work.
