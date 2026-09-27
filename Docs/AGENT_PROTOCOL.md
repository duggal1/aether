# Agent Protocol

Agents are first-class clients of the engine. Structured state is the default control surface; screenshots and raw coordinate interaction are fallbacks for genuinely visual tasks.

`Sources/AgentProtocol/AgentMessages.swift` is authoritative for the method set. This document describes the wire contract and every method as of the current tree (89 methods).

`browserd` accepts newline-delimited JSON over a local Unix-domain socket (default `/tmp/native-browser-engine.sock`). Every request contains an `id`, `method`, and optional `params`. Every response repeats the request `id` and contains either `result` or a structured `error`:

```json
{"id": "1", "result": {"ok": true}}
{"id": "2", "error": {"code": "engine_error", "message": "Page is not loaded: 1"}}
```

A missing result is a JSON `null`, not an absent key: `{"id": "3", "result": null}`. The response encoder always emits a present `result` key when the outcome is a result, so clients can distinguish "no match" from "no answer". Error codes are stable strings (`method_not_found`, `bad_parameter`, `engine_error`, …).

## Methods (84)

### Session and transport

```text
ping
```

### Contexts (3)

```text
context.create    context.destroy    context.list
```

### Page lifecycle and navigation (9)

```text
page.create       page.navigate      page.navigateInput page.back
page.forward      page.reload        page.resize        page.close
page.list
```

### Inspection and observation (7)

```text
page.inspect      page.query         page.queryAll     page.find
page.snapshot     page.wait          page.mutations
```

### Input and interaction (9)

```text
page.click        page.drag          page.type          page.setValue     page.pressKey
page.selectOption page.fill          page.submit       page.hover
page.focus
```

### Focus/scroll state (7)

```text
page.blur         page.focused       page.hovered      page.scroll
page.scrollOffset page.scrollIntoView  page.nodeAtPoint
```

### Evaluation and rendering (2)

```text
page.evaluate     page.render
```

### Page state and diagnostics (10)

```text
page.loadHTML     page.lifecycle     page.setLifecycle page.restore
page.history      page.console       page.networkLog
page.frame        page.workers       page.dialogs
```

### Dialogs (1)

```text
dialog.resolve
```

### Cookies (4)

```text
context.cookies   context.setCookie  context.removeCookie
context.clearCookies
```

### Storage (5)

```text
context.storageOrigins   context.storageValues   context.storageSet
context.storageRemove    context.storageClear
```

### Permissions (3)

```text
context.permission       context.setPermission   context.permissions
```

### Downloads (3)

```text
context.download  context.downloads  context.clearDownloads
```

### Profiles and checkpoints (5)

```text
context.openProfile      context.checkpoint      context.profileUsage
context.setCheckpoint    context.checkpointValue
```

### Bookmarks, suggestions, search provider (6)

```text
context.bookmarkAdd      context.bookmarks       context.bookmarkRemove
context.suggest          context.searchProvider  context.setSearchProvider
```

### Agent-readable credentials (5)

```text
credentials.list       credentials.get         credentials.save
credentials.delete     credentials.fill
```

### Sessions (4)

```text
session.create    session.list       session.destroy   session.pages
```

### Fleet (3)

```text
fleet.stats       fleet.pages        fleet.sweep
```

### Capture (1)

```text
page.capture
```

## Node identity

DOM nodes use a pair of unsigned values:

```json
{"index": 42, "generation": 3}
```

The generation prevents stale references from silently becoming references to newly allocated nodes.

Interactive inspection exposes semantic role, accessible name, current value, href, enabled/editable/visible state, and layout bounds where available. Snapshot output additionally contains the structured document tree, attributes, text, parent/children relationships, and mutation version.

`page.query` returns `null` when nothing matches; `page.queryAll` returns an empty array.

## Example

```json
{"id":"1","method":"context.create","params":{"name":"research"}}
{"id":"2","method":"page.create","params":{"context":1,"width":1280,"height":800}}
{"id":"3","method":"page.navigate","params":{"page":1,"url":"https://example.com"}}
{"id":"4","method":"page.query","params":{"page":1,"selector":"a"}}
{"id":"5","method":"page.click","params":{"page":1,"nodeIndex":17,"nodeGeneration":1}}
```

