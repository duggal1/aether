# Sessions, privacy, and identity — audit and verification record

Date: 2026-09-22. This is the evidence file for the Step 3 gap-fill slices.
Claims without a test name, command, or observed output below are not claims.

## 1. Profile identity audit (verified in code)

- Permanent profiles own a stable UUID: `BrowserRuntime.openProfile` parses the
  UUID from the profile directory name into `webProfileIdentifiers[contextID]`
  (`Sources/EngineRuntime/BrowserRuntime.swift`), and `WebKitContext(identifier:)`
  opens `WKWebsiteDataStore(forIdentifier:)` with that same UUID. SQLite profile
  UUID == WebKit store UUID by construction, stable across relaunch.
- `WebKitStoreCache.store(for: nil)` returns a **fresh** nonpersistent store per
  call (`Sources/EngineRuntime/WebKit/SystemWebRuntime.swift:15`). There is no
  shared ephemeral fallback anymore. Any prompt or doc quoting a `private let
  ephemeral` shared store describes the pre-fix version and must not be used.
- Permanent-context creation (`webPage`, `configureWebBlocking`,
  `webContextForCookies`) throws `invalidState` when the profile identifier is
  missing instead of silently sharing a store.
- `WebKitPage` sets `configuration.websiteDataStore = context.store` before the
  first navigation (`WebKitPage.swift:62`). Stores are never swapped under a
  live view; changing exit region applies proxy configuration to the existing
  store and never recreates it.

## 2. Session persistence (implemented + tested, real-account proof outstanding)

- Automated: `Tests/AgentTests/WebKitSessionPersistenceTests` (4/4 pass) —
  cookie markers survive a fresh `WebKitContext` for the same profile UUID,
  profiles are isolated, ephemeral contexts see neither direction, and the
  runtime cookie APIs are profile-scoped.
- Real end-to-end: `Tests/AgentTests/WebKitRealSessionTests` (2/2 pass, ~7 s,
  always on, localhost only) — a real `WKWebView` navigates over real HTTP to
  `session.html?seed=1`, all three markers (cookie, localStorage, IndexedDB)
  are observed, the context is destroyed, a **new** `BrowserRuntime` opens the
  same profile UUID, revisits without seed, and all three markers are still
  there; a second profile sees none. This exercises the true storage stack,
  not a store-pointer comparison. Boundary: same-machine runtime recreation,
  not full app-quit-plus-reboot (manual protocol below covers that).
- Manual fixture: `Fixtures/webkit/session.html` (`?seed=1` writes cookie +
  localStorage + IndexedDB markers; plain load reports them as JSON) for the
  tab-close / quit / reboot walkthrough served from `Fixtures/webkit`.
- Session restoration vs authentication persistence stay separate systems:
  SQLite `session_pages`/history restore tab identity; WebKit restores the
  authenticated experience. Restored tabs navigate lazily; private tabs are
  never archived.
- New: `BrowserSessionState` (`notLoaded/loading/navigated/
  reauthenticationRequired/failed`, `Sources/EngineRuntime/SessionAuthState.swift`).
  `navigated` deliberately never claims signed-in. `reauthenticationRequired`
  fires only on HTTP 401/403/407 or a login-URL redirect with prior history on
  the page. Nothing auto-clears website data on 401/403/redirect failure.
  Surfaced to the UI through `BrowserSessionStateProviding`/`EngineSessionState`
  (`BrowserFeaturePorts.swift`); adapter-mapped in
  `AetherEngineAdapter+Features.swift`; disconnected engine reports `.notLoaded`.
- Outstanding: the real Gmail/YouTube manual pass (protocol in
  `Docs/GOOGLE_AUTH_MATRIX.md`). No real credentials exist anywhere in the repo.

## 3. Passkeys (public APIs only, no entitlement theater)

- Shipped: `AetherEngineAdapter+Passkeys.swift` — real
  `ASAuthorizationWebBrowserPublicKeyCredentialManager` state
  (`isDeviceConfiguredForPasskeys`, `authorizationStateForPlatformCredentials`,
  `requestAuthorizationForPublicKeyCredentials`) plus `LAContext`
  `.deviceOwnerAuthentication` availability as `passkeyLocalAuthAvailable`.
  Settings → Passwords shows both rows; private-key material never enters
  Aether code, logs, or the agent protocol.
- `com.apple.developer.web-browser.public-key-credential` is **not** in
  `AetherApp.entitlements` and has not been requested. Requesting it means an
  Apple Developer request for a managed browser capability plus provisioning
  and signing changes; until granted, WebKit uses the OS standard flow where
  permitted. No code pretends otherwise.
- `ASWebAuthenticationSessionWebBrowserSessionManager` verified present in the
  installed SDK (handler protocol with begin/cancel); not integrated, pending
  verification of what the OS grants a non-default browser.
- Tests: `HumanIntegrationTests` passkey/session-state cases (5/5 with the
  fail-closed case). Hardware security keys are not required for ordinary
  support; hardware E2E stays a documented manual step.

