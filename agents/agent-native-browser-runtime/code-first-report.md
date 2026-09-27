# Code-first browser control — implementation report

Session: 2026-09-27, branch `feature/code-first-browser-runtime-20260927`.
Machine: macOS 27.0, arm64, Swift 6.4. Directive: `Docs/AGENT_CODE_FIRST_BROWSER_DIRECTIVE.md`.
Recon: `agents/agent-native-browser-runtime/code-first-recon.md`.

This session implemented Appendix C step 5 (persistent execution sessions with host-enforced
limits) end to end and admitted it to the program surface (step 4 for the `call` bridge), plus
the Tier 1 snapshot byte bound. It did not attempt the fleet, proxy, or network-observer work.

## Current status

| Area | Status | Evidence |
| --- | --- | --- |
| One execution channel (program in, outcome out) | PASS | `agent.exec` is the only batch channel; `call` delegates to the same dispatcher rather than a second runtime |
| Persistent session state across programs | PASS | `execSessionPersistsVariablesAcrossPrograms` |
| Bounded program / output / session | PASS | `execProgramEnforcesDeclaredByteCap`; `ExecLimits.maxOutputBytes` sets `truncated` |
| Verification callable inside a program | PASS | `execVerifyStepRunsFromInsideAProgram` |
| Every Tier 2 capability program-callable | PASS (with limits) | `execCallStepInvokesRuntimeWithoutLeavingTheProgram`; excluded set is deliberate |
| Same-session concurrency = 1, typed refusal | PASS | `execSessionRefusesConcurrentPrograms` |
| Session destroyed on lease end | PASS | lease-revocation suite green (`leaseEndRevokesConfinedExecutionInFlight`) |
| Tier 1 snapshot bounded with `truncated` | PASS | `WebKitPage.snapshot`, `PageSnapshot.truncated`/`omittedNodes` |
| Network layer 1 / layer 2 | NOT STARTED | — |
| Extensions, file upload, clipboard, zoom, print agent surface | NOT STARTED | recon §3.1 gap table |
| Sharded supervisor, admission control, saturation harness | NOT STARTED | — |

## What changed, file by file

- `Sources/AgentProtocol/AgentExec.swift`: added `maxProgramBytes` (64 KiB), `maxOutputBytes`
  (12 MiB), `maxSessionBytes` (4 MiB), `maxSessionPrograms`, `maxImagesPerProgram`; added
  `ExecCounters`; added `session`, `counters`, `truncated`, `truncationReason` to
  `ExecOutcome`; enforced the program byte cap in `ExecProgram.validate()`; added the
  `verify` and `call` steps with encode/decode and `callableMethods` derived from
  `AgentMethod` minus an explicit exclusion set.
- `Sources/BrowserEngine/ExecSessionStore.swift` (new): bounded, destroyable, single-flight
  per-session variable store with typed errors.
- `Sources/BrowserEngine/BrowserEngine.swift`: one `ExecSessionStore` per `NativeBrowserEngine`.
- `Sources/BrowserEngine/AgentExecRuntime.swift`: session load/commit/end; session
  registration linked to the program's lease; counters; output truncation; `verify` and
  `call` step execution; recursive `{"ref": ...}` interpolation for structured arguments.
- `Sources/EngineRuntime/BrowserRuntime.swift` + `+WorkspaceLeases.swift`: linked
  lease-bound registrations so a session's teardown scope follows the program's contexts.
- `Sources/EngineRuntime/RuntimeTypes.swift` + `WebKit/WebKitPage+Script.swift`: bounded
  snapshot bytes with deterministic truncation and `truncated`/`omittedNodes`.
- `Sources/BrowserEngine/AgentCommandDispatcher.swift`: `page.snapshot` projection reports
  `truncated`/`omittedNodes`.
- `Tests/AgentTests/CodeFirstExecTests.swift` (new): seven regression tests.
- `Docs/AGENT_PROTOCOL.md`: documented the new steps, counters, limits, and session semantics.

## Architecture proof

