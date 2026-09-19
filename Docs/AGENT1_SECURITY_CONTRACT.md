# Agent 1 security and integration contract (incremental)

This is the actual socket-facing contract introduced on the Agent 1 task branch.
It is **not** a macOS renderer sandbox or certification for hostile web content.

## Principal and context authority

- `browserd` constructs `AgentCommandDispatcher(requireCapabilities: true)`. Unit tests that directly instantiate the dispatcher still use its compatibility-only in-process default; that default MUST NOT be used for untrusted socket clients.
- `context.create` returns the normal context fields plus an opaque `capability` string. Treat it as a bearer secret. The daemon generates two UUIDv4 values and retains the grant only in memory.
- Every other supported `context.*` request supplies `params.capability` plus `params.context`. Every `page.*` request supplies `params.capability` plus `params.page`; `page.create` instead supplies `params.context`. `context.list` returns only contexts authorized by that capability. `ping` is public.
- The dispatcher consults BrowserRuntime for the page's context before acting; a caller-supplied `owner`, context number on a page request, or session name has no authority. Deleting a context revokes the in-memory grant.
- `browserctl --socket ... context-create` prints the capability. Subsequent CLI calls can provide it through `AETHER_CAPABILITY`. Avoid storing it in source control, logs or shared shell history.
- As yet unscoped `session.*`, `fleet.*`, `page.capture`, `dialog.resolve`, and `context.openProfile` return structured `unauthorized` errors from the daemon. A caller-selected `context.download` path and agent self-approval of privileged permissions are denied. This deliberately limits previous socket functionality until Agent 2/3 wire principal-aware APIs; the internal BrowserRuntime is unchanged.

A bearer token is **not** macOS audit-token/peer-process identity; any holder can use it. Socket chmod 0600 restricts other OS users but cannot isolate malicious processes running as the same OS account. Renderer-process sandbox, peer credential checks, capability delegation/revocation beyond context deletion, durable grants, approval workflow and principal-aware host profile/file grants are still open. Never identify a token holder as a particular executable or human.

## Shared contract for Agents 2 and 3

- Preserve `BrowserRuntime` as page/context authority. Use `ContextID`/the owning `PageID` for authorization, not freeform owner strings. Surface operations and media/network requests must inherit this authority.
- Add new `page.*` methods with a validated `page` parameter, or explicitly extend the dispatcher guard for exceptional methods. A new `context.*` method must include its `context` parameter. Do not create an unguarded global method. `page.create` is intentionally context-scoped.
- Agent 2: include principal capability and context in attach/control/session handoff, and authorize media-resource requests before crossing an eventual renderer IPC boundary. Never give child renderers bearer tokens or host file handles.
- Agent 3: bind profiles, downloads, capture and dialogs to a context or authenticated session; do not remove the existing deny-by-default guards to make the old fixture pass. The existing full `Scripts/verify_browser.py` requires adaptation to the new capability and sensitive-operation contracts; `Scripts/verify_authority.py` is a separate denial test, not a replacement for that suite.
- `NetworkSession` now has `HTTPRequest.sendsCookies` (true by default). `PageHostWiring.fetchHandler` sets false for cross-origin fetch, supplies Origin for cross-origin requests, validates preflight response origin/status, and verifies final response origin/mixed-content after redirects. Other page-initiated resource paths must receive the same policy. Redirect credentials and full CORS/SameSite semantics still require deeper network ownership work.

## Evidence and unsupported behavior

The root manifest includes these source paths and macOS CI compiles/tests them. `Tests/AgentTests/AgentAuthorityTests.swift` exercises two capabilities, forged owner labels, cross-context/page read rejection, revocation and fail-closed sensitive calls. `Tests/NetworkTests/NetworkTests.swift` checks script protection of HttpOnly cookies. `Tests/SecurityTests/SecurityTests.swift` checks preflight safelisting. `Scripts/verify_authority.py` operates through the real daemon's Unix socket on macOS.

The custom JS runtime still runs in privileged `browserd` process. No actual renderer child sandbox, hostile-iframe process isolation or crash containment is present. A bearer grant stops other clients that lack the token; it does not make malicious JS safe. No claim of broadly compatible production websites follows from these tests.
