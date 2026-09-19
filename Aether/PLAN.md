# Aether — Browser Engine Completion Plan

**Purpose:** Finish the existing custom Swift browser engine before building the human macOS GUI. This is the engine-only execution plan for coding agents. It supplements, rather than replaces, root TODO.md, RULES.md, AGENTS.md, SECURITY.md and Docs/IMPLEMENTATION_STATUS.md.

**Starting point:** Main has a passing macOS CI run for its current 174 tests, but that proves those implemented tests, not production browser compatibility. Engine 0 is a working architectural foundation, not a finished browser.

## Mission and invariants

Aether is a native macOS browser with a custom Swift browser engine and Metal rendering path. It has two equally important first-class operators: humans and external terminal agents (Codex, Claude Code, OpenCode and local processes). The model plans; Aether deterministically executes. Do not build an in-browser assistant or a separate automation browser.

- One browser/runtime, one document model, one network/security model, one set of profiles and pages. Headless and visible are **presentation modes of the same page**, not separate engines.
- Agents must be able to perform every **authorized human-equivalent browser operation** through stable structured APIs. They must not automatically inherit human profiles or bypass origin, website, file or permission security.
- No Chromium/WebKit/Chromium wrapper, duplicate scheduler, duplicate JS event loop, second profile DB, or duplicate compositor. Use existing Swift code and Apple system frameworks where appropriate. A custom engine removes dependence on Chromium's implementation choices; it does **not** remove web standards, protocol requirements, platform codec limits, site restrictions or security obligations.
- Small and correct first. Use a bounded hot-memory representation, SQLite for durable profile state, disk files for large cache blobs, and explicit GPU budgets. Do not optimize code that has not been made correct and exercised.
- No “complete” claims for an API stub, fixture-only test, source file excluded from the root package, or UI behavior with no window attached.

## Existing implementation to preserve

| Area | Verified source / current scope | Completion status |
|---|---|---|
| Core document pipeline | EngineCore, HTML, DOM, CSS, Style, Layout, Display, Graphics, Navigation | Foundation; incomplete browser standards and site compatibility |
| JavaScript/Web API | JavaScript, WebAPI, per-page runtime and DOM bindings | Custom interpreter, promises/modules/fetch subsets; far from complete |
| Agent control | AgentProtocol, browserctl, browserd, AgentCommandDispatcher, BrowserRuntime | Real native structured control; not yet every human interaction or authenticated multi-owner IPC |
| Silent browsing/capture | SoftwareRenderer, CaptureSessionAdapter, NativeCapture/CaptureCoordinator | Offscreen pixels and capture path exist; rich real-site visual parity unproven |
| Profiles/fleets | Persistence/ProfileStore, SQLiteStore, DiskCache, FleetScheduler | Implemented foundations; recovery/isolation under real workloads not proven |
| GPU | Graphics/MetalRenderer, compositor/tiles/atlas primitives | Main render path still uses SoftwareRenderer; Metal renderer is rects-only |
| Engine additions | Sources/EngineAdditions | Only AetherNetworkHardening is a live additional target in root Package.swift |
| Security | WebSecurity policy code, local socket | No production renderer sandbox or hardened hostile-page process isolation |
| Media/ads | No integrated dedicated video pipeline or content-blocking target found in the current root source | Not implemented |
| Human application | No SwiftUI/AppKit window or live surface target | Next phase, **not** part of this engine plan |

The existing page.workers dispatcher is not proof of worker support: BrowserRuntime.listWorkers currently returns an empty array. Existing page.render returns SoftwareRenderer pixels. The old standalone capture/additions READMEs may describe pre-integration states; root Package.swift and live caller paths win.

## P0. Establish a truthful executable baseline

