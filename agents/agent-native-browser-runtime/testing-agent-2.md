# Testing Agent 2

## Systems under test

- Human handoff, approval, and resume (original Agent 4).
- Workspace leases, ownership, expiry, and recovery (original Agent 5).
- Deterministic verification and Native/CLI/MCP surfaces (original Agent 6).

## Implementation inspected

- `Sources/EngineRuntime/Handoff/`, `BrowserRuntime+WorkspaceLeases.swift`, `WorkspaceLeases.swift`, `TaskVerification.swift`.
- `Sources/BrowserEngine/AgentCommandDispatcher+Authority.swift`, `AgentCommandDispatcher+Handoff.swift`, `AgentExecRuntime.swift`.
- `Sources/AgentProtocol/AgentAuth.swift`, `Sources/AgentMCP/AgentMCPServer.swift`, `Sources/browserctl/main.swift`, `Sources/browserd/main.swift`, `Sources/aether-mcp/main.swift`.
- Agent 4–6 reports, shared `discussion.md` and `issue.md`, plus focused tests in `Tests/AgentTests/`, `Tests/AgentMCPTests/`.

## Test environment

- macOS arm64, SwiftPM debug configuration, real `WKWebView` through `BrowserRuntime`.
- Real navigation verifier fixture uses a local Python HTTP server with `/ok` (200), `/error` (500), `/redirect` (302), and a restricted-port failure.
- Actual daemon/CLI/MCP exercise used a fresh authenticated `browserd` process and unique Unix socket/token paths.
- SwiftPM builds were serialized against another active test run; an integrated test compile failure in Agent 1's event test was repaired before continuing.

## Tests executed

- `swift test --no-parallel --jobs 1 --filter BranchHandoffTests`: 3/3 passed, including persisted interrupted handoff recovery and ephemeral privacy.
- `swift test --no-parallel --jobs 1 --filter WorkspaceLeaseTests`: 4/4 passed, including a live WebKit page lease expiry/freeze, expiry event identity, recovery against a new context identity, and principal ownership/spoofed agent ID rejection.
- `swift test --no-parallel --jobs 1 --filter realWebKitNavigationEventsDriveVerificationOutcomes`: passed after fixing stale verifier metadata.
- `swift test --no-parallel --jobs 1 --filter leasedWebKitHandoffResumesIntoVerifiedHumanState`: passed; real page mutation during handoff, exact page/context resume, verification, lease release/freeze, lifecycle identities, and sensitive-value non-disclosure.
- `browserctl` and stdio `aether-mcp` called a fresh authenticated daemon: both ping paths succeeded; modern MCP discover and delegated call returned the daemon's structured result; a wrong token received `unauthorized`.
- `swift test --no-parallel --jobs 1 --filter browserctl`: 2/2 passed. A subprocess integration exercised remote error exit status plus lease acquire/list/renew/release/reacquire/cancel against a fresh daemon.
- Focused subsystem suites passed: `BranchHandoffTests` 3/3, `WorkspaceLeaseTests` 4/4, `TaskVerificationTests` 5/5, and `AgentMCPServerTests` 3/3.
- Initial integrated build found two compile errors in `Tests/AgentTests/EventSystemValidationTests.swift`; the invalid `return Issue.record(...)` was corrected, and the already-present `Array(...)` fix resolves the reported ArraySlice comparison.

## Expected behavior

- Handoff preserves the live page identity, blocks agent operations until explicit resume, and persists safe lifecycle state.
- Lease expiry/release revokes workspace access, isolates owners, freezes pages, and allows explicit recovery after a process boundary.
- Verification uses current browser state and real observable evidence; absent evidence is inconclusive, not success.
- CLI and MCP thinly forward to the same daemon protocol and surface runtime failures accurately.

## Actual behavior

- Real WebKit HTTP 200 main-frame evidence verified; HTTP 500 mismatch failed; a 302 redirect to the expected destination verified; restricted-port navigation failure emitted `navigation.failed` and returned an inconclusive response assertion.
- The first real verifier attempt failed the title check even though navigation was complete: `runtime.verify` read cached `pageInfo` before WebKit's title observer updated. `TaskVerification.verify` now calls `synchronizedWebInfo`; the real test passes.
- A live one-second lease expired, published `lease.expired` with context identity, and froze its live WebKit page. Principal-scoped dispatcher acquisition ignored a spoofed agent label and rejected another synthetic principal.
- A live WebKit page accepted a simulated human change while handoff was open; the agent gate remained closed through completion, explicit resume restored access to the same page/context, and verification saw the resulting title/element. A human-entered sentinel value did not appear in handoff records or lifecycle event descriptions.
- `browserd`, `browserctl`, and MCP work across an actual authenticated Unix-socket boundary. MCP correctly returns a tool error for daemon errors. `browserctl` printed an unauthorized response for the wrong token but exited with status 0; this is fixed in the current tree and covered by a new process integration test, pending rerun.
- `browserctl` now delegates all five workspace lease operations to existing AgentProtocol methods; an actual daemon process test passed the lease lifecycle and metadata round-trip.

