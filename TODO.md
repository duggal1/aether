# TODO.md — Aether: the five milestones

This is the work plan. `AGENTS.md` is the code snapshot; `RULES.md` is the process; `DESIGN.md` owns UI decisions. Every item below is stated as a **demonstrable capability with evidence**, not a feature count.

Ordering matters: **1 → 2 → 3 → 4 → 5**. Milestone 2 ("have everything") is the spine — without it, milestones 3–5 have nothing real to stand on.

Status legend: `[ ]` not started · `[~]` partial · `[!]` blocked. Update this file as items move.

---

## M0. Unblock verification first (do this today)

Do not start milestones 1–5 while the tree cannot be built and tested.

- [ ] Install full Xcode and `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`. Reason: with Command Line Tools only, `swift test` fails with `plugin for module 'TestingMacros' not found`; the tests are fine, the host is not.
- [x] Fix `Sources/JavaScript/JSTextCodec.swift:42` — `writeTypedElement` called without `try` (compile error).
- [x] Fix `Sources/EngineCore/Geometry.swift` — add `Point.zero` (`SoftwareRenderer` did not conform to `OffscreenRendering`).
- [ ] Run `swift build -c release` to a green build, then `nice -n 10 swift test --no-parallel --jobs 1`. Record the result here. Never run build and test concurrently on this 8 GiB host.
- [ ] Refresh `Docs/VALIDATION.md` with real numbers from this host. It currently claims `27 tests passed` and a green release build that do not match the tree.
- [ ] Rewrite `Docs/AGENT_PROTOCOL.md`: it documents ~25 methods; `AgentMessages.swift` has 76.

---

## M1. Front end — the human browser (`[ ]` not started)

There is currently **zero** UI code in this package. This milestone builds the entire human-facing shell as a new app target. Nothing here may weaken the engine, and nothing here may create a second navigation path.

**Rule: `DESIGN.md` is the source of truth for every pixel. Read it fully before writing a view. Then `ENHANCE-DESIGN.md`, only after the UI actually works.**

- [ ] New macOS app target (`AetherApp`) using SwiftUI for views + AppKit where macOS windows/text editing demand it. Add to `Package.swift`; keep it a client of `NativeBrowserEngine`, never a fork of it.
- [ ] Window + chrome skeleton: window group, native titlebar, tabs, address/search field, back/forward/reload, new tab, keyboard shortcuts, menus.
- [ ] Tab model bound to `BrowserRuntime` pages: one authoritative tab list, stable IDs, no duplicate tab state. An agent-created page must appear as a coherent tab with no special-casing.
- [ ] Web surface: render the engine's `DisplayList`/`PixelBuffer` through `MetalRenderer` into a `CAMetalLayer`; wire input → `HitTesting` → runtime (`click`, `type`, `pressKey`, `scrollTo`, `focus`).
- [ ] Profiles UI: personal / work / agent profiles with isolated cookies, storage, history, site data (`context.*` + `ProfileStore`).
- [ ] Human essentials: address-bar navigation, history, bookmarks, downloads UI, media playback, find-in-page, and an explicit zoom policy per `DESIGN.md`.
- [ ] Design system implementation: exactly the `DESIGN.md` tokens (stone palette, System/Light/Dark, Instrument Sans 400/500 with verified PostScript names), restrained motion, no glass everywhere.
- [ ] Agent-visible state in the UI: execution status, ownership of sessions/tabs, and the agent-vs-human origin of an action — without a chatbot sidebar.
- [ ] Accessibility + performance pass: VoiceOver, focus rings, Reduce Motion/Transparency, no main-thread engine work, profile with Instruments.

**Exit criteria:** a human can browse real sites with no visible automation residue; an agent-opened tab is indistinguishable in state coherence from a human-opened tab; no engine module was modified to make a visual detail work.

---

## M2. Back end — "have everything" (`[~]` partially exists)

The engine exists end to end, but "everything" means: correct, complete, debuggable, and honest about its limits. Each sub-item is a real gap in the current tree, not a wish.

