<!-- INIT-RULES:START — do not remove this marker. Managed by `init rules`. -->
> [!IMPORTANT]
> **Strictly and forcefully read `./RULES.md` BEFORE doing anything else — and stay fully aligned with it for the entire task.**
>
> **Scope: RULES.md applies to real, complex work — especially complex back-end work (features, architecture, database/migrations, security, performance, infrastructure, difficult debugging, cross-system changes, and anything where testing/verification is part of the core workflow). This is mandatory there — no skipping.**
>
> **Out of scope: do NOT apply RULES.md ceremony to super-simple front-end minor edits, small code edits, typo/copy fixes, trivial styling tweaks, or other tiny low-risk changes. For those, just inspect → edit → verify.**
<!-- INIT-RULES:END -->

# AGENTS.md — Aether Engine: Operating Contract + Codebase Snapshot

This file is the fastest correct path into this repository. It describes **the code that exists**, not the code we wish existed. `TODO.md` holds the work plan, `RULES.md` holds the process, `DESIGN.md` owns every native UI decision, `ENHANCE-DESIGN.md` owns the UI polish pass, `HANDOFF.md` holds the previous agent's handoff, `Docs/` holds deeper protocol/architecture notes.

Snapshot basis: `Package.swift` + all of `Sources/` — 128 Swift files, ~28,650 lines. All numbers below were counted from the files, not estimated.

## 0. What this project is

One native macOS browser, two first-class users. Humans get an exceptionally clean, fast browser. Terminal AI agents (Codex, Claude Code, OpenCode) get a programmable execution environment with the same engine underneath.

**The agent owns its sessions. The browser is an execution environment, not the agent's supervisor.**

No Chromium, Electron, Tauri, Rust, React, or Cloud control plane. Apple frameworks are used where they are the correct systems primitive: **system WebKit** (`WKWebView`), Metal, CoreText/CoreGraphics, ImageIO, Foundation/Network, Swift structured concurrency. See `Docs/WEBKIT.md`.

Current honest state: **WebKit-backed agent runtime, mid-migration.** The app and the agent control plane run on system WebKit. An 85-method local agent protocol, page lifecycle management, profiles, credentials, and capture are live. The original from-scratch engine (`HTML`/`CSS`/`Layout`/`JavaScript` custom pipeline) is being retired in favour of WebKit — see `work/plan/backend/retire-custom-engine.md` for the classification and step status. It is **not** a hardened sandbox for hostile content: renderer-process isolation and a production macOS sandbox profile are not implemented (`Docs/IMPLEMENTATION_STATUS.md`).

> **Migration boundary:** the standalone `.experimental` backend is still the default for engine-library clients, fixtures and research. The app adapter selects `.webKit`. Both paths share `AgentProtocol`, `NodeID` identity, and `BrowserRuntime`. This is an explicit, documented boundary — not a claim that the custom engine supports the modern web.

## 0.1 Measured vs designed

The single largest risk in this repository is an unfalsifiable scale claim. Everything below is separated into what has actually been run on a real machine and what is an architectural target. **No claim in this repository may exceed the measured column without saying so.**

| | Measured (reproducible today) | Designed (not yet demonstrated) |
|---|---|---|
| **Concurrent pages** | **8** pages in one daemon | 50–100+; the directive targets hundreds of thousands of workspaces (`Docs/AGENT_CODE_FIRST_BROWSER_DIRECTIVE.md` §9) |
| **Daemon RSS at 8 pages** | **80.9 MiB** (`82816 KiB`) — **excludes all WebKit XPC services** | per-page cost with WebKit services attributed |
| **Runtime fleet caps** | `maxActivePages = 8`, `fleetMemoryBudget = 512 MiB` (`Sources/EngineRuntime/BrowserRuntime.swift:136-137`) | real admission control, sharding, bounded renderer pools (`Docs/ROADMAP.md`, Engine 2 — not started) |
| **Protocol** | 85 methods over a local Unix socket | — |
| **Platform** | macOS 27.0 floor (`Package.swift:6`); all evidence gathered on arm64, 8 CPU / 8 GiB | — |
| **Latency vs headless Chromium** | **Slower.** Aether cold dispatch 746.6 ms / ready 1382.4 ms vs Chrome 240.9 / 570.5 on a 20-site run (`perf-results/headless_20260925_161917/report.md`) | parity |
| **Cold-start cost per workspace** | **Not measured.** No p50/p95/p99 cold-start figure exists. | required by directive §9 |

Evidence files: `agents/codex/webkit-performance/results/local-after.json` (8-page run, RSS, query/snapshot latency), `agents/opencode/perf-baseline/results/baseline-2026-09-21.md` (49.3 MiB daemon RSS with 11+ live pages; notes that WebKit XPC RSS is launchd-owned and machine-wide shared, so it is **not attributable per app**), `perf-results/` (headless latency comparisons).

Two things a reader should not have to discover the hard way:

