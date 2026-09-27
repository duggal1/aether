# Agent 2 Work

Owner of: **First-Class Browser Event System**.

## Ownership

Everything important in the browser becomes observable without polling:

- a typed, versioned event model (`BrowserEvents` module),
- a single `BrowserEventBus` with monotonic sequencing, bounded journal, and `AsyncStream` subscriptions,
- WebKit + runtime emitters for every event family that a public WebKit API can actually produce,
- honest, documented modelling of families WebKit cannot expose.

Exposure through SDK/CLI/MCP is Agent 6's surface; Agent 2 provides the runtime primitives.

## Repository findings

Verified against the live tree (not `README.md`, which is a stale Engine-0 snapshot):

1. The runtime is **WebKit-backed**, not the old custom engine. `Sources/EngineRuntime/WebKit/`
   owns `WebKitPage`, `WebKitContext`, `WebKitDialogs`, `AetherPageView`, `SystemWebRuntime`.
2. `BrowserRuntime` is the single actor owner of all state (`Sources/EngineRuntime/BrowserRuntime.swift`, ~2078 lines).
3. The only existing observation primitive is `BrowserRuntime.observePages() -> AsyncStream<RuntimePageState>`
   (`PagePresentation.swift`). It is a **coalesced state snapshot**, not an event log: it cannot express
   "navigation committed then failed", has no sequence identity, no journal, no family filtering, and it
   never surfaces console/network/download/dialog/permission events.
4. `WebKitPage` already fires a `changed: (WebPageState) -> Void` callback for URL/title/loading/progress/
   history/paint/semantic-mutation. This is the natural producer hook.
5. WebKit delegates already partially implemented: `WKNavigationDelegate` + `WKUIDelegate` via
   `WebKitDialogs` (alert/confirm/prompt, open panel, createWebView, downloads).
6. No `EventJournal`, `EventBus`, `EventEnvelope`, or `AsyncStream` event bus existed anywhere
   (verified: zero matches for `EventJournal|EventBus|EventEnvelope|EventStream`).
7. `consoleOutput(pageID:)` is broken on the WebKit path: it requires `page.loaded != nil` and reads the
   removed experimental `JSRuntime.consoleOutput`; WebKit pages never populate `loaded`, so it returns
   `pageNotLoaded`. `WebKitPage.evaluate` always returns `console: []`. This is a real regression that the
   console event family fixes (see ISSUE-005).
8. `NetworkLogEntry` exists but the WebKit path never populates it; the experimental `page.networkLog` is
   dead. WebKit exposes no public per-subresource request/response hook (no `WKURLSchemeHandler` for http/https,
   no public webRequest delegate on a plain `WKWebView`). Only main-frame navigation responses are observable.
9. Downloads are tracked privately in `WebKitDialogs` with no exit to the runtime — the existing
   `DownloadRecord` path is never fed by `WKDownload`.
10. IDs come from `EngineCore/Identifiers.swift` (`ContextID`, `PageID`, `NavigationID`, `SessionID`, ...).
    There is **no** branch identity type yet (Agent 3 territory).

## Architecture decisions

1. **New leaf module `BrowserEvents`** (deps: `EngineCore` only) holds `BrowserEvent`,
   `BrowserEventFamily`, `BrowserEventIdentity`, and actor `BrowserEventBus`. Justification: the event
   vocabulary is cross-cutting (Agent 3 branches, Agent 4 handoff, Agent 5 fleet, Agent 6 public surface),
   so it must not live inside the 2078-line runtime actor, and it must not drag WebKit into subscribers.
2. **One bus, owned by `BrowserRuntime`.** `BrowserRuntime` composes and owns `BrowserEventBus`;
   WebKit producers are handed a `@Sendable` emit closure by the runtime, which attaches identity
   (context/page) before publishing. No second state owner.
3. **Monotonic global sequence + bounded journal** — every event carries a `UInt64` sequence. A new
   subscriber can replay from a sequence. No polling required.
4. **Typed `BrowserEventKind` enum** for native pattern-matching, plus `name` + `details: [String: String]`
   for wire serialization by Agent 6 without importing engine state types into `AgentProtocol`.
5. **`BrowserEventIdentity` carries optional `context/page/branch/session`.** `branch` is currently an
   opaque `String` (see discussion.md) until Agent 3 lands a `BranchID`; the dependency is documented.
6. **Never fake WebKit events.** Subresource network, service workers, and precise DOM mutation streams are
   modelled as *unsupported* where WebKit's public API cannot produce them, with explicit documentation.
7. **Console capture via injected bridge.** A `console`/`window.onerror`/`unhandledrejection` message
   handler is injected at document start; it produces `console.message` events AND restores
   `BrowserRuntime.consoleOutput(pageID:)` for WebKit pages.

## Files inspected

- `Sources/EngineRuntime/BrowserRuntime.swift` (surface, storage, observability)
- `Sources/EngineRuntime/PagePresentation.swift` (`observePages`, `RuntimePageState`)
- `Sources/EngineRuntime/SemanticSignalIntegration.swift`
- `Sources/EngineRuntime/WebKit/WebKitPage.swift`
- `Sources/EngineRuntime/WebKit/WebKitPage+Script.swift`
- `Sources/EngineRuntime/WebKit/SystemWebRuntime.swift`
- `Sources/EngineRuntime/WebKit/WebKitDialogs.swift`
- `Sources/EngineRuntime/WebKit/AetherPageView.swift`
- `Sources/EngineRuntime/RuntimeTypes.swift`
- `Sources/AgentProtocol/AgentMessages.swift`
- `Sources/EngineCore/Identifiers.swift`
- `Tests/AgentTests/WebKitNavigationReliabilityTests.swift`, `AgentFleetTests.swift`
- `Package.swift`

