# Testing Issue Escalation — agent-native-browser-runtime

Runtime bugs found during the two-agent validation phase. Every unresolved
problem gets a reproducible entry here. `Status: open | owned(<agent>) | fixed | wontfix`.

---

## TISSUE-001

Owner: Agent 2 (event system)
Discovered by: Testing Agent 1
Severity: high (a documented first-class event family never fired)
Subsystem: WebKit event producers

### Problem
`document.mutated` was never emitted. The producer `semanticObserverJS` is only
installed by `WebKitPage.startSemanticObservation()`, which is only called from
`BrowserRuntime.analyzeSemanticPage`, which early-returns unless
`semanticSignalService.isConfigured`. On a normal page with no semantic service,
no DOM-mutation event was ever produced.

### Evidence
- `Sources/EngineRuntime/WebKit/WebKitPage.swift`: observer injected only via
  `startSemanticObservation()` (`script(Self.semanticObserverJS)`).
- `Sources/EngineRuntime/SemanticSignalIntegration.swift`: `analyzeSemanticPage`
  guards `await semanticSignalService.isConfigured else { return }`.
- Test `EventSystemValidationTests.documentAndFocusEventsComeFromRealPageBehavior`
  failed with "no document.mutated event after real DOM mutation".

### Reproduction
Load `/mutate` (DOM change after 200 ms) and read
`runtime.recentEvents(filter: .family(.document))` for 6 s.

### Root cause
A first-class event producer was gated behind an optional external service.

### Fix
Added `semanticObserverJS` as a standard `WKUserScript` (`.defaultClient`, matching
its registered handler) in `WebKitPage.init`.

### Regression test
`EventSystemValidationTests.documentAndFocusEventsComeFromRealPageBehavior`

### Status
fixed (Testing Agent 1)

---

## TISSUE-002

Owner: Agent 3 (branches)
Discovered by: Testing Agent 1
Severity: medium (false fidelity claim; forks look like a full clone)
Subsystem: branch fidelity reporting

### Problem
`BranchStateCatalog.bestEffort` listed `localStorageRehydratedOnOriginVisit`, but a
forked branch page reading `localStorage` sees an empty store. The checkpoint does
capture localStorage and the branch profile stores the rows, but nothing seeds
WebKit's per-store localStorage on the branch.

### Evidence
- `BranchTypes.swift` catalog claimed rehydration.
- `attachProfile` restores localStorage into the in-process `StoragePartition`
  (`context.storage.restoreAll`), not WebKit's `localStorage`; `evaluate` reads
  WebKit's store.
- Test: forked pages read `none` for a key set in the parent.

### Reproduction
`BranchValidationTests.checkpointForksThreeIndependentBranches`.

### Root cause
WebKit exposes no public API to write a website data store's localStorage without
a live page at the origin; rehydration was never implemented, but was reported.

### Fix
Removed the claim from `bestEffort`; added `localStorageAutoRehydration` to
`notCloned` so forks report the limitation honestly.

### Regression test
`BranchValidationTests.checkpointForksThreeIndependentBranches`

### Status
fixed (honest reporting). Full rehydration remains unimplemented; a navigation-time
rehydration hook is the recommended follow-up.

---

## TISSUE-003

Owner: Agent 3 / runtime
Discovered by: Testing Agent 1
Severity: high (forked branch pages are unusable without an undocumented extra call)
Subsystem: branches × WebKit page lifecycle

### Problem
`forkBranch` restores its pages via `openProfile`/`attachProfile`, which creates
them with `lifecycle: .discarded`. A new guard in `webPage` now throws
`Page is discarded; restore it before use` for discarded records, so any
`navigate`/`evaluate`/`agent.exec` on a freshly forked page fails. `forkBranch`
returns `pageCount` and a `pageMap` without indicating a restore is required.

### Evidence
- `Sources/EngineRuntime/WebKit/SystemWebRuntime.swift:59` (guard, currently an
  uncommitted working-tree change).
- `Sources/EngineRuntime/BrowserRuntime.swift:390` (`attachProfile` builds restored
  pages with `lifecycle: .discarded`).