1. **There is no memory-per-page number and no RSS-vs-concurrency curve.** One 20-worker sweep is recorded in `work/plan/backend/retire-custom-engine.md` (8 workers was the sweet spot; 20 workers collapsed with blocking off, survived with blocking on) and is explicitly flagged as confounded. `agents/agent-native-browser-runtime/testing-agent-2.md:87` states plainly: *"No realistic fleet concurrency, memory-pressure, suspension/resume, or many-workspace benchmark was run. No scale claim is made."*
2. **`fleet.stats` does not measure memory or agents.** It counts pages by lifecycle state and estimates bytes from a formula (`nodeCount*256 + displayCommands*128 + imageBytes + responseBytes`, or a flat 8 MiB per live `WKWebView`). `fleet.pages` and `fleet.sweep` iterate every context and page — an O(fleet) scan, which the directive's own §9.5 forbids on any per-operation path.

## 1. Engineering laws (non-negotiable)

Build the engine as a serious systems project, not a demo.

- Keep the architecture modern, reliable, direct, and simpler than the problem naturally wants to become.
- Do not over-engineer. Every abstraction must earn its existence through correctness, performance, isolation, or reuse.
- Use modularity aggressively. Keep modules cohesive, dependencies one-directional, and public surfaces small.
- Prefer explicit types, deterministic behavior, bounded resource use, and measurable performance.
- Keep source code self-explanatory. Do not add explanatory source comments. Toolchain-required directives are the only exception.
- Treat memory, latency, frame time, and unnecessary work as correctness concerns.
- Prefer structured concurrency and value semantics where they improve clarity. Do not create actors, tasks, allocations, processes, or abstractions merely because they are available.
- Keep agent control native to the engine. Do not bolt automation on through screenshots when structured engine state exists.
- Never hide incomplete behavior behind fake compatibility claims. Implement, test, measure, then expand.
- Preserve the existing architecture unless a measured or correctness-driven reason justifies changing it.

Additional laws specific to this repository:

- **One engine, two faces.** Human UI and agent automation must call the *same* runtime. Never build a second automation path that bypasses `BrowserRuntime`.
- **No AI inference in the browser command path.** Commands are deterministic. The model that decides *what* to do lives outside the engine.
- **Structured state beats pixels.** Screenshots are a fallback for genuinely visual tasks, never the primary control protocol.
- **UI and automation share one runtime.** There is a native SwiftUI/AppKit shell (`AetherHumanUI`) and the agent control plane calls the same `BrowserRuntime` the human UI does. 51 files under `Sources/` import AppKit and 84 import SwiftUI. Off-screen agent pages are hosted in a real borderless `NSWindow` each (`Sources/EngineRuntime/WebKit/OffscreenPageHost.swift`) — this is a correctness requirement, not a UI feature: a `WKWebView` in no ordered window reports `visibilityState === "hidden"` and cannot receive trusted native input.

## 2. Architecture diagrams

### 2.1 Target dependency graph (from `Package.swift`)

Dependencies are strictly one-directional. Arrows mean "imports".

```text
EngineCore  (leaf — geometry, colors, IDs, atoms, buffers, dirty regions)
   │
   ├── DOM ──── HTML
   ├── CSS ──── Style ──
   ├── Text ────────────┴── Layout
   ├── Networking ── Images
   ├── Storage ─────── JavaScript ─ WebAPI
   ├── Persistence
   ├── WebSecurity
   ├── Scheduler
   └── Diagnostics

DOM + Style + Layout + CSS + Images ──→ Display ──→ Graphics

Navigation    = EngineCore + Networking + HTML + DOM + CSS + Style + Layout
                + Display + Graphics + Storage + JavaScript + WebAPI
                + Diagnostics + Images + WebSecurity          (pipeline owner)

EngineRuntime = Navigation + Graphics + Storage + Scheduler + Diagnostics
                + Persistence + JavaScript + CSS + WebAPI + Display + Layout
                (stateful runtime: contexts, pages, fleet, profiles)

AgentProtocol = EngineCore                                    (transport models only)

AetherCapture = no dependencies (nested path target, engine-agnostic)

BrowserEngine = EngineRuntime + AgentProtocol + AetherCapture + Graphics + Diagnostics
                (public facade + JSON command dispatcher)
```

### 2.2 Two interfaces, one runtime

```text
     HUMAN (not built yet)                    AGENT (built)
              │                                   │
              │  SwiftUI / AppKit                 │  browserctl (local, or --socket)
              ▼                                   ▼
     ┌────────────────────┐            ┌──────────────────────────┐
     │ NativeBrowserEngine│            │ browserd (daemon)        │
     │ (facade)           │            │ AgentSocketServer        │
     └─────────┬──────────┘            │ AgentCommandDispatcher   │
               │                       └────────────┬─────────────┘
               └──────────────┬─────────────────────┘
                              ▼
                 BrowserRuntime (actor — single owner of all state)
                              │
        ┌─────────────────────┼──────────────────────┐
        ▼                     ▼                      ▼
   ContextRecord         PageRecord            SessionRecord
   network / storage     loaded / javascript   context grouping
   cookies / profile     history / lifecycle
   permissions           viewport / scroll / focus
```

Both faces must mutate the same `BrowserRuntime`. There is exactly one actor for browser state.

### 2.3 Page load → pixels pipeline