`page.drag` accepts viewport CSS-pixel coordinates and requires the page to be attached to a visible WebKit surface:

```json
{"id":"6","method":"page.drag","params":{"page":1,"startX":220,"startY":340,"endX":780,"endY":510}}
```

`browserctl` mirrors these methods as subcommands (`browserctl --socket <path> page-query 1 a`, …) plus socket-free local commands: `inspect`, `render`, `eval`, `shell`, `capture`, `bench-info`.

## Honest limitations

- `page.workers` is a real method, but the runtime currently reports an empty worker list; workers are not implemented.
- `page.frame` exposes the primary frame only; cross-origin frames are not yet addressable.
- Evaluation shares the page's global lexical environment across `page.evaluate` calls (standard script semantics), and pending promise callbacks run before the result is returned.
- The protocol is intentionally local and deterministic. It contains no model provider, chatbot, cloud dependency, prompt format, or autonomous decision layer. External agents decide what to do; the browser engine exposes reliable primitives for doing it.

## Engine-native address/search and find-in-page (Agent 3 additions)

`page.navigateInput` takes `page` and `input`, optionally `providerURL` (HTTP(S) endpoint) and `queryParameter` (default `q`). It resolves explicit HTTP(S) URLs, bare domains and loopback addresses; other input becomes URL-component-encoded search terms. Unsupported URL schemes and embedded URL credentials fail. The method navigates the existing `PageID`, not a copy, and returns `{"kind":"url"|"search","url":"...","page":{...}}`. The provider is per-call, or the context's stored default when `providerURL` is omitted (see below); per-call endpoints are validated before use.

`page.find` takes `page`, `query`, optional `caseSensitive` (default false), and optional `limit` (1–1000; default 100). It searches visible text nodes in the live DOM snapshot, skips head/script/style/template/noscript and hidden ancestors, and returns a `mutationVersion` plus ordered `matches` with generational node identity, character offset/length, matched text, and available bounds. Offsets count Swift `Character` values, not UTF-16 code units. Search is a bounded snapshot operation, not a browser selection/highlight API; verify the mutation version before acting on stale matches. `browserctl --socket ... page-navigate-input` and `page-find` forward to these existing dispatcher methods.

**Authorization dependency:** the base protocol has no authenticated multi-principal socket; Agent 1's capability guard must authorize these new `page.*` methods against the owning context on integration. Do not expose them through a privileged socket without that guard. The `page.find` result does not grant access to a different page or profile.

## Engine-native bookmarks, suggestions, search provider (Agent 3 additions)

`context.bookmarkAdd` takes `context`, an HTTP(S) `url`, and an optional `title`; re-adding a URL updates its title and keeps the original creation time. `context.bookmarks` lists bookmarks oldest-first. `context.bookmarkRemove` takes `context` and `url`, and returns `{"removed": true|false}`. Only HTTP(S) URLs with a host are stored; other schemes fail. Bookmarks live in the context record and are written to the profile's `bookmarks` table (schema v3) on `context.checkpoint`, then restored by `context.openProfile`. There is no cross-context access: every method is scoped to one `ContextID`.

`context.suggest` takes `context`, a non-empty `prefix`, and an optional `limit` (1–50; default 8). It returns ordered `{"kind","url","title?"}` matches: context bookmarks whose URL or title contains the prefix (case-insensitive) first, then the context's own page histories most-recently-active first, de-duplicated by URL. Bookmark titles are returned; history entries carry no title. Suggestions never cross into another context's bookmarks, history, or profile.

`context.searchProvider` returns the context's stored `{"endpoint","queryParameter"}`, or the built-in Google default when none is stored. `context.setSearchProvider` takes `context`, an HTTP(S) `endpoint` without credentials, and an optional `queryParameter` (default `q`); endpoints that cannot build a search URL fail. The preference is stored immediately in the profile kv store, so it requires an opened profile; without one the default applies. `page.navigateInput` without `providerURL` resolves the owning context's stored provider through the live page record.

`browserctl --socket ... context-bookmark-add <context> <url> [title]`, `context-bookmarks`, `context-bookmark-remove`, `context-suggest`, `context-search-provider`, and `context-set-search-provider` forward to these dispatcher methods.

## Agent-readable credential vault

