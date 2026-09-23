# Google authentication compatibility matrix

Date: 2026-09-22. Host: macOS 27, Xcode SDK (MacOSX27.0.sdk, build 26A425).
Status convention: `untested` means exactly that. Nothing below is inferred from
homepage loads, and no flow is marked working without an observed sign-in.

## Why this matrix exists separately from session persistence

`WKWebsiteDataStore` persistence (Slice 2) proves Aether does not destroy its own
side of a session. It does not prove Google accepts Aether's browsing
environment. Google's OAuth documentation names `disallowed_useragent` for
authorization requests opened in disallowed embedded browsers including
`WKWebView`. That error applies to OAuth authorization endpoints, not to every
Google web sign-in, so each flow below must be tested independently.

## Flow matrix (all real-account rows: untested)

| Flow | Result | Notes |
|---|---|---|
| Google Search (signed out) | untested | No OAuth involved; expected to work, not yet run |
| Google Account sign-in (accounts.google.com) | untested | |
| Gmail login + session restore across relaunch | untested | Depends on Slice 2 persistence + provider acceptance |
| YouTube login + session restore | untested | |
| Notion → Continue with Google (popup) | untested | Popup/OAuth endpoint most likely to hit `disallowed_useragent` |
| Slack → Continue with Google (popup/redirect) | untested | |
| GitHub → Google authentication where offered | untested | |
| Google account chooser / multi-account switch | untested | Must use Google's own UI; no custom account layer |
| Reauthentication after provider-side expiry | untested | Must route to `BrowserSessionState.reauthenticationRequired`, never auto-wipe |

No user-agent spoofing, no injected script removing security checks, no OAuth
token interception, and no private Safari API is used or planned. If a provider
rejects the embedded environment, the supported fallback is an external
`ASWebAuthenticationSession` flow for Aether-owned integrations (below), and
honest reporting for website flows.

## `ASWebAuthenticationSessionWebBrowserSessionManager` (SDK-verified, not integrated)

Verified present in the installed SDK:

- `ASWebAuthenticationSessionWebBrowserSessionManager` (macOS 10.15+):
  `sharedManager`, `sessionHandler`, `wasLaunchedByAuthenticationServices`.
- Handler protocol `ASWebAuthenticationSessionWebBrowserSessionHandling`:
  `beginHandlingWebAuthenticationSessionRequest:` /
  `cancelWebAuthenticationSessionRequest:`.
- Passkey headers present: `ASAuthorizationWebBrowserPublicKeyCredentialManager`
  (`isDeviceConfiguredForPasskeys` macOS 26.2+),
  `ASAuthorizationWebBrowserPlatformPublicKeyCredentialProvider`,
  `ASAuthorizationWebBrowserSecurityKeyPublicKeyCredentialProvider`.

Not yet done: registering Aether as a `sessionHandler`, verifying what the OS
grants a non-default, non-entitled browser, and confirming this changes nothing
about Google's independent `disallowed_useragent` policy. Integration without
that verification would be a badge, not a capability.

## Aether-owned Google API access (pattern documented, not implemented)

Separate from website sessions. If Aether ever needs its own Gmail API access:

1. External `ASWebAuthenticationSession` authorization with PKCE against
   Google's native-app OAuth endpoint (registered client ID required; none exists).
2. Refresh token into `AetherKeychain` under
   `credentialAccount(profileID:provider:accountID:)` — never SQLite, never logs.
3. Never convert that token into website cookies; the API relationship and the
   website session are distinct authentications.

No client ID is registered and no OAuth code is written, because code without
registration would be untestable theater.

## Manual verification protocol (local only, secrets never committed)

1. Create a dedicated test profile; record its UUID.
2. Sign into the test Google account; visit Gmail and YouTube in separate tabs.
3. Close tabs, quit Aether, restart the Mac, reopen, revisit both sites.
4. Record per flow: persists / reauth-required / rejected, with the exact error
   (`disallowed_useragent` or otherwise) and which step produced it.
5. On logout, classify first: provider invalidation vs Aether storage loss
   (check `Fixtures/webkit/session.html` markers before blaming cookies).
6. Test credentials live in the operator's hands only. Never in files, tests,
   logs, screenshots, or diagnostics.
