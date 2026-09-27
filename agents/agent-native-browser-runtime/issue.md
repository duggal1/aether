# Shared Issue Escalation — agent-native-browser-runtime

Format per issue is defined in the team prompt. Open issues go here.
`Status: open | owned(<agent>) | fixed | wontfix`.

---

## ISSUE-001

Owner: Agent 3
Discovered by: Agent 1
Severity: blocking (whole-package build is red; no agent can compile or test)
Subsystem: EngineRuntime branches (`Sources/EngineRuntime/BrowserRuntime+Branches.swift`)

### Problem

`BrowserRuntime+Branches.swift` (476 lines, new file) references a companion
surface that does not exist yet, so `swift build` fails with ~40 errors, all
in that one file. Every other agent is blocked on compiling and testing until
this resolves.

### Evidence

`swift build` log (`/tmp/aether-exec-build.log` on this host), representative
errors:

```text
BrowserRuntime+Branches.swift: error: cannot find 'branchRecords' in scope (x5)
BrowserRuntime+Branches.swift: error: cannot find 'contextBranchIDs' in scope (x4)
BrowserRuntime+Branches.swift: error: cannot find 'branchContexts' in scope (x4)
BrowserRuntime+Branches.swift: error: cannot find 'loadBranchRecords' in scope (x3)
BrowserRuntime+Branches.swift: error: cannot find 'saveBranchRecords' in scope (x2)
BrowserRuntime+Branches.swift: error: cannot find 'describe' in scope (x2)
BrowserRuntime+Branches.swift: error: cannot find 'attachedPageMap' in scope (x2)
BrowserRuntime+Branches.swift: error: cannot find 'withParentProfile' in scope
BrowserRuntime+Branches.swift: error: cannot find 'purgeWebKitStore' in scope
BrowserRuntime+Branches.swift: error: cannot find 'childBranchRecords' in scope
BrowserRuntime+Branches.swift: error: cannot find 'FilterEngine' in scope (missing import?)
BrowserRuntime+Branches.swift: error: value of type 'WebCookieValue' has no member 'expires' / 'sameSite'
BrowserRuntime+Branches.swift: error: 'nowSeconds' / 'contextCounter' / 'pageCounter' /
  'normalized' / 'loadPersistedDownloads' / 'storagePage' / 'originKey' inaccessible (private)
BrowserRuntime+Branches.swift:155: error: cannot call value of non-function type 'ContextID'
  (parameter `contextID` shadows method `contextID(containing:)`; same shape as the
  HandoffCenter.swift:50 breakage Agent 1 already fixed with `self.`)
BrowserRuntime+Branches.swift: error: cannot convert 'BrowserPageInfo' to 'BrowserBranchInfo' (x3)
BrowserRuntime+Branches.swift: error: extra arguments in call (ContextRecord init? check fields)
```

### Reproduction

`swift build` at repo root. Only file with errors is the branches file.

### Likely root cause

The file was written against a planned companion surface (branch record index,
`info(for:...)`/`describe(_:)` projections, `withParentProfile`,
`purgeWebKitStore`, actor stored state, widened helpers) that has not landed
yet. Possibly a second half of the change is still in flight.

### Files involved

- `Sources/EngineRuntime/BrowserRuntime+Branches.swift` (the broken file)
- `Sources/EngineRuntime/BranchTypes.swift` (Agent 1 repaired two brace-splice
  corruptions here to unblock parsing; content untouched otherwise)
- `Sources/EngineRuntime/BrowserRuntime.swift` (owns the private helpers and
  the actor state the branches file needs)

### Proposed fix

Agent 3 to land the missing companion surface (or split the file so the
compilable prefix merges first). Agent 1 deliberately did NOT invent branch
storage/design to make it compile — that is Agent 3's ownership.

### Blocked work

All agents: `swift build` / `swift test` for any target depending on
EngineRuntime (i.e. everything behind `BrowserEngine`).

### Status

fixed

### Resolution

The report is stale against the current checkout: `BrowserRuntime+Branches.swift` was absent at
inspection time, so the reported 476-line implementation and its compiler diagnostics could not be
reproduced. The incomplete `BranchTypes.swift` draft was retained and connected to a new runtime
implementation in `Sources/EngineRuntime/BrowserRuntime+Branches.swift`. That implementation uses
existing `ProfileStore` tables/KV and creates a fresh UUID-backed WebKit store per fork. The
AgentTests target compiled and both focused branch/handoff tests passed, including fork isolation,
deletion, lifecycle, and restart recovery. `swift test --filter BranchHandoffTests --no-parallel
--jobs 1` passed all 3 tests. Other AgentTests failures are described in `discussion.md`.

---

## ISSUE-002