`credentials.save` takes `context`, `origin`, `username`, `password`, and an optional `label`. It is the explicit-save path (human confirmation dialog or an authorized agent call — never silent harvesting) and upserts on `(origin, username)`: same credential id, new secret, refreshed `updatedAt`. Origins are normalized to `scheme://host[:port]`; `https` anywhere, `http` only for loopback (`localhost`, `127.0.0.1`, `::1`) — remote `http` is refused. Metadata (`id`, `profile`, `origin`, `username`, `label`, `createdAt`, `updatedAt`) lives in the profile's `credentials` table (schema v4); the secret lives only in the macOS Keychain (`fun.aether.secure-storage`, `WhenUnlockedThisDeviceOnly`, account `<profileUUID>:credential:<id>`) and never in SQLite, snapshots, logs, or events. `credentials.list` returns metadata only. `credentials.get` is the single operation that returns a password, for one credential id owned by the caller's context profile. `credentials.delete` removes metadata and secret. `credentials.fill` takes `page` and `credential`, refuses origin mismatches, and fills the page's generic login form through its own `__aetherCredentialForms.fill` primitive. Every method is scoped to one `ContextID`: a credential saved under profile A is invisible to profile B.

The native save-password confirmation, autofill choices, and Passwords settings use this same profile vault. Existing credentials from the earlier Internet Password Keychain format migrate on first vault access; their old Keychain item is deleted only after the replacement metadata and generic-password secret have been stored. The native UI follows the same loopback-only `http` rule as the agent API.

`browserctl --socket ... credentials-list <context> [origin]`, `credentials-get <context> <id>`, `credentials-save <context> <origin> <username> <password> [label]`, `credentials-delete <context> <id>`, and `credentials-fill <page> <id>` forward to these dispatcher methods.

**Authorization dependency:** same as above — these `context.*` methods need Agent 1's capability check against the owning context on integration. `context.setSearchProvider` accepts an arbitrary endpoint but only builds a search URL from it; it performs no fetch and grants no network authority beyond the existing navigation path.

## Local agent execution: `agent.exec` (Agent 1 addition)

`agent.exec` runs a whole multi-step program beside the browser runtime in a
single RPC instead of one round trip per operation. It takes `program` (an
`ExecProgram` object) and an optional overriding `timeoutMs`, and returns an
`ExecOutcome`. `browserctl --socket <path> exec <program.json>
[--timeout-ms N]` forwards to it.

A program declares `version` (currently 1), an optional attributing
`session` id (verified to exist, not created), an optional `timeoutMs`, an
`onError` policy (`stop` or `proceed`), and an ordered `steps` list (1–1000
declared, 100k executed, `forEach` over at most 10k items — over-limit is an
error, never silent truncation). Step ops: `createContext`, `createPage`,
`navigate`, `loadHTML`, `query`, `queryAll`, `click`, `type`, `evaluate`,
`snapshot`, `inspect`, `wait`, `verify`, `call`, `restore`, `set`, `assert`,
`forEach`, `if`, `result`. `restore` activates a hibernated page (`page.restore`
in step form) —
every page returned by a branch fork starts hibernated and
`BrowserBranchInfo.restoreRequiredPages` names them, so a program can activate
the branch page it is about to drive without a second RPC.
Variables are bound with `into` and referenced as `{"ref":
"var.path[0].field"}`; any other JSON is a literal, and `{"literal": ...}`
escapes a literal object that would otherwise look like a reference.
Conditions (`assert`, `if`) support `eq`, `ne`, `exists`, `notExists`,
`empty`, `contains`, `gt`, `lt`.

`verify` runs a `BrowserVerificationPlan` against real state without leaving
the program (directive §8.1). The plan's `page` may be a reference
(`{"ref": "pg.id"}`), as may the nested `checks`, and the bound value is the
three-valued verification result. The plan's page is gated to the program's
lease exactly like a page step.

`call` invokes any other AgentProtocol method from inside the program through
the same dispatcher, so Tier 2 capabilities that are not first-class steps
(fill, select, submit, find, scroll, history, cookies, storage, permissions,
downloads, captures, `events.recent`, and so on) are still program-callable
(§4.2.2). `method` is the exact method name; `params` is the params object and
may carry `{"ref": "..."}` markers anywhere. The call is refused with
`unauthorized` for `agent.exec`, `task.verify` (use the `verify` step), lease,
session and fleet lifecycle methods, the handoff and approval gates,
`context.create`/`context.destroy`, and `credentials.get` — and any
context/page it names is gated against the program's lease before dispatch.
Capabilities with no program-callable equivalent are a defect, not a
limitation (§4.2.2, §13.2).

