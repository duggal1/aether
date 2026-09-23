# S1 Results — Socket ownership/cancellation + cookie regression

## Changes

1. `Sources/AgentProtocol/UnixSocket.swift` — rewritten server loop:
   - Poll-based accept (100 ms default) — cancellation-responsive, no accept busy-spin.
   - `SO_RCVTIMEO` / `SO_SNDTIMEO` on accepted client fds (defaults: 60 s read, 30 s write) — blocking recv/send release themselves.
   - `SocketWorkerTable` (Mutex): tracks client fds; `interruptAll()` uses `shutdown(SHUT_RDWR)` so cancellation unblocks in-flight recv/send immediately (Darwin close() does not reliably wake blocked recv — shutdown does).
   - Connection cap (default 64): over-limit accepts are closed immediately.
   - `AgentSocketClient` gained read/write timeouts (default 30 s) so browserctl cannot hang forever.
   - Long-running authorized commands preserved: timeouts apply only to recv/send, not handler execution. Covered by test.
   - Error taxonomy unchanged: `transport` / `unauthorized` codes identical.
2. `Sources/AetherApp/Integration/AppAutomationHost.swift` — `shutdown()` + `deinit` cancels the server task (was fire-and-forget forever).
3. `Sources/AetherApp/Integration/AetherEngineAdapter.swift` — `shutdown()` now stops the automation host first.
4. `Tests/AgentTests/AgentSocketLifecycleTests.swift` — 8 new tests: idle timeout, partial-message stall, abrupt disconnect, normal shutdown unlink, cancellation releases blocked idle client, connection limit, slow authorized handler, **cookie dispatcher round-trip (historical crash regression)**.

## Verification

- New socket/cookie tests: **11/11 pass** (`s1` filtered runs).
- Full AgentTests: 64 tests, 47 pass, **17 fail — byte-identical to S0 pre-existing list, 0 new failures**.
- Live release smoke: `browserd --no-auth` + `browserctl ping` / `context-create` / `context-set-cookie` / `context-cookies` all OK; clean kill.
- RPC latency vs S0 (n=200): ping p50 0.054→0.047 ms, page.query p50 0.267→0.218 ms, cookies p50 0.186→0.172 ms, RSS 67.7→68.3 MB — **no regression**.

## Blocking environmental note

Full-package `swift build --build-tests` intermittently fails on **user's concurrent BrowserUI edits** (`AetherSymbol.cookie` missing while `BrowserIcons` references it). Not touched — design work in flight. Engine targets + AgentTests build and run cleanly via `--target AgentTests` + `--skip-build`.
