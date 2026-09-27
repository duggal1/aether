# Code-first browser control — implementation report

Session 2: 2026-09-27, branch `feature/code-first-browser-runtime-20260927`.
Machine: macOS 27.0, arm64, Swift 6.4. Directive: `Docs/AGENT_CODE_FIRST_BROWSER_DIRECTIVE.md`.
Recon: `agents/agent-native-browser-runtime/code-first-recon.md`.

Session 1 delivered Appendix C step 5 (persistent execution sessions, host-enforced limits,
`verify`/`call` steps). Session 2 delivered the Tier 1 read-channel work (document-start
install, bounded diffable snapshots) and admitted the missing §6 capabilities to the agent
surface (Tier 2 raw capability), with CLI/MCP parity.

## Current status

| Area | Status | Evidence |
| --- | --- | --- |
| One execution channel (program in, outcome out) | PASS | `agent.exec`; `call` delegates to the same dispatcher |
| Persistent session state across programs | PASS | `execSessionPersistsVariablesAcrossPrograms` |
| Bounded program / output / session | PASS | `execProgramEnforcesDeclaredByteCap`; `truncated` on cap |
| Verification callable inside a program | PASS | `execVerifyStepRunsFromInsideAProgram` |
| Every Tier 2 capability program-callable | PASS (with typed limits) | `execCallStepInvokesRuntimeWithoutLeavingTheProgram`, `execCallReachesTier2CapabilityWithoutLeavingTheProgram` |
| Same-session concurrency = 1, typed refusal | PASS | `execSessionRefusesConcurrentPrograms` |
| Session destroyed on lease end | PASS | lease-revocation suite green |
| Tier 1 extractor installed at document start | PASS | `WebKitPage.init`; DOM batch bench still passes |
| Tier 1 snapshot bounded + diffable | PASS | `execSnapshotSinceGenerationIsUnchangedWhenNothingChanged` |
| Zoom / stop / print / clipboard / extensions | PASS | `agentCanQueryAndSetPageZoom`, `agentCanPrintPageToARealPDFArtifact`, `extensionListIsTruthfulWhenNoExtensionIsInstalled` |
| File upload | PASS WITH LIMITATION (typed `unsupported`) | `fileUploadReportsTypedUnsupportedRatherThanSilentNoOp` |
| Network layer 1 / layer 2 | NOT STARTED | — |
| Extension enable/disable/invoke | NOT STARTED | `extension.setEnabled` returns typed `unsupported` |
| Sharded supervisor, admission control, budgets, saturation harness | NOT STARTED | — |

## What changed, file by file

### Session 1 — execution channel
- `Sources/AgentProtocol/AgentExec.swift`: limits (`maxProgramBytes` 64 KiB, `maxOutputBytes`
  12 MiB, `maxSessionBytes` 4 MiB, `maxSessionPrograms`, `maxImagesPerProgram`), `ExecCounters`,
  `ExecOutcome.session/counters/truncated/truncationReason`, program byte cap, `verify` and
  `call` steps, `callableMethods` derived from `AgentMethod` minus an exclusion set.
- `Sources/BrowserEngine/ExecSessionStore.swift` (new): bounded, destroyable, single-flight
  per-session state.
- `Sources/BrowserEngine/AgentExecRuntime.swift`: session load/commit/end, linked lease
  teardown, counters, output truncation, `verify`/`call` execution, `{"ref": ...}`
  interpolation, typed `unsupported` mapping.
- `Sources/EngineRuntime/BrowserRuntime.swift` + `+WorkspaceLeases.swift`: linked lease-bound
  registrations.
- `Sources/BrowserEngine/BrowserEngine.swift`: one `ExecSessionStore` per engine.

### Session 2 — Tier 1 read channel
- `Sources/EngineRuntime/WebKit/WebKitDOMScript.swift`: extractor source plus a tiny
  `activation(generation:)` used once a document's extractor is current.
- `Sources/EngineRuntime/WebKit/WebKitPage.swift`: installs the extractor at document start in
  the isolated client world; tracks `domInstalledGeneration`.
- `Sources/EngineRuntime/WebKit/WebKitPage+Script.swift`: `domScript` sends only activation on
  a same-generation read; `snapshot` takes `since` and returns an `unchanged` no-op.
- `Sources/EngineRuntime/RuntimeTypes.swift`: `PageSnapshot.truncated/omittedNodes/unchanged`;
  `BrowserRuntimeError.unsupported`.
- `Sources/BrowserEngine/AgentCommandDispatcher.swift`: `page.snapshot` honours `since` and
  reports `truncated`/`omittedNodes`/`unchanged`; `DispatchError.unsupported` mapping.

### Session 2 — Tier 2 capabilities
- `Sources/EngineRuntime/WebKit/WebKitPage+AgentCapabilities.swift` (new): zoom factor
  get/set, `stopLoading`, `printPDF` via `WKWebView.pdf(configuration:)`, `loadedExtensions`.
- `Sources/EngineRuntime/BrowserRuntime+AgentCapabilities.swift` (new): `stopLoading`, `zoom`,
  `setZoom`, `printPage`, `clipboardRead`/`clipboardWrite`, `uploadFile` (typed unsupported),
  `listExtensions`; `BrowserExtensionInfo`.
