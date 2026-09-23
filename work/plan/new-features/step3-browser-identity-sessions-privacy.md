# Step 3 — Production Browser Identity, Sessions, Passkeys, Keychain, Privacy, Geographic Routing

Route: new-features. Status: executing. Owner: opencode agent.

## Define

Required behavior (user prompt filtered through repository reality):

1. Website sessions persist across restarts because each permanent profile owns a stable
   `WKWebsiteDataStore` UUID; never destroy auth state on 401/redirect failure.
2. Private contexts never share website data with each other or with permanent profiles.
3. Profile isolation is proven by tests (cookies, local storage, store identity).
4. Passkeys use Apple's real browser APIs; entitlement limitations are reported honestly.
5. Aether-owned secrets (proxy credentials today) live in Keychain, namespaced per profile.
6. Search locality (default San Francisco / 94158) is independent of network exit region.
7. Browser-scoped egress via `WKWebsiteDataStore.proxyConfigurations` + `Network.ProxyConfiguration`
   (SOCKS5 or HTTP CONNECT, `applyCredential`, fail-closed via `allowFailover = false`).
8. Exit regions (SF, NY, Boston, Philadelphia, Direct) select real user-provisioned endpoints;
   no ZIP-to-IP fiction; no fake green status — connected only after an egress probe returns
   the observed public IP (optionally matched against an expected IP).
9. Settings UI gains a Network Privacy section, a Search Location section, truthful
   Passwords & Passkeys status, and an Authentication panel backed by an explicit
   `BrowserSessionState` model that never claims auth from mere navigation success.

Constraints:

- Preserve existing SQLite/ProfileStore split: WebKit owns website data; SQLite owns app state.
- Preserve UI ↔ one-runtime architecture; UI never imports EngineRuntime (adapter converts).
- No second settings store: app preferences stay in BrowserPreferences/UserDefaults.
- No UA spoofing, no cookie extraction into SQLite/Keychain, no custom payment vault,
  no NetworkExtension tunnel, no exit-server deployment (no infra credentials here).
- macOS 27 / Swift 6; AetherHumanUI is swiftLanguageMode v5 in root manifest.

## Evidence from inspection (audit)

- `WebKitStoreCache.shared` returns ONE shared ephemeral store for every `identifier == nil`
  call → unrelated private/fallback contexts would share website data. `WebKitContext.ephemeral()`
  correctly creates fresh stores; the shared fallback is the defect.
- Profile ID flow: `BrowserProfile.id` → adapter directory name → `openProfile` parses UUID →
  `webProfileIdentifiers[contextID]`. Stable across launches. `createContext` mints a temp UUID
  that openProfile overwrites before first page in the app path; `openProfile` does not drop an
  already-cached `webContexts[contextID]` built on the temp store (edge: pages before openProfile).
- `destroyContext` never releases the store from `WebKitStoreCache.named`.
- Session restoration exists: `checkpoint` → `session_pages`/`history`; `attachProfile` recreates
  discarded page records; UI restores tabs lazily (surfaces attach via `BrowserPageActivating`
  on selection in BrowserContentView).
- SDK verified: `WKWebsiteDataStore.proxyConfigurations: [Network.ProxyConfiguration]` (macOS 14+);
  `ProxyConfiguration(socksv5Proxy:)`, `init(httpCONNECTProxy:tlsOptions:)`,
  `applyCredential(username:password:)`, `allowFailover`.
  `ASAuthorizationWebBrowserPublicKeyCredentialManager` (macOS 13.3+): authorizationState,
  requestAuthorization, `isDeviceConfiguredForPasskeys` (26.2+).

## Slices

1. Engine store-identity hardening: non-shared ephemeral, release on destroy,
   reset cached context on profile-identifier change when no live pages,
   throw on permanent path with missing identifier. Tests: distinct stores,
   ephemeral isolation, release.
2. `AetherKeychain` in Persistence (service `fun.aether.secure-storage`,
   `WhenUnlockedThisDeviceOnly`, account namespacing `profile:provider:account`) + tests.
3. Network route: engine `setNetworkRoute`/`clearNetworkRoute`/`probeEgress(contextID:)`;
   UI `AetherExitRegion`, `BrowserNetworkRoute`, per-region endpoints (no secrets),
   `NetworkRouteStatus` with six honest states; adapter port methods
   (apply/probe/setProxyCredential via Keychain); Network Privacy settings section.
4. Search locality: `SearchLocality.sanFrancisco` default persisted in BrowserPreferences;
   opt-in query-append toggle (default off); AddressResolver + BrowserWindowModel wiring;
   Search settings section; tests prove locality ≠ route independence.
5. Passwords & Passkeys settings: real `ASAuthorizationWebBrowserPublicKeyCredentialManager`
   state + signing-entitlement detection; `BrowserSessionState` + conservative classifier +
   Authentication panel (navigation-level truth only).
6. Privacy logging audit (no cookie/token/password logging) + profile-isolation cookie test.
7. Verify: `swift build` (root), `Sources/BrowserUI && swift build`,
   `nice -n 10 swift test --no-parallel --jobs 1`; update `Docs/WEBKIT.md`;
   write `Docs/SESSIONS_PRIVACY_IDENTITY.md` (audit + unresolved external restrictions);
   conclusion under `agents/opencode/step3-identity-sessions/`.

## Success criteria

- Builds green (root + BrowserUI); tests green on this Xcode host (or documented failure).
- Isolation and locality/route-independence covered by tests.
- No claim of passkey entitlement approval, exit-IP privacy, or Google OAuth coverage
  without observed evidence; unresolved items listed in the identity doc.

## Assumptions recorded

- App preferences persist in UserDefaults (existing BrowserPreferences), not SQLite —
  "do not create a second preferences database" honored.
- Exit endpoints are user-provisioned; regions without endpoints report unavailable.
- Egress probe uses `https://api.ipify.org?format=json` on manual action only (not in tests).
- Password autofill / payment vault: documented limitation only (no public general API
  path verified for third-party macOS browsers beyond platform mechanisms).
