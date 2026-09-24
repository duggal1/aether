# PLAN v2: Four-browser comparison, rewritten from scratch (2026-09-24)

## Why v1 failed (recorded so nobody repeats it)

1. Fresh `--user-data-dir` profiles trigger Dia/Chrome first-run onboarding (email wall).
   NEVER benchmark a blank profile on a browser with mandatory onboarding.
2. Executing browser binaries directly from the sandboxed shell breaks SingletonLock /
   profile writes. ALWAYS launch via `open -a` (proper macOS launch context).
3. JavaScript-via-AppleScript needs per-browser user toggles; sandboxed prefs are
   unreadable AND unwritable from our shell. Dead end without user action. Stop trying.
4. safaridriver needs Safari's "Allow Remote Automation" toggle. Same wall.
5. Throwaway /tmp scripts with 5 different mechanisms = unmaintainable thrash. Deleted.

## The design (one runner, one mechanism per browser, real profiles only)

New file: `Scripts/four_browser_compare.py` — single owner of all 4-browser measurement.
`Scripts/aether_perf_stress.py` is KEEP (proven: FCP-gated, correct `--app` commands,
real Aether data already collected). Deleted: all /tmp scratch scripts (done).

| Browser | Navigate | Readiness signal | Screenshot |
|---|---|---|---|
| Aether | `browserctl --app app-open/app-navigate` | `app-metrics` FCP + contentReady (works today) | `screencapture -l` window id (works today) |
| Chrome | quit → `open -a --args --remote-debugging-port` (REAL profile) → CDP `Page.navigate` | CDP `Runtime.evaluate` paint probe (FCP/LCP/nav timing) | CDP `Page.captureScreenshot` (exact viewport, no focus hacks) |
| Dia | same as Chrome, different port/app | same probe JS everywhere | same |
| Safari | AppleScript `set URL` (no JS needed for navigation) | visual first-paint: poll `screencapture -l` window, first frame ≠ blank | same captures |

Safari readiness detail: no JS, no toggles, no permissions. Poll window screenshots at
~10Hz after navigation starts; first frame differing from the blank/loading baseline
beyond threshold = first visual paint. Decode with system Quartz; if unavailable,
byte-size heuristic + saved frames for manual review. Method asymmetry vs FCP is
DISCLOSED in every report, never papered over. If the user later flips one Safari
toggle (Allow Remote Automation), Safari upgrades to exact FCP via safaridriver.

## Rules the runner obeys

- Real profiles only. Sequential browsers (zero contention). Restore each browser
  (quit flagged instance, reopen normally) when done.
- Paired home→route × N, cold (fresh launch) + warm separated, median/p95/worst,
  raw JSON + screenshots under `perf-results/<stamp>/`. One browser failing never
  blocks the others; setup failure is reported, never a number.
- Validation gate: 1 site × 4 browsers × 1 rep green before ANY 20-URL run.

## Then (unchanged from v1)

Triage Jack & Jill → source fixes (WebKitPage pool reuse, KVO/MainActor fan-out, glow
settle) with per-fix before/after → full 20-URL run → harden. Acceptance per §10.