## Failures found

- Fixed verifier's stale-title read in `Sources/EngineRuntime/TaskVerification.swift`; regression is `realWebKitNavigationEventsDriveVerificationOutcomes`.
- Fixed `browserctl` returning process success on an RPC error in `Sources/browserctl/main.swift`; regression is `browserctlReturnsFailureForRejectedDaemonRequest`.
- Fixed an Agent 1 test-source compile error in `Tests/AgentTests/EventSystemValidationTests.swift` so the integrated target can compile.
- Lease revocation does not cancel an in-flight `agent.exec`; the dispatcher authorizes at admission and executor steps only check cancellation/authorization at operation boundaries. Open issue `TISSUE-001`.
- One daemon token maps every authenticated socket client to the same principal. Sharing the configured token across workers defeats distinct-principal isolation. Open issue `TISSUE-002`.
- Workspace lease CLI coverage was missing; thin existing-protocol mappings and a real-daemon regression are now in place. `TISSUE-003` is resolved.
- Daemon startup has no durable profile/workspace catalog; lease recovery is only reached after a supervisor recreates a context and reopens the known profile. Open issue `TISSUE-004`.

## Root causes

- `verify` previously used synchronous cached `pageInfo`; title-change delivery is asynchronous relative to navigation completion.
- `AgentSessionStore` exposes one immutable generated principal for its single expected token and returns it for every successful `bind`.
- `browserctl` dispatches only enumerated commands; no lease commands are mapped, despite the RPC/runtime methods existing.
- `browserd.main` constructs a fresh engine and dispatcher on every launch; workspace lease KV lives in a profile that is not rediscovered/reopened at startup.
- Lease lifecycle transitions suspend pages but have no cancellation-handle registry shared with `AgentExecRuntime`.

## Fixes made

- Refreshed page metadata before verification in `Sources/EngineRuntime/TaskVerification.swift`.
- Convert remote `AgentResponse.error` values into non-zero `browserctl` process exits while preserving the structured JSON response on stdout.
- Added `browserctl` workspace-lease acquire, renew, release, cancel, and list mappings to the existing dispatcher protocol.
- Corrected an invalid early return in the shared event validation test so it records the missing event and continues.

## Regression tests added

- `Tests/AgentTests/VerificationWebKitIntegrationTests.swift::realWebKitNavigationEventsDriveVerificationOutcomes`.
- `Tests/AgentTests/WorkspaceLeaseTests.swift::expiredLeaseFreezesItsLiveWebKitPageAndPublishesExpiry`.
- `Tests/AgentTests/WorkspaceLeaseTests.swift::authenticatedWorkspaceLeaseChecksPrincipalAndIgnoresAgentIDSpoofing`.
- `Tests/AgentTests/WorkspaceHandoffVerificationIntegrationTests.swift::leasedWebKitHandoffResumesIntoVerifiedHumanState`.
- `Tests/AgentTests/BrowserctlProcessIntegrationTests.swift::browserctlReturnsFailureForRejectedDaemonRequest`.
- `Tests/AgentTests/BrowserctlProcessIntegrationTests.swift::browserctlWorkspaceLeaseCommandsDelegateToDaemon`.

## Performance findings

- Lease expiry was observed within the reaper's one-second sweep cadence plus the test's 1.3-second wait; page freeze completed before the post-expiry assertion.
- No realistic fleet concurrency, memory-pressure, suspension/resume, or many-workspace benchmark was run. No scale claim is made.

## Integration findings

- Real WebKit + lease + handoff + verification works in one direct-runtime flow; lifecycle events retain context/page/branch attribution, and lease release freezes the resumed page.
- Authenticated CLI and MCP both reach the same daemon protocol; MCP is a thin `aether_call` adapter. CLI runtime failures and all lease operations now have fresh-daemon process coverage.
- Workspace lease cancellation does not terminate an in-flight execution; separate `ISSUE-007` in `issue.md` and `TISSUE-001` remain open.
- Profile reopen tests prove metadata-level recoverability, not automatic browserd restart recovery or restored live page state.
- No actual MFA/passkey/CAPTCHA provider or human UI takeover was automated; the local WebKit mutation validates lifecycle semantics only.

## Current status

Validation remains in progress; no system is marked fully PASS.

| Subsystem | Status |
| --- | --- |
| Agent 4 — handoff/approval/resume | PASS WITH LIMITATIONS |
| Agent 5 — leasing/isolation/recovery | PASS WITH LIMITATIONS |
| Agent 6 — verification | PASS WITH LIMITATIONS |
| Agent 6 — native/CLI/MCP surfaces | PASS WITH LIMITATIONS |

## Remaining failures

- Reproduce and resolve lease expiry/release cancellation of running `agent.exec` (`TISSUE-001`).
- Define distinct authenticated worker identity credentials (`TISSUE-002`).
- Add durable profile/workspace discovery or keep explicit supervisor-driven recovery semantics (`TISSUE-004`).
- Finish focused verification/MCP/CLI process suites and run broad repository validation; full repository tests have not yet been run by this agent.
