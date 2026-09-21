# Aether WebKit performance — 2026-09-21

Implemented three changes without changing navigation readiness, rendering policy, content blocking, or UI design:

- WebKit state updates publish only the changed page. Runtimes with no subscribers skip UI-state projection and retain no observation cache. Context/page creation and removal still use full reconciliation, including closure events.
- DOM preparation and queries/snapshots/actions execute together in one isolated-world JavaScript evaluation. Node-generation checks, password redaction, and wire schemas are preserved.
- Unix-socket writes suppress SIGPIPE per socket on Darwin, per send on Linux. Abandoned agent requests now fail their write instead of terminating the browser.

## Controlled measurements

| Measurement | Previous path | Changed path | Scope |
|---|---:|---:|---|
| 1,000 state updates with 512 logical pages | 1,389.46 ms | 8.80 ms | ~158× less time in a synthetic debug-build publication test; not loading speed |
| Median DOM query | 0.314 ms | 0.188 ms | 40% lower; 200 alternating samples per path on one loaded page, after warmup, identical results |
| Abandoned navigation client | SIGPIPE exit (-13) on first attempt | Survived 5 attempts | Saved previous release binary versus rebuilt release |

The broader local release benchmark did not demonstrate faster end-to-end queries: medians for 1/4/8 concurrent pages were 0.589/1.091/2.068 ms before and 0.917/1.075/2.410 ms after. This includes socket dispatch and runtime work and ran in separate processes. The controlled alternating test isolates the removed WebKit round trip; its improvement must not be presented as an end-to-end browser improvement.

The first saved-binary local run failed an assertion because at least one navigation response had an empty title at eight-way concurrency. That incomplete run remains in local-before.json. A diagnostic rerun passed and reproduced SIGPIPE; the candidate passed. This is not evidence that the title-response race was fixed.

## Verification

- Serialized release build passed (144 seconds).
- Seven targeted Swift tests passed: publication subscription/update/closure/stale-event behavior; publication scaling; DOM batching equivalence; native adapter/profile identity; runtime contexts; dispatcher lifecycle; invalid numeric input. No claim that the full legacy test suite passed.
- Local release integration passed with 1, 4, and 8 concurrent pages: real navigation, query/queryAll, filling/clicking, password redaction, bounded snapshots, stale-node rejection after reload, and cleanup to zero pages/contexts.
- Default authenticated transport survived 12 connections (6 completed requests and 6 abandoned replies); invalid credentials were rejected.
- All task-owned daemon processes are stopped after each harness run. Other applications and pre-existing daemons were left alone.

## Limits and next starting point

The live runtime is WebKit. Legacy custom-renderer enginebench timings do not describe real browsing. No GPU, compositor, frame-time, total browser memory, or whole-browser CPU improvement is established here. Daemon RSS excludes WebKit services and is recorded only as a partial observation. Zero lag is not established.

The historical 31 daemon restarts cannot be attributed solely to memory pressure: an abandoned client reproducibly kills the saved daemon with SIGPIPE under a small local workload. Apple's documented socket behavior supports the fix: https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/setsockopt.2.html

Next investigate actual navigation milestones and WebKit/network timing for the long public-site tail, with process/resource attribution and controlled repeated trials. Keep dispatch-to-title separate from FCP and interactive responsiveness.

## Follow-up verification (current tree)

- Serialized release build passed again with all changes from both workstreams.
- Sequential 16-site harness on the current release binary: 32/32 OK,
  median dispatch-to-title 283.88 ms, 0 daemon restarts
  (`results/seq-aether-final.json`). Prior medians on the same harness:
  483 ms (earlier workstream), 507 ms (after-change run), 505 ms
  (saved-binary run, 31 restarts). Run-to-run network variance dominates
  these deltas; this run is not evidence of a further loading-speed gain.
  It confirms the SIGPIPE survival across a full public-site run.
