# Recon: "steal the latest Google engine + passkeys/keychain/Touch ID from Search"

Asked for: port Search's Google search engine, and "everything" for passkeys,
keychain, Google account management, Touch ID, without deleting anything.

What the code actually contains, with the evidence:

## 1. Google search engine — Search has nothing newer to steal

| Thing | Search | Aether (already) |
|---|---|---|
| Google search template | `Engine.swift:26` → `https://www.google.com/search?q=%s` | `AddressResolver.swift:64` → identical |
| Google autocomplete | **none anywhere in Search** | `EngineRuntime/SearchSuggestions.swift:34` → `suggestqueries.google.com/complete/search?client=firefox` |
| Query escaping | `Engine.url(for:template:)`, `unreserved` set | identical (`SearchProvider.url(for:template:)`) |
| AI Mode | not modelled | `SearchProvider.googleAI`, `udm=50` (correct: Google's own shortcut is `google.com/ai` + `?udm=50`) |
| Suggest caching/debounce/ranking | none | `SearchSuggestService` (512-entry TTL cache, in-flight de-dup, warm) + `OmniboxSuggestionModel` |

Search's `Address.swift` is explicit that it does no search at all ("There is no
search here"). So there was nothing to port on that side.

**The real defect: Aether sent WebKit's default user agent.** `grep
applicationNameForUserAgent Sources` returned nothing before this change, so
every page got `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)
AppleWebKit/605.1.15 (KHTML, like Gecko)` — no `Version/x Safari/x` token. A
site that reads the UA (Google above all) takes that for an unknown browser and
serves its older page. The pasted Quantum code names exactly this and fixes it
with `Version/<macOS major>.0 Safari/605.1.15`.

Fixed: `Sources/EngineRuntime/WebKit/WebKitUserAgent.swift` +
`WebKitPage.makeConfiguration`, which every page view (and the prewarm view)
comes from. Verified against a live WKWebView in
`Tests/HumanIntegrationTests/UserAgentTests.swift`.

## 2. Passkeys, Touch ID, keychain — half of it exists already

Already in Aether:

- `BrowserUI/Foundation/AetherKeychain.swift` — full Security-framework
  wrapper (generic password, save/load/delete/contains).
- `AetherApp/Integration/AetherEngineAdapter+Passkeys.swift` — `LAContext`
  Touch ID availability, `ASAuthorizationWebBrowserPublicKeyCredentialManager`
  authorization state + request, i.e. the passkey permission and the UI for it
  (`Settings/PasswordsSettingsView.swift`, "Passwords & Passkeys").
- A credential vault + save/offer popover (`AetherCredentialVault`,
  `Native/AetherCredentialPopover`).

Missing (Search has it, Aether does not): the **WebAuthn ceremony itself** —
`Search/Sources/Search/Passkeys.swift`, 1159 lines. Search carries the ceremony
because leaving it to WebKit wedges `AuthenticationServicesAgent`: once a
conditional-mediation operation is opened and the app dies holding it, every
passkey request afterwards fails with "Request already in progress for
specified application identifier" until the agent restarts. The file intercepts
`navigator.credentials`, checks the requesting frame's origin, writes its own
client data, drives `ASAuthorizationPlatformPublicKeyCredentialProvider`, and
serves the credential back to the page.

Its dependencies are not separable: `Vault.swift` (378, keychain internet
passwords + Touch ID), `Passwords.swift` (276), `Forms.swift` (374),
`Accounts.swift` (92, the account list under a login field), `Session.swift`
(156), and `ExtensionShims.swift` (4399 lines) which is where the page-side
hooks live. It is threaded through Search's `Browser`/`Tab` state. A port is a
rewrite against Aether's actor model, not a file copy.

## 3. The blocker that outranks the port

Passkeys in a non-Safari browser need Apple's restricted entitlement
`com.apple.developer.web-browser.public-key-credential`, which only works
alongside a matching Developer ID provisioning profile embedded in the app —
`Search/Search.passkeys.entitlements` and `Prefs.entitledToPasskeys`
(`SecTaskCopyValueForEntitlement`) show both halves. Aether's entitlements
(`Sources/AetherApp/Resources/AetherApp.entitlements`) have neither, and the
packaging script signs ad-hoc (`AETHER_SIGNING_IDENTITY` defaults to `-`).

Adding the key alone would break the build: a restricted entitlement without a
matching profile makes `codesign` refuse. Without it, the code in
`AetherEngineAdapter+Passkeys.swift` reports `.denied`/`.unavailable` and the
platform will not offer the app's passkeys at all — so porting the 1159 lines
first would be work that cannot run.

Needed before that port can be worth starting: an Apple Developer account with
the entitlement granted for Aether's App ID, a Developer ID provisioning
profile carrying it, a team identifier in the entitlements, and a real signing
identity in `build_aether_app.sh`.