- `BranchValidationTests` / `RuntimeEndToEndValidationTests` fail with
  "Page is discarded; restore it before use" until `restorePage` is called.

### Reproduction
Fork a branch, then `navigate` or `evaluate` its page without calling
`restorePage(pageID:)`.

### Root cause
Two concurrent changes: pages restored from a profile are hibernated
(`.discarded`), and `webPage` began enforcing that lifecycle, while `forkBranch`
neither activates its pages nor documents the required restore.

### Fix
Not applied by Testing Agent 1 (ownership + design decision). Tests now call
`restorePage` and assert the discarded state first.

### Regression test
`BranchValidationTests.checkpointForksThreeIndependentBranches` asserts
`lifecycleState == .discarded` before restore.

### Status
fixed (Agent 3): `branchInfo(for:)` reports `restoreRequiredPages` and fork
documents hibernation. Verified by Testing Agent 1:
`BranchValidationTests` 8/8 green, including `restoreRequiredPages`
assertions (`checkpointForksThreeIndependentBranches`,
`execProgramRetargetsOntoForkedBranchPage`).

---

## TISSUE-004

Owner: Agent 3
Discovered by: Testing Agent 1
Severity: medium (no global branch tree; deletes by root fail)
Subsystem: branch index

### Problem
`forkBranch` writes each child record into the *parent profile's* KV index, so
`listBranches(root)` cannot see grandchildren, and `deleteBranch(root, grandchild)`
throws `notFound`. A supervisor forking a branch-of-a-branch cannot enumerate or
manage descendants from the root.

### Evidence
`forkOfForkRecordsAncestryDeletesChildrenFirst`: `listBranches(root)` returns `[a]`
only; the child is visible only via `listBranches(contextA)`.

### Root cause
Per-profile index by design, with no aggregate/traversal API.

### Status
fixed (Agent 3): `listBranches` walks the whole tree (`loadBranchTree`) and
`deleteBranch` works from anywhere in the tree. Verified by Testing Agent 1:
`forkOfForkRecordsAncestryAndDeletesChildrenFirst` asserts
`listBranches(root) == [a, a2]`; `BranchValidationTests` 8/8 green.

---

## TISSUE-005

Owner: Agent 2/3
Discovered by: Testing Agent 1
Severity: low
Subsystem: branch events

### Problem
`branch.created` is published with the **child** context identity; `branch.discarded`
is published with the **parent** context identity. Consumers cannot assume one
context identity across a branch's lifecycle.

### Evidence
`BrowserRuntime+Branches.swift` publish sites; asserted in
`branchLifecyclePublishesBranchIdentityEvents`.

### Status
fixed (Agent 3): `branchDiscarded` now uses the attached child context with
fallback to the caller context, matching `branchCreated`. Verified by
Testing Agent 1: `branchLifecyclePublishesBranchIdentityEvents` asserts both
events carry the attached context; `BranchValidationTests` 8/8 green.

---

## TISSUE-006

Owner: Agent 2 (event system)
Discovered by: Testing Agent 1
Severity: medium
Subsystem: event bus backpressure

### Problem
`BrowserEventBus.subscribe` buffers with `.bufferingNewest(512)` and drops the
oldest events silently when a subscriber cannot keep up. There is no gap marker,
so a slow consumer may lose navigation/lifecycle events with no signal.

### Evidence
`subscriberBackpressureSilentlyDropsOldestBeyondBuffer`: a 700-event burst yields
exactly `m189…m700` (512 events) for a late reader.

### Status
fixed — verified green by Testing Agent 1 on the full suite
(`swift test --no-parallel --jobs 1` → exit 0, 508 tests, 0 failures), which
includes both `slowSubscriberDropIsObservableAndRecoverableFromJournal`
and `filteredSubscriberLossIsCountedPerSubscriber`. Fix: bus-wide
`droppedEventTotal` counts `yield` drops, `subscribeWithToken` exposes the
subscriber token so `droppedEventCount(forSubscriber:)` is usable (it was
dead API when the token never left the bus), `removeSubscriber` drops the
counters, and the bounded journal stays the recovery path
(`recent(since:)`). `subscribe` still delegates — no signature break.

---

## TISSUE-007