```text
HTTPRequest
  → NetworkSession (actor) ── HTTPCache (actor) ─ CookieJar (mutex)
  → response bytes
  → HTMLParser → HTMLTokenizer (streaming) → HTMLTreeBuilder → DOMDocument
      └ generational NodeID slots + mutation journal + version counter
  → ResourceDiscovery  ──┬─ stylesheets ─┐
                         ├─ images ──────┼─ concurrent load, ordered scripts
                         └─ scripts ─────┘
  → StyleResolver (+ SelectorMatcher, MediaQuery, LayerOrder) → StyledDocument
  → LayoutEngine (block / inline / flex / grid / position / overflow / forms)
      └ LayoutTree of LayoutBox + LayoutFragment, HitTesting for input
  → DisplayListBuilder → DisplayList (rect / text / image / clip commands)
  → SoftwareRenderer  (deterministic RGBA8 — headless + tests)
    MetalRenderer     (macOS only — GPU path foundation)
  → PixelBuffer (+ dirty regions, PaintChunkIndex, TileCache, GlyphAtlas)
```

### 2.4 Agent command path

```text
agent (Codex / Claude Code / OpenCode / any process)
   │  newline-delimited JSON over a Unix-domain socket
   ▼
browserd --socket /tmp/native-browser-engine.sock
   → AgentSocketServer.run { request → AgentCommandDispatcher.handle(request) }
   → switch on AgentMethod (76 methods)
   → BrowserRuntime public API (80 public funcs) or CaptureCoordinator
   → AgentResponse { id, result | error { code, message } }
```

`browserctl` speaks the same protocol over the same socket (79 CLI subcommands) and also has socket-free local commands: `inspect`, `render`, `eval`, `shell`, `capture`, `bench-info`.

### 2.5 Page lifecycle / fleet state machine

```text
active ──► background ──► suspended ─► frozen ──► discarded
   ▲                                                │
   └──────────── restorePage / sweepFleet ◄──────────┘
```

`FleetScheduler.plan(candidates:maxActive:memoryBudgetBytes:now:)` ranks pages (pinned → importance → recency) and returns `.keep/.suspend/.freeze/.discard` per page. Idle > 600 s or ~0 bytes → discard; idle > 120 s → freeze; otherwise suspend. Runtime defaults: `maxActivePages = 8`, `fleetMemoryBudget = 512 MiB`.

### 2.6 Design-capture export pipeline

```text
CaptureCoordinator.capture(url:into:options:)
  → AetherCaptureEngine (implemented by BrowserCaptureEngine in EngineRuntime)
  → AetherCaptureSession (implemented by NativeCaptureSession)
  → scroll pass 1 (load lazy content) → scroll pass 2 (render real viewport tiles)
  → SectionDetector → FullPageAssembler → RasterCropper (overlap removed, coords kept)
  → ResourceCollector + CSSURLScanner (from engine cache — never re-fetched)
  → NativeImageEncoder (WebP if ImageIO offers it, else JPEG; PNG on request)
  → design-reference/
        manifest.json  website.html  computed-styles.json
        styles/*.css   assets/*      sections/*  screenshots/001.jpg …
        design-reference.md
```

## 3. Folder map (every top-level folder)

| Path | What it is | Status |
|---|---|---|
| `Package.swift` | SwiftPM manifest: 23 library targets, 3 executables, 14 test targets, Swift 6 language mode, macOS 15 minimum, tools 6.2 | source of truth |
| `Sources/` | The engine: 25 module directories, 128 Swift files, ~28.6k lines | active |
| `Tests/` | 18 Swift Testing files (~1.88k lines; 138 `@Test` including nested) | active |
| `Benchmarks/enginebench/` | `enginebench` executable: 10k-row HTML → parse/style/layout timings | active |
| `Fixtures/` | `basic.html`, `forms.html`, `scripts.html` — local test/demo pages | active |
| `Docs/` | `ARCHITECTURE.md`, `AGENT_PROTOCOL.md`, `IMPLEMENTATION_STATUS.md`, `ROADMAP.md`, `VALIDATION.md`, `PERFORMANCE.md` | partly stale |
| `Scripts/` | **empty** — no automation scripts exist yet | placeholder |
| `agents/codex/test-freeze/` | Raw evidence from a past agent: `plan/plan.md`, `results/*.json` (RSS/CPU watchdog samples) | evidence |
| `Sources/NativeCapture/` | Nested sub-package: own `Package.swift`, `README.md`, `Examples/`, `Sources/AetherCapture/`, `Tests/` | vendored |
| `.build/` | SwiftPM build output (git-ignored) | generated |

**Trap:** `Sources/NativeCapture/` contains a nested `Package.swift`. SwiftPM ignores nested manifests; the root manifest pulls in only `Sources/NativeCapture/Sources/AetherCapture` via `path:`. Do not add files expecting the root target to pick them up outside that path.


## 4. File inventory — every module, every file

Format: `file` — role (lines).

### 4.1 EngineCore — shared vocabulary (7 files, 438 lines)

| File | Role |
|---|---|
| `Atom.swift` | `Atom` interned string + `AtomTable` for repeated engine strings |
| `AtomicCounter.swift` | `AtomicCounter` for ID allocation |
| `ByteBuffer.swift` | growable byte buffer used by parsers/loaders |
| `Color.swift` | `RGBAColor` + rgba8 conversion used by paint and style serialization |
| `DirtyRegion.swift` | dirty-rect accumulation, union, coalescing |
| `Geometry.swift` | `Point`, `Size`, `Rect`, `EdgeInsets` — all phase-space geometry |
| `Identifiers.swift` | `EngineIdentifier` + `DocumentID/FrameID/ContextID/PageID/NavigationID/RequestID/ResponseID/DownloadID/WorkerID/DialogID/SessionID`, `GenerationID` |