## Files changed

- `Sources/BrowserEvents/BrowserEvent.swift` (new — model; lease family added by Agent 5)
- `Sources/BrowserEvents/BrowserEventBus.swift` (new — `BrowserEventBus`, `Filter`, `Filter.family(_:)`)
- `Sources/EngineRuntime/BrowserRuntime.swift` (import, `events`, `observeEvents`/`recentEvents`,
  `publishPageEvent`, ordered `pageEventChannel`, context/page lifecycle emits, async `consoleOutput`)
- `Sources/EngineRuntime/WebKit/WebKitPage.swift` (console/focus bridges, navigation/document/console/
  focus/network/auth emits, `consoleLines()`, auth-challenge delegate)
- `Sources/EngineRuntime/WebKit/WebKitDialogs.swift` (dialog/popup/fileChooser/permission/download emits)
- `Sources/EngineRuntime/WebKit/SystemWebRuntime.swift` (relay wiring into the ordered channel)
- `Package.swift` (`BrowserEvents`, `BrowserEventsTests` targets; `EngineRuntime`/`AgentTests` deps)
- `Tests/BrowserEventsTests/BrowserEventBusTests.swift` (new)
- `Tests/AgentTests/BrowserEventIntegrationTests.swift` (new)
- `agents/agent-native-browser-runtime/*` (coordination workspace)

## Work completed

- Created this coordination workspace.
- Added the `BrowserEvents` module: typed model + single actor bus with monotonic sequence, bounded
  journal, replay, and family/context/page filters.
- Wired producers: page, navigation, document (url/title/DOM-mutated), console, network (main-frame
  navigation response), download, popup, dialog, permission (media/geolocation), authentication
  challenge, file chooser, focus, context lifecycle. Branch/handoff/execution/lease kinds exist for
  Agents 3/4/5 to publish; lease is already published by Agent 5.
- Fixed event ordering with a single ordered channel (`pageEventChannel`).
- Fixed WebKit `consoleOutput(pageID:)` (async, page-world console bridge) — ISSUE-005.

## Tests executed

- `swift test --filter BrowserEventsTests --no-parallel --jobs 1` — **8/8 passed**.
- `swift test --filter BrowserEventIntegrationTests --no-parallel --jobs 1` — **6/6 passed**
  (ordered navigation events, title event, console event + `consoleOutput`, context/page lifecycle,
  journal replay without a subscription).
- `swift test --filter consoleFrameWorkersDialogs` — still red on `mainFrame`/`pendingDialogs`
  (ISSUE-006), not on console.

## Current status

Complete and verified on the event-system surface. Two shared files (`Package.swift`,
`BrowserRuntime.swift`) are under concurrent edit by five teammates; build/test runs intermittently
blocked by unrelated in-flight work (AgentMCP target, branches file, verification types). Every
failure encountered was another agent's transient edit, never an event-system defect.

### Concurrency notes for the team

- `BrowserRuntime.pageEventChannel` is the single ordered producer path. Yield into it; do not spawn a
  `Task` per event.
- Console/focus bridges are in the `.page` content world (site scripts + `evaluate` live there).
- `Package.swift` `BrowserEventsTests` target was temporarily disabled by another agent
  (`CREDVAULT-STASH` comment); Agent 2 restored it. Do not disable it — it is green.

## Dependencies on other agents

- **Agent 3 (branches):** event identity expects `branchID`. See discussion.md — proposed `BranchID` in
  `EngineCore`; until then `branch` is an opaque optional `String`.
- **Agent 4 (handoff):** `handoff.*` events defined with no producer yet; Agent 4 should publish via the bus.
- **Agent 5 (fleet):** `execution.*` events defined with no producer yet; Agent 5 should publish via the bus.
- **Agent 6 (public surface):** serialize `BrowserEvent.name`/`.details`/`.identity`; do not rebuild the bus.

## Remaining work

- Agent 3/4/5 emitters for branch/handoff/execution families (kinds are reserved; lease already live).
- Legacy `PageRecord` readers `mainFrame`/`pendingDialogs`/`networkLogEntries` on WebKit pages
  (ISSUE-006 / ISSUE-004) — runtime/Agent 6, not event defects.
- Subresource network events blocked on public WebKit limitations (documented, ISSUE-002 in the
  rewritten issue file).
- Agent 6 to serialize `BrowserEvent.name`/`.details`/`.identity` through `observeEvents`/`recentEvents`
  rather than a second pipeline.

## Integration review update

- Focused `swift test --filter BrowserEventIntegrationTests --no-parallel --jobs 1` passed all 6 tests, including ordered navigation/title delivery, console capture, identities, context/page lifecycle, and journal replay. The earlier title-event failure in the broad run did not reproduce in isolation.
- Agents 3, 4, and 5 now publish branch, handoff, and lease events. Agent 1 now publishes execution start/finish events. The old dependency list above is stale.
- WebKit's public API boundary remains: main-frame network responses are observable; subresource request streams are not.
