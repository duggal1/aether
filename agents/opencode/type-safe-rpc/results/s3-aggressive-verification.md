# S3 — aggressive verification of the typed RPC slice (not a smoke test)

Date: 2026-09-22. Full Xcode host. All builds/tests serial (`--jobs 1`, `nice`).

## 1. Full suite vs s0 baseline

Built all 17 engine test targets (excluding `HumanIntegrationTests`, which does not
compile due to pre-existing concurrent UI breakage
`AdapterTests.swift:35 PasskeyAuthorizationState.allCases`, and `AetherHumanUITests`).
`swift test --skip-build --no-parallel --jobs 1`: **303 passed, 21 failed**.
Failing set is byte-identical to `s0-preexisting-failed-tests.txt`
(compared via `sort`+`diff`; only `()` suffix formatting differs).
Zero new failures, zero fixed. All 21 are capture-adapter, design-symbol,
find-in-page, fleet, media, scroll suites — untouched by this change.

## 2. Live authenticated daemon + real website (browserctl + browserd, token auth)

- `context-create`, `page-open https://example.com complete` → `loaded:true`,
  `title:"Example Domain"`, history tracked.
- `page-snapshot` → full structured tree (roles, bounds, text, link href).
- `page-eval "document.title + '|' + ..."` → `Example Domain|2`.
- `context-set-cookie 1 probe live123 example.com /` → `ok:true`;
  `context-cookies` lists it; page JS `document.cookie` → `probe=live123`
  (agent protocol → runtime → WebKit store → live page, end to end).
- Wrong token → `unauthorized / authentication failed`, clean rejection.

## 3. Real Swift typed client (`AgentTypedClient`, compiled against current sources)

- `ContextSetCookie` → `ok:true`; `ContextListCookies` → both cookies;
  `PageNavigate(page:1, example.com)` → `title=Example Domain loaded=true`.
- `ContextListCookies(context: 2^53+1)` → `Context not found` (exact, not rounded).
- `PageNavigate(page:0)` → `engine_error / Invalid or missing parameter: page`.
- Compile-fail proof: wrong `Input` for a procedure is a type error.

## 4. Wire discriminators through the live daemon (raw socket, --no-auth)

- `context.destroy {9007199254740993}` → `Context not found: 9007199254740993`
  (exact 2^53+1 through JSON text → `.integer` → dispatcher).
- `context.destroy {18446744073709551615}` → `Context not found: ...615`
  (UInt64.max via new `.uint` case).
- `context.destroy {1.5}` → `Invalid or missing parameter: context` (still rejected).
- `page.navigate {settle:"bogus"}` → navigation attempted (failed only on
  restricted test port) — invalid settle still defaults to `.complete`.

## 5. Load assault: 20 parallel clients + 60 abrupt disconnects

11,462 successful ping/snapshot round-trips in 8 s, 0 errors; partial-message and
authed-then-vanish slams; post-assault ping/snapshot/eval all functional.
Daemon RSS 23 MB after. No crash, no hang, no wedge.

## 6. Findings (honest, with scope)

- FIXED: `AgentCommandDispatcher+Authority.identifier()` parsed IDs through
  `Double`, silently remapping huge IDs before the ownership check, and the
  `context.create` bind did the same. Now `exactUInt64` (fail-closed).
  Existing `authenticatedPageListingUsesContextOwnership` + all auth/cookie tests green.
- NOT FIXED (out of scope, needs human decision): `AgentSessionStore` lockout is
  global and permanent — 5 bad tokens from any source bricks auth for everyone
  until daemon restart (reproduced live; legitimate client locked out). Suggest:
  per-source counting and/or lockout expiry. Existing
  `socketAuthLocksOutAfterRepeatedFailures` enshrines current behavior.
- NOT FIXED (scale-out item): browserctl parses all numeric CLI args via
  `Double(...)` — exact below 2^53, lossy above. Fix in S4 CLI migration.
- NOT FIXED (pre-existing): listed cookies show `secure:true` when unset;
  originates bridge-side (`secure ?? false` preserved). Needs bridge-side check.
- Cold-start note: fresh `browserd` takes several seconds (WebKit spin-up) before
  the socket appears — poll for it; `sleep 1` races it. No bug.