### 4.2 DOM (6 files, 790 lines)

| File | Role |
|---|---|
| `NodeID.swift` | generational `NodeID` (index + generation); stale IDs must never alias new nodes |
| `Node.swift` | `DOMNode`, `DOMAttribute`, `NodeKind` |
| `Document.swift` | `DOMDocument`: compact slot storage, insertion/removal, mutation version, bounded mutation journal, selector entry points |
| `Mutation.swift` | `DOMMutation`, `DOMMutationType` — the agent-observation substrate |
| `Semantics.swift` | `SemanticNode` + `DOMSemantics`: role/name/value/href/enabled/editable/visible |
| `Snapshot.swift` | `DOMSnapshot`, `DOMSnapshotNode`: serializable tree with attributes, text, parent/children, version |

### 4.3 HTML (5 files, 1395 lines)

| File | Role |
|---|---|
| `HTMLToken.swift` | token model (`HTMLToken`, `HTMLAttributeToken`) |
| `HTMLTokenizer.swift` | streaming tokenizer, chunk-safe, raw-text elements |
| `HTMLTreeBuilder.swift` | tree construction: implicit closes, foster parenting, mis-nested formatting, templates (771 lines) |
| `HTMLParser.swift` | `HTMLParser.parse` entry point + `HTMLParseResult` |
| `HTMLSerialization.swift` | serializes a live DOM back to HTML (used by capture) |

### 4.4 CSS (6 files, 1200 lines)

| File | Role |
|---|---|
| `CSSToken.swift` | token types |
| `CSSTokenizer.swift` | tokenizer |
| `CSSParser.swift` | rules, declarations, at-rules, media/layer handling |
| `CSSModel.swift` | selectors, specificity, declarations, rules, stylesheet model |
| `CSSCalc.swift` | `calc()` evaluation |
| `MediaQuery.swift` | media query matching + `LayerOrder` cascade sorting |

### 4.5 Style (4 files, 842 lines)

| File | Role |
|---|---|
| `ComputedStyle.swift` | the style surface: display/position/flex/overflow/visibility/content-visibility, `ContainFlags`, `StyleLength`, `ComputedStyle`, `DisplayType` |
| `SelectorMatcher.swift` | selector matching against the DOM (311 lines) |
| `StyleResolver.swift` | cascade + inheritance + viewport-aware resolution → `StyledDocument` |
| `StyledDocument.swift` | computed style per node + style pipeline state |

### 4.6 Text (3 files, 148 lines)

| File | Role |
|---|---|
| `TextMetrics.swift` | `TextRunMetrics`, `TextMeasuring` protocol |
| `SystemTextMeasurer.swift` | CoreText measurer on macOS, deterministic fallback elsewhere |
| `TextRunCache.swift` | bounded measurement cache keyed by `TextCacheKey` |

### 4.7 Layout (5 files, 537 lines)

| File | Role |
|---|---|
| `LayoutModel.swift` | `LayoutBox`, `LayoutTree` |
| `LayoutFragments.swift` | `LayoutFragment`, `ScrollViewport`, culling helpers |
| `LayoutEngine.swift` | block/inline/flex/grid/position/overflow layout, intrinsic form-control sizing |
| `HitTesting.swift` | point → node resolution |
| `PipelineInvalidation.swift` | `RenderDirtyFlags`, `PipelineInvalidation`, `FramePipelineState`: what a change must invalidate |

### 4.8 Images (3 files, 73 lines)

| File | Role |
|---|---|
| `ImageResource.swift` | `DecodedImage`, `ImageError` |
| `ImageDecoder.swift` | ImageIO/CoreGraphics decode when available, stub elsewhere |
| `ImageLoader.swift` | `ImageLoader` over `Networking` |

### 4.9 Networking (5 files, 613 lines)

| File | Role |
|---|---|
| `HTTPTypes.swift` | `HTTPMethod`, `HTTPRequest`, `HTTPResponse`, `HTTPCachePolicy`, `NetworkError` |
| `NetworkSession.swift` | actor: performs requests, applies cache policy, records timings |
| `HTTPCache.swift` | bounded actor cache with `CacheSnapshot` |
| `CookieJar.swift` | cookie store: domain/path/expiry/SameSite/secure/httpOnly, mutex-guarded (264 lines) |
| `ResourceLoader.swift` | `ResourceRequest`, `ResourceLoader` for subresources |

### 4.10 WebSecurity (6 files, 482 lines)

| File | Role |
|---|---|
| `Origin.swift` | origin parsing + effective-port comparison |
| `CORS.swift` | preflight + response checks, simple method/header rules |
| `ContentSecurityPolicy.swift` | CSP parse + inline/script decisions |
| `Policy.swift` | `NavigationPolicy`, `FramePolicy`, `DownloadPolicy`, `MixedContent`, `PermissionBoundary` |
| `PermissionPolicy.swift` | `WebPermission`, `PermissionDecision`, actor `PermissionStore` |
| `SandboxPolicy.swift` | `SandboxPolicy` flags |

### 4.11 Storage (2 files, 87 lines)

| File | Role |
|---|---|
| `LocalStorage.swift` | `LocalStorage` + `StoragePartition`: origin-partitioned, context-scoped |
| `PersistentStore.swift` | persisted download record type |

### 4.12 Persistence (3 files, 785 lines)

