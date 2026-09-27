# Testing Agent 1

Validation owner for **Agent 1 — Local Agent Execution Runtime**, **Agent 2 — First-Class
Browser Event System**, and **Agent 3 — Branchable Browser Contexts**. (Agent 4–6 are
Testing Agent 2's.)

Everything below was reproduced on this working tree against real WebKit and a real local
HTTP origin unless explicitly labelled otherwise. No subsystem is called PASS because a
method exists or a unit test passes.

## Systems under test

1. **Local execution runtime** — `ExecProgram` (`Sources/AgentProtocol/AgentExec.swift`),
   `AgentExecRuntime` (`Sources/BrowserEngine/AgentExecRuntime.swift`), `agent.exec` route.
2. **Browser event system** — `Sources/BrowserEvents/`, `BrowserRuntime.events` /
   `observeEvents` / `recentEvents`, WebKit producers in `Sources/EngineRuntime/WebKit/`.
3. **Branchable browser contexts** — `Sources/EngineRuntime/BranchTypes.swift`,
   `BrowserRuntime+Branches.swift`.

## Implementation inspected

- `Sources/AgentProtocol/{AgentExec,AgentMessages}.swift`
- `Sources/BrowserEngine/{AgentExecRuntime,AgentCommandDispatcher,AgentCommandDispatcher+Authority}.swift`
- `Sources/BrowserEvents/{BrowserEvent,BrowserEventBus}.swift`
- `Sources/EngineRuntime/{BrowserRuntime,BrowserRuntime+Branches,BranchTypes,
  BrowserRuntime+WorkspaceLeases,WorkspaceLeases,TaskVerification}.swift`
- `Sources/EngineRuntime/WebKit/{SystemWebRuntime,WebKitPage,WebKitPage+Script,WebKitDialogs}.swift`
- Work files `agent-1-work.md`, `agent-2-work.md`, `agent-3-work.md`, `discussion.md`,
  `issue.md`, and Testing Agent 2's report/discussion posts.

## Test environment

- macOS (Darwin, macOS 27 SDK), Swift 6.4, Xcode toolchain, `apple/arm64`.
- `swift test --no-parallel --jobs 1` (serialized; WebKit is not safe to interleave with
  the other agent's runs).
- Real loopback HTTP fixture (`Tests/AgentTests/ValidationFixtureServer.swift`, Python
  `http.server`) plus real WebKit navigation/evaluate/cookies/localStorage.
- Suites owned here: `ExecRuntimeValidationTests` (15), `EventSystemValidationTests` (11),
  `BranchValidationTests` (8), `RuntimeEndToEndValidationTests` (5) — **39/39 pass**
  (`swift test --no-parallel --jobs 1 --filter
  'ExecRuntimeValidationTests|EventSystemValidationTests|BranchValidationTests|RuntimeEndToEndValidationTests'`).
- Full repository suite: `swift test --no-parallel --jobs 1` → **exit 0, 508 tests, 0
  failures**, all 21 test targets (the count grows as the other agent adds tests; see
  "Whole-repository regression" below).

## Tests executed

### 1. Local execution runtime — `ExecRuntimeValidationTests` (15/15)

- 400 real DOM nodes iterated in **one** `agent.exec` invocation: `operations == 4`,
  `stepsExecuted == 806`, 401 results, ~1.4 s. Proves locality: the loop costs zero
  external round trips.
- Transport instrumented at the dispatcher boundary: 40 `evaluate` steps behind **one**
  `dispatcher.handle(...)` call, `operations == 43`, one response.
- Multi-page workload (added here): two pages in one context driven by one invocation,
  `operations == 7`, 32 ordered results, still exactly one boundary call.
- Malformed programs: unknown op rejected at decode; version/step/timeout bounds; empty
  `forEach` binding; undefined ref → `undefinedVariable`; non-array `forEach` →
  `typeMismatch`; `forEach` over its limit refused (never silently truncated); unknown
  `session` → `sessionNotFound`.
- Cancellation mid-loop → `cancelled` in **< 2 s** (measured), no leaked lease
  registration, runtime still responsive, new context/page usable afterwards.
- Deadline mid-navigation (6 s `/slow`) → `timeout` in < 1 s, not 6 s.
- Page closed mid-wait → step `failed` (never silent success), no crash.
- `execution.started` / `execution.finished` paired with the invocation id and terminal
  status.
- Lease revocation (joint with Testing Agent 2): confined program revoked mid-navigation
  on lease release → `cancelled` with `error.code == "leaseRevoked"`, no results, latency
  < 3 s, registration released. Host-run variant (untouched-context expiry) also covered.

### 2. Browser event system — `EventSystemValidationTests` (11/11)

- Real HTTP navigation: `navigation.started → committed → finished` in order,
  `navigation.redirected`, monotonic sequences, correct page/context identity,
  non-decreasing timestamps.
- Rapid superseding navigations keep monotonic ordering under load.
- 300 console lines delivered in order, none lost; the journal agrees with the stream.
- `document.mutated` from a real DOM mutation; `focus.changed == true` from a real
  `focus()`.
- `network.navigationResponse` with status + MIME type; `navigation.failed` with
  `benign=false` on a refused connection.
- `page.created` / `page.closed` / `context.destroyed` on real close/destroy.
- Two simultaneous subscribers receive identical, non-duplicated sequences.
- Backpressure characterised: 700-publish burst → 512 newest delivered, oldest dropped.
  Now **observable** (`droppedEventTotal == 188`) and **recoverable**: the dropped prefix
  is still in the journal and served back by `recent(since:)`, and a consumer can detect
  the hole from the sequence numbers alone.

### 3. Branchable contexts — `BranchValidationTests` (8/8)

- S42 built from a real origin (cookie + localStorage), checkpointed, forked into A/B/C:
  distinct contexts, distinct WebKit store UUIDs, page remap, correct record count.
- Fork report now names `restoreRequiredPages` (the hibernated pages) instead of leaving a
  consumer to hit `Page is discarded` mid-program; driving a hibernated page without
  restoring still fails loudly, restoring clears the field.
- Cookies cloned into every branch, isolated after A-only mutation; localStorage not
  auto-rehydrated (reported honestly in `notClonedState`).
- Fork-of-fork records ancestry; the **root sees the whole tree** and can delete a
  grandchild (its record is removed from the owning branch's index); deleting a parent
  with children is refused.
- Branch records survive a fresh `BrowserRuntime` over the same profile directory.
- Invalid checkpoint / unknown branch / empty name / unknown context / ephemeral
  checkpoint all fail with typed errors.
- `branch.created` / `branch.discarded` both carry the branch's own context identity.
- Storage cost measured: parent 378 216 B vs branch 122 960 B (no full profile copy).
- An exec program re-targets onto a forked branch page **and activates it inside the
  program** with a `restore` step.

### 4. Cross-system — `RuntimeEndToEndValidationTests` (5/5)

- Full lifecycle: lease → exec → ordered events → checkpoint S42 → fork A/B → branch
  isolation → approval/handoff parks branch A → human changes real page state → resume →
  agent reads the human's value → verification `verified` → release lease → destroy
  context with branch B intact.
- Failure injection: lease expiry freezes the workspace and `lease.expired` is already in
  the journal the moment the expired state is readable; verification never returns
  optimistic success (wrong URL / missing element → `failed`, unobservable network →
  `inconclusive`); cancelled handoff releases the agent; page closed under a lease keeps
  the lease consistent and releasable.

## Expected behavior

- A multi-step program runs inside one invocation with bounded, cancellable, typed
  outcomes; N browser operations are not N external round trips.
- Events come from real browser behavior, ordered, identity-carrying, bounded,
  multi-subscriber, with loss that is observable and recoverable — never silent.
- A checkpoint forks into independent branches with isolated cookies/storage, durable
  identity, correct metadata, clean deletion, an explicit activation contract, and honest
  fidelity reporting.
- Losing a workspace lease stops the work that lease authorized.

## Actual behavior

All of the above hold on this tree. The three defects found earlier in this session
(`document.mutated` never firing, an untrue branch fidelity claim, and a silent
backpressure hole) are fixed and regression-tested; the two remaining capability limits
(no WebKit localStorage rehydration; per-profile branch index) are reported honestly and
now have explicit API/contracts rather than hidden behaviour.

## Failures found (this session)

1. **Forked branch pages were unusable and the report did not say so.** A fork returns
   `.discarded` pages, `webPage` throws `Page is discarded; restore it before use`, and
   `agent.exec` had **no** way to activate a page. → TISSUE-003.
2. **Branch index was per-profile.** `listBranches(root)` could not see grandchildren and
   `deleteBranch(root, grandchild)` failed `notFound`, so a supervisor could not enumerate
   or manage the tree it forked. → TISSUE-004.
3. **Branch lifecycle events used inconsistent context identity.** `branch.created`
   carried the child context, `branch.discarded` the parent's. → TISSUE-005.
4. **Subscriber backpressure was silent.** Beyond 512 buffered events the oldest were
   dropped with no counter or signal. → TISSUE-006.
5. **Lease state was observable before its event.** `expireWorkspaceLeases` published
   `lease.expired` only after `await suspendWorkspace(...)`. → TISSUE-007.
6. **A lost lease did not stop a running program.** Lease expiry/release suspended pages
   but an in-flight `agent.exec` kept driving the (now frozen) workspace. → ISSUE-007 /
   Testing Agent 2's TISSUE-001.
7. **Orphaned fixture servers leaked.** `Process` + `defer { terminate() }` never runs on
   an abnormal exit; six orphaned servers held ports and broke unrelated suites. →
   TISSUE-008.
8. **The whole `AgentTests` bundle crashed (SIGSEGV) at ~405 tests.** Every full
   repository run aborted: no test after `MediaControlTests.mediaJavaScriptBindings`
   executed, so "all existing tests" could not be run at all. → TISSUE-010 (new).

## Root causes

1. `forkBranch` restores its pages through `openProfile`/`attachProfile`, which creates
   them hibernated; the contract was neither reported nor reachable from `agent.exec`.
2. `forkBranch` persists each child record into the *parent profile's* index; nothing
   traversed the resulting tree.
3. Two publish sites picked different identities for the same branch lifecycle.
4. `BrowserEventBus.subscribe` used `.bufferingNewest(512)` and discarded the `yield`
   result, so drops were unobservable.
5. Persist → checkpoint → publish ordering in the expiry path.
6. Admissions were authorized once at the dispatcher; nothing connected a lease
   transition to the executor's cancellation.
7. A test-process `defer` cannot run when the process is killed.
8. `MediaControlTests`' window helper created an `NSWindow` programmatically (where
   `isReleasedWhenClosed` defaults to `true`), then called `close()`: AppKit released the
   window and ARC released its strong reference again. The over-release corrupted the main
   run loop's autorelease pool and crashed the bundle later in `objc_release`. Confirmed by
   running with `NSZombieEnabled=YES`: `*** -[NSWindow release]: message sent to
   deallocated instance` and a `_NSZombie_NSWindow` frame.

## Fixes made

1. **TISSUE-003** — `ExecStep.restore` (new step op, `page.restore` in step form) plus
   `BrowserBranchInfo.restoreRequiredPages` (computed live from page lifecycle, with a
   decoding default so older reports still decode). A program can now activate the branch
   page it is about to drive in the same invocation; callers of the native API are told
   exactly which pages need it. Hibernating pages on fork is kept on purpose (a fork must
   not block on the network).
2. **TISSUE-004** — `loadBranchTree` walks each branch's directory (or its live context's
   profile) depth-first; `listBranches` returns the whole subtree from any root, and
   `deleteBranch` resolves a record anywhere in the tree, removes it from the index of the
   profile that owns it, and still refuses a branch with children.
3. **TISSUE-005** — `branch.discarded` now publishes the branch's own attached context
   (falling back to the caller's context for a dormant branch), matching `branch.created`.
4. **TISSUE-006** — the bus counts what it dropped (`droppedEventTotal`, plus a
   per-subscriber accessor) by inspecting the `yield` result; the journal remains the
   catch-up path. Loss is now measurable and recoverable instead of silent.
5. **TISSUE-007** — expiry and release/cancel now revoke, publish, then suspend. The
   regression test reads the journal immediately after observing the expired state.
6. **ISSUE-007** — Runtime gains a lease-bound-work registry
   (`registerLeaseBoundExecution` / `unregisterLeaseBoundExecution` /
   `expandLeaseBoundExecution` / `revokeLeaseBoundExecutions`); `AgentExecRuntime`
   registers each run, is revoked at the next step boundary, and reports
   `cancelled` + `error.code == "leaseRevoked"` (never swallowed by `onError: proceed`).
   Delivered jointly with Testing Agent 2, who extended the registry to expand by touched
   context and to cancel the run's child task.
7. **TISSUE-008** — the fixture server now runs a parent-watchdog thread and exits when the
   test process dies, so a killed run can never leave a listener behind.
8. **TISSUE-010** — set `isReleasedWhenClosed = false` on the test window. The full
   repository suite went from "aborts at test ~405" to **508 tests, 0 failures, exit 0**.

## Regression tests added

- `Tests/AgentTests/ExecRuntimeValidationTests.swift` —
  `execDrivesTwoPagesInOneInvocation`, `leaseEndRevokesConfinedExecutionInFlight`,
  cancellation-latency and no-leaked-registration assertions.
- `Tests/AgentTests/EventSystemValidationTests.swift` —
  `slowSubscriberDropIsObservableAndRecoverableFromJournal`.
- `Tests/AgentTests/BranchValidationTests.swift` —
  `forkReportNamesPagesRequiringRestore`; the tree/delete and event-identity tests were
  strengthened to the new contract (root enumerates and deletes descendants; both branch
  lifecycle events carry the branch's context); `execProgramRetargetsOntoForkedBranchPage`
  now activates the forked page with an in-program `restore` step.
- `Tests/AgentTests/RuntimeEndToEndValidationTests.swift` — lease-expiry ordering asserted
  directly from the journal after the state became readable.
- `Tests/AgentTests/ValidationFixtureServer.swift` — orphan watchdog.
- `Tests/AgentTests/MediaControlTests.swift` — window is no longer
  released-when-closed (crash regression).

## Performance findings

- 400-node DOM loop: ~1.4 s, **4** browser operations, one invocation.
- 43 browser operations behind one dispatcher call: ~0.4 s.
- Two-page program: 7 operations, one invocation, ~0.5 s.
- Deadline mid-navigation returns in < 1 s (does not wait out the 6 s page).
- Cancellation mid-loop observed in < 2 s; lease revocation of a confined program in
  < 3 s (both measured against a 6 s in-flight navigation).
- Event ordering held under a 6-way superseding-navigation burst; 300 console messages
  delivered without loss inside the bounded buffer.
- Fork storage: branch ≈ 0.33× the parent profile directory (no full clone).
- Subscriber buffer is newest-512; a 700-event burst drops 188 (now counted) and all 188
  are recoverable from the journal.
- Whole repository suite: 508 tests, all targets, ~2 minutes serialized, no crash.

## Integration findings

- **exec × handoff (Agent 4):** exec fails closed with `handoff_active` for a parked page;
  after resume it reads the human's real change.
- **exec × branches (Agent 3):** `pageMap` + `restoreRequiredPages` + the `restore` step
  make a fork usable inside the executing program; the branch record stays in its parent
  profile, which the tree traversal now handles.
- **events × branches:** branch lifecycle events carry branch identity and a consistent
  context identity.
- **lease × exec (Agent 5 × Agent 1) — the important fix:** admission-only authorization
  was not enough; a lease transition now revokes the work it authorized, in one step of
  latency, with an explicit `leaseRevoked` outcome.
- **verification × events (Agent 6):** `navigationResponse` verification consumes the
  event journal and returns `inconclusive` when nothing observable matched.
- **events × tests / AppKit:** the bundle-wide crash was an AppKit ownership bug in a test
  helper, not a runtime bug; it masked every test after ~405.

## Whole-repository regression

```
swift test --no-parallel --jobs 1     # → exit 0, 508 tests, 0 failures
```

Per-suite highlights relevant to this ownership: `AgentExecTests`, `BrowserEventsTests`
(8), `BrowserEventIntegrationTests`, `BranchHandoffTests`, `WorkspaceLeaseTests` (4),
`RuntimeEndToEndValidationTests` (5), `ExecRuntimeValidationTests` (15),
`EventSystemValidationTests` (11), `BranchValidationTests` (8), `MediaControlTests` (3),
`TaskVerificationTests` (5), `WebKitNavigationReliabilityTests` (11) — all green. The
previously red legacy-`PageRecord` suites (`CaptureAdapterTests`, `PageFindTests`,
`AgentFleetTests`) are green in this run too, so the ISSUE-004 migration gap no longer
reproduces.

## Current status

| Subsystem | Status |
| --- | --- |
| Agent 1 — Local execution runtime | **PASS** |
| Agent 2 — Browser event system | **PASS WITH LIMITATIONS** |
| Agent 3 — Branchable browser contexts | **PASS WITH LIMITATIONS** |

- **Agent 1 PASS.** Real WebKit workloads with proven locality (N operations, one
  invocation), bounded and cancellable execution with measured latency, typed failures,
  correct lifecycle events, no crash or leak under page closure, timeout, cancellation, or
  lease revocation. Limitations (not exec defects): a program-created context is not
  auto-destroyed on cancellation; a step in flight against a page that is being frozen can
  still complete before the revocation boundary is observed.
- **Agent 2 PASS WITH LIMITATIONS.** Ordering, identity, multi-subscriber delivery,
  bounded journal, console/document/network/lifecycle/focus events verified from real
  browser behaviour; the dead `document.mutated` producer was fixed; loss is now counted
  and recoverable. Limitations: no per-subresource network events (documented WebKit gap);
  the legacy `networkLogEntries` projection is not backed by WebKit events; the
  subscriber buffer is a fixed newest-512 with recovery only through the bounded journal;
  download/popup/dialog/permission/authentication/fileChooser producers need a real window
  and were not exercised end-to-end here.
- **Agent 3 PASS WITH LIMITATIONS.** Checkpoint/fork isolation, durable identity, ancestry,
  tree enumeration/deletion, restart recovery, bounded fork cost, and typed error handling
  verified; hibernated fork pages now have an explicit, reachable activation contract.
  Limitations, unchanged and reported honestly: WebKit localStorage is captured but not
  auto-rehydrated on a branch (no public API to seed a store without a live page);
  sessionStorage/IndexedDB/service workers/caches/client certs/server-bound sessions are
  not cloned; there is no merge.

## Remaining failures

- **None in Agents 1–3's own suites** (39/39) and **none in the repository** (508/508
  as of the last full run, including three runs after my final edits).
- Known, non-regressing product limitations, each visible in the API rather than hidden:
  no branch merge, no localStorage rehydration, no clone of sessionStorage/IndexedDB/
  service workers/caches, per-profile branch storage (trainable through the tree walk),
  and no per-subresource network events.
- `TISSUE-003`–`TISSUE-008` and `TISSUE-010` are fixed; `TISSUE-009` (media) was fixed by
  Testing Agent 2 and its suite now passes. `ISSUE-007` is closed by the revocation work.

## How to reproduce

```bash
# Everything I own (39 tests)
swift test --no-parallel --jobs 1 --filter \
  'ExecRuntimeValidationTests|EventSystemValidationTests|BranchValidationTests|RuntimeEndToEndValidationTests'

# The crash this round found and fixed (was SIGSEGV, now 3/3 green)
swift test --no-parallel --jobs 1 --filter MediaControlTests

# Whole repository
swift test --no-parallel --jobs 1
```

## Session note 2026-09-27 — lease-cancel-exec merge + test-hygiene fixes

This session continued as Testing Agent 1 against a live tree with a second
editor working the same files; everything below was coordinated in
`testing-discussion.md` to avoid splice collisions.

- **Lease revocation of in-flight `agent.exec` (ISSUE-007 / TA2-TISSUE-001):
  closed.** The runtime side (`registerLeaseBoundExecution`,
  `revokeLeaseBoundExecutions` on release/cancel/expiry before suspend) had
  landed without an executor caller. A teammate wired the confined path
  (static `allowedContexts` + `requestRevocation` flag + `leaseRevokedCode`
  + `leaseEndRevokesConfinedExecutionInFlight`); I completed it to all runs:
  `run()` spawns one child task per program (box with cancel-on-adopt, so a
  revoke racing registration still lands), registers with the static set
  **plus** dynamic `expandLeaseBoundExecution` on every context the program
  touches (`requirePage` now always resolves `pageInfo`; `gateContext` and
  `createContext` also expand), and revoke does both `box.cancel()` (prompt,
  aborts in-flight sleeps) and the state flag (precise code/step path,
  overrides `onError: proceed`). `CancellationError` outcomes consult the
  flag so the evidence reads `leaseRevoked`. New regression
  `leaseExpiryRevokesUnconfinedExecutionTouchingTheContext`: host run +
  reaper expiry → `cancelled` in ~1.1 s, empty results, zero leaked
  registrations, runtime responsive. Do not rework `AgentExecRuntime.swift`
  run()/box design without replying in testing-discussion.
- **TISSUE-006 backpressure signal: completed.** `subscribeWithToken`
  returns the subscriber token so `droppedEventCount(forSubscriber:)` is
  callable (it was dead API — the token never left the bus);
  `removeSubscriber` now drops its counters; new regression
  `filteredSubscriberLossIsCountedPerSubscriber` (700-burst → exact 188).
  `subscribe` delegates unchanged.
- **User report (white test window + speaker audio during test runs):
  fixed.** Cause was `MediaControlTests.present()`: a borderless window with
  `orderFrontRegardless()` plus scripted `play()` on an unmuted fixture
  video. Fixture `/media` is muted; the window is alpha-0, mouse-transparent,
  offscreen, and ordered with non-activating `orderFront(nil)`; both media
  tests now assert `muted == true`. A `dismissTestWindow` helper stops loads
  and detaches views before close.
- **TISSUE-003/004/005: verified fixed by Agent 3** (`restoreRequiredPages`,
  tree-walk `listBranches`/`deleteBranch`, consistent created/discarded
  identity); `BranchValidationTests` 8/8 green, no new code needed.
- **TISSUE-007 ordering + TISSUE-008 orphans:** ordering already correct
  (revoke → publish → suspend) with a green regression test; killed 4
  confirmed-stale (PPID 1) fixture orphans and added the reparent watchdog
  to `WebKitNavigationReliabilityTests`' inline script. Three files still
  bootstrap bare `python -m http.server` (`WebKitRealSessionTests`,
  `WebKitEgressProbeLiveTests`, `CredentialVaultTests`) — migrate to the
  shared helper when touched.
- **TISSUE-009 media:** green (3/3 with the JS-scalars test) with muted
  fixture + presented window; no runtime policy change. The teardown SIGSEGV
  seen mid-session was root-caused under TISSUE-010 (programmatic NSWindow
  `isReleasedWhenClosed` default + `close()` double-release), not memory
  pressure as first suspected.
