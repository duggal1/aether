# Agent 2 — Steps 4–5

Base: 01f9ec1. Branch: agent2/shared-page-surface-20260920.

First coherent integration: retain a bounded raster on each existing PageRecord, share it between render/capture and attachment frame requests, expose revision/damage/metrics, validate attachment lifetime, and prove attach/detach preserves DOM/JS/scroll. Keep attachment local to the trusted embedding API until Agent 1's authentication contract is integrated. No owner string is an identity.

Changes: Graphics retained raster; EngineRuntime page surface DTOs and actor entry points; focused AgentTests/RenderingTests; serial RSS-bounded suite and release build. Conservative full viewport damage on changed frames; unchanged frames avoid raster. Explicit origins remain supported for capture. Reclaim retained pixels on discard/close.

Remaining mission requirements are not completed by this slice: tiled/compositor/glyph integration, Metal parity, authenticated co-control and approvals, native media and all-network-path blocking. Implementing those safely requires the renderer/identity/network contracts on Agent 1's separate draft branch. Do not bypass that boundary or claim the engine-only gate passes.
