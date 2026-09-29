# Google parity, and the auth port from Search

## 1. Google: Aether now matches the Quantum reference exactly

Checked line by line against the pasted Quantum source and `Search/`.

| | Quantum | Aether |
|---|---|---|
| Search template | `https://www.google.com/search?q=` | **same** (`AddressResolver.swift:64`) |
| Query escaping | strict unreserved set | **same set, char for char** (`AddressResolver.swift:81`) |
| Autocomplete | `suggestqueries.google.com/complete/search?client=firefox&q=` | **same endpoint, `q` parameter** (`SearchSuggestions.swift:34`, `SuggestEndpoint`) |
| Safari UA | `Version/<os>.0 Safari/605.1.15` | **same string** (`WebKitUserAgent.swift`) |
| AI Mode | — | `google.com/ai` + `udm=50` (`AddressResolver.swift:36,130`) |
| Suggestions cache | none | 512-entry TTL cache |

The UA is the one that mattered, and Aether was missing it entirely: `applicationNameForUserAgent`
appeared nowhere in `Sources`, so every page — Google included — got WebKit's default
`Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)`
with no `Version/x Safari/x` token. Google reads that as an unknown browser and serves the
older results page. `WebKitUserAgent.safariToken` is now set in `WebKitPage.makeConfiguration`,
which feeds every page view and the prewarm view.

One difference in Aether's favour: Quantum applies its UA only when `home == true` in
`addTab`, so a tab opened by `window.open` (its `createWebViewWith` passes `home: false`)
never gets it. Aether's configuration is built once per page view, so there is no such gap.

## 2. What was portable from Search, and what was already here

Read end to end: `Passkeys.swift` (1159), `ExtensionShims.swift` (4399), `Vault.swift` (378),
`Passwords.swift` (276), `Forms.swift` (374), `Accounts.swift` (92), `Session.swift` (156).

Already in Aether, no port needed: `AetherKeychain`, `AetherCredentialVault` (Security
InternetPassword, per-profile label, origin-scoped), `CredentialVault` + `credentialSecrets`
in EngineRuntime (save/list/secret/delete/fill, origin-bound), `AetherEngineAdapter+Passkeys`
(`LAContext` + `ASAuthorizationWebBrowserPublicKeyCredentialManager`), the "Passwords &
Passkeys" pane, `__aetherCredentialForms.fill` with the same native-setter + input/change
primitive Search's `put()` uses, and `AetherLocalAuth.prove` for reveal/copy.

**Blocked, and not by porting work:** the WebAuthn ceremony carrier itself. `Passkeys.swift`
is 1159 lines of `ASAuthorizationController` that exist because leaving the ceremony to
WebKit wedges `AuthenticationServicesAgent` ("Request already in progress for specified
application identifier"). Passkeys in a non-Safari browser need the restricted entitlement
`com.apple.developer.web-browser.public-key-credential` **plus** a matching Developer ID
provisioning profile (`Search/Search.passkeys.entitlements` and `Prefs.entitledToPasskeys`
are the two halves in Search). Aether signs ad-hoc and holds neither, so the entitlement key
was deliberately **not** added: a restricted entitlement without a matching profile makes
`codesign` fail and breaks the build.

Also not portable as written: `PasswordsPanel`/`AccountList` are Search's own SwiftUI design
system over Search's `Browser` object; Aether has its own settings surface and port layer.
`Session.swift` is Search's tab-session persistence — not auth despite the name.

## 3. Ported this pass: the password export reader

`Sources/BrowserUI/Sources/AetherHumanUI/Foundation/CredentialTransfer.swift` — Chrome and
Google Password Manager CSV, Search's `Vault.take(csv:)` parser (quoted fields, doubled
quotes, newlines inside quotes) on Aether's origin model instead of Search's host model:

- `origin(for:)` goes through the same `AetherCredentialVault.origin(for:)` the vault itself
  uses, so an import can never invent a credential the vault would refuse.
- A url carrying user information is dropped, which is what refuses an Android package
  (`android://…@com.vendor.app/`) rather than offering it to whoever owns that domain.
- Plain `http` is refused outside loopback, the same rule `CredentialVault.saveCredential`
  already enforces. Those rows are counted as skipped, never reshaped.
- Same site and name twice collapses to the last row, matching the vault's upsert.

`PasswordsSettingsView` gained "Import from Chrome → Choose File…" in the saved-passwords
card. The import is Touch ID gated (`AetherLocalAuth.prove`) before a single secret is
written, and reports kept versus skipped.

Nothing was deleted from Aether, and nothing under `Search/` was modified. Note: the `Search`
gitlink was already dirty in the working tree (`ab6efbb` → `1ec28a0`) before this session —
not touched here, and worth deciding on separately.

## 4. Verification

- `swift build` clean.
- `AetherHumanUITests`: **111 tests in 25 suites, all passing** (10 new in `CredentialTransferTests`).
- `HumanIntegrationTests`: 21 tests, 1 failure — `nativeAdapterPreservesPageAndProfileIdentity`,
  a pre-existing title race (pass/fail/pass over three runs earlier, unrelated to these changes).