Read AGENTS.md, RULES.md, Package.swift, Docs/IMPLEMENTATION_STATUS.md, Docs/ADDITIONS_INTEGRATION.md and relevant implementations before edits. Update the capability table to distinguish implemented-and-wired, implemented-but-incomplete, source-only, unsupported, and tested-on-real-sites. Test the **root** package on macOS, then the actual browserd/browserctl navigation-to-pixels flow. Preserve the currently passing test corpus.

Evidence: a reproducible test log, one real rendered/captured dynamic page, unsupported-feature report, and a file-to-runtime integration map. Never interpret 174 passing tests as 174 web standards.

## P0. Hostile-content security and actual session authority

Move untrusted page execution out of the privileged browser host into restricted macOS renderer processes. BrowserRuntime remains the authority over contexts/pages and orchestrates child renderers; it must not give hostile JS in-process host authority. Implement authenticated IPC, least-privilege sandbox, site/origin isolation policy, renderer crash containment/recovery, origin- and profile-scoped file/credential permissions, denial-by-default and explicit authorization for sensitive actions.

Finish enforceable SOP, CORS/preflight, CSP, cookie/SameSite/HttpOnly behavior, HSTS across redirects, mixed content, frame ancestry, TLS/certificate decisions, permission prompts and safe download/file paths. Require secure owner/session binding at the socket, not a self-declared JSON owner. Test cross-profile reads, hostile iframe, malicious navigation, renderer crash, credential theft attempts and concurrent agent principals. An agent has human-equivalent browser controls **inside its authorized session**, not unrestricted machine or account access.

Exit: hostile pages cannot read browserd secrets or another profile; denied requests fail predictably; a crashed renderer does not kill other contexts; origin policies apply equally to human and agent actions.

## P0. Complete the document and JS execution core

Extend existing HTML tokenizer/tree builder toward relevant WHATWG behavior: encoding, templates, foster parenting/adoption, foreign content, fragments, forms and malformed markup. Finish DOM event/focus/selection/editing, frames and shadow-tree foundations.

Extend CSS selectors/cascade/custom properties/value resolution, fonts, pseudo-elements, media/container queries and layout for full flex/grid/tables, replaced elements, sticky/fixed positioning, overflow and nested scrolling. Repair actual site failures with standards fixtures, not one-off site hacks.

Advance the existing JavaScript runtime with correct ECMAScript semantics, memory management/GC, async jobs and microtasks, modules, typed arrays, DOM bindings and Web APIs. Do not install the additions' second microtask queue. Prioritize actual dependencies of production SPAs: Fetch/Streams, AbortController, URL APIs, WebSocket, IndexedDB, workers, WebAssembly, Canvas 2D, and service workers as the implementation reaches them. A method that returns an empty worker list is not worker support.

Exit: representative interactive/authenticated SPAs run without silently skipped scripts; controlled standards fixtures and previously failing site flows pass with no duplicate JS/DOM model.

## P0. One real rendering pipeline for silent AND visible clients

Wire Agent 2's existing FramePipelineState, RetainedCompositor, PaintChunkIndex, TileCache, GlyphAtlas, ResourceLedger and FrameRecorder into real navigation, mutation, scroll and paint. The current BrowserRuntime.refreshPage broadly recomputes style/layout/display and BrowserRuntime.render invokes SoftwareRenderer. Keep the deterministic software path for tests and fallback, but implement the real retained Metal path: text, glyphs, images, clipping, transforms, opacity, correct color, tiles, scrolling, video surfaces, damage and asynchronous GPU resource ownership.

Expose a presentation-neutral page surface contract: create/resize viewport; render next frame; subscribe to frame/damage/state changes; obtain a screenshot from that **same page**; receive hit-tested input; attach/detach a future native window without reloading, cloning sessions or switching engines. Headless must run JS, DOM, media policy and rendering without creating app windows. “Visible” becomes real only when the subsequent SwiftUI/AppKit shell actually attaches to this contract.

Exit: one PageID produces the same meaningful page state and equivalent pixels in offscreen and attached-surface harnesses; compositor-only changes do not relayout; broken page rendering yields a real error rather than a fabricated screenshot.