## 4. Keychain (implemented, scoped)

- `AetherKeychain` (`fun.aether.secure-storage`,
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`): update-or-add, load, delete,
  contains. Account namespacing `<profileUUID>:<provider>:<accountID>` and
  `proxy:<endpointID>`. Proxy credentials live only in Keychain; SQLite,
  UserDefaults, and logs never receive them (asserted by
  `persistedPreferencesNeverCarrySecrets`).
- Website session tokens are never copied into Keychain or SQLite. WebKit is
  the source of truth for website state; Keychain is the source of truth for
  Aether-owned secrets only.

## 5. Search locality vs network route (independent, tested)

- `SearchLocality.sanFrancisco` (US/CA, 94158, nearby 94105/94103/94110) is the
  default in `BrowserPreferences`; provider parameters only (`gl`/`hl`, `kl`,
  `setmkt`); locality query terms opt-in, default off. Route changes never
  rewrite locality and vice versa (existing independence tests still pass).
- ZIP codes are search-locality preferences, never IP assignments. No code maps
  a ZIP to an address.

## 6. Egress routing (plumbing + verification, no free fixed IP)

- `BrowserNetworkRoute` + `RouteEndpoint` (+ new optional `expectedExitIP`) →
  `BrowserRuntime.configureWebProxy` → `Network.ProxyConfiguration` on the
  profile's store, `allowFailover = !failClosed`, missing/unreachable endpoint
  under fail-closed blackholes via `WebProxyEndpoint.failClosedBlackhole`.
- `connected` requires a live `api.ipify.org` probe, and when `expectedExitIP`
  is set, probe output must equal it — otherwise `.unavailable` with the
  observed IP still shown. Configuring an endpoint never claims a hidden IP.
- There is no free-forever stable fixed-region IP: stable exits cost
  infrastructure, free tiers need a card, Tor rotates and alarms provider
  security checks. `routeEndpoints` therefore defaults to empty; regions
  without endpoints report unavailable/blocked, never a fabricated location.
- Free verification shipped: `Scripts/verify_egress.sh` (direct-IP observe +
  blackhole fail-closed demo + optional bounded `tcpdump` capture of echo-host
  traffic only; ran live 2026-09-22 incl. `--capture`: all PASS) and
  `Fixtures/webkit/egress.html` (public-IP, WebRTC ICE, IPv4/IPv6 reachability
  report for manual runs).
- Live probe evidence (`Tests/AgentTests/WebKitEgressProbeLiveTests`, gated
  behind `AETHER_LIVE=1`, ran green 2026-09-22 in real WebKit): public IP
  observed via echo endpoint, IPv4 fetch reachable, IPv6 unreachable on this
  network, host ICE candidate correctly mDNS-obfuscated
  (`*.local`), **server-reflexive candidate exposes the public IP** — standard
  WebRTC behavior, and exactly why the route must be verified end-to-end
  rather than trusted from a badge. WebRTC is deliberately not disabled to
  make a test pass.
- Known boundary (documented, not papered over): per-store proxying covers
  WebKit traffic; native `URLSession` calls and non-WebKit processes need
  their own routing. No NetworkExtension tunnel is shipped.

## 7. Privacy audit (implemented + tested)

- No `print`/`NSLog`/`os_log` of secrets in `Sources/`; CLI prints are explicit
  user-requested output only. Dispatcher error messages carry IDs and
  caller-supplied navigation parameters, never cookie values, tokens, or
  Keychain material.
- `Tests/AgentTests/PrivacyLoggingTests` (2/2 pass): cookie canaries absent
  from dispatcher errors and unrelated results; cookie listing stays scoped to
  its own context.
- Cookie values remain available over the authorized agent socket to the owning
  session (`context.cookies`) — an existing profile-scoped capability, not a
  leak path. Agent pages never cross profiles.

## 8. Unresolved externals (not implemented, not faked)

1. Apple browser-passkey entitlement approval.
2. User-provisioned regional exit servers (or acceptance that none exist).
3. Google `disallowed_useragent` outcomes per flow (`Docs/GOOGLE_AUTH_MATRIX.md`,
   all rows `untested`).
4. Real-account session-restore evidence across reboot.
5. Full WebRTC/DNS/IPv6 leak measurement on a provisioned route.

## 9. Pre-existing failures observed on this host (not caused by these slices)

Full suite 2026-09-22 (`swift test --no-parallel --jobs 1`, 17 target runs):
15 green, 2 red — `AgentTests` (79 tests, 39 issues across experimental-engine
fleet/capture/media/find paths) and `AetherHumanUITests` (52 tests, 4 issues,
all `DesignSystemTests` symbol/font contracts). Zero failures in any test added
or touched by these slices (verified by name against the full log). The failing
paths (`CaptureSessionAdapter`, software renderer, fleet accounting, Design
tokens) are untouched by these slices and fail identically in kind with or
without this diff. `swift build -c release --jobs 1` is green, as is the
standalone `Sources/BrowserUI` build.