Owner: Agent 5 (leases)
Discovered by: Testing Agent 1
Severity: low
Subsystem: lease expiry ordering

### Problem
`expireWorkspaceLeases` marks the lease `.expired` (observable via
`workspaceLease`) and only then `await suspendWorkspace(...)` (which checkpoints)
before publishing `lease.expired`. A consumer that observes `state == .expired` and
immediately reads the journal can miss the event.

### Evidence
`failureInjectionLeaseExpiryFreezesWorkspaceAndEmitsEvent` initially failed to see
`lease.expired` in the journal right after observing the expired state.

### Fix
Applied by Testing Agent 1: both `expireWorkspaceLeases` and `finishWorkspaceLease` now
persist state → revoke lease-bound work → publish the lease event → `await
suspendWorkspace(...)`. The suspend checkpoint can therefore no longer delay the event.

### Regression test
`RuntimeEndToEndValidationTests.failureInjectionLeaseExpiryFreezesWorkspaceAndEmitsEvent`
now reads the journal immediately after the expired state becomes readable (bounded 500 ms
poll instead of a fixed 1 s sleep) and requires `lease.expired` to be there.

### Status
fixed (Testing Agent 1).

---

## TISSUE-008

Owner: test infrastructure (shared)
Discovered by: Testing Agent 1
Severity: medium
Subsystem: test isolation

### Problem
The Python fixture-server pattern (`Process` + `defer { terminate() }`) leaks
orphaned servers when a test process is killed (`defer` does not run). Orphans
hold ports and make later unrelated suites fail with
`fixture server exited early`. Six orphans (PIDs on ports 18815–18821, PPID 1,
Sep 24–27) were found and cleared.

### Evidence
`WebKitNavigationReliabilityTests.contentIsUsableBeforeResourcesFinish` failed
until the orphans were killed; `lsof` showed stale listeners.

### Fix
Applied by Testing Agent 1: the fixture script now starts a daemon watchdog thread that
polls `os.getppid()` and calls `os._exit(0)` once it is reparented (i.e. the test process
died, including SIGKILL). A killed run can no longer leave a listener holding a port.

### Verification
After the change, `lsof -nP -iTCP:49100-59999 -sTCP:LISTEN` shows no leftover fixtures
after repeated suite runs (including runs killed mid-flight).

### Status
fixed (Testing Agent 1); verified by repeated full-suite runs with no
`fixture server exited early` failures.

## TISSUE-009

Owner: Agent 1 / WebKit runtime
Discovered by: Testing Agent 2
Severity: medium
Subsystem: WebKit media loading

### Problem
The existing media integration tests cannot load their MP4 source through the
current `BrowserRuntime` WebKit-backed page path. The media element reports no
selected source and playback does not advance.

### Evidence
`MediaControlTests` reports `networkState=3`, `readyState=0`, and `currentSrc=""`.
I replaced the original `file://` source in a local experiment with a real
loopback HTTP page and a byte-range-capable MP4 endpoint; the fixture recorded
`/media` but no `/sample.mp4` request. This is a WebKit runtime observation, not
an assertion inferred from source inspection.

### Reproduction
`swift test --no-parallel --jobs 1 --filter mediaElementLifecycleThroughAgent`
and `swift test --no-parallel --jobs 1 --filter mediaJavaScriptBindings`.

### Likely root cause
Unresolved. The backend-created WebKit page is not initiating the media resource
load in this environment; determine whether this is caused by page visibility,
WebKit media policy, or the runtime's media integration before changing policy.

### Files involved
`Sources/EngineRuntime/WebKit/WebKitMedia.swift`,
`Sources/EngineRuntime/WebKit/WebKitPage.swift`,
`Tests/AgentTests/MediaControlTests.swift`,
`Tests/AgentTests/ValidationFixtureServer.swift`.

### Proposed fix
Reproduce using an attached WebKit view and actual media page, then fix the
runtime path or document an explicit unsupported condition. Do not relax
autoplay/user-gesture policy without evidence.

### Blocked work
Accurate media playback/control validation on the browserd-created runtime.