The outcome carries a per-run `executionID` (UUID; join key for handoff
records and the event stream), a `status` (`completed`, `failed`, `timeout`,
`cancelled`), ordered `results`, final `vars`, `stepsExecuted` and
`operations` counters (operations count browser-touching steps only, as
batching proof), `counters` (a typed `ExecCounters`: `boundaryCalls` — always
1 per program, the batching proof — plus `snapshots`, `waits`, `images`,
`verificationChecks`, `runtimeCalls`, `coordinateActions`), `truncated` and
`truncationReason` naming any applied cap, per-step `failures`, and a terminal
`error` with the failing step path. Program deadlines (default 30s, max 300s)
and task cancellation produce `timeout`/`cancelled` with partial state
preserved.

Limits are enforced by the host, not the program, and are reported rather than
silently softened (§5.3): a program's encoded size is capped at 64 KiB
(`ExecLimits.maxProgramBytes`), driver-visible `results` at 12 MiB
(`maxOutputBytes`, over-limit sets `truncated`), and a session's retained
variable set at 4 MiB (`maxSessionBytes`).

Authorization: host connections run unrestricted; non-host principals are
confined to contexts they own (resolved dynamically per page op, including
through variables), and `createContext` is refused under confinement —
pre-create via `context.create` first. Every page op additionally honors the
handoff gate: pages parked for human control fail steps with `handoff_active`.
Unknown program versions and unknown ops fail closed (`badParameter`).

Lease binding: a program confined to leased contexts is registered against
those workspaces. When the authorizing lease is released, cancelled, or
expires, the runtime revokes the program at the next step boundary; it ends as
`cancelled` with `error.code == "leaseRevoked"` (never swallowed by
`onError: proceed`), so an agent that loses its workspace cannot keep driving
the browser. Unrestricted host executions are never revoked.

Persistent sessions: a program naming a `session` loads that session's retained
variable set and commits its final variables back on completion, so state
written by one program is visible to the next program in the same session
(§5.1). Session state is bounded (§5.1.3), destroyed in constant time on lease
release/cancel/expiry and on `destroy` (§5.1.4), and one session runs one
program at a time — a concurrent program is refused with `sessionBusy`
(§5.3.7). A failed, timed-out, cancelled, or revoked program leaves the
session's previous state intact: partial work never becomes the session's
truth. After a daemon restart the session is rebuilt empty; no live heap is
restored (§5.1.5).

## Human-parity capabilities (code-first additions)

Every method below is reachable program-side through the `call` step and
through native, CLI, and MCP, and every one is a real platform call rather
than a simulated one:

- `page.stopLoading {page}` — aborts the in-flight navigation.
- `page.zoom {page}` — the current page zoom factor (1.0 = 100%).
- `page.setZoom {page, factor}` — sets zoom, clamped to 0.25–5 like the human
  control; the applied factor is returned.
- `page.print {page, path}` — writes a real PDF artifact and returns its byte
  size. Success is the file on disk, never the gesture.
- `page.clipboardRead` / `page.clipboardWrite {text}` — the system clipboard.
  Explicit calls only; nothing reads or writes it automatically.
- `extension.list {page}` — the extensions loaded on the page's profile
  controller (`identifier`, `name`, `loaded`, `inspectable`). An empty list is
  a truthful "none installed".

Typed limitations, reported rather than silently ignored (`code:
"unsupported"`): `page.uploadFile {page, path}` — WebKit exposes no public API
to populate a file input outside the user-picked panel; `extension.setEnabled`
and `page.moveTab` — not yet implemented. Typed-refusal semantics follow §6.7
and §12.1.14: an unsupported capability is visible in the API, not hidden.

Structured state reads are bounded and diffable: `page.snapshot {page, limit,
[since]}` returns `truncated`/`omittedNodes` when a cap applied, and an
`unchanged: true` snapshot with no nodes when `since` still matches the
current `mutationVersion`. The in-page extractor is installed once per
document as a document-start user script in the isolated client world, so a
same-document read sends only a generation activation, not the extractor
(directive §4.1, §10.3.3).
