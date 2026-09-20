# Agent 2 shared page surface — partial Steps 4–5

## Implemented path

`NativeBrowserEngine.runtime` → `BrowserRuntime.attachSurface(PageID)` returns a local attachment handle to that existing page. It creates no document, JS interpreter, context, or navigation. One attachment per page is allowed; detach invalidates the handle. Close removes the page and invalidates all its handles. Discard releases retained pixels; requesting a frame on an unloaded page fails rather than returning stale pixels.

`requestFrame(surface, after:)` and `frame(pageID, after:)` rasterize the same live display list at the current page scroll. `resizeSurface` calls the existing resize operation. `nodeAtSurfacePoint` calls the existing scroll-aware hit test. `clickSurface` dispatches that node through the existing click/event/navigation path. A detached handle cannot perform these operations.

Existing `render(pageID, origin:)`, including the capture adapter caller, shares the same `RetainedRaster` on `PageRecord`. Its default origin remains zero for compatibility; current-scroll screenshots should use `frame(pageID).pixels` or explicitly supply the scroll origin. A capture request at a different origin can advance the raster revision, even if DOM state is unchanged.

Unchanged display list, viewport and origin reuse retained pixels. Changes conservatively invalidate the whole viewport. Each consumer passes its last frame revision; a new consumer omits it and receives full damage even when another consumer already rendered the frame. `mutationVersion` independently exposes live DOM revision. This is pull-based observation, not an event subscription stream.

The raster budget is checked before pixel allocation (128,000,000 bytes by default). `ResourceLedger`, fleet memory estimates, and returned `FrameReport` account for retained pixel bytes. Reports measure frame-request/raster time; they do not claim to include earlier navigation or layout time. `FrameRecorder` retains bounded reports. `FramePipelineState` marks refresh and scroll invalidation and clears pending work after raster succeeds. Scrolling does not invoke layout. DOM refresh remains conservative full style/layout/display rebuild.

The budget bounds retained engine pixel storage, not pixels retained by callers, display lists, allocator transients, or total process RSS. One prior pixel buffer may coexist with a replacement while the actor commits its value state.

## Authority and integration

These are trusted in-process embedding APIs, just like the existing runtime API. A `PageSurface` is an opaque attachment-lifetime handle, NOT an authenticated principal or a grant to a profile. No socket method, capability bypass, self-declared owner, or media network path is added. Do not expose this API to an untrusted client without Agent 1's page/context authorization. Agent 1's current context bearer token does not establish distinct human/agent identities; authenticated co-control remains open.

Shared runtime changes are deliberately limited to PageRecord fields, surface/frame methods, render, discard cleanup, scroll/refresh invalidation and fleet byte estimates. Agents 1 and 3 retain ownership of authorization, networking, dispatcher/CLI and profile changes. Integrate their patches deliberately; no branches are merged by this work.

## Not completed

No native window is attached or tested. Attachment tests exercise the presentation-neutral engine handle, not visible-mode UI. There is no input lease, human takeover, pause/abort, consequential-action approval, secret-entry boundary, ordered actor event stream, or authenticated three-contender test.

RetainedCompositor, PaintChunkIndex, TileCache and GlyphAtlas remain outside the live raster path. Metal remains its previous rectangles-only implementation. Text/images continue through the existing software renderer. No partial repaint, transform expansion, asynchronous GPU ownership or media texture path is claimed.

Step 5 remains unsupported: no integrated HTMLMediaElement/AVFoundation playback, HLS segment authorization, MSE, DRM, codec qualification, content blocker, filter-list updates, cosmetic rules or YouTube playback/blocking evidence. Do not introduce AVPlayer URL loading that bypasses the context network policy to close this gap superficially. Agent 1's actual renderer/process and principal boundaries remain open; these APIs cannot make arbitrary hostile sites safe.

Steps 4–5 and the engine-only exit gate remain incomplete.