## P0. Live human–agent co-control contract

Design the engine now; implement the polished UI later. An agent may operate (a) an isolated headless context or (b) a human-approved visible page/context. In visible mode, human and agent observe and modify the **same** PageID, DOM, scroll, selection, navigation, JS and cookies as permitted. Render an observable ordered event stream with actor, operation, timestamp, affected page/node, outcome and error. Provide pause/abort/take-over/return-control, atomic input ownership, action ordering and approval before consequential operations; avoid simultaneous keyboard/focus races.

Support attaching a headless agent page to a window and detaching it again without rerunning navigation. Protect password/secret entry and do not expose private human profiles to a headless agent by default. Test two agents plus a human contender, race/cancel behavior and identical page state after handoff. A screenshot-only mirrored replay is NOT live shared-page control.

## P0. Browser-grade video and audio engine

Implement **web media semantics** in the custom browser while delegating codec work to supported native Apple media APIs. Use AVFoundation for appropriate playback/HLS, VideoToolbox for available hardware decode, CoreMedia/CoreVideo buffers, audio scheduling and Metal texture composition. Build native HTMLMediaElement/video/audio lifecycle, play/pause/seek/rate/mute/volume, buffering, timing and events, audio/video sync, subtitles, full-screen/PiP hooks, error handling, poster/image fallback and resource cleanup.

Support tested progressive media and HLS; implement Media Source Extensions (MSE) or a standards-compatible equivalent where needed by adaptive sites. Handle codec/container capability reporting and fallback for H.264/HEVC/AV1/VP9 only when the target machine/API actually supports the relevant path. DRM/EME and commercial protected streams need legitimate platform/provider integration; report unavailable cases. Maintain authenticated session and CORS/redirect/content-blocking policy for every media segment.

**4K and 8K are device/codec/bitrate/display-dependent qualification targets, not universal promises.** Prove 1080p/4K and supported 8K test streams on named Apple hardware with correct frames, audio sync, seeking, recovery, background behavior and memory bounds. A YouTube page is not “supported” just because its HTML loads; verify real playback.

## P0. Built-in aggressive content and tracking blocker

Build a single engine-level filter owner, not a Chromium extension. Place classification before **all** page-initiated network requests, including image/script/frame/fetch/media/WebSocket paths and redirects; preserve origin/CSP/cookie checks. Support compiled and bounded network rules, well-defined priorities/exceptions, domain/resource types, first/third party context, cosmetic DOM rules, updates/rollbacks, per-profile policy and per-site temporary allowlist. Respect filter-list licenses. Count blocked requests and false positives without leaking browsing history.

Include maintained YouTube-specific filters and playback regression tests. **Do not promise every YouTube ad will always be blocked**: first-party/server-inserted ads and site changes can be indistinguishable from content or break playback. Aim to block as much as can be identified reliably, recover from site changes, preserve normal video and report measurable outcomes. No false “100% ad free” pass condition.

Exit: blocker applies equally to visible/headless pages and video segments, common ad/tracker fixtures are blocked, normal login/video flows remain functional, site exceptions work, and filter updates cannot silently brick browsing.

## P1. Profiles, search/navigation and human-ready engine services

Keep the existing SQLiteStore/ProfileStore/DiskCache; no extra DB or ORM. Add durable and distinct personal/work/agent contexts with separate cookies, cache, history, permissions, localStorage, IndexedDB, session restore and profile corruption recovery. Secure sensitive credentials through platform-appropriate storage and permissions, not ordinary visible SQLite values. Establish stable tab/page grouping and session-ownership semantics usable by a future GUI; no duplicate UI-owned page state.

Implement address-bar **engine services** for URL vs search query, configurable provider/search templates, navigation suggestions/history, bookmarks/history metadata, downloads and find-in-page. The search field, tabs, profile picker and settings screens themselves belong to the later GUI phase.