| File | Role |
|---|---|
| `SQLiteStore.swift` | thin `SQLite3` wrapper: `SQLiteValue`, `SQLiteConnection`, `SQLiteStore` |
| `ProfileStore.swift` | per-context durable profile: cookies, localStorage, history, session pages, permissions, cache entries, checkpoints (428 lines) |
| `DiskCache.swift` | CryptoKit content-addressed blob store |

### 4.13 JavaScript (22 files, 12,980 lines — largest module)

| File | Role |
|---|---|
| `JSRuntime.swift` | **interpreter core** (3,467 lines): `JSValue`, `JSObject`, `JSFunction`, `JSEnvironment`, `JSHostHooks`, `JSError`, `JSWellKnown`, timer host protocols |
| `JSParser.swift` | parser (1,324 lines) → `JSStatement`/`JSExpression` AST |
| `JSLexer.swift` | lexer + `JSToken` |
| `JSAST.swift` | AST node definitions |
| `JSBuiltinsCore.swift` | object/function/global/`Object.*` builtins |
| `JSBuiltinsTypes.swift` | `Number`, `Boolean`, `Symbol`, `Date`, `Math`, `JSON` etc. (941 lines) |
| `JSBuiltinsString.swift` | `String` + prototype methods (723 lines) |
| `JSBuiltinsError.swift` | error constructors + format/stack behavior (420 lines) |
| `JSBuiltinsCollections.swift` | `Array`, `Map`, `Set`, `WeakMap` (632 lines) |
| `JSTypedArrays.swift` | `ArrayBuffer`, typed arrays, `DataView` (878 lines) |
| `JSRegExp.swift` | regex compile/exec translation layer |
| `JSPromise.swift` | promise state, capabilities, microtask hooks |
| `JSBigInt.swift` | BigInt arithmetic |
| `JSModules.swift` | `JSModuleRecord`/`JSModuleRegistry` (import/export) |
| `JSTextCodec.swift` | `TextEncoder`/`TextDecoder`, `atob`/`btoa` |
| `JSTimersFetch.swift` | `setTimeout`/`setInterval`, `fetch`, `Response`/`Headers` (610 lines) |
| `DOMBindings.swift` | DOM wrapper objects carrying native `NodeID` (941 lines) |
| `DOMEvents.swift` | event dispatch, bubbling, `preventDefault` |
| `DOMWindow.swift` | `window`/`document`/global mirroring |
| `Events.swift` | `JSEventRegistry`, `JSEventState`, `JSEventDispatchResult` |
| `StorageBindings.swift` | `localStorage` binding into origin partitions |

### 4.14 WebAPI (5 files, 239 lines)

| File | Role |
|---|---|
| `EventLoop.swift` | actor `WebEventLoop` — pumps tasks/microtasks |
| `Timers.swift` | actor `WebTimerManager` |
| `TimerBridge.swift` | `JSTimerBridge`: `JSTimerHost` + `JSPumpableTimers` |
| `FetchAPI.swift` | `FetchAPI`, `FetchResult`, `FetchBridge` |
| `PageScriptHost.swift` | `PageScriptHost`: wires runtime + DOM + networking + storage per page |

### 4.15 Display (5 files, 430 lines)

| File | Role |
|---|---|
| `DisplayList.swift` | `DrawRectCommand`, `DrawTextCommand`, `DrawImageCommand`, `ClipCommand`, `DisplayCommand`, `DisplayList` |
| `DisplayListBuilder.swift` | layout tree → display list, z-ordering, clipping |
| `Compositor.swift` | `CompositorLayer`, `RetainedCompositor`, `ScrollResult`: retained layers + scroll damage |
| `PaintChunks.swift` | `PaintChunk`, `PaintChunkIndex`, chunk grid for bounded repaint |
| `ImageMemoryPolicy.swift` | decoded-image budget/eviction policy |

### 4.16 Graphics (8 files, 726 lines)

| File | Role |
|---|---|
| `Renderer.swift` | `OffscreenRendering` protocol + `RendererError` |
| `SoftwareRenderer.swift` | deterministic CPU rasterizer (headless + tests) |
| `MetalRenderer.swift` | macOS Metal renderer (error path elsewhere) |
| `PixelBuffer.swift` | RGBA8 buffer, blending, PNG read/write via CoreGraphics/ImageIO |
| `RasterTiles.swift` | `TileKey`, `TileRequest`, `RasterTile`, `TileCoverage`, `TileCache` |
| `GlyphAtlas.swift` | shelf-packed glyph atlas |
| `DamageCulling.swift` | `DirtyRegion`/`DisplayList` damage intersection |
| `ResourceBudget.swift` | `ResourceCategory`, `ResourcePressure`, `ResourceBudget`, `ResourceLedger` |

### 4.17 Navigation (3 files, 381 lines)

| File | Role |
|---|---|
| `NavigationTypes.swift` | `LoadedPage` (the loaded-document bundle), `NavigationError` |
| `NavigationPipeline.swift` | orchestrates fetch → parse → resources → style → layout → display |
| `ResourceDiscovery.swift` | finds stylesheets/images/scripts in a parsed document |

### 4.18 Diagnostics (2 files, 157 lines)

| File | Role |
|---|---|
| `Metrics.swift` | `EngineMetrics`, actor `MetricsCollector`, `MetricClock` |
| `FrameMetrics.swift` | `FrameReport`, `FrameRecorder`: frame-stage timing |

