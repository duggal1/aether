# PLAN: Make Aether the Bun of Browsers (P0 performance)

Date: 2026-09-24. Status: planning — no source edits yet.
Smoke test (this session): `/tmp/four_browser_smoke.py` → ALL_PASS on `https://example.com/`
(Aether `browserctl --app app-open` rc=0; Safari/Chrome/Dia processes running; screenshots saved
to `/tmp/four_browser_smoke/`. Known harness gaps found, listed in §0.)

Goal: near-zero avoidable Aether overhead; kill pathological outliers (Jack & Jill pricing
899ms → 13,647ms); fix gradient loading-indicator overrun; prove everything with identical
4-browser comparisons. Never fabricate; never remove features; never fake completion.

## 0. Smoke-test findings (already proven, carry forward)

1. Aether CLI for the real app is `browserctl --app app-open|app-status|...`, NOT
   `page.navigate` / socket `ping`. `browser_comparison_once.py` / `aether_perf_stress.py`
   must be audited for stale subcommands before the full loop (a failed harness is not a
   browser result).
2. Safari/Chrome JS-via-AppleScript probing is permission-gated (fails without
   "Allow JavaScript from Apple Events"). Full harness must NOT depend on it — use
   WebKit `performance.getEntriesByType` inside Aether where we own the WebView, and
   `estimatedProgress`/screenshot-grep or CDP where available for others; always disclose
   measurement asymmetry instead of inventing parity.
3. Dia `open -a` needs retry/wait (window index -1719 on cold start).
4. `screencapture -x` without focusing the target window captures the desktop (today's
   aether.png proves it). Full harness must activate (`open -a` + `osascript activate` /
   `CGWindowList`) each browser before capture.

## 1. Measurement doctrine (fixes the "confusing navigation commits with visible content" trap)

Per-URL, per-browser, sequentially (never parallel — no contention contamination), N≥5 warm
+ 1 cold, record: `requestStart/responseStart/responseEnd` (navigation timing),
FCP, LCP, `domContentLoadedEventEnd`, `loadEventEnd`, wall time to `contentReady`, plus
full distribution (median, p90, p95, max — never average-only). Cold = fresh profile/process;
warm = same WebView, second visit. Same Mac, same network, comparable cache states, same
navigation sequence. Raw JSON + screenshots saved under `perf-results/<date>/`.

## 2. Suspect list (repo-grounded, from this session's inspection)

- `Sources/EngineRuntime/WebKit/WebKitPage.swift` — nav core. Fresh
  `WKWebViewConfiguration()` per page in `init` (line 169) → no `WKProcessPool` /
  `websiteDataStore` reuse audited; 6 KVO observers → `scheduleChange()` → MainActor hop
  per tick (lines 186–209); `publish()` state fan-out on every progress tick; `didCommit`
  / `didFinish` / `decidePolicyFor*` delegate path (lines 502–630) is the first trace
  target for the 13.6s outlier. `WebKitNavigationProbe` already exists — enable it.
- `Sources/EngineRuntime/WebKit/WebKitPrewarm.swift` — 16×16 warm view exists; verify it
  shares pool/store with real pages or it warms nothing.
- `Sources/BrowserUI/.../Design/AetherNavigationGlowState.swift` — glow phases
  (`started→awaitingContent→contentVisible`); indicator overrun = settle condition waits on
  `didFinish`/full progress instead of first visible content. Fix = bind settle to
  `contentReady`/FCP signal, keep `didFinish` as backstop only.
- `Sources/BrowserUI/.../Foundation/AetherLatencyProbe.swift`,
  `Sources/BrowserUI/.../Native/PersistentPageSurface.swift`,
  `State/BrowserWindowModel.swift`, `State/BrowserState.swift` — audit for MainActor
  contention, duplicate observers, tab-sync fan-out during navigation.
- Existing harness: `Scripts/aether_perf_stress.py`, `Scripts/browser_comparison_once.py`
  — repair per §0 before trusting any number.

## 3. Execution phases

- Phase 1 — Harness repair (no src changes): fix stale `browserctl` subcommands, sequential
  runner, window-focus capture, cold/warm separation, distribution stats, raw-result saving.
  Validate on 1 URL × 4 browsers. Gate: harness passes twice deterministically.
- Phase 2 — Outlier triage: Jack & Jill home vs pricing in all 4 browsers. If all 4 slow →
  website-side, record + move on. If Aether-only → `WebKitNavigationProbe` trace of
  `decidePolicy→didCommit→didFinish`, redirect chain, content-process creation, cache
  behavior. One variable at a time (RULES §8).
- Phase 3 — Overhead removal loop (PROFILE→IDENTIFY→FIX→BUILD→LAUNCH→MEASURE→COMPARE→REPEAT):
  config/process-pool reuse, delegate-path leanness, KVO/MainActor coalescing, JS-injection
  audit, background-task isolation, glow-settle fix. Each fix = one before/after 4-browser
  run on the same URLs. Revert on regression.
- Phase 4 — Full comparison: `aether_perf_stress.py` + `browser_comparison_once.py` on all
  20 URLs, all 4 browsers, saved results, before/after report.
- Phase 5 — Harden: `swift build -c release`, `swift test --no-parallel`, no new warnings
  in touched modules; update `Docs/VALIDATION.md` numbers (currently stale).

## 4. Acceptance (matches user §10)

Real source diffs; before/after numbers per fix; outlier explained with trace evidence;
indicator settles on visible content; no feature removal; no regressions; real Aether.app
tested; 4-browser raw results saved.

## 5. Non-goals / guards

No benchmark manipulation, no fake completion timers, no disabling systems for numbers,
no custom-engine rendering work (retiring per AGENTS.md), no parallel-browser runs, no
claiming superiority without data.