Owner: unassigned (all agents read)
Discovered by: Agent 1
Severity: high (work destruction; erodes trust in shared tree)
Subsystem: team workflow / git hygiene

### Problem

Files are being deleted or reset without owner consent:

- `Tests/AgentTests/AgentExecTests.swift` (Agent 1, new) vanished from disk
  twice, both times shortly after a `swift test` run. Recreated from scratch
  both times; currently protected via `git add -N` + `/tmp` backup.
- `git status` shows staged deletions (`D`) of five UI files under
  `Sources/BrowserUI/Sources/AetherHumanUI/` (`Design/AetherViewportGlow.swift`,
  `Settings/AdvancedSettingsView.swift`, `Settings/NetworkSettingsView.swift`,
  `Settings/SearchLocationSettingsView.swift`, `Settings/USFlagView.swift`).
- `agents/agent-native-browser-runtime/agent-1-work.md` was reset to a
  280-byte stub, wiping a full work file (since rewritten by Agent 1).

### Evidence

`git status --porcelain` output on this host; missing-file errors from the
edit tool (`File ... not found` immediately after a successful edit +
test run).

### Reproduction

Unknown actor. Candidates: a teammate cleanup script, `git clean -fdx`,
staged `git rm`, or an external sync process.

### Likely root cause

Unknown. Needs each agent to confirm they are not running destructive
commands.

### Files involved

Listed above, plus whatever else may have been silently removed.

### Proposed fix

- Everyone: confirm in discussion.md that you run no `git clean`, `git rm`,
  `git restore`, `git revert`, `git checkout --`, or bulk delete scripts.
- Everyone: `git add -N` new files promptly so `git clean` skips them, and
  keep off-tree backups of in-flight work until committed.
- Owner of the UI deletions: either restore them or declare the refactor
  intentionally in discussion.md.

### Blocked work

Agent 1 verification (twice delayed). Potentially anyone with uncommitted
new files.

### Status

open

---

## ISSUE-004

Owner: Agent 2 (page-state ownership), cc Agent 5
Discovered by: Agent 1
Severity: high (20+ failing tests across fleet/capture/find/media/session
suites; agent-observable state incomplete for WebKit-loaded pages)
Subsystem: EngineRuntime legacy `PageRecord` vs WebKit page path

### Problem

The runtime has two page paths and only one is populated for WebKit loads:

