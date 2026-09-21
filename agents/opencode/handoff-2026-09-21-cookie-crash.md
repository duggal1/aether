# Agent handoff — browserd SIGKILL on cookie APIs (2026-09-21 ~18:53 IST)

## What is going on

`browserd` dies reproducibly when any cookie command runs
(`context-set-cookie`, `context-cookies`, ...). Three crash logs:
`~/Library/Logs/DiagnosticReports/browserd-2026-09-21-185310.ips`,
`-185239`, `-185345`. Ping/context-create survive; the first cookie call kills it.

## Root cause (confirmed from crash frames, not a guess)

```
WebKit::crashDueToApplicationCallingMainThreadOnlyWebKitAPIFromBackgroundThread()
-[WKHTTPCookieStore setCookie:completionHandler:]
closure #1 in BrowserRuntime.setCookie(contextID:cookie:)
```

New code in `Sources/EngineRuntime/WebKit/WebCookieStorage.swift`
(`list/set/remove/clearCookies`) touches `WKWebsiteDataStore` /
`WKHTTPCookieStore` from the `BrowserRuntime` actor's background executor.
WebKit deliberately crashes main-thread-only API called off-main.
Exception: EXC_BREAKPOINT / SIGKILL, termination namespace FOUNDATION code 1.

## Why I am stuck

The straightforward fix (wrap calls in `await MainActor.run`) hits Swift 6
isolation design problems:

- The shared store cache (`webContexts: [ContextID: WebKitContext]`) lives on
  the actor. MainActor closures cannot read actor state synchronously, and
  `WKWebsiteDataStore` is not Sendable, so the store object cannot be passed
  across the isolation boundary without a fight.
- `WebKitContext` init is `@MainActor` (fine), but the cookie ops need the
  cached store object from actor state.
- Prior related work in-tree: `WebKitStoreCache` (MainActor, in
  `SystemWebRuntime.swift`) already caches `forIdentifier:` stores but is only
  used at creation time; `configureWebBlocking` (rule-store compile/lookup)
  runs off-main today and has NOT crashed — so the main-thread requirement
  bites the cookie store first, rule store status unknown.

Related files: `Sources/EngineRuntime/WebKit/WebCookieStorage.swift` (new,
all four funcs + `webStore(for:)` helper), `Sources/EngineRuntime/BrowserRuntime.swift`
(caller side; storage funcs nearby use live-page JS and are unaffected),
`Sources/EngineRuntime/WebKit/SystemWebRuntime.swift`
(`WebKitStoreCache`, `configureWebBlocking`).

Tests depending on the outcome: `Tests/AgentTests/AgentFleetTests.swift`
(`contextCookiesStoragePermissions` — was rewritten to expect WebKit-backed
cookies with a live `loadHTML` page; currently fails only because the daemon
dies). New regression tests: `Tests/AgentTests/AgentSocketAuthTests.swift`
(3/3 pass, unrelated, green).

## What I need from the next agent

1. A concrete pattern for MainActor-gated `WKWebsiteDataStore` /
   `WKHTTPCookieStore` access that preserves single-object-per-identifier
   process sharing (do NOT create a second parallel cache keyed by UUID —
   distinct store objects for one identifier silently split WebKit process
   pools; see `dev.to/kylmora` findings in the web research).
2. Whether `WKContentRuleListStore` compile/lookup also needs the same
   treatment or is genuinely thread-safe (it hasn't crashed yet).
3. Full code for the fix, then: release build green, cookie round-trip
   (`set → list → remove → clear`) over a live `browserd` with zero
   DiagnosticReports entries, then the cookie/storage block of
   `AgentFleetTests`, then the aggressive 20-site sequential harness
   (`/tmp/aether_seq_fixed.py aether`) to confirm no regression.

## Constraints (do not break)

- No `import WebKit` in `BrowserRuntime.swift`: WebKit's legacy `DOMDocument`/
  `DOMNode` collide with ours (hard build error). WebKit-framework types live
  in `Sources/EngineRuntime/WebKit/*.swift` only.
- `WKWebsiteDataStore` objects must stay singletons-per-identifier.
- Public API names (`list/set/remove/clearCookies`, storage funcs) are called
  by `AgentCommandDispatcher` and tests — keep signatures.
- Verify with a live daemon, not just `swift build`. Watch
  `~/Library/Logs/DiagnosticReports/browserd-*.ips`.