- [ ] **HTML to WHATWG parity:** full insertion modes, foster-parenting edge cases, templates, foreign content, encoding detection, adversarial parser fixtures.
- [ ] **CSS depth:** pseudo-classes/elements, specificity edge cases, cascade layers, custom properties, container queries, modern color/value syntax.
- [ ] **Layout correctness:** complete flex/grid algorithms, tables, replaced elements, floats, fragmentation, sticky positioning, real overflow/scroll containers.
- [ ] **JavaScript toward real ECMAScript:** fix the ~55 existing JavaScript-module warnings; proper GC/runtime semantics; broaden syntax coverage; deepen promises/microtasks, modules, typed arrays, streams; shrink the unsupported surface with tests that prove it.
- [ ] **Incremental pipeline:** replace broad recomputation with dependency-driven style invalidation, subtree layout invalidation, display-list damage, retained tiles, and compositor-only updates. The hooks already exist (`PipelineInvalidation`, `PaintChunks`, `DamageCulling`, `RetainedCompositor`) — wire them.
- [ ] **Security boundary:** renderer-process isolation and a real macOS sandbox before any hostile-content claim. Harden redirects, cookies, origin policy, CORS, CSP, permissions, storage partitioning, focus/selection, files, downloads, and form edge cases.
- [ ] **Crash + resource recovery:** restart/recover a page or worker safely; bounded renderer pools; page freeze/discard/restore under real memory pressure (the policy exists in `FleetScheduler`; prove it under load).
- [ ] **Debugging surface, native:** structured console errors, JS exceptions, navigation failures, DOM mutation streams, network diagnostics, layout info, and evidence export.
- [ ] **Full test program:** every gap above gets a test; add adversarial fixtures, fuzz parser/runtime boundaries, and convert every fixed bug into a regression test. Keep Swift Testing as the convention.
- [ ] **Truthful docs:** keep `Docs/ARCHITECTURE.md`, `IMPLEMENTATION_STATUS.md`, and `README.md` matching reality. Never claim compatibility without a test.

**Exit criteria:** `swift test` covers every milestone-2 claim and passes on an Xcode host; every "not implemented" row in `Docs/IMPLEMENTATION_STATUS.md` is either implemented with tests or still explicitly listed as not implemented.

---

## M3. Advanced agent-native capability (`[~]` partially exists)

The agent interface is already real: 76 `AgentMethod`s, a Unix-socket daemon, `browserctl`, lifecycle/fleet management, and design capture. This milestone makes it deep, complete, and pleasant for Codex / Claude Code / OpenCode.

- [ ] **MCP adapter** backed by the same internal commands — no second command path, no duplicated logic. The protocol stays deterministic and free of model inference.
- [ ] **Session ownership hardening:** explicit owner for every session/context/page; concurrent agents never steal each other's tabs; cancellation and timeouts on every operation; stable session IDs.
- [ ] **True headless fleet:** many silent sessions with no Dock/window proliferation, each actually rendering and running scripts, bounded by memory pressure and real concurrency. Configurable per-worker tab budget (start at ~20, measure).
- [ ] **Interaction completeness:** drag, upload, download, keyboard sequences/modifiers, hover chains, file pickers, multi-select, iframe targeting, scrolling inside nested scroll containers, and condition-based waits instead of sleeps.
- [ ] **Design extraction (already first-class) — finish it:** lazy-load coverage, sticky/fixed overlay de-duplication, cross-origin and canvas limitations reported as explicit warnings, `manifest.json` linking every screenshot to its page section, responsive viewport sets, and honest CSS-fidelity labeling.
- [ ] **Developer inspection:** reproduce a production failure through an agent and get back failing operation + observed error + reproduction steps + supporting artifacts (console, network, DOM mutations, screenshot).
- [ ] **Universal application automation:** prove Gmail/Slack/YouTube/Sheets/internal dashboards work through the same primitives. No hardcoded per-site support, ever.
- [ ] **Permissions + approval:** consequential actions can require approval; credentials stay protected; complete execution control without unrestricted credential access.
- [ ] **Agent ergonomics:** structured, stable error codes; explicit timeouts/cancellation; deterministic results; a machine-readable capability listing so an agent can discover what exists instead of guessing.

