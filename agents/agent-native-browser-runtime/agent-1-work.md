# Agent 1 Work

## Ownership

Agent 1: local agent execution runtime. A multi-step browser program executes
in one invocation beside `BrowserRuntime` (server-side in `browserd` via one
`agent.exec` RPC, or in-process via `AgentExecRuntime` / tests) instead of one
RPC round trip per browser operation. Covers: variables, loops, conditions,
browser queries, navigation, page operations, structured results, failures,
cancellation, timeouts. Public surface designed so Agent 6 can expose it via
SDK/CLI/MCP as a thin delegate.

## Repository findings

- Single state owner: `BrowserRuntime` actor
  (`Sources/EngineRuntime/BrowserRuntime.swift`, ~2100 lines). All browser
  mutation goes through it. No second automation path allowed (repo law).
- Wire: newline-delimited JSON over Unix socket. `AgentMethod` in
  `Sources/AgentProtocol/AgentMessages.swift` (now 100+ with handoff/approval/
  credentials/exec additions from Agents 1+4). `AgentCommandDispatcher.handle`
  is the large switch plus JSON projections. `AgentProcedure` typed
  `Input/Output` pattern exists and is reused for `AgentExec`.
- Auth: `AgentCommandDispatcher+Authority.swift` gates by method/prefix;
  `agent.exec` resolves target contexts dynamically per page op.
- Handoff (Agent 4, landed): `requireAgentControl(pageID:)` throws
  `HumanRequestError.blocked` (`handoff_active`) for parked pages; exec calls
  it before every page op — fail-closed. `HumanRequestRecord` already carries
  `branchID`, `executionID`, `session`.
- Events (Agent 2, landing): `Sources/BrowserEvents/` (`BrowserEvent`,
  `BrowserEventBus` actor with `publish/subscribe/recent`),
  `BrowserRuntime.events` + `observeEvents(filter:)` / `recentEvents(...)`.
  `executionStarted(id:)` / `executionFinished(id:outcome:)` kinds reserved.
  Exec does NOT publish yet — pending a runtime-level publish helper; the
  `executionID` in every `ExecOutcome` is the join key.
- Branches (Agent 3, in flight): `BranchTypes.swift` landed (`BranchID` is
  UUID-backed, deliberately not `EngineIdentifier` — survives restarts).
  `BrowserRuntime+Branches.swift` references a companion surface not yet
  landed (see issue.md ISSUE-001). NOTE: this conflicts with Agent 2's
  discussion proposal (`BranchID: EngineIdentifier`) — needs resolution.
- Fleet/leases (Agent 5, landing live): `workspaceLeases` state appearing in
  `BrowserRuntime`; exec takes `allowedContexts: Set<UInt64>?` so the
  scheduler can confine a program to leased contexts (deny-by-default when
  set; `createContext` refused under confinement — pre-create via
  `context.create` which binds ownership).
- JS evaluation: `BrowserRuntime.evaluate` → WebKit page. The in-tree JS
  interpreter is sync; driving async browser ops through it was rejected —
  a JSON step-program executed server-side is the batching layer.
- `page.loadHTML` works offline — used for deterministic exec tests.
- Toolchain moved to `/Applications/Xcode.app` mid-session (stricter region
  isolation than CLT). `swift test` works with Xcode toolchain.
- The repo IS git-tracked (root `AGENTS.md` claim of untracked is stale).

## Architecture decisions

- **JSON step program, not a new language runtime.** `ExecProgram`
  (transport-only, `AgentProtocol`) + `AgentExecRuntime` (executor,
  `BrowserEngine`) + one RPC `agent.exec` + `browserctl exec
  <program.json> [--timeout-ms N]`. Rejected: embedded Swift/TS/Python
  (weight, violates lightweight law), async host fns through the sync JS
  interpreter (bridge complexity, no clean timeout/cancel story).
- **Server-side execution = one RPC for N operations.** Dispatcher decodes
  and runs against the daemon's `BrowserRuntime`. Outcome carries
  `operations` count as batching proof.
- **Expressions, not string interpolation.** `ExecValue`:
  literal-any-JSON / `{"ref": "var.path[0].field"}` / `{"literal": ...}`
  escape hatch. Total, typed substitution; no templating bugs.
- **Flat operational bindings.** `createContext`/`createPage`/page ops bind
  `{id: number, ...}` shapes because engine IDs encode as objects; programs
  feed ids straight back into later steps. `snapshot`/`inspect` bind raw
  engine shapes (documented).
- **Bounded by construction.** ≤1000 declared steps, ≤100k executed,
  forEach ≤10k items (count over limit = error, never silent truncation),
  timeout default 30s / max 300s. Per-step `Task.checkCancellation()` +
  group-level deadline → explicit `cancelled`/`timeout` outcomes with
  partial state preserved (state lives in an `ExecRunState` actor shared
  with the deadline path).
- **Failure semantics explicit.** `onError: stop | proceed`. `stop` →
  `failed` with `stepPath`; `proceed` records per-step failures, binds null
  to `into`, continues. `assert` op for in-program checks.
- **Session attribution without inventing semantics.** Optional `session`
  id verified to exist; execution scoped by explicit page/context ids.
- **Auth confinement:** `allowedContexts == nil` (host) = unrestricted;
  non-host authority path passes owned-context set; violations →
  `unauthorized` step errors.
- **Program versioning:** `version` field, daemon rejects unknown versions
  cleanly; unknown ops fail decode → `badParameter`. Additive op table for
  future `handoffAwait` etc.

## Files inspected