- `Sources/AgentProtocol/AgentMessages.swift`: `page.stopLoading`, `page.zoom`, `page.setZoom`,
  `page.print`, `page.clipboardRead`, `page.clipboardWrite`, `page.uploadFile`, `page.moveTab`,
  `extension.list`, `extension.setEnabled`.
- `Sources/BrowserEngine/AgentCommandDispatcher.swift`: dispatcher cases for the above.
- `Sources/BrowserEngine/AgentCommandDispatcher+Authority.swift`: `extension.*` page-scoped
  like `page.*` for non-host principals.
- `Sources/browserctl/main.swift`: CLI commands + usage for every new method.

### Tests and docs
- `Tests/AgentTests/CodeFirstExecTests.swift`: 13 tests (exec channel + Tier 1 + Tier 2).
- `Docs/AGENT_PROTOCOL.md`: execution-session, steps, limits and a human-parity section.

## Architecture proof
- One execution channel: `call` constructs an `AgentRequest` and routes it through the same
  `AgentCommandDispatcher` — no second batching or verification implementation.
- Tier discipline: `ExecCounters` records tier usage; no image is produced or injected unless
  a program asks; no coordinate action is taken where a ref exists.
- Structured state: refs remain `NodeID(index, generation)` and fail loudly when stale; the
  snapshot carries `truncated`/`unchanged`.

## Efficiency proof

| Rule | Detector | Measured / observed | Test |
| --- | --- | --- | --- |
| One boundary call per program (§10.1.1) | `ExecCounters.boundaryCalls` | 1 | `execCallStepInvokesRuntimeWithoutLeavingTheProgram` |
| Injected source per operation (§10.3) | `domInstalledGeneration` | same-document reads send activation (~40 B) instead of the extractor (~3.5 KiB) | DOM batch bench still green |
| Re-reading unchanged state (§10.1.4) | `PageSnapshot.unchanged` | no nodes re-serialized when `since` matches | `execSnapshotSinceGenerationIsUnchangedWhenNothingChanged` |
| Unbounded output / session (§5.3) | `truncated`, session byte cap | typed `truncated`/`sessionLimitExceeded` | `execProgramEnforcesDeclaredByteCap` |

## Isolation and secret proof
- `call` excludes `credentials.get`; a program supplies intent, never a value (`§11.3.2`).
- `call` params and `verify` plans are gated against the program's leased contexts before
  dispatch (`gateCallParams`); `extension.list` is page-scoped in the authority map.

## Fixes made

| Defect | Root cause | Fix | Regression test |
| --- | --- | --- | --- |
| Program state died with the run | per-run `ExecRunState` | session store load/commit | `execSessionPersistsVariablesAcrossPrograms` |
| Verification was wire-only | no `verify` step | `verify` step | `execVerifyStepRunsFromInsideAProgram` |
| Tier 2 required leaving the program | no `call` bridge | `call` step | `execCallStepInvokesRuntimeWithoutLeavingTheProgram` |
| Extractor re-transmitted per op | no document-start install | document-start script + activation | DOM batch bench |
| Stable page re-read fully | no diff read | `since` + `unchanged` | `execSnapshotSinceGenerationIsUnchangedWhenNothingChanged` |
| Clipboard / zoom / print / extensions absent | no methods | real WebKit/AppKit-backed methods | Tier 2 tests |
| File upload silently absent | no method | typed `unsupported` | `fileUploadReportsTypedUnsupportedRatherThanSilentNoOp` |

## Verified commands

```
swift build                                                     # Build complete
swift test --filter CodeFirstExecTests --no-parallel --jobs 1   # 13/13 passed
swift test --filter "ExecRuntimeValidationTests|AgentExecTests|TaskVerificationTests|BrowserEventsTests" --no-parallel --jobs 1  # 28/28 passed
swift test --filter AgentTests --no-parallel --jobs 1           # 192 tests, 17 suites, 0 failures
```

## Remaining failures
- None introduced by this work in the suites run above.

## Limitations (honest, typed, visible in the API)
- File upload: `page.uploadFile` returns `unsupported`; WebKit has no public API to populate a
  file input outside the user-selected panel.
- Extension enable/disable/invoke: `extension.setEnabled` returns `unsupported`; no extension
  is installable through the agent surface yet, and `extension.list` reports the loaded set.
- Frames: refs are main-frame only; no per-frame snapshot path.
- Snapshot `unchanged` is a whole-tree no-op check, not a per-node delta.
- Network visibility is navigation-level only (§7 layers 1 and 2 absent).
- Fleet: no shard supervisor, admission control, per-workspace budgets, hibernation, or
  saturation harness (§9).

## Next steps (smallest first)
1. Network layer 1 observer (in-page fetch/XHR patch at document start, bounded + redacted).
2. Per-node snapshot delta (return only changed subtrees, not just a whole-tree no-op).
3. Per-frame snapshot scoping via frame-targeted evaluation.
4. Extension loading + enable/disable/invoke, replacing the `unsupported` refusals.
5. Cost-ledger query per page (§4.0.2).
6. Network layer 2 local proxy (§7.3), then the shard supervisor and scale harness (§9).