## P1. Finish agent interaction and capture semantics

Make the current CLI/dispatcher complete and versioned: keyboard modifiers/sequences, drag/drop, clipboard, file upload/pickers, nested scroll, actual frame selection, dialogs, wait-for-navigation/element/network/visual-stability, cancellation, timeouts, screenshots, meaningful PDFs and downloadable artifacts. Implement real workers/frames where advertised; remove or explicitly mark unsupported methods until they work. Events and errors must be structured; screenshots are for visual evidence, not the default control mechanism.

Maintain Capture 1 as a client of the **same** runtime. Cover dynamically loaded pages, responsive viewports, long-page overlap/sticky behavior, exact loaded styles where available, cache-only assets, privacy redaction, section mapping, completeness warnings and capture cancellation. Never claim inaccessible cross-origin DOM/DRM/canvas state was extracted.

## P1. Compatibility, accessibility and release gates

Add high-value tests for Google Search, real authenticated apps, dynamic forms, long scrolling pages, responsive layouts, YouTube/media playback, ad-heavy pages, downloads and profile isolation. Avoid site-specific hardcodes and respect access controls. Integrate accessibility tree, native text input/IME, international fonts, selection, keyboard semantics and focus. Preserve a feature-gap ledger for Canvas, WASM, workers, Service Workers, WebGL/WebGPU, WebRTC, DRM and printing/PDF; do not quietly mark all of them “done.”

Test representative site workflows end-to-end on the macOS host: navigate → run JS → interact → scroll → screenshot → download → restore. Run denial cases, renderer crashes, two agents, headless-to-visible handoff, media seek, blocker false positives and profile reopen. Measure correctness-critical frame timing, bounded RAM and no leaks, but defer unrelated micro-optimization/UI polish to its later phase. Hardware and format qualification must name the machine and actual decoder path.

## Execution order and exact handoff

1. Audit real wired capabilities; keep root build/tests green.
2. Security/process boundaries and authenticated agent ownership.
3. Standards/JS/network correctness sufficient for production sites.
4. Shared headless/attachable rendering plus human–agent control contract.
5. Native media playback and built-in blocker, integrated with networking/rendering.
6. Profiles/search engine services, complete agent actions/capture and standards tail.
7. Run the engine-only exit gate below; update documentation with evidence.

**Engine-only exit gate:** a sandboxed, supported modern-web page can load, run scripts, render real text/images/media, accept the same authorized human-style inputs from an agent, be screenshotted silently, attach to/detach from a visible host without state recreation, preserve profile isolation, block supported ads/trackers, recover from expected failures and complete a substantial realistic task. All described behavior has integration evidence on macOS. Do not claim universal website parity or every ad blocked.

**NEXT, NOT PART OF THIS FILE:** build the native SwiftUI/AppKit browser GUI on the above engine contract: windows, Metal-backed page surface, tabs/tab groups, omnibox with selectable search engines, profiles, permissions, bookmarks, downloads, video controls, shortcuts, menus, agent-control status and live watching. Then complete polished external agent adapters (including MCP) against the **existing** dispatcher, and finally perform aggressive concurrent real-world human+agent testing. No frontend-only fake browser and no second runtime.

## Sources for implementation decisions

- Repository: README.md, AGENTS.md, RULES.md, Package.swift, Docs/IMPLEMENTATION_STATUS.md, Docs/ROADMAP.md, Docs/ADDITIONS_INTEGRATION.md, SECURITY.md.
- Apple VideoToolbox: https://developer.apple.com/documentation/VideoToolbox
- Apple AVFoundation: https://developer.apple.com/documentation/avfoundation/
- Apple HLS: https://developer.apple.com/documentation/http-live-streaming
- ABP filtering syntax (evaluate licensing before bundled list distribution): https://help.adblockplus.org/adblock-plus-help-center/how-to-write-filters