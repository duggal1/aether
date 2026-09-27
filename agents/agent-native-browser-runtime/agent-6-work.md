# Agent 6 Work

## Ownership

Task verification and public agent access through the native Swift API, CLI, and MCP adapter.

## Repository findings

- The package is a Swift 6.2 macOS package. `BrowserRuntime` is the state-owning actor, `NativeBrowserEngine` is its public facade, and `AgentCommandDispatcher` maps local socket protocol requests to that runtime.
- `AgentProtocol` already defines `AgentTypedClient`, typed `AgentProcedure` contracts, and a broad `AgentMethod` set. `browserctl` already covers `agent.exec` over the socket; the native execution implementation is being developed in this tree.
- `BrowserEvents` and `BrowserRuntime.observeEvents` / `recentEvents` already exist in the shared working tree. The event identity and details fields are designed for public serialization.
- There is no MCP target or MCP implementation in the package.
- Runtime result types already expose page URL/title/load state, semantic nodes, navigation response events, network log entries, and persisted download metadata. WebKit only exposes main-frame navigation responses through public APIs; per-subresource network verification cannot be claimed from the current WebKit path.
- The shared issue log initially recorded an Agent 3 branch compilation blocker; that issue was resolved before focused tests. Several agents' shared files are modified, so Agent 6 kept changes within its own modules and narrow adapter integration points.
- The native UI had a separate Internet Password vault for confirmation, autofill, and Passwords settings. The engine vault stores metadata in ProfileStore and secrets as generic Keychain passwords, so these paths needed a compatibility migration rather than sharing a Keychain item class.
- Legacy Keychain records may contain an explicit port value of `0`; treating that as a URL port prevented origin matching during migration. IPv6 host normalization also needs brackets when assigned through `URLComponents.host`.
- `suggestRanksBookmarksBeforeHistory` asserted that a bookmark ranked above a direct URL and allowed live network suggestions. The deterministic contract uses local-only results, with direct URL ranked before bookmark and history candidates.

## Architecture decisions

- Verification will be a typed runtime capability operating on live BrowserRuntime state, with structured per-check evidence and aggregate verified, failed, or inconclusive status. A successful action response alone will not imply task success.
- Network and WebKit download assertions require an event sequence cursor so old matching events cannot satisfy the current task. Download records can instead be checked by their returned download ID.
- Native clients will call the same runtime capability directly through `NativeBrowserEngine`; CLI and MCP will forward typed protocol requests to the existing dispatcher rather than implement verification or browser state separately.
- MCP will be a lightweight protocol adapter over the existing Agent socket surface; no browser engine, persistence store, or MCP-specific runtime will be introduced.
- Only observable WebKit evidence will produce a definitive result. Missing or unsupported evidence will be reported as inconclusive.

## Files inspected

- `Package.swift`, `AGENTS.md`, `Docs/ARCHITECTURE.md`, `Docs/AGENT_PROTOCOL.md`
- `Sources/AgentProtocol/AgentMessages.swift`, `AgentProcedure.swift`, `Procedures.swift`, `AgentExec.swift`, `JSONValue.swift`, `AgentCodec.swift`, `UnixSocket.swift`
- `Sources/BrowserEngine/BrowserEngine.swift`, `AgentCommandDispatcher.swift`, `AgentCommandDispatcher+Authority.swift`
- `Sources/EngineRuntime/BrowserRuntime.swift`, `RuntimeTypes.swift`, WebKit page/runtime files
- `Sources/BrowserEvents/BrowserEvent.swift`, `BrowserEventBus.swift`
- `Sources/browserctl/main.swift`, `Sources/browserd/main.swift`
- `Sources/EngineRuntime/WorkspaceLeases.swift`, `BrowserRuntime+WorkspaceLeases.swift`, `Sources/EngineRuntime/Handoff/`
- `Tests/AgentTests/AgentFleetTests.swift`, `WorkspaceLeaseTests.swift`, `BranchHandoffTests.swift`
- Agent 2 and Agent 5 work files, shared discussion, and shared issue log

## Files changed

- `Package.swift`
- `Sources/BrowserVerification/VerificationTypes.swift`
- `Sources/EngineRuntime/TaskVerification.swift`
- `Sources/BrowserEngine/BrowserEngine+Verification.swift`
- `Sources/AgentProtocol/AgentMessages.swift`, `VerificationProcedures.swift`
- `Sources/BrowserEngine/AgentCommandDispatcher.swift`, `AgentCommandDispatcher+Authority.swift`, `AgentCommandDispatcher+Handoff.swift`
- `Sources/AgentMCP/AgentMCPServer.swift`
- `Sources/aether-mcp/main.swift`
- `Sources/browserctl/main.swift`
- `Tests/BrowserVerificationTests/VerificationTypesTests.swift`
- `Tests/AgentTests/TaskVerificationTests.swift`
- `Tests/AgentMCPTests/AgentMCPServerTests.swift`
- `Tests/AgentTests/AgentFleetTests.swift` (unique test names to resolve an integrated compiler failure)
- `Docs/AGENT_VERIFICATION_AND_MCP.md`
- `agents/agent-native-browser-runtime/agent-6-work.md`, `discussion.md`, `issue.md`
- Credential UI integration: `Sources/AetherApp/Integration/AetherEngineAdapter+Credentials.swift`, `Sources/BrowserUI/Sources/AetherHumanUI/Engine/BrowserFeaturePorts.swift`, `Foundation/AetherCredentialVault.swift`, `Native/AetherCredentialPopover.swift`, `Settings/PasswordsSettingsView.swift`, `State/BrowserWindowModel.swift`
- Credential fill/runtime and regression coverage: `Sources/EngineRuntime/CredentialVault.swift`, `WebKit/WebKitPage+Script.swift`, `Tests/HumanIntegrationTests/AdapterTests.swift`, `Tests/AgentTests/BookmarksSearchTests.swift`

