# Agent Protocol

Agents are first-class clients of the engine. Structured state is the default control surface; screenshots and raw coordinate interaction are fallbacks for genuinely visual tasks.

`browserd` accepts newline-delimited JSON over a local Unix-domain socket. Every request contains an `id`, `method`, and optional `params`. Every response repeats the request `id` and contains either `result` or a structured error.

## Methods

```text
ping

context.create
context.destroy
context.list

page.create
page.navigate
page.back
page.forward
page.reload
page.resize
page.close
page.list

page.inspect
page.query
page.queryAll
page.snapshot
page.wait
page.mutations

page.click
page.type
page.setValue
page.evaluate
page.render
page.capture
page.metrics
```

## Node identity

DOM nodes use a pair of unsigned values:

```json
{"index": 42, "generation": 3}
```

The generation prevents stale references from silently becoming references to newly allocated nodes.

Interactive inspection exposes semantic role, accessible name, current value, href, enabled/editable/visible state, and layout bounds where available. Snapshot output additionally contains the structured document tree, attributes, text, parent/children relationships, and mutation version.

## Example

```json
{"id":"1","method":"context.create","params":{"name":"research"}}
{"id":"2","method":"page.create","params":{"context":1,"width":1280,"height":800}}
{"id":"3","method":"page.navigate","params":{"page":1,"url":"https://example.com"}}
{"id":"4","method":"page.query","params":{"page":1,"selector":"a"}}
{"id":"5","method":"page.click","params":{"page":1,"nodeIndex":17,"nodeGeneration":1}}
```

The protocol is intentionally local and deterministic. It contains no model provider, chatbot, cloud dependency, prompt format, or autonomous decision layer. External agents decide what to do; the browser engine exposes reliable primitives for doing it.
