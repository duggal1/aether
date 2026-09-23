# S0 Baseline — Type-Safe RPC Modernization

Date: 2026-09-22 · Host: macOS 27.0 arm64, 8 CPUs, 8 GiB · Swift 6.4 (Xcode selected)

## Recovery

- Git root: `/Users/harshitduggal/workspace/Aether` (own repo, 635 tracked files; **not** home-dir repo — AGENTS.md stale on this).
- 55 uncommitted changes at start (44 BrowserUI design files — untouched except as noted).
- In-tree snapshots: `agents/opencode/type-safe-rpc/before/` (44 Swift files + Package.swift + git-status-before.txt).
- Off-tree recovery: `/var/folders/ct/cwpf7vpn059fkp932tq9zm4m0000gn/T/opencode/aether-recovery/aether-working-tree-20260922-145955.tar.gz` (26 MB, full tree excl. .build).

## Build-blocker fix (pre-existing WIP, not modernization)

- `AetherEngineAdapter+Network.swift`: empty `BrowserProxyCredentialStoring` conformance missing `deleteProxyCredential`. Implemented as direct mirror of existing `saveProxyCredential` keychain delete path (same file, lines 70–79). One method added; no design change.

## Test baseline (serial, `nice -n 10 swift test --skip-build --no-parallel --jobs 1`)

- Exit 1 · **276 passed · 21 failed** (44 issues) — full log `/tmp/aether-s0-test-baseline.log`.
- Pre-existing failed list: `s0-preexisting-failed-tests.txt`.
- Failures cluster: (a) AgentTests WebKit "Page is not loaded" / capture / find / media — 16 tests; (b) BrowserUI design symbol tests — 5 tests.
- **These are pre-existing.** Success gate for later phases = no *new* failures vs this list.

## enginebench (release)

```
nodes=50006
parse_ms=475.410125
style_ms=182.583916
layout_ms=865.673792
boxes=50003
```

## RPC latency (release browserd, `Scripts/rpc_latency_bench.py`, n=200, 1 conn/call)

| Op | p50 ms | p95 ms | p99 ms |
|---|---|---|---|
| ping | 0.054 | 0.227 | 0.552 |
| context.create+list | 0.100 | 0.129 | 0.135 |
| page.query | 0.267 | 0.660 | 1.347 |
| context.setCookie | 0.228 | 0.588 | 0.713 |
| context.cookies | 0.186 | 0.332 | 0.517 |
| page.loadHTML | 3.367 | 4.901 | 57.402 |
| page.snapshot | 16.864 | 20.839 | 28.098 |

- JSON encode ≈ 1.9 µs/call, decode ≈ 2.0 µs/call — **codec is noise vs WebKit work** (corroborates: do not replace JSON without evidence).
- browserd RSS after run: **67,696 KB**.
- Cookie set/list through live daemon succeeded (historical crash path healthy in this run).
- Artifact: `s0-rpc-baseline.json`.

## Interpretation for later phases

1. Serialization is ~2 µs; ping p50 54 µs end-to-end. S5 will re-run this harness; expect *no* meaningful win from codec changes.
2. Real latency lives in loadHTML/snapshot (WebKit).
3. Gate every subsequent phase: full serial test run, compare failures against this baseline list.
