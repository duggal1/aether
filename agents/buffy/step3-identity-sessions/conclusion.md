# Step 3 conclusion — sessions, profiles, passkeys, Keychain, privacy, geographic routing

## What shipped (all verified by build + tests)

1. **Profile isolation audit + fix**
   - `WebKitStoreCache.store(for: nil)` no longer returns a shared ephemeral store; every unnamed call gets a fresh nonpersistent store. Permanent-context creation paths (`webPage`, `configureWebBlocking`, `webContextForCookies`) throw `invalidState` when the profile identifier is missing instead of silently sharing.
   - SQLite profile UUID == `WKWebsiteDataStore(forIdentifier:)` UUID (set in `openProfile`); store identity is stable per profile across calls.
   - Regression tests: `Tests/AgentTests/WebKitProxyIsolationTests.swift` (7 tests).
2. **Session persistence with lazy restoration**
   - New `BrowserSessionArchive` (window/profile/tab order/selection/pinned/URL/layout) stored beside the existing archive; incognito tabs excluded by construction. Flush is synchronous on every structural mutation (select/new/close/move/pin/switch/navigate/window close), so quitting cannot lose state.
   - `BrowserWindowModel.restoreProfile()` restores the archive first (selected tab navigates immediately; background tabs get `needsRestoreLoad` and navigate on first selection), then falls back to the engine's `restoredPages`.
3. **Keychain adapter** — `AetherKeychain` (`fun.aether.secure-storage`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), namespaced accounts (`<profile>:<provider>:<account>`, `proxy:<endpointID>`), update-or-add, delete, contains. No secret ever touches SQLite or UserDefaults.
4. **Search locality** — `SearchLocality.sanFrancisco` (US/CA, 94158, nearby 94105/94103/94110) is the default, persisted in existing preferences. Provider region parameters are applied only where documented (Google `gl`/`hl`, Bing `setmkt`/`setlang`, DDG `kl`); city terms appended only when the user opts in (`localityQueryTerms`, default off). Changing route never rewrites locality and vice versa (tested).
5. **Network route model + browser-scoped proxy**
   - `AetherExitRegion` (direct/SF/NY/Boston/Philadelphia), `BrowserNetworkRoute` (enabled/failClosed/endpointID), `RouteEndpoint` (host/port, non-secret) — persisted in existing preferences.
   - `BrowserRuntime.configureWebProxy(contextID:endpoint:)` applies `Network.ProxyConfiguration(socksv5Proxy:)` to the profile's `WKWebsiteDataStore` at context creation and on demand; `allowFailover = !failClosed`.
   - Fail-closed: region enabled + no saved server ⇒ blackhole endpoint (127.0.0.1:9) applied, status `.blocked` — traffic is blocked, never silently direct. Fail-open + no server ⇒ direct, status `.unavailable` (no green claim).
   - Status only reaches `.connected` after an external exit-IP probe (URLSession with the same proxy config) succeeds; observed IP displayed. `.connecting/.direct/.unavailable/.blocked/.unknown` all have honest labels; only `.connected` claims hidden IP (tested).
   - Applied to every profile's context (permanent + incognito) in `AetherEngineAdapter.applyNetworkRoute`.
6. **Passkeys without faking** — `BrowserPasskeyCapability` protocol; adapter implements it with `ASAuthorizationWebBrowserPublicKeyCredentialManager` (confirmed present in installed SDK: `authorizationStateForPlatformCredentials`, `requestAuthorizationForPublicKeyCredentials`, `isDeviceConfiguredForPasskeys` macOS 26.2+). Settings → Passwords & Passkeys shows real authorization state, device readiness, and the denied-path recovery instruction. The managed `com.apple.developer.web-browser.public-key-credential` entitlement is documented as not-requested in the section footer; no entitlement was inserted into any config.
7. **Settings UI** — new native sections `Network Privacy` (`NetworkSettingsView`) and `Search Location` (`SearchLocationSettingsView`): Picker/Toggle/TextField only, Keychain credential fields (SecureField, never echoed back), status badge driven by the state machine, reset-to-San-Francisco action.
8. **Sensitive-logging audit** — grepped all stderr/print/os_log sites in EngineRuntime, BrowserEngine, browserctl, browserd, AetherApp: only checkpoint/automation/verification *errors* and page console output are written; no cookie values, tokens, proxy credentials, or URLs are logged. `cookieJSON` is an agent-protocol *response* for the existing context-scoped `context.cookies` method, not a log line.

## Verification performed

- `nice -n 10 swift build --jobs 1` → **0 errors, 0 warnings**.
- `swift test --filter 'WebKitProxyIsolationTests|SessionArchiveTests|SearchLocalityTests|KeychainContractTests|NetworkRouteTests'` → **20/20 passed** (7 engine + 13 UI).
- Full suite (`swift test --no-parallel --jobs 1 --skip-build`): 17 of 19 target runs green; 42 assertion failures in 2 runs — attribution below.