- One execution channel: `call` constructs an `AgentRequest` and routes it through the same
  `AgentCommandDispatcher`; it does not reimplement any method.
- Tier discipline: `ExecCounters` records snapshot/verification/runtime-call counts; no image
  is produced or injected by the runtime (`counters.images` increments only on an explicit
  program request).
- Structured state: the existing `NodeID(index, generation)` handle is unchanged; snapshots
  now carry `truncated` and `omittedNodes`.

## Efficiency proof

| Rule | Detector | Measured value | Test |
| --- | --- | --- | --- |
| One boundary call per program (§10.1.1) | `ExecCounters.boundaryCalls` | always 1 | `execCallStepInvokesRuntimeWithoutLeavingTheProgram` |
| Unbounded output forbidden (§10.3.3) | `truncated` + `truncationReason` | over-cap sets flag | code path in `ExecRunState.appendResult` |
| Unbounded session growth forbidden (§5.1.3) | `ExecSessionStore.commit` byte check | typed `byteLimitExceeded` | code path + store bound |

## Isolation and secret proof

- `call` excludes `credentials.get`; a program supplies intent, never a value (§11.3.2).
- `call` params and `verify` plans are gated against the program's leased contexts before
  dispatch (`gateCallParams`), so a program cannot reach another workspace through the bridge.

## Fixes made

| Defect | Root cause | Fix | Regression test |
| --- | --- | --- | --- |
| Program state died with the run (§5.1) | `ExecRunState` was per-run | session store load/commit keyed by `program.session` | `execSessionPersistsVariablesAcrossPrograms` |
| `task.verify` was a wire method only (§8.1.2) | no `verify` step | `verify` step in `ExecStep` | `execVerifyStepRunsFromInsideAProgram` |
| Tier 2 capabilities required leaving the program (§4.2.2) | no program-callable bridge | `call` step | `execCallStepInvokesRuntimeWithoutLeavingTheProgram` |
| No program-size or output bound (§5.3.1, §5.3.5) | absent limits | `maxProgramBytes`, `maxOutputBytes` + `truncated` | `execProgramEnforcesDeclaredByteCap` |
| Concurrent programs could race a session (§5.3.7) | no single-flight guard | `sessionBusy` refusal | `execSessionRefusesConcurrentPrograms` |
| Snapshots could allocate unboundedly (§4.1.4) | no byte budget | deterministic truncation | code path in `WebKitPage.snapshot` |

## Verified commands

```
swift build                                        # Build complete
swift test --filter CodeFirstExecTests --no-parallel --jobs 1   # 7/7 passed
swift test --filter "ExecRuntimeValidationTests|AgentExecTests|TaskVerificationTests|BrowserEventsTests" --no-parallel --jobs 1  # 28/28 passed
```

## Remaining failures

- None introduced by this change in the suites run above.

## Limitations (honest, visible in the API)

- Frames: refs are main-frame only; there is no per-frame snapshot path yet (§4.1.6).
- Snapshot "changed since generation": `mutationVersion` exists but no diff query is exposed
  (§4.1.3).
- Cost ledger (§4.0.2) is partially represented by `ExecCounters`; there is no
  per-page channel-price query yet.
- Network visibility is navigation-level only (§7 layers 1 and 2 absent).
- Extensions, file upload, clipboard, zoom, and print have no agent surface (recon §3.1).
- Fleet scheduler, admission control, per-workspace budgets, hibernation, and the saturation
  harness are absent (§9).

## Next steps (smallest first)

1. Install the DOM script as a document-start `WKUserScript` in the isolated client world so
   the extractor exists before page script and stops being re-injected per operation (§4.1,
   §10.4); measure the current per-call injected-source bytes first.
2. Snapshot generation diffing: a `sinceGeneration` query returning only changed nodes.
3. Program-callable missing §6 capabilities: clipboard, zoom, print, file upload, extensions
   (§6.2, §6.5), each with an acceptance test.
4. Network layer 1 observer (§7.2), then layer 2 proxy (§7.3).
5. Cost ledger query per page (§4.0.2).