- WebKit path (`webPage(pageID).*`): navigate, loadHTML, query, queryAll,
  scroll, evaluate, wait — works (Agent 1's exec tests prove it).
- Legacy `PageRecord` path (`requirePage` → `page.loaded`): hover, focus,
  blur, pressKey, fill, selectOption, submitForm, historyEntries,
  networkLogEntries, consoleOutput, mainFrame, listWorkers, pendingDialogs,
  nodeAtPoint, metrics, lifecycle suspend/restore, fleet byte estimates,
  capture, find, media — throws `pageNotLoaded` or returns empty for pages
  loaded via `loadHTML`/WebKit navigate, because nothing populates
  `PageRecord.loaded`, `history`, or `networkLog` on that path.

### Evidence

`swift test --filter AgentTests` (this host): failing tests include
`hoverFocusBlurRoundtrip`, `scrollAndHitTesting`, `keyboardFillSelect`,
`lifecycleSuspendFreezeDiscardRestore`, `fleetSweepDemotesExcessPages`,
`findInPage*` (3 tests), `media*` (2), `capture*` (3),
`realSession*` (2), `suggestRanksBookmarksBeforeHistory`,
`scrolledRenderMatchesViewportGeometry`, and
`contentIsUsableBeforeResourcesFinish`. Representative:

```text
Caught error: Page is not loaded: 1  (hover/focus/pressKey/fill paths)
Expectation failed: history.result?.array?.count == 1 (got 0)
Expectation failed: result...["matches"]?.array?.count == 1 (got 0)
```

Follow-up: Agent 2's later focused `BrowserEventIntegrationTests` run passed 6/6, including
`navigationEmitsOrderedTypedEvents` and title-change delivery. That event failure from the earlier
broad run is no longer a confirmed symptom; the legacy WebKit page-state readers remain the
reproducible ownership gap.

### Reproduction

`swift test --filter AgentTests --no-parallel` at repo root.

### Likely root cause

The WebKit migration (`SystemWebRuntime`, `webPage`, `synchronizedWebInfo`)
moved loading/observation to `WKWebView` without back-filling the legacy
record fields that ~20 APIs and their tests still read. Either the legacy
readers must be rehomed onto WebKit state, or the WebKit load path must
maintain the record — an ownership decision for Agent 2/5, not a drive-by
fix.

### Files involved

- `Sources/EngineRuntime/BrowserRuntime.swift` (`requirePage` readers:
  hover/focus/history/networkLog/console/mainFrame/workers/dialogs/...)
- `Sources/EngineRuntime/WebKit/SystemWebRuntime.swift` (WebKit load path)
- `Tests/AgentTests/AgentFleetTests.swift`, `PageFindTests.swift`,
  `MediaControlTests.swift`, `CaptureAdapterTests.swift`, etc.

### Proposed fix

Agent 2/5 to decide the single source of truth for page state and migrate
the legacy readers (or the tests, if the legacy shapes are intentionally
retired — but then update the tests explicitly, don't leave them red).

### Blocked work

Agent 1 exec coverage is limited to WebKit-path ops until this resolves
(click/type/evaluate work; hover/focus/fill/pressKey steps will fail with
`pageNotLoaded` on WebKit pages — documented limitation, not an exec bug).

### Status

open

### Integration review update

Several older failures in the broad AgentTests run were independently reproduced and corrected:
`loadHTMLBuildsInspectableDocument` now distinguishes synthetic `loadHTMLString` content from an
HTTP response, preserves its current URL as history, and returns its document title; the
`dispatcherExposesFleetSurface` history assertion and `consoleFrameWorkersDialogs` now pass.
`navigationEmitsOrderedTypedEvents` also passes in a focused six-test BrowserEventIntegrationTests
run. The remaining legacy WebKit operations and capture/find/media failures remain open.

## ISSUE-003

Owner: Agent 6
Discovered by: Agent 6
Severity: medium
Subsystem: Agent test integration

### Problem

The integrated AgentTests target did not compile because two workspace lease tests used identical Swift function names in two source files.

### Evidence

swift test --filter VerificationTypesTests reached AgentTests module compilation and reported duplicate declarations for workspaceLeaseLifecycleAndIsolation() and workspaceLeaseRecoversAgainstNewContextIdentity() in AgentFleetTests.swift and WorkspaceLeaseTests.swift.

### Reproduction

Run swift test --filter VerificationTypesTests from the repository root.

### Likely root cause

The lease lifecycle/recovery coverage was added to both the existing AgentFleet test file and the dedicated WorkspaceLease test file during integration.

### Files involved

- Tests/AgentTests/AgentFleetTests.swift
- Tests/AgentTests/WorkspaceLeaseTests.swift

### Proposed fix

Keep both coverage paths and give the fleet-local variants distinct test function names.

### Blocked work

SwiftPM test compilation and all focused test runs using the AgentTests target.

### Status

resolved

### Resolution

Renamed the two fleet-local test functions to agentFleetWorkspaceLeaseLifecycleAndIsolation and agentFleetWorkspaceLeaseRecoveryAfterDestroy. The dedicated lease test names remain unchanged.

---

## ISSUE-005

Owner: Agent 2
Discovered by: Agent 2
Severity: medium (agent-visible regression + blocks console events)
Subsystem: EngineRuntime / WebKit console

### Problem

`BrowserRuntime.consoleOutput(pageID:)` could not work for WebKit pages: it required the removed
`PageRecord.loaded` and returned the dead `JSRuntime.consoleOutput`. `WebKitPage.evaluate` always
reported `console: []`.

### Evidence

- `BrowserRuntime.consoleOutput` guarded `page.loaded != nil`.
- WebKit pages never populate `PageRecord.loaded`.
- `WebKitPage+Script.swift`: `evaluate(_:)` returns `console: []`.

### Reproduction

`Tests/AgentTests/AgentFleetTests.swift::consoleFrameWorkersDialogs` calls `console.log('hi there')`
then asserts `consoleOutput == ["hi there"]`.

### Likely root cause

Experimental→WebKit migration left the console reader on dead state.

### Files involved

`Sources/EngineRuntime/BrowserRuntime.swift`, `Sources/EngineRuntime/WebKit/WebKitPage.swift`.

### Proposed fix

Inject a `console`/`window.onerror`/`unhandledrejection` bridge into the **page** content world,
emit `console.message` events, and serve `consoleOutput(pageID:)` (now `async`) from the bridge's
bounded line buffer.

### Blocked work

Console event family; console assertions in agent tests.

### Status

fixed by Agent 2 as part of the event stream. Verified by
`Tests/AgentTests/BrowserEventIntegrationTests.swift::consoleMessagesEmitEventsAndFeedConsoleOutput`.
(`AgentFleetTests::consoleFrameWorkersDialogs` still fails on `mainFrame`/`pendingDialogs`, see ISSUE-006.)

---

## ISSUE-006

Owner: runtime / Agent 6 (agent surface); related to ISSUE-004
Discovered by: Agent 2
Severity: medium (pre-existing agent-visible regression)
Subsystem: EngineRuntime legacy `PageRecord` readers on WebKit pages

### Problem

The WebKit runtime did not provide `mainFrame(pageID:)` from live page state. The old report also
misstated `pendingDialogs` as throwing: it returns the legacy queue, which is empty for WebKit
pages. `networkLogEntries` remains the legacy network logger and is not populated from WebKit.

### Evidence

- Before the integration fix, `BrowserRuntime.mainFrame` required `PageRecord.loaded`, which the
  WebKit path does not populate.
- `WebKitDialogs` emits `dialog.opened` events but presents native NSAlert sheets; it does not
  expose a runtime queue or agent-resolvable dialog ID.
- WebKit main-frame responses are available through `network.navigationResponse`. A call to
  `loadHTML` uses `loadHTMLString` and has no HTTP response to log.

### Reproduction

`consoleFrameWorkersDialogs` previously failed at `mainFrame` for a loaded WebKit page. It now passes
after `mainFrame` reads `webStates`. `loadHTMLBuildsInspectableDocument` now passes after history
seeding and title fallback; it expects no HTTP log for synthetic HTML.

### Likely root cause

The migration left legacy `PageRecord` readers disconnected from WebKit state. Native alert sheets
and network response events have different semantics from the old in-process dialog/network logs.

### Files involved

- `Sources/EngineRuntime/BrowserRuntime.swift`
- `Sources/EngineRuntime/WebKit/SystemWebRuntime.swift`
- `Sources/EngineRuntime/WebKit/WebKitDialogs.swift`
- `Sources/BrowserEvents/BrowserEvent.swift`

### Proposed fix

`mainFrame` now reads `WebPageState`; `SystemWebRuntime` records the current URL for documents not
listed in WK back-forward history and synchronously falls back to `document.title` when WebKit's
title property has not caught up. Keep `network.navigationResponse` as the authoritative WebKit
response signal. A first-class, agent-resolvable native dialog queue remains a distinct design task.

### Blocked work

No longer blocks `loadHTMLBuildsInspectableDocument` or `consoleFrameWorkersDialogs`. Main-frame
response consumers should use `BrowserEvents`; the old `networkLogEntries` projection still does
not include WebKit responses.

### Status

Partially resolved. `mainFrame` is fixed, and the prior claim that `pendingDialogs` throws was
incorrect. Native dialog resolution and a typed WebKit-to-NetworkLogEntry projection are not
implemented.

## ISSUE-007

Owner: Agent 5 with Agent 1 integration
Discovered by: integration review
Severity: high (a worker can keep executing after losing its workspace lease)
Subsystem: workspace lease revocation / `agent.exec`

### Problem

Lease expiry, release, and cancellation suspend the workspace pages but do not cancel an in-flight
`agent.exec` invocation. The executor's cancellation support only responds to `Task` cancellation;
there is no link from lease state transitions to the request task. A running program can therefore
continue after the host has revoked its workspace, and may report completion after the lease is no
longer valid.

### Evidence

- `BrowserRuntime+WorkspaceLeases.swift::finishWorkspaceLease` and `expireWorkspaceLeases` persist
  the new state, call `suspendWorkspace`, and publish an event; they do not signal execution tasks.
- `suspendWorkspace` stops page navigation and freezes pages but does not cancel RPC handler tasks.
- `AgentExecRuntime.run` races execution against its deadline and handles parent task cancellation,
  but does not observe lease lifecycle events or re-check active lease state between operations.
- `AgentCommandDispatcher.handle(_:principal:ownership:)` checks the lease before dispatch only.

### Reproduction

Start a long `agent.exec` wait on a leased page, then have the host call
`workspace.lease.cancel` or wait for lease expiry. The lease API returns after suspending the page;
there is no cancellation signal or lease-specific terminal result delivered to the exec request.

### Likely root cause

Workspace leases and execution tasks have separate lifecycles. The dispatcher has an authenticated
principal ID at request admission, but the executor receives only an allowed-context set; the lease
manager has no registry of execution cancellation handles.

### Files involved

- `Sources/EngineRuntime/BrowserRuntime+WorkspaceLeases.swift`
- `Sources/BrowserEngine/AgentExecRuntime.swift`
- `Sources/BrowserEngine/AgentCommandDispatcher+Authority.swift`
- `Sources/BrowserEngine/AgentCommandDispatcher.swift`

### Proposed fix

Bind each non-host exec invocation to its authenticated principal and the leased context it actually
uses. Register a cancellation handle with the workspace lease lifecycle; expiry/release/cancel should
cancel that invocation and preserve its partial `ExecOutcome` as `.cancelled`. Avoid cancelling work
for unrelated contexts merely because the same principal owns them.

### Blocked work

Reliable lease revocation while a worker is executing; Agent 5's lease isolation guarantee is only
admission-time today.

### Status

open
