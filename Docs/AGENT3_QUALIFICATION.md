# Agent 3: engine-only qualification ledger and gate verdict

Branch: `agent3/engine-services-gate-20260920-work` (continues `origin/agent3/engine-services-gate-20260920`).
Base: `main@01f9ec1d9df377cf8377852e1400782a4366b7a0`.
Host for all runs below: macOS 27.0 (26A5425a), arm64, Apple Swift 6.4, Command Line Tools.

Classification follows `Docs/IMPLEMENTATION_STATUS.md`: **wired** = implemented and exercised
in the live root-package path with tests; **incomplete** = implemented with known gaps;
**source-only** = present but excluded from the live root package or unused by callers;
**unsupported** = not implemented. "Tested on real sites" is claimed nowhere: real-network
evidence is loopback fixtures plus smoke-level public navigation.

## Evidence this turn

| Artifact | Result |
| --- | --- |
| `swift build -c release` | Build complete, only the known-benign `search path ... not found` linker warnings |
| `Scripts/test_macos.py` (serial, RSS-bounded) | **193/193 tests passing, exit 0** across 15 targets (peak tree RSS ≈ 0.1–1.2 GiB depending on build vs test phase) |
| `Scripts/verify_browser.py` against release `browserd` | **24/24 checks passing**, incl. dynamic DOM-to-raster green pixel `(0,255,0)`, dynamic capture PNG green pixel, typed-address navigation, download bytes, profile checkpoint/reopen, isolation/lifecycle cleanup, bounded/parallel captures, and the new engine-services persistence check |
| `enginebench` baseline | Unchanged harness; rerun on demand before performance claims |

New regression coverage: `Tests/AgentTests/BookmarksSearchTests.swift` (8 tests: bookmark
round-trip/upsert/remove, non-web-URL denial, profile checkpoint round-trip, corrupt-profile
fails-closed, suggest ranking/limits, provider default/persist/denial, dispatcher surface).
Fixed: wrong case-sensitive `page.find` expectation (`== 2` → `== 1`; the fixture holds
exactly one lowercase match).

## Capability ledger (Agent 3 scope + dependencies)

| Capability | Classification | Evidence / dependency |
| --- | --- | --- |
| Typed URL/search input (`page.navigateInput`) | wired (incomplete) | Live dispatcher → `BrowserRuntime.navigate`; loopback + search-kind tests; stored per-profile provider fallback. No provider UI, no suggestion ranking inside the address field |
| Live find-in-page (`page.find`) | wired (incomplete) | Live snapshot search with mutation version; daemon-observed JS mutation; hidden-ancestor filtering. No selection/highlight API |
| Bookmarks | wired (incomplete) | Same-context CRUD, schema-v3 durable table, checkpoint/open round-trip, daemon-verified across reopen. No import/export, no sync, no folders/tags |
| Navigation suggestions | wired (incomplete) | Bookmarks-first + own-context history, bounded, de-duplicated. No frecency ranking, no remote suggestions |
| Search provider preference | wired (incomplete) | Validated endpoints, immediate kv persistence, requires opened profile. No multi-provider list, no UI |
| Profile checkpoint/restore | wired (incomplete) | Storage, session pages, bookmarks, provider restore; corrupt DB fails closed with context intact. No crash-recovery soak, no cross-principal authorization |
| Dynamic-page render/capture pixels | wired (incomplete) | Green-pixel assertions in viewport raster and capture PNG after JS mutation. Fixture-only; no real-site visual parity |
| Capture (static/long/parallel/timer) | wired (incomplete) | Daemon-verified formats, truncation bounds, leak checks. Cooperative cancellation present; no same-PageID attach proof |
| Authenticated session ownership, renderer sandbox/crash containment | unsupported on this branch | Agent 1 branch (`origin/agent1/security-standards-core-20260920`) implements capability-gated dispatcher + fetch/CORS/cookie hardening; **not integrated here**. New Agent 3 methods resolve authority via standard `page`/`context` params, so Agent 1's generic guard covers them with no special case |
| Shared silent/visible page surface, retained Metal pipeline | unsupported on this branch | Agent 2 contract pending; live path remains `SoftwareRenderer` |
| Native media playback, engine content blocker | unsupported | No media/blocker target in root package; Agent 2 scope |
| Workers, WebAssembly, Canvas 2D, service workers, WebGL/WebGPU, WebRTC, DRM, printing/PDF, accessibility/IME | unsupported or source-only | `page.workers` returns `[]` by design; see `Docs/ADDITIONS_INTEGRATION.md` for source-only drops |

## Engine-only exit-gate verdict (unchanged: OPEN)

A green Agent 3 branch satisfies its Step 6 engine-services slice and the two Step 1
evidence follow-ups (dynamic-page pixels, file-to-runtime map), but the engine-only exit
gate from `Aether/PLAN.md` requires the integrated Agents 1+2+3 tree: sandboxed hostile
renderers, authenticated co-control, attached-surface handoff, real media, and live
blocking are not present on this branch. Do not advance to GUI work on the strength of
this branch alone. The final gate must rerun `Scripts/test_macos.py` and
`Scripts/verify_browser.py` against the merged SHAs and record exact run/artifact IDs
for every condition above before any status changes to passing.
