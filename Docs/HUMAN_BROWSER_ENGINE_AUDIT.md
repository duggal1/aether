# Human Browser Engine Audit (Phase 2A)

Scope: audit of the live engine on `agent3/engine-services-gate-20260920-work@731231b`
(base `main@01f9ec1`). Audit-only pass: no systems were implemented for this document.
Documentation was treated as a claim and re-checked against code, tests, and live runs.

## Proof environment and reproduction

Host: macOS 27.0 (26A5425a), arm64, 8 CPUs, 8 GiB RAM, Apple Swift 6.4 (Command Line
Tools only). Repo-blessed commands only (`Scripts/test_macos.py` serial + RSS-bounded;
plain `swift test` fails on this host for a toolchain reason — missing Testing macro
plugin path — not a code reason).

| Command | Result on this tree |
| --- | --- |
| `swift build -c release` | Build complete (only the known-benign `search path ... not found` linker warnings) |
| `python3 Scripts/test_macos.py --timeout 1800 --maximum-rss-mib 3072 -- --skip-build` | **193/193 tests passing, exit 0**, 15 targets, peak tree RSS 96 MiB in the test phase (full build+test runs on this host peaked ≈0.76–1.15 GiB; hence the serial RSS-bounded runner) |
| `python3 Scripts/verify_browser.py --bin <release> --output /tmp/aether-audit` | **24/24 daemon checks passing**, peak daemon RSS 52 MiB, incl. JS-mutated green viewport pixel, green capture PNG pixel, typed-address navigation, profile reopen, bookmark/provider persistence |
| `.build/out/Products/Release/enginebench` (10k rows, ~50,006 nodes) | Run A: parse 610 ms / style 279 ms / layout 1357 ms. Run B: parse 468 ms / style 187 ms / layout 1017 ms. Host variance only; regression baseline, not a product claim |

Stale-doc corrections found during this audit: suite is **193 tests, not 177**;
dispatcher is **84 methods, not 76**; `MetalRenderer` is **source-only**, not "wired
(minimal)" (zero callers, zero tests); HSTS is **source-only** (`Sources/EngineAdditions`,
excluded from the root package), so the "HSTS-on-navigation" status line overstates this
tree. `AGENTS.md`'s "no SwiftUI/AppKit code" claim re-verified true (no
`SwiftUI`/`AppKit`/`NSWindow`/`CAMetalLayer` under `Sources/`, `Tests/`, `Benchmarks/`).

## 1. Evidence-backed capability matrix

Verdicts: **WORKING** (live path + tests) / **PARTIAL** (live but gapped) /
**SOURCE-ONLY** (compiles, never executed by the live path) / **MISSING** (absent) /
**UNVERIFIED** (cannot be verified without a window/real site).