### 4.19 Scheduler (3 files, 198 lines)

| File | Role |
|---|---|
| `EngineScheduler.swift` | `EnginePriority`, actor `EngineScheduler`: admission/priority for page work |
| `FleetScheduler.swift` | `FleetAction`, `FleetCandidate`, `FleetPlan`, `FleetScheduler.plan`: the lifecycle policy |
| `FrameScheduler.swift` | `FrameStage` option set, `FrameScheduler` |

### 4.20 AgentProtocol (4 files, 368 lines)

| File | Role |
|---|---|
| `AgentMessages.swift` | `AgentMethod` (76 methods), `AgentRequest`, `AgentResponse`, `AgentError` |
| `JSONValue.swift` | `JSONValue` — the wire type, no engine dependency |
| `AgentCodec.swift` | encode/decode helpers |
| `UnixSocket.swift` | `AgentSocketClient`, `AgentSocketServer`, `AgentTransportError` (Darwin/Glibc) |

Agent method groups (`AgentMethod`): `ping` · context lifecycle/cookies/storage/permissions/downloads/profile/checkpoints (`context.*`) · page lifecycle/navigation/inspection/input/JS/render/metrics (`page.*`) · `dialog.resolve` · sessions and fleet (`session.*`, `fleet.*`) · `page.capture`.

### 4.21 EngineRuntime (4 files, 2,993 lines — the heart)

| File | Role |
|---|---|
| `BrowserRuntime.swift` | **the actor that owns everything** (2,143 lines): contexts, pages, sessions, history, navigation, DOM queries, input, forms, JS eval, render, cookies, storage, permissions, dialogs, downloads, profiles, fleet, capture; 80 public funcs + ~60 private helpers |
| `RuntimeTypes.swift` | all runtime value types + errors: `BrowserContextInfo`, `BrowserPageInfo`, `InspectedNode`, `PageInspection`, `PageSnapshot`, `FleetStats`, `FleetPageInfo`, `CookieInfo`, `PermissionInfo`, `HistoryEntry`, `NetworkLogEntry`, `AgentDialogInfo`, `AgentDownloadInfo`, `AgentFrameInfo`, `BrowserSessionInfo`, `PageLifecycleState`, `BrowserRuntimeError` (16 cases), capture DTOs |
| `PageHostWiring.swift` | per-page live wiring: `LiveViewport`, `SharedStyledDocument`, `PendingPageAction`, fetch handler enforcing scheme/mixed-content/CORS, `computedStyleValue` serialization, CSS color/length formatting |
| `CaptureSessionAdapter.swift` | `BrowserCaptureEngine` + actor `NativeCaptureSession`: adapts the runtime to the `AetherCapture` protocols |

### 4.22 BrowserEngine (2 files, 1,017 lines — public face)

| File | Role |
|---|---|
| `BrowserEngine.swift` | `NativeBrowserEngine` facade over `BrowserRuntime` (+ `typealias BrowserEngine`). Start here for the supported surface |
| `AgentCommandDispatcher.swift` | `AgentCommandDispatcher.handle`: the 76-method switch plus every JSON projection (`pageJSON`, `nodeJSON`, `snapshotJSON`, `metricsJSON`, …) and `DispatchError` (736 lines) |

### 4.23 NativeCapture (13 files, 1,049 lines — vendored, engine-agnostic)

Path target: `Sources/NativeCapture/Sources/AetherCapture` (10 files).

| File | Role |
|---|---|
| `EnginePort.swift` | `AetherCaptureEngine` + `AetherCaptureSession` protocols and `AetherPageState`/`AetherRaster`/`AetherDocumentSnapshot`: the only adaptation point |
| `CaptureCoordinator.swift` | actor orchestrating the export (285 lines) + `RasterCropper` byte-exact crop |
| `CaptureFolder.swift` | on-disk export layout, path containment |
| `FullPageAssembler.swift` | bounded full-page composite |
| `SectionDetector.swift` | structural section detection from tags/roles/rects |
| `ResourceCollector.swift` | collects HTML/CSS/assets from the engine cache + `CSSURLScanner` |
| `DesignReference.swift` | emits `design-reference.md` |
| `NativeImageEncoder.swift` | `AetherImageEncoder` + WebP/JPEG/PNG encoder with runtime detection |
| `EngineClosureAdapter.swift` | closure-based adapters for tests/embedding |
| `Types.swift` | `CaptureOptions`, `CaptureManifest`, `CaptureResult`, `CaptureFormat`, `CaptureFailure`, sections/assets/files |
| `../Examples/AgentDispatch.swift` | `runAgentCapture(...)` example binding for a CLI/MCP registry |
| `../Tests/AetherCaptureTests/CaptureTests.swift` | 6 tests with a fake encoder/engine — fixtures only, not a renderer |

### 4.24 browserctl (1 file, 692 lines)

`Sources/browserctl/main.swift` — `@main BrowserControl`. Local mode (`inspect`, `render`, `eval`, `shell`, `capture`, `bench-info`) plus remote mode over `--socket` with 79 subcommands mirroring `AgentMethod`. Its usage string (bottom of the file) is what agents see on a usage error — keep it in sync when adding commands.

### 4.25 browserd (1 file, 30 lines)

