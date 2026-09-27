# Agent 4 Work

## Ownership

Durable human handoff and approval requests, page parking, agent-control gating, and resume.

## Repository findings

- `HandoffCenter` and `HandoffLedger` already held the runtime model, state transitions, bounded
  observation stream, and profile KV persistence.
- Agent dispatcher methods already gated page mutations and sensitive reads while a handoff was
  pending/active, and restore converted process-scoped open requests to `interrupted`.
- Gaps: handoff creation did not checkpoint browser state, persistence errors were swallowed, and
  the shared `BrowserEventBus` did not receive handoff lifecycle events.

## Architecture decisions

- Require a configured profile for handoff creation and persist every lifecycle mutation. Durable
  contexts receive a branch checkpoint before parking; ephemeral contexts stay in memory and do not
  copy private state into persistent storage.
- Publish requested and parked at creation, completed/cancelled at human resolution, and resumed
  after the agent resumes. Keep entered field values out of handoff records and events.
- Leave approval requests separate from page parking; an approval queue does not imply that the
  human must control a page.
- After process restart, WebKit cannot restore arbitrary in-memory DOM/form state. Recovery restores
  the durable profile context and requires the supervisor to select its restored page; no promise
  is made that unsaved page memory survives.

## Files inspected

- `Sources/EngineRuntime/Handoff/HandoffCenter.swift`
- `Sources/EngineRuntime/Handoff/HandoffLedger.swift`
- `Sources/EngineRuntime/Handoff/HandoffTypes.swift`
- `Sources/BrowserEngine/AgentCommandDispatcher+Handoff.swift`
- `Sources/BrowserEvents/BrowserEvent.swift`
- `Sources/EngineRuntime/BrowserRuntime.swift`
- `Tests/AgentTests/AgentTests.swift`

## Files changed

- `Sources/EngineRuntime/Handoff/HandoffCenter.swift`
- `Tests/AgentTests/BranchHandoffTests.swift`

## Work completed

- Handoff request checkpoints durable contexts before recording and parking the page; ephemeral
  contexts park in memory without a durable checkpoint.
- Profile persistence failures now propagate through request and transition APIs.
- Handoff lifecycle events include context/page plus optional session/branch identity.
- Added focused coverage for blocking, lifecycle event order, resume, and restart restoration.
- Handoff records retain the branch checkpoint ID; URL credentials, query, and fragment values are
  removed from handoff metadata before persistence or RPC serialization.
- Agent reads that can expose page content, cookies, localStorage, or permissions are blocked while
  human control is active.
- Credential read/write/fill and task verification commands are also blocked during page handoff.
- An interrupted handoff cannot resume without an explicit page restored in the same context.
- Agent control remains parked after human completion until `resumeHandoff` succeeds; an interrupted
  request blocks the context until its replacement page is explicitly attached and resumed.

## Tests executed

- `swiftc -frontend -parse` over branch, handoff, runtime, dispatcher, verifier, and focused test
  sources: passed.
- `swift test --filter AgentTests --no-parallel`: handoff lifecycle, persistence, agent-control
  gating, and interrupted restart test passed. Other unrelated tests in that broad target failed;
  see the shared discussion before attributing those failures.
- `swift test --filter BranchHandoffTests --no-parallel --jobs 1`: passed, 3 tests, including
  lifecycle event order, control gating, persistence, restart recovery, and ephemeral handoff.

## Current status

Implementation, full target compilation, and focused runtime tests pass.

## Dependencies on other agents

- Uses Agent 2's reserved handoff event kinds and shared `BrowserEventBus`.
- Handoff branch identity remains opaque `String`, consistent with event and lease envelopes.

## Remaining work

- None for this ownership area.

## Integration review update

- Ephemeral handoff persistence now correctly remains in memory: no branch checkpoint or profile write is made. `ephemeralHandoffStaysInMemory` verifies the request is available in its originating runtime and absent after reopening the profile.
- The focused `BranchHandoffTests` suite now passes 3/3, including durable restart recovery and the ephemeral privacy case.
