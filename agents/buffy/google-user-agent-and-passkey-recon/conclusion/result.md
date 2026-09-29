# Result: the Google page was old because the user agent was not Safari's

## Change

- `Sources/EngineRuntime/WebKit/WebKitUserAgent.swift` (new) — `safariToken`:
  `Version/<max(26, macOS major)>.0 Safari/605.1.15`.
- `Sources/EngineRuntime/WebKit/WebKitPage.swift` — `makeConfiguration` sets
  `applicationNameForUserAgent`. That one function feeds the page view
  (`WebKitPage.swift:833`) and the prewarm view (`WebKitPrewarm.swift:21`), so
  every page the browser shows now carries it.

Nothing else about search was touched: the template, the strict query escaping,
the Google autocomplete endpoint and its cache were already what the Quantum
snippet does, and Search's own Google code is the same template as Aether's.

## Verification

- `Tests/HumanIntegrationTests/UserAgentTests.swift` (new, 3 tests):
  - `pageConfigurationCarriesTheSafariUserAgent` — the configuration every page
    gets carries the token (uses `WebKitContext.ephemeral()`, no data store
    touched).
  - `safariTokenNamesAVersionAndSafariItself` — shape of the token.
  - `thePageIsToldItIsSafari` — a real `WKWebView` loads and reports
    `navigator.userAgent`; it contains `AppleWebKit/605.1.15`, `Version/` and
    `Safari/605.1.15`. This is the one that proves the page, not just the
    configuration, sees Safari.
- `swift build` clean; `AetherHumanUITests` 101/101; `HumanIntegrationTests`
  20 tests, 19 pass — see below.

## Not a regression

`nativeAdapterPreservesPageAndProfileIdentity` (`Tests/HumanIntegrationTests/
AdapterTests.swift:22`) is flaky on this tree: three consecutive runs of only
that test gave pass / fail / pass. It reads a page title straight after
`loadHTML` and races the renderer. A user-agent string cannot affect title
readiness. Worth fixing separately; not caused by this change.

## Next

The passkey work is blocked before it is hard — see `results/recon.md`. The
portable first slice, needing no Apple entitlement, is the keychain-backed
logins (Search's `Vault.swift` + `Passwords.swift` + the account list in
`Accounts.swift`) against Aether's existing `AetherKeychain` and
`AetherCredentialVault`.