## Work completed

- Added typed task assertions for page URL/title, selector state, main-frame response, download artifacts, and registered external verifiers.
- Implemented ordered per-check evidence and aggregate status. Event-backed response/download checks use a since-sequence cursor; download checks can also use a concrete DownloadID.
- Exposed task verification through NativeBrowserEngine and task.verify. Exposed a scoped, resumable events.recent protocol method for CLI/MCP clients while retaining native AsyncStream subscriptions.
- Added browserctl task-verify/events-recent commands and a stdio aether-mcp executable that forwards aether_call tools to the Agent socket.
- Added verification, protocol, and MCP tests plus interface documentation.
- Fixed the handoff gate to resolve `task.verify`'s nested `plan.page`; scoped `events.recent` reads are also blocked during handoff to avoid exposing navigation event details. Added a dispatcher regression test for both paths.
- Fixed duplicate workspace lease test function names found during integrated AgentTests compilation; recorded ISSUE-003.
- Unified human confirmation, autofill, and Passwords settings with the runtime credential vault. Legacy Internet Password entries migrate lazily into profile-scoped metadata plus a generic-password Keychain secret; the old item is deleted only after migration succeeds. Autofill selection carries metadata only and fills through the isolated WebKit client world.
- Enabled human save offers for loopback HTTP origins while continuing to reject remote cleartext HTTP. Added IPv6 normalization and avoided interpreting legacy Keychain port `0` as an explicit port.
- Corrected the bookmark/history ranking test to disable nondeterministic network suggestions and assert the intended rank ordering rather than an invalid absolute top-rank expectation.

## Tests executed

- `swift test --filter VerificationTypesTests` passed (3 tests).
- Shared `swift test --filter AgentTests --no-parallel` built the integrated AgentTests target and ran 132 tests; all four original Agent 6 `TaskVerificationTests` passed. The overall target reported 47 issues in other suites, chiefly WebKit/page-state and fixture-server failures. A later focused Agent 2 event run passed all 6 integration tests, including title-change delivery.
- Agent 4's `swift test --filter BranchHandoffTests --no-parallel --jobs 1` passed (2 tests).
- `swift test --filter AgentMCPServerTests` passed (3 tests).
- `swift test --filter dispatcherBlocksVerificationAndEventReadsDuringHumanHandoff` passed (1 regression test).
- `git diff --check` passed.
- The first `VerificationTypesTests` attempt exposed duplicate lease test function names; renamed the fleet-local variants and recorded resolution under `ISSUE-003`.
- `swift test --filter 'Credential|suggestRanksBookmarksBeforeHistory|legacyCredentialOriginNormalizationHandlesIPv6AndDefaultPorts|adapterMigratesLegacyHumanCredentialsIntoRuntimeVault'` passed, including live WebKit credential signup/save/relogin, profile isolation, restart persistence, migration, and ranking coverage.
- `swift test --filter 'WorkspaceTests|PersistenceTests|AddressResolverTests|OmniboxCommitTests|NavigationEntryTests|PrivateRouteTests|SessionArchiveTests|SearchLocalityTests|KeychainContractTests|NetworkRouteTests|SymbolContractTests|TypographyContractTests|NavigationGlowStateTests|PaletteContractTests|NavigationGlowWiringTests|IconSystemTests|SearchPort'` passed (97 tests in 22 suites).
- `git diff --check` passed after the final changes.

## Current status

Implementation and focused validation complete. Verification/MCP, runtime credential vault, human UI credential migration, suggestion ranking, persistence, and selected UI test suites passed. Package products, including `browserctl` and `aether-mcp`, compiled during the SwiftPM test build. The wider AgentTests target remains red for failures tracked outside this subsystem; Agent 2's focused event suite subsequently passed.

## Dependencies on other agents

- Agent 1 confirmed its dispatcher/CLI/AgentMethod execution points are frozen; the task.verify/events.recent additions are separate routes.
- Agent 2 owns the event bus. Verification that reads main-frame response events must use the event model already present and must respect its documented WebKit limitations.
- Agent 3/4 handoff and branch work is now part of the shared test target. The verifier is included in Agent 4's parked-page observation gate.
- Agent 5 lease changes exposed duplicate test names across AgentFleetTests and WorkspaceLeaseTests; the fleet-local names are now unique.
- Human UI credential flows now depend on `BrowserCredentialVaultProviding`, implemented by the Aether adapter over `BrowserRuntime`; the UI does not receive credential secrets for list or selection.

## Remaining work

- The Agent 2/5 owners still need to resolve or explicitly disposition the WebKit page-state integration failures tracked by `ISSUE-004` before the full AgentTests target can pass.
- Remote HTTP credential origins remain intentionally unsupported; only loopback HTTP and HTTPS are accepted.