| System | Verdict | Paths + symbols | Test / reproduction + observed result | Missing work |
| --- | --- | --- | --- | --- |
| GPU rendering / compositor / window | MISSING | `Sources/Graphics/MetalRenderer.swift` (`renderRectangles` only: rects + color + opacity). Live path is `BrowserRuntime.render` → `SoftwareRenderer` → `PixelBuffer` | No caller of `MetalRenderer` in `Sources/`, `Tests/`, `Benchmarks/`, `browserctl`, `browserd`; no test target covers it. Daemon `page.render` returns deterministic RGBA PNG (verified 1280×800 in qualification runs) | Text/glyph/image/clip/transform/opacity pipeline, retained compositor wired into navigation/mutation/scroll, `CAMetalLayer` attach, damage subscription, frame times, memory bounds |
| Presentation contract (attach/detach) | MISSING | No surface/attach API on `BrowserRuntime` or `NativeBrowserEngine` | `page.capture` uses a *separate* temporary page, not the interactive `PageID` (`CaptureSessionAdapter.swift`) | Agent 2 contract: create/resize viewport, request frame, observe damage, screenshot same page, hit-tested input, attach/detach without reload |
| Web compatibility (real sites) | PARTIAL | `HTML/` tokenizer/tree builder, `DOM/`, `CSS/` + `Style/`, `Layout/`, `JavaScript/` interpreter, `WebAPI/` bridges, `Navigation/NavigationPipeline.swift` | Fixture-only evidence: 193 unit/integration tests + loopback daemon checks pass; **zero real-site passes recorded**. `getSelection` returns null (`DOMWindow.swift:248`); no `@font-face`; no tables/floats/fragmentation/sticky; JS has no GC spec, no streams/workers | Standards corpus, shadow trees/ranges, layout gaps, ECMAScript completeness, and target-site qualification (Agent 1 Step 3 scope) |
| Video / audio | MISSING | No `AVFoundation`/`VideoToolbox`/`CoreMedia`/`CoreVideo` imports; no media target in `Package.swift` | Nothing to run; YouTube-style playback unverified and unimplemented | Full media engine (Agent 2 scope); no 1080p/4K/8K claim possible |
| Navigation / search models | PARTIAL | `BrowserRuntime.navigate/goBack/goForward/reload`, `NavigationInputResolver` (URL vs query), `searchProvider`/`setSearchProvider` (kv-persisted), `suggestNavigation` | Daemon-verified: redirects, typed address on live page, history back/forward/reload, suggestion ranking. No `stopLoading` symbol anywhere | Stop/abort navigation, TLS error surfacing (URLSession defaults only; no `SecTrust`/pinning code), omnibox UI (Phase 2B) |
| Tabs / windows models | PARTIAL | `PageRecord` history/lifecycle, `suspendPage`/`restorePage`, `FleetScheduler`, sessions grouping contexts, profile session-page restore | Daemon-verified: suspend/freeze/discard/restore round-trip, fleet sweep, session reopen restores discarded pages | Tab pin, recently-closed-tab undo, multiwindow ownership (no window concept exists), GUI layouts (Phase 2B) |
| Profiles / accounts models | PARTIAL | `ContextRecord` (isolated network/storage/permissions/downloads/bookmarks), `ProfileStore` schema v3 + `DiskCache`, `openProfile`/`checkpoint` | Daemon-verified: cross-context storage isolation, checkpoint/reopen restores storage + session pages + bookmarks + provider, corrupt profile fails closed | Profile-picker/switching UI, per-site data management UI, multiple-accounts UX (engine primitive is adequate: N isolated contexts), credential-leakage soak testing |
| Passwords / passkeys | MISSING | No `Keychain`/`SecItem`/`LocalAuthentication`/`AuthenticationServices` symbols anywhere | Nothing to run | Apple Keychain/Password AutoFill, WebAuthn/passkeys, Touch ID, account/permission boundaries |
| Bookmarks | WORKING | `BrowserRuntime.addBookmark/listBookmarks/removeBookmark`, `ProfileStore` bookmarks table, `context.bookmarkAdd/bookmarks/bookmarkRemove` | 8 new tests pass; daemon-verified across profile reopen | Import/export, folders/tags, bookmark UI (Phase 2B) |
| History | PARTIAL | `historyEntries(pageID)` (per-page URL lists), `context.suggest` prefix match | Daemon-verified prefix suggestions; no full-text search, no visit timestamps, no cross-page aggregation beyond suggest | Searchable-history store, frecency, history UI |
| Downloads | PARTIAL | `startDownload/listDownloads/clearDownloads`, `DownloadPolicy`, `AgentDownloadInfo` | Daemon-verified byte-exact download; states are `completed`/`failed` only; whole-body fetch then atomic write | Progress events, cancellation, reveal-in-Finder, caller-path containment **on this tree** (exists only on unmerged Agent 1 branch), downloads UI |
| File upload / clipboard | MISSING | No upload/picker symbols; clipboard appears only as permission-name strings (`PermissionPolicy.swift`, `Policy.swift`), no read/write API | Nothing to run | Upload/picker flows, clipboard API with authorization |
| Permissions model | PARTIAL | `PermissionStore`, `setPermission/permissionDecision/listPermissions`, agent-driven | Tests pass; decisions persist per profile | Human prompt UI, approval workflow, sensitive-permission gating (Agent 1 denies agent self-approval on its branch; unmerged) |
| PDF / printing | MISSING | No `PDFKit`/`CGPDF`/print symbols | Nothing to run | Viewer, export, printing |
| Developer inspector (human) | MISSING (backend PARTIAL) | Agent `page.inspect/query/snapshot`, `InspectedNode` role/name/value/href/bounds, `HTMLSerialization`, capture `computed-styles.json` + assets | Agent-side inspection verified; no element picker, no highlight overlay, no visual console/network panel | Human inspector UI bound to the same inspection backend (Phase 2B) |
| Reader / Markdown | MISSING | `SectionDetector` serves design-capture sections, not article extraction; no readability code | Nothing to run | Article/document extraction, Markdown export preserving original |
| Content blocking / privacy | MISSING | No filter target, no rule engine, no classification owner in root package | Nothing to run | Engine-level filter before all request paths incl. media/WebSocket/redirects (Agent 2 scope) |
| Keyboard / focus / selection | PARTIAL | `pressKey`, `focus/blur/focusedNode`, `click/type/fill/submit`, `HitTesting` | Agent-driven input verified incl. fill + hit-testing; `getSelection` is null; no IME handling; no platform key-event routing (needs a window) | Real event routing, IME/composition, selection API, focus-visible semantics |
| Accessibility tree | PARTIAL (backend) / MISSING (platform) | `DOM/Semantics.swift` (`SemanticNode` role/name/value) surfaced via agent inspect | Roles/names observed in `page.query` results; no `NSAccessibility` tree, no VoiceOver path | Platform accessibility tree, announcements, audit |
| Origin / policy enforcement | PARTIAL | `WebSecurity/` (Origin, CORS/preflight, CSP, mixed content, frame/download policy), cookie `SameSite`/`HttpOnly`, scheme guards | Unit + daemon denial tests pass (blocked navigation, scheme denial, HttpOnly script protection) | HSTS (source-only here), frame-ancestor enforcement gaps, redirect-chain hardening (Agent 1 branch, unmerged), TLS decision surfacing |
| Process isolation / sandbox / crash recovery | MISSING | JS executes in privileged `browserd`; no child renderer, no sandbox profile, no crash boundary | No test possible; any hostile page shares the host process | Full Step 2 (Agent 1 remaining work); page-level `restorePage` exists but is lifecycle management, not crash containment |

