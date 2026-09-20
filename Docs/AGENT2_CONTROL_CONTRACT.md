# Agent 2 live co-control — engine contract (Steps 4–5, incremental)

## Implemented path

`BrowserRuntime` is still the only owner of contexts, pages, and sessions. The
surface patch from PR #7 is unchanged: `attachSurface` returns a local embedding
handle, `requestFrame`/`frame` share one `RetainedRaster` per `PageRecord`, and
reads (`query`, `snapshot`, `frame`, `render`, `inspect`) never require a lease.

### Input lease (one driver at a time)

`acquireInput` / `releaseInput` / `takeoverInput` / `handoffInput` manage a single
optional `inputHolder` per page. Empty means open control, so every existing
caller without contention behaves exactly as before. Once held, `click`, `type`,
`setValue`, `fill`, `selectOption`, `pressKey`, `focus`, `blur`, `scrollTo`,
`scrollIntoView`, `clickSurface`, and all navigation through `performNavigation`
admit only the holder. Everyone else, including unattributed callers, receives
`PageControlError.inputHeld(holder)` and a `denied` event naming the holder.
`takeoverInput` transfers unconditionally and records the previous holder.
`handoffInput` transfers atomically only from the expected holder.

### Pause, abort, resume

`pausePage` blocks the same gated set with `PageControlError.paused`, including
script-initiated navigations and restores that arrive while paused; those surface
as script errors or thrown errors, not silent skips. `abortPage` clears the lease
and pauses in one step. `resumePage` admits only the pauser. Lease management
itself stays available while paused so a contender can take over a stuck page.

### Approval for consequential navigation

`requireNavigationApproval` arms one-shot approval per page. While armed, every
`performNavigation` caller (`navigate`, `goBack`, `goForward`, `reload`,
anchor/form/Enter submissions, script navigations) needs `approveNavigation`
first; otherwise it fails with `PageControlError.approvalRequired("navigate")`
before any transport. Each grant admits exactly one navigation and is consumed
at admission, success or transport failure alike. `clearNavigationApproval`
disarms. `loadHTML` stays ungated: it is the explicit content-setup path used by
tests, fixtures, and capture, not a lateral navigation.

### Ordered event stream

Every page carries a bounded (512) `controlLog` with a monotonic
`controlSequence`. `controlEvents(pageID:after:)` returns the log or its tail.
Outcomes are `admitted`, `denied`, or `success`; control-plane transitions log
`success`. Denials carry `error` values `input-held`, `paused`, or
`approval-required`. Input events on `input[type=password]` record detail
`redacted` and never the entered text. `ControlActor` labels are
caller-supplied; they are audit strings, not authentication (see below).

## Authority and integration

These are trusted in-process APIs, like the rest of `BrowserRuntime`. Nothing
here is exposed on the socket: the dispatcher has no new method, and no
capability bypass, owner string, media path, or network path was added. Socket
exposure must follow the Agent 1 contract: new `page.*` methods carry a
validated `page` parameter plus `params.capability`, and surface/control
operations inherit the owning context's authority. Never hand a child renderer a
bearer token or host file handle.

Agent 3 coordination: `controlEvents` is the audit source for agent-action
history and capture completeness notes. Do not remove the deny-by-default
dispatcher guards to make old fixtures pass; co-control defaults (open lease,
unpaused, unarmed approval) apply at the runtime layer only.

### Hit-tested input repair

`HitTesting.node(at:in:)` iterated `LayoutTree.paintOrder.reversed()`. The
layout engine appends boxes post-order (deepest descendants first, root last),
so the reversed walk returned the outermost containing ancestor for almost any
in-content point, and `nodeAtPoint`/`nodeAtSurfacePoint`/`clickSurface` could
not reach nested controls. The walk now goes deepest-first, which matches the
array's construction order. `DisplayListBuilder` never consumed `paintOrder`
(it sorts document order plus z-index), so painting is unaffected. z-index
out-of-DOM-order hit resolution remains future work.

Shared-file note: this patch touches `BrowserRuntime.swift` in regions disjoint
from Agent 1's `configureRuntime`/cookie hunks. Merging must keep both. No
branches are merged by this work.

## Not completed

No native window is attached; attachment tests exercise the engine handle only.
There is no dispatcher/CLI exposure, no Metal text/glyph/image parity (rects
only, software path still renders), no media playback, and no content blocker.
`RetainedCompositor`, `PaintChunkIndex`, `TileCache`, and `GlyphAtlas` remain
outside the live raster path, and damage stays full-viewport conservative. Steps
4–5 and the engine-only exit gate remain incomplete.
