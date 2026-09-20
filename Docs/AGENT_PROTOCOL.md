# Agent Protocol

Agents are first-class clients of the engine. Structured state is the default control surface; screenshots and raw coordinate interaction are fallbacks for genuinely visual tasks.

`Sources/AgentProtocol/AgentMessages.swift` is authoritative for the method set. This document describes the wire contract and every method as of the current tree (84 methods).

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
page.click        page.type          page.setValue     page.pressKey
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

**Authorization dependency:** same as above — these `context.*` methods need Agent 1's capability check against the owning context on integration. `context.setSearchProvider` accepts an arbitrary endpoint but only builds a search URL from it; it performs no fetch and grants no network authority beyond the existing navigation path.
