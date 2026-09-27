# Agent 3 Work

## Ownership

Branchable browser contexts: durable checkpoints, isolated profile/WebKit stores, branch
identity, listing, and cleanup.

## Repository findings

- `BrowserRuntime.checkpoint(contextID:)` captures SQLite profile tables and download metadata.
- `openProfile` restores profile rows into a new context and assigns a named WebKit data-store UUID
  from the profile directory name when that name is a UUID.
- The reported `BrowserRuntime+Branches.swift` compile failure did not reproduce from the current
  tree: that file was absent. `BranchTypes.swift` existed as a model draft without runtime behavior.
- Public WebKit APIs do not clone a complete website data store. Runtime forks use copied Aether
  profile rows plus a fresh UUID-backed WKWebsiteDataStore; sessionStorage, IndexedDB, workers,
  caches, and server-side authentication remain outside the cloning guarantee.

## Architecture decisions

- Keep one checkpoint payload in the parent profile KV store and create independent profile
  directories for forks; this avoids copying the parent SQLite file while preserving existing
  migration and profile ownership boundaries.
- Persist branch records in the parent profile KV index. Use UUID `BranchID` values as durable IDs
  and as the child website-data-store identifiers.
- Report fidelity explicitly. Cookies are read from the live WK store and seeded into the fork;
  localStorage is refreshed from reachable live page origins and otherwise uses persisted rows.
- Refuse to fork ephemeral contexts so private cookie/storage values are not copied into durable
  branch profiles.
- No branch merge operation is exposed: merging cookies, localStorage, and browser history back
  into a parent has no safe conflict rule and can invalidate server-bound sessions. A future merge
  can be limited to explicitly selected, independently mergeable data.

## Files inspected

- `Sources/EngineRuntime/BrowserRuntime.swift`
- `Sources/EngineRuntime/BranchTypes.swift`
- `Sources/EngineRuntime/WebKit/WebCookieStorage.swift`
- `Sources/Persistence/ProfileStore.swift`
- `Sources/Storage/PersistentStore.swift`
- `Sources/BrowserEvents/BrowserEvent.swift`
- `Package.swift`

## Files changed

- `Sources/EngineRuntime/BrowserRuntime.swift`
- `Sources/EngineRuntime/BrowserRuntime+Branches.swift`
- `Sources/EngineRuntime/BranchTypes.swift` (existing model reused)
- `Sources/EngineRuntime/WebKit/WebCookieStorage.swift`
- `Tests/AgentTests/BranchHandoffTests.swift`

## Work completed

- Added durable branch checkpoints and forks using profile KV payloads and separate WebKit store
  identifiers.
- Added branch listing, parent/child association, branch-created/discarded events, page remapping,
  child-first deletion, and cleanup.
- Fork cookies from the current WebKit cookie store and seed into the new store; preserve cookie
  attributes supported by the existing runtime storage bridge.
- Capture live localStorage for reachable current-page origins; preserve persisted values for
  origins WebKit cannot currently expose.
- Added a focused integration test for independent branch identities, page restoration, listing,
  and deletion.

## Tests executed

- `swiftc -frontend -parse` over branch, handoff, runtime, dispatcher, verifier, and focused test
  sources: passed.
- `swift test --filter AgentTests --no-parallel`: the new checkpoint/fork/isolation/deletion test
  passed. The broader target compiled, but unrelated existing AgentFleet/WebKit integration tests
  failed in this run; see the shared discussion before attributing those failures.
- `swift test --filter BranchHandoffTests --no-parallel --jobs 1`: passed, 3 tests. Deletion also
  asserts that the branch profile directory is removed.

## Current status

Implementation, full target compilation, and focused runtime tests pass.

## Dependencies on other agents

- Browser events carry branch identity as an opaque `String`, matching the shared event envelope.
- Workspace leases accept branch IDs as strings; no scheduler changes were required.

## Remaining work

- None for this ownership area.
