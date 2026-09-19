# Agent Protocol

Agents are first-class clients of the engine. Structured state is the default control surface; screenshots and raw coordinate interaction are fallbacks for genuinely visual tasks.

`AgentMessage.swift` is authoritative for the method set. This document describes the wire contract and every method as of the current tree (76 methods).

`browserd` accepts newline-delimited JSON over a local Unix-domain socket (default `/tmp/native-browser-engine.sock`). Every request contains an `id`, `method`, and optional `params`. Every response repeats the request `id` and contains either `result` or a structured `error`:

```json
{"id": "1", "result": {"ok": true}}
{"id": "2", "error": {"code": "engine_error", "message": "Page is not loaded: 1"}}
```

A missing result is a JSON `null`, not an absent key: `{"id": "3", "result": null}`. The response encoder always emits a present `result` key when the outcome is a result, so clients can distinguish "no match" from "no answer". Error codes are stable strings (`method_not_found`, `bad_parameter`, `engine_error`, …).

## Methods (76)

### Session and transport

```text
ping
```

### Contexts (3)

```text
context.create    context.destroy    context.list
```

### Page lifecycle and navigation (8)

```text
page.create       page.navigate      page.back         page.forward
page.reload       page.resize        page.close        page.list
```

### Inspection and observation (6)

```text
page.inspect      page.query         page.queryAll
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