## 2. Verified working parts

`BrowserRuntime` is the single authority over contexts/pages/sessions (confirmed by
tracing `browserd → AgentSocketServer → AgentCommandDispatcher → NativeBrowserEngine →
BrowserRuntime`); headless and future visible are the same page model. Navigation,
history, DOM/CSS/layout pipeline, deterministic software raster, JS eval with cross-call
lexical scope, cookies/storage/permissions isolation, downloads bytes, bookmarks,
suggest, search-provider persistence, session restore, fleet lifecycle, and capture
export all execute through live root-package paths with green regression coverage
(193/193) and daemon evidence (24/24).

## 3. Partial / missing parts

See matrix. In one line: everything a human can *see or touch* (window, GPU pixels,
video, keychain, prompts, upload, clipboard, PDF, reader, blocker, IME, platform a11y)
is missing; the engine models underneath tabs, profiles, search, history, downloads,
permissions, and inspection are partial-to-working and are the correct attachment
surface for Phase 2B.

## 4. Critical blockers, ordered by dependency

1. **Renderer isolation + sandbox (Agent 1 remainder).** Without it, attaching real
   websites to a human window is unsafe. Gates all real-site usage.
2. **Presentation contract + retained compositor (Agent 2).** Without same-`PageID`
   attach/detach, damage, and input, a SwiftUI shell can only screenshot-mirror, which
   the plan bans. Gates every visible pixel.