`Sources/browserd/main.swift` — `@main BrowserDaemon`. Parses `--socket` (default `/tmp/native-browser-engine.sock`), builds one `NativeBrowserEngine`, one `AgentCommandDispatcher`, one `AgentSocketServer`, serves until terminated. This is the entire daemon.

### 4.26 Benchmarks (1 file, 46 lines)

`Benchmarks/enginebench/main.swift` — generates 10,000 `.row` divs, prints `nodes`, `parse_ms`, `style_ms`, `layout_ms`, `boxes`. This is the only regression benchmark; extend it instead of inventing a new harness.

## 5. Entry points (where to start reading)

| Goal | Start at |
|---|---|
| What can the engine do for an agent? | `Sources/BrowserEngine/BrowserEngine.swift` → `Sources/EngineRuntime/BrowserRuntime.swift` |
| What can an agent send over the wire? | `Sources/AgentProtocol/AgentMessages.swift` → `Sources/BrowserEngine/AgentCommandDispatcher.swift` |
| How does a page become pixels? | `Sources/Navigation/NavigationPipeline.swift` → `BrowserRuntime.performNavigation` |
| How is loaded page state shaped? | `Sources/Navigation/NavigationTypes.swift` (`LoadedPage`), `Sources/EngineRuntime/RuntimeTypes.swift` |
| Why is a frame slow? | `Sources/Diagnostics/Metrics.swift`, `Sources/Layout/PipelineInvalidation.swift`, `Sources/Graphics/DamageCulling.swift` |
| How does capture/export work? | `Sources/NativeCapture/Sources/AetherCapture/CaptureCoordinator.swift` → `Sources/EngineRuntime/CaptureSessionAdapter.swift` |
| How do the two interfaces share state? | `BrowserRuntime` (one actor), `Sources/EngineRuntime/PageHostWiring.swift` (per-page bridges) |

## 6. Environment, build, and verification

Host measured for every number below: macOS 27.0 (26A5425a), arm64, 8 CPUs, 8 GiB RAM, Swift 6.4, **Command Line Tools only** (`xcode-select -p` → `/Library/Developer/CommandLineTools`; no `/Applications/Xcode*.app`).

```bash
swift build -c release          # engine + browserctl + browserd + enginebench
swift test --no-parallel        # 138 @Test cases across 14 test targets
.build/release/browserd --socket /tmp/native-browser-engine.sock &
.build/release/browserctl --socket /tmp/native-browser-engine.sock ping
.build/release/enginebench      # parse/style/layout regression baseline
```

### Hard-won environment facts — read before "debugging" the toolchain

1. **`swift test` currently fails on this host for a toolchain reason, not a code reason.** With Command Line Tools only, the Swift Testing macro plugin is missing: `external macro implementation type 'TestingMacros.TestDeclarationMacro' could not be found for macro 'Test'; plugin for module 'TestingMacros' not found`. Fix the host, not the tests: install full Xcode and `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`, or run tests on an Xcode machine. Do not migrate tests to XCTest to work around a missing plugin without a human decision.
2. **Never run builds and tests in parallel, and never let `swift test` run unbounded on an 8 GiB host.** A prior agent's watchdog run (evidence in `agents/codex/test-freeze/results/`) measured peak tree RSS ≈ 410 MiB, ≈ 89% CPU, plus heavy system swap and compressor pressure. Use `nice -n 10 swift test --no-parallel --jobs 1`, prefer `--skip-build` when the build is current, and do not start a build while a test run is active.
3. **A fresh full release build takes minutes and streams enormous compiler command lines.** Redirect and grep instead of reading output: `swift build -c release > /tmp/build.log 2>&1`, then search the log for `error:`.
4. **`Documentation/` does not exist.** Docs live in `Docs/` and at the repository root.
5. **The Git repository root is `/Users/harshitduggal`, not this folder.** `Aether/` is currently untracked (`git ls-files` returns nothing for engine paths; `git log` shows unrelated home-directory commits). Do not rely on `git diff`, `git checkout`, or `git log -- Aether/...` to recover engine files. Copy before overwriting.
6. Expected benign noise: `ld: warning: search path '/Library/Developer/CommandLineTools/Developer/Library/Frameworks' not found`. Ignore it. Real, worth-fixing warnings exist in the JavaScript module (~55 non-linker warnings: unused/never-mutated variables, `JSError` carrying non-`Sendable` `JSValue`, write-only `self`/`runtime` captures).

### Known code defects found during this snapshot

| Location | Defect | State |
|---|---|---|
| `Sources/JavaScript/JSTextCodec.swift:42` | `writeTypedElement(...)` is `throws` but called without `try` → hard compile error in `TextEncoder.encodeInto` | fixed in this snapshot (added `try`) |
| `Sources/EngineCore/Geometry.swift` | `Point` had no `.zero` while `Size`, `EdgeInsets`, `StyleLength` all do; `SoftwareRenderer.render(..., origin: Point = .zero)` therefore failed to compile and `SoftwareRenderer` did not conform to `OffscreenRendering` | fixed in this snapshot (added `public static let zero = Point()`) |
| Whole tree | Because of the two defects above, **the tree did not compile** as it stood. Treat pre-existing "build green / 27 tests passed" claims in `Docs/VALIDATION.md` as stale. | needs a clean build + full test run on an Xcode host |

## 7. Non-negotiable contracts

