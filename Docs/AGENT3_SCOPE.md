# Agent 3: execution scope and dependent engine-only gate

Base: `main@01f9ec1d9df377cf8377852e1400782a4366b7a0`. Branch: `agent3/engine-services-gate-20260920`. Preserve the existing Step 1 evidence, the 177-test reported baseline, and later Agent 1/2 commits. Source and new regression tests are not macOS verification until CI finishes.

## Delivered on this branch

- Typed URL versus search-query resolution through `page.navigateInput` and `browserctl page-navigate-input`, using `BrowserRuntime.navigate`. The provider is per-request, or the context's stored default when omitted; custom defaults persist per profile (`context.setSearchProvider`/`context.searchProvider`, validated HTTP(S) endpoints without credentials).
- Explicit handling of unsupported URL schemes and forbidden URL userinfo, with regression tests.
- Live bounded `page.find` / `browserctl page-find` over visible DOM text nodes and snapshot mutation version; tests cover hidden nodes, case sensitivity, limits, and post-JS mutation. No fabricated selection or highlight support.
- Per-context bookmarks (`context.bookmarkAdd`/`context.bookmarks`/`context.bookmarkRemove`): HTTP(S)-only, same-context, durable in the profile `bookmarks` table (schema v3) via checkpoint/open round-trip, with regression tests.
- Navigation suggestions (`context.suggest`): bookmarks-first, then own-context page histories, de-duplicated, bounded; never crosses contexts.
- Profile robustness: a failed `openProfile` now closes the store instead of leaking it; a corrupt profile database fails closed while the context stays usable (regression test).
- Extended real-daemon verification of a JavaScript DOM/style change in viewport pixels and the capture PNG, plus a typed address going through the live page, plus bookmark/provider persistence across profile reopen.
- File-to-runtime integration map at `Docs/AGENT3_INTEGRATION_MAP.md`.
- Separate macOS Actions workflow running bounded Swift tests plus the real daemon/capture harness and uploading evidence.
- Corrected a wrong case-sensitive `page.find` test expectation (lone lowercase match counts 1, not 2).

Eight new dispatcher methods change the method count from the reported **76 to 84** on this branch (`page.navigateInput`, `page.find`, three bookmark methods, `context.suggest`, two search-provider methods); `Docs/AGENT_PROTOCOL.md` documents all of them. Agent 1's future authenticated principal checks must cover all page- and context-scoped methods when the branches integrate: the new methods resolve authority through the standard `page`/`context` parameters, so the generic `page.*`/context capability guard covers them with no special case. No versioned protocol or authenticated owner claim is made by this addition.

## Engine-only exit conditions

| Condition | Status on this branch | Evidence / dependency |
| --- | --- | --- |
| Live scripts mutate the DOM and produce captured pixels | **Verified on `b03abe81`** | macOS CI run `35468196462`, artifact `10591289876`: live viewport and captured PNG RGB `(0,255,0)` |
| Source file-to-runtime map | Source-traced; written | `Docs/AGENT3_INTEGRATION_MAP.md` |
| Authenticated session and sandboxed hostile renderer | **Fail: not implemented in base** | Agent 1 security/process contract required |
| Standards-based modern interactive/authenticated app | **Not qualified** | Agent 1 standards and realistic site qualification |
| Same `PageID` in silent/attached visible presentation | **Fail: no attached surface** | Agent 2 shared rendering contract required |
| Authorized human+two-agent co-control | **Fail: no principal authority** | Agent 1 and Agent 2 shared input contract required |
| Actual supported media playback/seek | **Fail: no media engine in base** | Agent 2 integration required |
| Engine-level blocker before all network paths | **Fail: no integrated blocker in base** | Agent 2 integration required |
| Profile isolation and restore | **Partial: controlled fixture passed, extended this turn** | Profile reopen restores storage, session pages, bookmarks, and search provider; cross-context storage isolation tested; corrupt profile fails closed with context intact. Cross-principal authorization and crash-recovery under load unqualified (Agent 1) |
| Recovery, accessibility, sustained memory | Not qualified at final-gate level | Renderer crash, IME, hardware and soak evidence outstanding |

On `b03abe81`, the release build, bounded 182/182 Swift tests and daemon harness passed on macOS 15 (`35468196462`, artifact `10591289876`). This turn, on the current branch: release build green; bounded serial suite **193/193 passing**; real-daemon qualification **24/24 checks passing** including dynamic DOM-to-raster pixels, dynamic capture pixels, typed address, profile reopen, and the new engine-services persistence check (local run `/tmp/aether-agent3-local/results.json`; CI artifacts upload on push via `agent3-engine-evidence.yml`). The legacy unbounded parallel CI remains red on Fetch assertions; Agent 1 PR #5 owns the bounded-runner workflow change and must be preserved.

**Verdict: Step 7 remains open.** A green Agent 3 branch alone cannot satisfy the engine-only gate or authorize GUI work. Run the final pass against the newest integrated Agents 1/2/3 SHAs; report exact artifact IDs and failures before changing these statuses.