3. **GPU text/image/clip/transform pipeline (Agent 2).** Software fallback suffices for
   dev shells, not for scroll/input performance claims.
4. **Target-site compatibility tail (Agent 1 Step 3).** Fixture-green ≠ website-working;
   qualify dynamic apps, auth flows, and forms before promising a browser.
5. **Media engine + content blocker (Agent 2).** Both are architectural, not UI work.
6. **Human-trust systems: Keychain/passkeys, permission prompts + approval workflow,
   IME/platform a11y, upload/clipboard/PDF/reader.** Required before human-usable;
   independent of the shell and implementable against engine APIs once 1–2 land.
7. **Unmerged-branch reconciliation.** Agent 1 (`agent1/redirect-boundary-20260920@e1dc17a`:
   capabilities, redirect/CSP hardening) and this branch diverge with one docs-only
   merge conflict; the `verify_browser.py` ↔ capability/`openProfile`-denial adaptation
   is specified in `Docs/AGENT3_QUALIFICATION.md` but not yet executed against merged SHAs.

## 5. Files to extend (per blocker)

1. `Sources/WebSecurity/*`, new renderer-process target + `Sources/EngineRuntime/BrowserRuntime.swift` orchestration, `Sources/AgentProtocol/UnixSocket.swift` peer identity.
2. `Sources/EngineRuntime/BrowserRuntime.swift` (surface API), `Sources/Display/*`, `Sources/Graphics/MetalRenderer.swift`, new SwiftUI/AppKit shell target (Phase 2B only).
3. `Sources/Graphics/MetalRenderer.swift`, `Sources/Graphics/GlyphAtlas.swift`, `Sources/Graphics/RasterTiles.swift`, `Sources/Display/Compositor.swift`.
4. `Sources/HTML/*`, `Sources/Layout/*`, `Sources/JavaScript/*`, `Sources/WebAPI/*` + `Tests/*/fixtures`.
5. New media target (AVFoundation/VideoToolbox/CoreMedia) + filter owner on the `NetworkSession`/navigation request path (`Sources/Networking/NetworkSession.swift`, `Sources/Navigation/NavigationPipeline.swift`, `Sources/EngineRuntime/PageHostWiring.swift` validators must be wrapped, not bypassed).
6. New Keychain/credential module, permission-prompt flow in `BrowserRuntime` + dispatcher, `Sources/WebAPI/*` (clipboard/upload), new PDF/reader modules.
7. Merge `agent1/redirect-boundary-20260920` + `agent3/engine-services-gate-20260920-work` (+ Agent 2) via reviewable PRs; adapt `Scripts/verify_browser.py`.

## 6. Reproducible tests and benchmarks

Covered under Proof environment above. Raw artifacts: `/tmp/aether-audit/results.json`
(24/24), daemon log alongside it, suite log via `Scripts/test_macos.py`. No GUI or
real-site E2E was possible — there is no window and no media path to test.

## 7. Phase 2A go / no-go

**NO-GO for starting the user-facing Phase 2B SwiftUI shell.** The engine is a genuine,
tested execution core with working headless models, but a human shell today would have
no attachable page surface (blocker 2), no GPU presentation (blocker 3), no sandbox
between hostile pages and the user's machine (blocker 1), no video, and no keychain —
so it could only demo fixtures while implying a browser. A scaffold/dev shell behind
explicit unsupported flags may proceed **only after** blockers 1–2 land and the
integration gate in `Docs/AGENT3_QUALIFICATION.md` passes against merged SHAs; do not
relabel that scaffold as Phase 2B complete. Revisit this verdict when the ledger's open
conditions close with macOS integration evidence.