- `BrowserRuntime` is the **only** owner of browser state. UI and agents both go through it.
- `NodeID` is `(index, generation)`. Never store only the index; never resurrect a removed node.
- Structured inspection is the control surface; pixels are the fallback.
- Every agent method returns `AgentResponse` with either `result` or `error { code, message }`. Keep error codes stable.
- `EngineCore` stays a leaf. Adding a dependency to it is an architecture change, not a convenience.
- `AgentProtocol` must never import engine state types; it models transport only.
- `AetherCapture` stays engine-agnostic; adapt it through `EnginePort.swift`, never by importing `EngineRuntime` into it.
- No explanatory source comments (repo law). Names and types carry the meaning.
- Keep public surfaces small: adding a capability is `BrowserRuntime` + one DTO + one dispatcher case + one `AgentMethod` + one CLI subcommand + one test, not a new type hierarchy.

## 8. Change-routing table

| I want to… | Touch these |
|---|---|
| Add an agent capability | `EngineRuntime/BrowserRuntime.swift` → `RuntimeTypes.swift` (if a new DTO) → `BrowserEngine/BrowserEngine.swift` → `BrowserEngine/AgentCommandDispatcher.swift` → `AgentProtocol/AgentMessages.swift` (new `AgentMethod`) → `browserctl/main.swift` (subcommand + usage text) → `Tests/AgentTests/` |
| Add a CLI-only command | `browserctl/main.swift`, if it needs no protocol round-trip |
| Fix HTML parsing | `HTML/HTMLTreeBuilder.swift` + tokenizer; prove it in `Tests/HTMLTests/` with a malformed fixture |
| Fix CSS or style | `CSS/` → `Style/StyleResolver.swift`; prove it in `Tests/CSSTests/` |
| Fix layout | `Layout/LayoutEngine.swift`; prove it in `Tests/LayoutTests/` |
| Fix painting/rendering | `Display/DisplayListBuilder.swift` → `Graphics/SoftwareRenderer.swift`; prove it in `Tests/RenderingTests/` |
| Add JS semantics or builtins | the matching `JavaScript/JSBuiltins*.swift` or `JSRuntime.swift`; prove it in `Tests/JavaScriptTests/` |
| Improve performance | measure first with `enginebench` + `FrameRecorder`/`EngineMetrics`, then `Layout/PipelineInvalidation.swift`, `Display/PaintChunks.swift`, `Graphics/RasterTiles.swift`, `Graphics/DamageCulling.swift` |
| Change lifecycle/fleet policy | `Scheduler/FleetScheduler.swift` + `BrowserRuntime.sweepFleet`; prove it in `Tests/AgentTests/AgentFleetTests.swift` |
| Change persistence | `Persistence/ProfileStore.swift` → `SQLiteStore.swift`; prove it in `Tests/PersistenceTests/` |
| Change capture output | `NativeCapture/Sources/AetherCapture/` (plus `Types.swift` for the manifest) and `EngineRuntime/CaptureSessionAdapter.swift`; prove it in the nested `CaptureTests.swift` |
| Build the human UI | **Nothing exists yet.** Follow `DESIGN.md`, then `ENHANCE-DESIGN.md`. Add a new app target; never put UI inside engine modules |
| Add a test | Swift Testing (`import Testing`, `@Test`, `#expect`) — that is the convention in all 138 existing tests |

## 9. Doc map and staleness warnings

| File | Authority | Staleness |
|---|---|---|
| `AGENTS.md` (this file) | operating contract + code snapshot | current |
| `TODO.md` | the work plan | current |
| `RULES.md` | process rigor | current |
| `DESIGN.md` | **all** native UI/visual decisions (tokens, palette, motion, bans) | current; UI not implemented |
| `ENHANCE-DESIGN.md` | UI polish pass (run only after the UI works) | current; UI not implemented |
| `Docs/ARCHITECTURE.md` | pipeline + module layering | **stale** — describes the retired custom engine (`SoftwareRenderer`/`MetalRenderer` headless path) as current. Superseded by `Docs/WEBKIT.md` and `work/plan/backend/retire-custom-engine.md` |
| `Docs/AGENT_PROTOCOL.md` | protocol overview | **stale**: documents ~25 methods; 76 exist. `AgentMessages.swift` is authoritative |
| `Docs/IMPLEMENTATION_STATUS.md` | capability status table | mostly accurate |
| `Docs/ROADMAP.md` | Engine 0/1/2/3 phases | accurate as intent |
| `Docs/VALIDATION.md` | past validation run | **stale**: claims `27 tests passed`, a Linux host, and a green release build; the current tree has 138 tests, runs on macOS, and had two compile errors fixed today |
| `Docs/PERFORMANCE.md` | optimization order + rules | accurate as intent |
| `HANDOFF.md` | previous agent's handoff, 11-item priority list | accurate; still the best ordered engineering backlog |
| `README.md` | public framing + CLI examples | accurate |
| `SECURITY.md` | security boundary | accurate: no sandbox, no process isolation |
| `Sources/NativeCapture/README.md` | capture module contract | accurate |

When you change behavior, update the doc that owns it. When you learn a non-obvious repository fact (toolchain trap, surprising API behavior, module gotcha), write it down here or in `Docs/` instead of leaving it in a chat log. That is the difference between this repo getting faster for the next agent and getting slower.