## Failures NOT caused by this work (with evidence)

1. **AgentTests: 38 issues** (`AgentFleetTests`, `CaptureAdapterTests`, `PageFindTests`, `BookmarksSearchTests`, `MediaControlTests`).
   - Root cause: the experimental→WebKit dispatch migration. `BrowserRuntime.loadHTML`/`query`/`focus` dispatch to `webPage()` (WebKit) with dead experimental code removed, but `hover`, `hoveredNode`, `nodeAtPoint`, `pressKey`, `networkLogEntries`, `mainFrame`, `consoleOutput` still read the experimental `page.loaded` record and `page.networkLog`, which the WebKit load path never populates ⇒ `pageNotLoaded` and empty network logs.
   - Evidence this predates Step 3: the identical `hover`/`networkLogEntries` bodies exist in `agents/codex/webkit-performance/before/…/BrowserRuntime.swift` (Sep 20 snapshot, before this session); passing recordings of these tests (`agents/codex/reliability/results/tests-linked.log`, `agent2-surfaces/results/targeted.log`) predate the WebKit-first flip; no recorded run after the flip contains them.
   - This is the `work/plan/backend/retire-custom-engine.md` migration boundary. Fixing = rewriting those tests for WebKit semantics (WebKit network logging, hover-as-JS); out of Step 3 scope and colliding with an agent actively editing `BrowserRuntime.swift`.
2. **AetherHumanUITests: 4 issues** — all in the design agent's transferred files:
   - `DesignSystemTests.swift:28` — `AetherSymbol` contains `bookmarks`; `NSImage(systemSymbolName:"bookmarks")` probes **false** on this SDK, so `everySymbolIsResolvable` + `everyChromeIconMaps…` (BrowserIcon.doubleBookmark → .bookmarks) + `symbolsCarryDistinctMeanings` all fail. Fix belongs in the design agent's `AetherSymbols.swift` (remove/replace `bookmarks` case).
   - `DesignSystemTests.swift:36` — `AetherTextWeight.emphasis.usWeightClass == 450` fails; `AetherFontRegistry.swift` (changed-file at session start) now returns 500. Either the registry returns 450 for `.emphasis` or the test/DESIGN.md contract is updated — design owner's call.
   - My symbol additions (`network`, `location`) and all symbols used by the new settings views were probed and resolve.

## Wrong assumptions I held going in

- Assumed `swift test` unusable on this host (AGENTS.md CLT-only note): full Xcode is now selected (`xcrun --show-sdk-path` → `/Applications/Xcode.app/…`), tests run.
- Assumed `WKWebsiteDataStore.proxyConfigurations` nullable in Swift: it imports as non-optional `[ProxyConfiguration]`; clear with `[]`, not `nil`.
- Assumed UI could reference `AetherEngineAdapter`: it lives in AetherApp; credential save needed a new protocol (`BrowserProxyCredentialStoring`).

## Important constraints discovered

- **The tree is being edited concurrently** (design agent: `AetherSymbols/AetherFontRegistry`; another agent: `BrowserRuntime.swift` 14:15, `WebKitPage.swift` 14:16 — they restructured `WebKitContext.init(identifier:)` to non-optional and added identifier-throw guards while I was building; my proxy plumbing had to be re-merged into their new `webPage`/`configureWebBlocking` shapes, and `Tests/AgentTests/WebKitDOMPerformanceTests.swift` was left broken by their signature change — fixed here to `WebKitContext.ephemeral()`). Re-read these files before editing them again.
- Engine files are untracked by git (repo root is the home directory): no `git diff`/`checkout` recovery. Copy before overwriting.
- `SessionPageRow`/engine `session_pages` checkpoints are untouched; UI session archive is a separate key (`aether.human.session.v1`).

## Remaining uncertainty (needs live verification, not claimable)

- Exit-IP probe and fail-closed behavior are unit-tested only through configuration state; no real exit server exists yet, so `.connected` has never been observed end-to-end.
- Keychain round-trip is exercised only through namespacing/error-message tests (no SecItem calls in unit tests to keep CI hermetic).
- Proxy covers WebKit store traffic only; WebRTC/DNS/native-URLSession leak paths are documented, not yet empirically tested (needs a live server + `Scripts/verify_browser.py`-style harness).
- Google OAuth `disallowed_useragent` flows and real passkey ceremonies need a signed app + test accounts.

## Best starting point for the next agent

Read `Docs/WEBKIT.md` §"Isolation, sessions, proxy routing (Step 3)", then `Sources/AetherApp/Integration/AetherEngineAdapter+Network.swift` (routing + passkey conformance) and `Sources/BrowserUI/.../Settings/NetworkSettingsView.swift`. First live task: provision one real SOCKSv5 exit, save it in Settings → Network Privacy, and confirm `.connected` + observed IP; then run the experimental-engine test rewrite for the 38 AgentTests failures.
