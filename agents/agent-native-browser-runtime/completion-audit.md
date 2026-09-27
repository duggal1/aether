# Six-Agent Runtime Completion Audit

Audit date: 2026-09-27

## Result

The six workstreams are **not fully complete as an integrated system**. Several core
capabilities have focused passing tests, but the integrated `AgentTests` target is still red and
the shared issue registers contain unresolved runtime, isolation, CLI, and recovery work. This
report records the checkout evidence; it does not waive or close those issues.

## Validation performed

- `swift test --filter AgentTests --no-parallel --jobs 1` built the package products and ran 171
  tests across 16 suites. It finished with **32 reported issues**.
- The run passed the multi-step execution, exec timeout/cancellation, event lifecycle, branch and
  handoff, credential flow, and workspace lease expiry/recovery cases shown in the test output.
- The same run reproduced failures in legacy WebKit operations and state projections, including
  scroll/hit testing, keyboard/fill/select, lifecycle restoration, fleet byte estimates, media, and
  capture. WebKit real-session cases also failed because their fixture server exited early; those
  failures need an isolated rerun before attributing them to runtime code.
- Agent reports record focused passes for the event bus/integration suite, branch/handoff suite,
  verification/MCP suites, and selected human UI/persistence suites. Those focused results do not
  make the failing integrated target green.
- `git diff --check` passed for the cursor/runtime integration changes in the preceding review.

## Workstream status

| Agent | Audit status | Evidence and remaining work |
| --- | --- | --- |
| 1 — Local execution | Partial, core path verified | `agent.exec` batching, loops, conditions, cancellation, deadlines, and lifecycle events pass focused tests. WebKit legacy operations used inside programs still hit the runtime gaps listed under ISSUE-004. |
| 2 — Browser events | Core event system verified with boundaries | Typed ordered events, console integration, lifecycle identity, and subscribers have focused passing coverage. Subresource request observation is unavailable through the current public WebKit API and is documented as unsupported. |
| 3 — Branches | Focused implementation verified | Branch/checkpoint/handoff tests pass, including isolation and persistence cases. Full target remains affected by other WebKit integration failures. |
| 4 — Human handoff | Focused implementation verified with limits | Persisted/interrupted handoff, privacy, gating, and resume tests pass. Automated tests do not exercise real MFA/CAPTCHA/passkey providers or a complete native human-control UI session. |
| 5 — Fleet and leases | Incomplete | Lease lifecycle, expiry, and profile-level recovery tests pass. In-flight exec revocation, shared-token worker identity, CLI lease commands, and daemon-startup workspace discovery remain open in `testing-issue.md` (TISSUE-001–004); ISSUE-007 also tracks execution revocation. No realistic concurrency or memory-pressure benchmark was run. |
| 6 — Verification and interfaces | Partial | Verification, MCP delegation, credential flow, and selected CLI tests have focused passes. The primary CLI still lacks lease management commands; automated verification is limited to available WebKit evidence; full AgentTests is red. |

## Open integration issues

- **ISSUE-002:** Five unrelated UI source files are deleted in the current worktree without an
  ownership/resolution note. The deletions were left intact because the audit could not establish
  whether they are intentional; they must not be restored or discarded blindly.
- **ISSUE-004:** WebKit pages still do not satisfy the legacy `PageRecord` assumptions used by
  several operations and projections. The current integrated test run reproduces a subset of this
  gap. Update the issue with the precise current failure list after isolated reruns.
- **ISSUE-006:** Main-frame metadata and console behavior have fixes, but native dialog resolution
  and a WebKit-backed network-log projection remain unimplemented or explicitly unsupported.
- **ISSUE-007 / TISSUE-001:** Lease release/expiry freezes pages but has no cancellation link to an
  already-running `agent.exec` request.
- **TISSUE-002:** A shared daemon token maps all its clients to one principal, so workers sharing
  that token are not independently identifiable.
- **TISSUE-003:** `browserctl` lacks acquire/renew/release/cancel/list workspace-lease commands.
- **TISSUE-004:** Lease records can be recovered after a supervisor reopens a known profile, but
  `browserd` has no durable workspace/profile catalog for automatic discovery after restart.

See `issue.md` and `testing-issue.md` for reproduction steps, evidence, and ownership.

## Completion gate

Do not mark the six-agent upgrade complete until the open issues are fixed or explicitly
dispositioned with supported semantics, the failing AgentTests cases are isolated and resolved (or
removed only with an intentional contract change), and the integrated target passes. The current
evidence does not support an “all work complete / no issues” declaration.