**Exit criteria:** a terminal agent completes a substantial real web task using only `browserctl`/MCP, with no screenshots required for the deterministic parts, and receives structured artifacts.

---

## M4. Performance + polish (`[~]` foundations exist)

Performance is correctness. Claims require measurement — `enginebench`, `EngineMetrics`, `FrameRecorder`, and Instruments, never language choice or GPU marketing.

- [ ] Baseline every milestone-2/3 path with `enginebench` and record before/after numbers in `Docs/PERFORMANCE.md`. Keep the host caveat: numbers are a regression baseline, not a cross-machine claim.
- [ ] Enforce the optimization order: avoid work → reuse work → invalidate narrowly → parallelize independent work → move real raster/compositing to the GPU.
- [ ] Startup and interaction latency: minimize startup, first paint, navigation latency, input-to-paint, and background activity. Set explicit budgets rather than aspirations.
- [ ] Memory: decoded-image eviction, texture residency, frozen-page release, glyph-atlas bounds, and fleet memory accounting (`ResourceBudget`/`ResourceLedger` exist — make them gate behavior).
- [ ] Metal renderer to production quality: GPU tiles, image textures, glyph-atlas uploads, clip/transform stacks, async upload, damage-driven compositing, and `CAMetalLayer` presentation of the engine's display list.
- [ ] Cleaner UI without new dependencies: fewer permanent elements, sharper typography, immediate transitions. Every permanent component must earn its space.
- [ ] Release gates: memory, p95 interaction latency, navigation latency, frame cost, unnecessary layout work, texture residency, background-page cost.
- [ ] Pin the benchmark harness into CI so regressions are caught automatically instead of argued about.

**Exit criteria:** measured improvements with preserved fixtures, no `enginebench` regression, and release gates defined and enforced.

---

## M5. Aggressive ultra testing — agents drive the real browser (`[ ]` not started)

The final proof is not unit tests. It is external coding agents (Claude Code, Codex, OpenCode) using Aether to do real work on the real web while humans keep browsing in the same app.

- [ ] Harness: a scripted runner that starts `browserd`, drives real flows through `browserctl`/MCP, and captures evidence (structured results, artifacts, timings, failures) per run.
- [ ] Task corpus over real applications: authenticated sessions, dynamic SPAs, very long pages, heavy forms, uploads/downloads, video pages, ad-heavy sites, internal dashboards.
- [ ] Concurrency corpus: many parallel agents, tab-ownership conflicts, cancellation mid-flight, one agent crashing while others continue.
- [ ] Recovery corpus: renderer crash, navigation failure, network drop, timeout, memory pressure, and frozen/discarded page restore in the middle of a task.
- [ ] Sustained soak: hours of continuous browsing + agent execution under a constrained memory budget (this host: 8 GiB) with RSS/CPU/swap watchdogs, reusing the method in `agents/codex/test-freeze/`.
- [ ] Honest failure reporting: every failure becomes a filed defect with reproduction steps and evidence — never a "close enough" pass.
- [ ] Human-in-the-loop validation: while agents hammer the browser, a human browses normally; the UI must stay responsive and uncluttered.
- [ ] Publish a repeatable scoreboard: tasks attempted / completed / failed with evidence links, so progress is measurable run over run.

**Exit criteria (the product's own definition of done):** a developer can hand a terminal agent a substantial web task, the agent executes it through Aether, the developer inspects the evidence, and receives the completed artifacts — while the human browser remains responsive and uncluttered.

---

## How to extend this file

- Add work under the milestone it belongs to. Do not create a sixth milestone without a genuinely distinct objective.
- Every item must be a capability with a test or measurement behind it. If it cannot be verified, it is not an item yet.
- Move completed items to `## Done` with the evidence (test name, benchmark number, file). Do not delete history.
- Keep the ordering: verification environment → back-end truth → agent depth → performance → real-agent ultra testing.

## Done

- [x] Two blocking compile errors fixed: `JSTextCodec.swift` missing `try`, `Geometry.swift` missing `Point.zero`. Neither was verified with a full build (the run was stopped on purpose), so M0's green-build item is still open.