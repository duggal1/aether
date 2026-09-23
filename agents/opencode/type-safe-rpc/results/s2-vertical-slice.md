# S2 — one complete typed RPC vertical slice (navigate + cookies)

Date: 2026-09-22. Host has full Xcode (`xcode-select -p` → Xcode.app); M0 toolchain blocker gone.

## Scope (caveat 3: slice before scale-out)

`AgentProcedure` infra + `PageNavigate`, `ContextSetCookie`, `ContextListCookies`
through dispatcher handlers + `AgentTypedClient`. No `Authority.swift` changes.
No browserctl changes (its `Double(args[i])` ID parsing is a known scale-out item, S4).

## Fixes applied this session (all in slice, wire-compatible)

1. `Procedures.swift` — removed `settle` throw from `PageNavigate.Input.validate()`.
   Old dispatcher defaulted invalid settle to `.complete`; the throw broke that.
   Dispatcher fallback `flatMap(PageReadiness.init(rawValue:)) ?? .complete` unchanged.
2. `AgentCommandDispatcher.handle` — added `catch AgentProcedureError` mapping to
   `engine_error` / `"Invalid or missing parameter: <key>"`, byte-identical to the
   old `DispatchError.badParameter` wire format. Without it, `validate()` errors
   leaked `AgentProcedureError(...)` debug text onto the wire.
3. `unsigned()` / `integer()` now prefer `exactUInt64` / `exactInt64`; `nodeID()`
   parses via `exactUInt64` then narrows to `UInt32`. `.number`+`exactly:` kept as
   fallback for genuine floating-point input.
4. `JSONValue` gained `case uint(UInt64)` (decode order Bool → Int64 → UInt64 →
   Double; `==`/hash keep `.integer(1) == .number(1.0)` and extend it to uint).
   Without it, any ID above `Int64.max` decayed through `Double`. No other file
   switches exhaustively on `JSONValue` (JS `case .number` matches are `JSValue`;
   Persistence matches are `SQLiteValue`), so the addition is contained.

## Verification (serial; 8 GiB host)

- `swift build --target BrowserEngine --target browserd --target browserctl` green.
- `swift test --skip-build --no-parallel --jobs 1 --filter socket|Socket|cookie|Cookie`:
  13/13 pass (7 socket lifecycle incl. cancellation-releases-blocked-client and
  slow-authorized-handler-survives, auth tests, cookie regression, profile scope).
- Full `swift test` still blocked by pre-existing, unrelated
  `Tests/HumanIntegrationTests/AdapterTests.swift:35`
  (`PasskeyAuthorizationState has no member 'allCases'`) from concurrent UI edits.
  Not touched (UI out of scope).
- Live daemon (`browserd --no-auth`) + raw-socket probe:
  - `context.destroy {9007199254740993}` → `Context not found: 9007199254740993`
    (exact 2^53+1, not rounded, not badParameter).
  - `context.destroy {18446744073709551615}` → `Context not found: ...615`
    (UInt64.max survives the wire).
  - `context.destroy {1.5}` → `engine_error / Invalid or missing parameter: context`.
  - `page.navigate {page:0}` → `engine_error / Invalid or missing parameter: page`.
  - `page.navigate` with `"settle":"bogus"` → WebKit attempted navigation
    (failed only on restricted port 9) — invalid settle still defaults, no regression.
  - `context.setCookie` → `{"ok":true}`; `context.cookies` → array with the cookie.
- `browserctl ping` against the daemon works (CLI compat).
- Compile-fail proof: `client.call(PageNavigate.self, input: ContextSetCookie.Input(...))`
  fails typecheck (`cannot convert ... to PageNavigate.Input`).

## Observations for scale-out (not fixed here)

- Listed cookie shows `"secure":true` though unset; mapping passes runtime value
  through (`secure ?? false` preserved from old code), so this originates in the
  WebKit cookie bridge. Pre-existing; needs a bridge-side check, not a dispatcher fix.
- `.integer(Int64.max) == .number(2^63)` hash mismatch (pre-existing Double-rounding
  edge in `hash(into:)`); practical ID domain never hits it.
- browserctl parses every numeric CLI arg via `Double(...)` — exact for IDs < 2^53,
  lossy above. Fix during S4 CLI migration (use `.integer`/`.uint` for ID args).
