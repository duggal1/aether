# Retire the Custom Web Engine — migration plan

Decision (final): WebKit (`WKWebView`) is the exclusive website engine.
Retire the custom web-engine implementation. Preserve the custom browser.

Baseline: release build green before migration (`swift build -c release --jobs 1`,
exit 0). Rebuild after every step below.

## Classification

### A. Remove (custom web-engine implementation)

| Module | Role | Removal precondition |
|---|---|---|
| `HTML` | custom tokenizer/tree builder | B/C migrated; enginebench replaced |
| `CSS` (+`CSSCalc`, `MediaQuery`) | custom tokenizer/parser | same |
| `Style` | selector match/cascade/resolver | same |
| `Text` measurer/cache | custom text metrics | same |
| `Layout` | custom layout engine | same |
| `Display` | display list/compositor/paint chunks | keep only types still used by bridge, or migrate bridge off them |
| `Graphics` renderers | `SoftwareRenderer`, `MetalRenderer`, tiles, atlas, budgets | keep `PixelBuffer` type until capture path migrated |
| `Images` decode/loader | custom image pipeline over `Networking` | WebKit owns page images; keep only what capture needs |
| `JavaScript` interpreter + builtins | custom ECMAScript runtime | agent JS interface migrated to `WebKitPage.evaluate` |
| `WebAPI` timers/fetch bindings | custom bindings for the interpreter | same |
| `Navigation` pipeline | fetch→parse→style→layout pipeline | runtime keeps orchestration shape, pipeline body removed |
| `Networking` resource loading for pages | page-subresource loading | WebKit owns page networking; keep only what agent/CLI tooling needs |
| `AetherApp/Presentation/EnginePageView*` | retired Metal-loop page view | DONE (removed, no references remain) |
| `Benchmarks/enginebench` | custom-pipeline benchmark | replace with WebKit navigation timing or drop |
| Engine-specific tests | `HTMLTests`, `CSSTests`, `LayoutTests`, `RenderingTests`, `JavaScriptTests`, `WebAPITests`, `PerformanceTests`, parts of `AgentTests`/`BlockerTests` | remove with their modules; add WebKit-backed browser tests |

### B. Preserve (browser infrastructure)

`AetherHumanUI` (SwiftUI chrome, tabs, omnibox), `AetherApp` shell + `Integration`
adapters, tab/session/history/bookmark/download state, profiles + `Persistence`
(SQLite), `AgentProtocol` (transport models), `AetherCapture`, `ContentBlocker`
filter lists, `EngineCore` (geometry/IDs/atoms), `DOM` identity types (`NodeID`)
used by the WebKit agent bridge, `WebSecurity` policy types, `Scheduler`
fleet policy, `Diagnostics` metrics, `Media` registry/bridge, `browserctl` /
`browserd` CLIs.

### C. Migrate (mixed modules)

| Module | Keep | Remove / replace |
|---|---|---|
| `EngineRuntime/BrowserRuntime` | actor, contexts/pages/sessions, profiles, fleet, agent DTOs, WebKit wiring | every `.experimental` branch; custom pipeline state (`PageRecord.loaded`, JS hosts, display lists) |
| `EngineRuntime/PageHostWiring`, `PagePresentation`, `PageEditing` | WebKit-backed paths | experimental paths |
| `EngineRuntime/MediaMirror` | media registry bridge | `JavaScript` import (retype against WebKit values) |
| `BrowserEngine` facade + dispatcher | public API, JSON projections | `Graphics` import (keep only `PixelBuffer` or move the type) |
| `WebKitPage+Script` | evaluate/query/snapshot/find | `Graphics` import if type moves |
| `browserctl` | all subcommands | retarget from experimental to WebKit backend |
| `AgentTests` | protocol/dispatcher coverage | experimental-backend fixtures → WebKit-backed |

## Ordered steps

1. DONE — Remove retired `EnginePageView` Metal view + dead adapter casts.
2. Retarget `browserctl`/`browserd` to `.webKit`; verify `ping`, navigation,
   snapshot over the socket.
