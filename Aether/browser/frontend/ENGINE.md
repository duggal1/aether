# Aether — Human Browser Engine Audit

**Task: verify Phase 2A before building the Phase 2B SwiftUI browser.** This is an audit of the *live engine*, not a feature proposal or an excuse to rebuild existing work. Do not implement missing systems during this pass unless explicitly directed.

## Read and trace the actual code

Start with `RULES.md`, `AGENTS.md`, `Package.swift`, `Docs/IMPLEMENTATION_STATUS.md`, `Docs/ARCHITECTURE.md`, `Docs/VALIDATION.md`, and `DESIGN.md`. Treat documentation as a claim to check, **not evidence of working functionality**. Follow calls through `BrowserEngine → BrowserRuntime → Navigation/JavaScript/Style/Layout/Graphics/Networking/Persistence`, including tests and root-package target membership. Code in `Sources/EngineAdditions` or another nested package does not count as integrated unless it executes through the root runtime. Do not confuse an agent command, stub, mock, or headless fixture with a functioning human-browser capability.

## Initial audit leads from the current repository

The repository's implementation-status document reports basic navigation, HTTP, DOM/CSS/layout, JavaScript, offscreen rendering, persistent contexts, history, downloads, agent operations, and native capture as **wired but incomplete**. It reports the live renderer as **software**, with **Metal foundation only**, and media, WebRTC/DRM, canvas/WebAssembly/workers, service workers, process isolation, and production sandboxing as unsupported. `AGENTS.md` says there is **no SwiftUI/AppKit human shell yet**. Its documented 177 passing tests and local-fixture smoke test **do not establish modern-website compatibility**. Independently re-check every statement against the latest code and live tests.

## Verify every human-engine requirement

Mark each item **WORKING / PARTIAL / SOURCE-ONLY / MISSING / UNVERIFIED**. For every row, provide file paths + symbols, a real test or reproduction, the observed result, and the exact missing work.

| System | Required proof |
| --- | --- |
| Rendering/performance | Actual GPU-backed macOS window/compositor, smooth scroll/input/tab switching, correct repaint/invalidation, bounded RAM/CPU, measured frame times. A Metal class existing is insufficient. |
| Web compatibility | Real HTML/CSS/JS websites, dynamic apps, forms, redirects, cookies, fetch, fonts, responsive layouts, media queries, selection and keyboard interaction. Document unsupported APIs. |
| Video/audio | Real playback, fullscreen, seek, controls, hardware decoding where available; test 1080p/4K/8K on supported hardware and report dropped frames. Never claim universal 8K. |
| Navigation/search | Back/forward/reload/stop; URL-or-search omnibox with Google default and configurable search providers; errors/TLS handling. |
| Tabs/windows | Create/close/reopen/pin/suspend/restore, multiwindow ownership, session persistence; top-tabs and sidebar layouts must share runtime state without reloading pages. |
| Profiles/accounts | Independent persistent cookies/cache/local storage/history/permissions per profile; fast switching; multiple Google accounts within one profile; no credential leakage between profiles or agents. |
| Passwords/passkeys | Actual Apple Keychain/Password AutoFill integration, save/update/autofill, WebAuthn/passkeys and Touch ID through supported Apple APIs; account/permission boundaries. Do not mistake a custom Keychain record for iCloud Passwords integration. |
| Everyday browser | Bookmarks, searchable history, downloads with progress/cancel/reveal, file upload, clipboard, permissions, PDF viewing/export/printing, restore after crashes. |
| Developer inspector | Live element selection/highlighting, DOM tree, relevant/full CSS, computed styles, assets/SVG, console/network errors, copy HTML/CSS, export AI design kit. Backend capture alone is not a human inspector. |
| Reader/Markdown | Readable article/document extraction with links/code/tables, copy/export Markdown; original document unchanged. |
| Blocking/privacy | Engine-native ads/trackers/cookie-banner handling, per-site exceptions, no extension requirement, measured site breakage; YouTube blocking verified, not promised. |
| Accessibility/security | Keyboard/IME, accessibility tree, focus/selection, permission prompts, origin boundaries, hostile-site process isolation/sandbox, crash recovery. |

**UI-specific features** (settings sidebar, profile dropdown, dark/light appearance, new-tab shortcuts and the two tab layouts) belong to Phase 2B, but verify that the engine provides the models, persistence and events they require. `DESIGN.md` owns visual styling; Dia screenshots establish structure only.

## Run proof, not checkbox theater

1. Build the root package and all active subpackages on macOS; run the full existing suite and release build. Record exact commands, machine, commit, failures, and logs.
2. Create missing tests for each claimed backend capability. Exercise live engine paths, not isolated pure helpers alone.
3. Perform GUI and real-site end-to-end tests where a GUI exists. If there is no native window yet, mark GUI/GPU/video/autofill as **UNVERIFIED or MISSING**, never PASS. Use local fixtures plus representative JavaScript-heavy sites; don't infer compatibility from a static page.
4. Benchmark startup, navigation, p50/p95 input/frame latency, memory per tab, 5/20/50-tab behavior, background usage, and sustained playback. Compare on the same machine. Report failure modes and hardware limits.
5. Confirm each existing component is actually hooked to `BrowserRuntime`; identify duplicates, dead code, unintegrated targets, placeholder implementations, and security blockers.

## Required deliverable

Produce `Docs/HUMAN_BROWSER_ENGINE_AUDIT.md` with: (1) an evidence-backed capability matrix; (2) verified working parts; (3) partial/missing parts; (4) critical blockers **ordered by dependency**, not invented completion percentages; (5) specific files to extend; (6) reproducible tests and benchmark results; and (7) a **Phase 2A go/no-go** for starting the human SwiftUI shell. A green build alone is never a pass. Do not claim the browser is Chrome/Safari-class until modern websites, GPU presentation, video, authentication, and security have been demonstrated.