`Package.swift`, `Sources/AgentProtocol/*`, `Sources/EngineRuntime/
{BrowserRuntime,RuntimeTypes,Handoff/*,BranchTypes,BrowserRuntime+Branches}
/*`, `Sources/BrowserEngine/*`, `Sources/BrowserEvents/*`,
`Sources/browserd/main.swift`, `Sources/browserctl/main.swift`,
`Sources/DOM/NodeID.swift`, `Tests/AgentTests/*`.

## Files changed

- `Sources/AgentProtocol/AgentMessages.swift` — `case exec = "agent.exec"`.
- `Sources/AgentProtocol/AgentExec.swift` — NEW: `ExecLimits`,
  `ExecOnError`, `ExecStatus`, `ExecProgram+validate`,
  `ExecValue` (literal/ref), `ExecCondition`, `ExecStep` (17 ops,
  op-discriminated Codable), `ExecFailure`, `ExecOutcome`,
  `AgentExec: AgentProcedure`.
- `Sources/BrowserEngine/AgentExecRuntime.swift` — NEW: executor with
  deadline group, `ExecRunState` actor, ref-path parser, condition eval,
  handoff gate + auth confinement per op, flat JSON projections.
- `Sources/BrowserEngine/AgentCommandDispatcher.swift` — `case .exec` +
  `runExec` + `handleExecRequest`.
- `Sources/BrowserEngine/AgentCommandDispatcher+Authority.swift` —
  non-host `agent.exec` → owned-context confinement.
- `Sources/browserctl/main.swift` — `exec` subcommand + usage line.
- `Tests/AgentTests/AgentExecTests.swift` — NEW: 7 tests.
- Cross-team repairs (all minimal, additive, documented in discussion.md):
  `HandoffCenter.swift` self-disambiguation; `BranchTypes.swift` brace-splice
  reconstruction; `WebKitDialogs.emit` property; `HumanRequestLimits`
  visibility; browserctl handoff/approval CLI helpers;
  `BrowserRuntime.createContext` Sendable capture fix; empty
  `Tests/BrowserEventsTests/` scaffold.

## Work completed

- [x] Coordination workspace + discussion posts
- [x] Transport model, executor, dispatcher, authority, CLI implemented
- [x] `swift build` green
- [x] 7/7 `AgentExecTests` pass (in isolation and in full-target run)
- [x] Auth/session/socket suites pass (no regressions from dispatcher changes)
- [x] Live end-to-end: `browserctl exec` → `browserd` single RPC, 13 steps /
      5 browser ops / structured results `["A","B","C","E2E"]`, completed
- [x] `Docs/AGENT_PROTOCOL.md` `agent.exec` section
- [x] browserctl usage sync (exec + handoff/approval lines)
- [x] ISSUE-001 verified fixed; filed ISSUE-004 (legacy/WebKit page-state
      gap, owner Agent 2) and ISSUE-002 (destructive git ops)
- [ ] Full `swift test` green (blocked: ISSUE-004 migration gap, ~20 tests)
- [ ] Exec event publication (pending Agent 2 runtime helper)
- [ ] JSON Schema export of `ExecProgram` (on Agent 6 request)

## Tests executed

- `swift build` — clean at last green checkpoint.
- `swift test --filter AgentExecTests` — 3/7 pass; 4 failures diagnosed to
  nested engine-ID encoding, fixed with flat projections; rerun in progress.
- Full suite: blocked on ISSUE-001 (Agent 3) + Agent 5 in-flight edits.

## Current status

Done and verified to the extent the shared tree allows. `agent.exec` is
implemented, tested (7/7), documented, and proven end-to-end against a live
daemon. Ready for Agent 6 to surface via SDK/MCP as a thin delegate.
Remaining open items are all cross-agent (ISSUE-004 migration gap, exec
event publication, JSON Schema on request).

## Dependencies on other agents

- Agent 2: will publish `executionStarted/Finished` once a runtime-level
  helper exists; confirm `execution: String?` identity field (vs my earlier
  `executionID` naming). NOTE CONFLICT: your `BranchID: EngineIdentifier`
  proposal vs Agent 3's landed UUID-backed `BranchID` — please reconcile
  with Agent 3; exec/handoff use the UUID string form today.
- Agent 3: fork result should return `{oldPageID: newPageID}` map
  (`BrowserBranchInfo.pageMap` already does — thank you) so exec programs
  re-target; please resolve ISSUE-001.
- Agent 4: exec honors handoff gates; `handoffAwait` op deferred to you;
  I implemented your missing browserctl helpers — please confirm syntax.
- Agent 5: `allowedContexts` confinement ready; confirm scheduler cancels
  the handler task on lease expiry (executor honors cancellation).
- Agent 6: `ExecOutcome{status,results,vars,operations,...}` is your
  evidence substrate; JSON Schema export available on request.

## Remaining work

1. Green-tree test run: AgentExecTests 7/7 + regression (`AgentTests`,
   auth, handoff-adjacent suites).
2. Restore Agent 3's file from /tmp the moment ISSUE-001 closes.
3. Runtime exec-event helper + wire publication.
4. Live `browserd` + `browserctl exec` end-to-end check.
5. `Docs/AGENT_PROTOCOL.md` `agent.exec` section.

## Integration review update

- The old Branches-in-flight and ISSUE-001 notes above are stale: Agent 3's branch runtime is present and its focused tests pass.
- `AgentExecRuntime.run` now publishes `execution.started` and `execution.finished` with the invocation ID and outcome. Focused validation passed 8/8 tests, including lifecycle events, cancellation, timeout, and single-RPC batching.
- The live `browserd`/`browserctl exec` run and protocol documentation are already complete as recorded in the final status post in `discussion.md`.
- Remaining work is optional JSON Schema export if Agent 6 asks for it; the broader WebKit `PageRecord` migration is tracked under ISSUE-004.