3. Strip `.experimental` branches from `BrowserRuntime` navigation/inspection
   paths (`navigate`, `goBack/Forward`, `reload`, `inspect`, `snapshot`,
   `evaluate`, `render`, `scroll`, `focus`), keeping one backend.
4. Migrate agent JS/snapshot interfaces fully onto `WebKitPage`; delete
   `PageHostWiring` experimental half and custom `DOM` document storage use.
5. Move `PixelBuffer` (and any surviving leaf types) out of `Graphics`;
   delete renderers/tiles/atlas.
6. Delete pipeline modules (`HTML`, `CSS`, `Style`, `Layout`, `Display`
   remainder, `JavaScript`, `WebAPI`, `Navigation` pipeline, `Images`
   remainder, `Text`), updating `Package.swift` after each deletion.
7. Replace `enginebench` with WebKit navigation timing; prune obsolete tests;
   add WebKit-backed browser coverage (navigation, JS eval, snapshot, stale
   nodes, storage across reload).
8. Final: `Package.swift` graph contains no pipeline modules; full `swift
   build -c release`, `swift test --no-parallel --jobs 1`, `--verify-webkit`
   run with screenshots.

## Status (measured, read before continuing)

- Steps 1, 2, 3, 5 done, release build green after each.
- Step 2 proof: headless `eval`/`render`/`inspect`, daemon `ping`,
  socket `page-open` + `page-snapshot` with real DOM — all exit 0.
- Step 3: 32 `backend == .webKit` branch sites collapsed; `backend`
  property, `BrowserRenderingBackend` enum, and all call-site args removed.
  No `backend`/`.experimental` references remain in `Sources/` or `Tests/`.
- Step 5: custom renderers deleted (`SoftwareRenderer`, `MetalRenderer`,
  tiles, atlas, budgets, `DamageCulling`); `PixelBuffer` + `RendererError`
  moved to `EngineCore` (minus the `DecodedImage` blend helper, which only
  served the dead renderer); `Graphics` is a one-line re-export shim;
  `RenderingTests` target removed.
- Perf work: `receiveWebState` now calls `publishPageStates()` (fixes stale
  URL/title/loading in UI after in-page navigations); prewarm (view +
  `about:blank` at `createPage`); reclaim on suspend/freeze/discard with
  reload-on-restore; `suspendPage` is now async.
- Fleet anomaly (unreproduced): one `fleet-sweep 1` discarded 11/11 active
  pages; three later sweeps keep-first correctly. Do not chase without a
  reproduction; re-verify sweep behavior after the next runtime edit.
- Memory note: closing WKWebViews does not shrink WebKit child RSS —
  WebKit intentionally retains cached processes/page cache (its own speed
  strategy). Reclaim value is fewer live views (no JS/DOM/KVO per
  background tab), observable via `fleet-pages` lifecycle, not via `ps`.
- Next: private experimental helpers in `BrowserRuntime` (still referenced
  by dead tails), then pipeline module deletion in dependency order.

## Perf track (measured)

- `context.blocking` method + `page-snapshot [limit]` + `page-open [commit|complete]`
  shipped; usage text synced. Runtime WebKit linkage verified: system
  WebKit 625.1.29, no bundled engine.
- Sweep byte-estimate: live WebKit views count 8MB default (was 0 =
  always-discard); `lastActive` now updates on web state publish.
- Scaling (20 heavy sites, fresh ctx per level): 8 workers is the sweet
  spot; 20 workers collapses OFF (65.8s makespan) but survives ON (21.9s).
  Blocking ON: medians -25-40%, compile 30-218ms once. Caveat: conditions
  ran in fixed order (OFF then ON), so warmth confounds the ON gain —
  treat as preliminary; interleave to confirm.
- Settle=commit saves 0.8-2.4s on long-tail pages, ~0 on fast pages.
- Foreground FCP stays sub-second on award sites; background tabs measure
  the throttle, not the engine.

## Rules for every step

- Migrate before deleting. Never break the green build across steps.
- One step per build+verification cycle.
- No explanatory source comments. Keep public surfaces small.
- Do not claim completion per step without the build + relevant test evidence.