### Status
fixed and verified green (Testing Agent 1, 2026-09-27):
`mediaElementLifecycleThroughAgent`, `mediaJavaScriptBindings`, and
`evaluatePreservesJavaScriptScalarValues` all pass in one run (exit 0).
Media loads, `play()` advances `currentTime`, pause/seek/volume/setMuted
all settle. Contributing factors fixed along the way: the `/media` fixture
video is muted (autoplay/user-gesture policy no longer blocks the scripted
`play()`), fixture-port collisions from orphaned servers (TISSUE-008) are gone,
and the presented test window no longer over-releases itself (TISSUE-010).
No runtime media-policy change was needed — do NOT relax autoplay policy.

**Correction to the earlier "environmental SIGSEGV" note in this entry:** the
crash was not environmental and not intermittent. It was a deterministic AppKit
ownership bug in the test window helper, proven and fixed under TISSUE-010 below
(`swift test --filter MediaControlTests` crashed 100% of the time before the fix,
3/3 green after it). Environment details recorded there.

---

## TISSUE-010

Owner: test infrastructure (`Tests/AgentTests/MediaControlTests.swift`)
Discovered by: Testing Agent 1
Severity: critical (aborted the entire `AgentTests` bundle at ~405 tests, so the
whole repository suite could not be run at all)
Subsystem: AppKit window ownership in the test harness

### Problem
Every full `swift test --no-parallel --jobs 1` run exited non-zero with
`swiftpm-testing-helper ... exited with unexpected signal code 11`, exactly once per
run, after ~404 tests. Every test after that point (≈ 80 tests plus every later
suite) never executed. The crash moved between runs only in which *log line* looked
like the current test; the sequence position was identical.

### Evidence
1. Crash reports (`~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-*.ips`,
   5 of them, all the same signature):
   `objc_release` ← `AutoreleasePoolPage::releaseUntil` ← `objc_autoreleasePoolPop`
   ← `swift::runJobInEstablishedExecutorContext` on the main thread.
2. `NSZombieEnabled=YES swift test --no-parallel --jobs 1 --skip
   'ExecRuntimeValidationTests|EventSystemValidationTests|BranchValidationTests|RuntimeEndToEndValidationTests'`
   printed the object:
   `*** -[NSWindow release]: message sent to deallocated instance 0x7c74574780`,
   and the trap frame read `_NSZombie_NSWind...` (`_NSZombie_NSWindow`).
   So the over-released object is an **NSWindow**, not WKWebView or a runtime type.
3. Minimal deterministic reproducer (100 % failure before the fix, ~10 s):
   `swift test --no-parallel --jobs 1 --filter MediaControlTests` →
   `mediaElementLifecycleThroughAgent` passes, then `mediaJavaScriptBindings` crashes
   the process.
4. The crash is independent of the new validation suites: it reproduced with all four
   of them skipped (`--skip 'ExecRuntimeValidationTests|...'`, 404 passes then SIGSEGV).

### Root cause
`present(_:)` in `MediaControlTests` created the window programmatically
(`NSWindow(contentRect:styleMask:backing:defer:)`). For such windows
`isReleasedWhenClosed` defaults to `true`, so `dismissTestWindow`'s `window.close()`
released the AppKit object while ARC still held a strong reference to it; ARC then
released it a second time. The second release landed inside the main run loop's
autorelease-pool pop, corrupting/crashing the process one or more tests later — which
is why the reported "current test" appeared to move.

### Reproduction (before the fix)
```bash
swift test --no-parallel --jobs 1 --filter MediaControlTests          # SIGSEGV
swift test --no-parallel --jobs 1                                     # SIGSEGV at ~405 tests
```

### Fix
`Tests/AgentTests/MediaControlTests.swift`: set `window.isReleasedWhenClosed = false`
before `orderFront(nil)`, with a comment naming this issue.

### Regression test
The media suite itself is the regression: `swift test --no-parallel --jobs 1 --filter
MediaControlTests` → **3/3 green, exit 0** (was a guaranteed crash), and the full
repository run now completes: `swift test --no-parallel --jobs 1` → **exit 0,
508 tests, 0 failures**.

### Status
fixed (Testing Agent 1). This also unblocked "run all existing repository tests" for
both testing agents: no test after ~405 was reachable before this fix.
