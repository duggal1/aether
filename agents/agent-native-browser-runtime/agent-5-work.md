# Agent 5 Work

## Ownership

Agent 5 — workspace leasing and fleet ownership. Lease records bind an agent identity to an
existing isolated browser context; optional branch and repository/worktree metadata stay attached
to the lease.

## Repository findings

- `BrowserRuntime` is the state owner; each `ContextRecord` owns pages, network, storage,
  permissions, downloads, bookmarks, and a profile. WebKit contexts and website data stores are
  keyed by `ContextID`.
- `browserd` hosts `NativeBrowserEngine` and dispatches JSON RPC. Authenticated requests flow
  through `AgentOwnershipRegistry`; direct context ownership currently exists only in that
  process-local registry.
- `AgentProtocol` already exposes `fleet.stats`, `fleet.pages`, and `fleet.sweep`; these report
  page lifecycle/memory planning, not workspaces or leases.
- `BrowserRuntime` has `createContext`, `destroyContext`, `openProfile`, page lifecycle controls,
  and per-profile SQLite KV persistence. `EngineScheduler` schedules jobs; it is not a workspace
  scheduler.
- `ProfileStore` can persist small JSON records via `setKV`/`getKV`. Context IDs and page IDs are
  process-scoped counters. Agent 3's `BranchID` is UUID-backed and durable.
- Tests use Swift Testing in `Tests/AgentTests/AgentFleetTests.swift`; existing fleet tests cover
  page demotion, context isolation, sessions, and RPC visibility, but not leases.
- No lease APIs, lease persistence, repository/worktree mapping, automatic suspension task, or
  WebKit scale benchmark exists yet. `browserd` restart does not reconstruct context ownership.

## Architecture decisions

- Treat one existing `ContextID` as one isolated browser workspace; do not duplicate browser state
  or create a second scheduler around WebKit contexts.
- A lease owns access to one context and can record optional `BranchID`, repository root, and
  worktree path. Workspace creation/branch forking remain separate operations.
- Keep lease policy independent from page eviction. Existing `FleetScheduler` manages page memory;
  it cannot safely lease/recover contexts.
- Crash recovery must not reuse process-local `ContextID` values. Persist the profile directory and
  stable workspace/lease identity, reopen the profile to obtain a new context, and treat leases
  from an earlier daemon generation as recoverable.
- User of lease methods must be authenticated and ownership checked; caller-supplied agent labels
  are not authority. Coordination with Agent 1/6 is required for that wire surface.

## Files inspected

- `Sources/EngineRuntime/BrowserRuntime.swift`
- `Sources/EngineRuntime/RuntimeTypes.swift`
- `Sources/EngineRuntime/BranchTypes.swift`
- `Sources/EngineRuntime/Handoff/HandoffCenter.swift`
- `Sources/Scheduler/EngineScheduler.swift`
- `Sources/Scheduler/FleetScheduler.swift`
- `Sources/EngineAdditions/Sources/AetherResourceControl/FleetPolicy.swift`
- `Sources/AgentProtocol/AgentMessages.swift`
- `Sources/AgentProtocol/AgentAuthority.swift`
- `Sources/BrowserEngine/AgentCommandDispatcher.swift`
- `Sources/BrowserEngine/AgentCommandDispatcher+Authority.swift`
- `Sources/browserd/main.swift`
- `Sources/Persistence/ProfileStore.swift`
- `Tests/AgentTests/AgentFleetTests.swift`
- `Package.swift`

## Files changed

- `agents/agent-native-browser-runtime/discussion.md`
- `agents/agent-native-browser-runtime/agent-5-work.md`

## Work completed

- Completed repository and runtime boundary audit; identified that existing fleet functionality is
  page eviction only and does not provide workspace ownership or durable leases.
- Proposed a context-backed lease API and requested dedicated lease lifecycle event kinds.

## Tests executed

- None yet. Whole-package build is currently blocked by ISSUE-001 in Agent 3's branch subsystem.

## Current status

Implementation in progress; API boundary is documented. Lease authority and crash recovery need to
be integrated without bypassing `AgentOwnershipRegistry`.

## Dependencies on other agents

- Agent 2: lease event kinds in `BrowserEvents`.
- Agent 3: stable `BranchID` attachment where available; runtime must not rely on incomplete branch
  implementation for core lease operations.
- Agent 1: authenticated identity/capability rules for new lease RPC methods.
- Agent 6: CLI/public interface should call the runtime lease API, not implement a second lease
  store.

## Remaining work

- Implement durable workspace lease records, ownership-safe acquire/renew/release/cancel, expired
  lease recovery, fleet visibility, and RPC integration.
- Add lease lifecycle tests and run focused validation after ISSUE-001 is resolved.

## Integration review update

- Workspace lease implementation is present in `WorkspaceLeases.swift` and `BrowserRuntime+WorkspaceLeases.swift`, with dispatcher and authorization routes, profile persistence, expiry reaper, lifecycle events, and tests. The initial status above is stale.
- `workspaceLeaseRecoversAgainstNewContextIdentity` passed. The fleet-local test had incorrectly treated graceful `destroyContext` as a crash; that path correctly persists `.released`. It now tests released-lease reacquisition and passes. `ContextID` values are process-local counters and may numerically repeat after restart; durable workspace identity is the UUID `workspaceID`.
- Active execution cancellation on lease expiry/release is still not wired. See ISSUE-007 for concrete evidence and the cross-agent integration needed.
- Focused validation after that correction: `agentFleetWorkspaceLeaseReacquisitionAfterGracefulDestroy` passes. `workspaceLeaseRecoversAgainstNewContextIdentity` passes separately.
