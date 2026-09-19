# Agent 3: execution scope and dependent engine-only gate

Base: `main@01f9ec1d9df377cf8377852e1400782a4366b7a0`. Branch: `agent3/engine-services-gate-20260920`. Preserve the existing Step 1 evidence, the 177-test reported baseline, and later Agent 1/2 commits. Source and new regression tests are not macOS verification until CI finishes.

## Delivered on this branch

- Typed URL versus search-query resolution through `page.navigateInput` and `browserctl page-navigate-input`, using `BrowserRuntime.navigate`. Provider endpoint/query-key configuration is per request; persistent per-profile provider preference is still missing.
- Explicit handling of unsupported URL schemes and forbidden URL userinfo, with regression tests.
- Live bounded `page.find` / `browserctl page-find` over visible DOM text nodes and snapshot mutation version; tests cover hidden nodes, case sensitivity, limits, and post-JS mutation. No fabricated selection or highlight support.
- Extended real-daemon verification of a JavaScript DOM/style change in viewport pixels and the capture PNG, plus a typed address going through the live page.
- File-to-runtime integration map at `Docs/AGENT3_INTEGRATION_MAP.md`.
- Separate macOS Actions workflow running bounded Swift tests plus the real daemon/capture harness and uploading evidence.

Two new dispatcher methods change the method count from the reported **76 to 78** on this branch; `Docs/AGENT_PROTOCOL.md` documents both. Agent 1's future authenticated principal checks must cover all page-scoped methods when the branches integrate. No versioned protocol or authenticated owner claim is made by this addition.

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
| Profile isolation and restore | **Partial: controlled fixture passed on `b03abe81`** | macOS run `35468196462` reopens discarded tab and storage, plus cross-context storage test; cross-principal authorization and corruption recovery unqualified |
| Recovery, accessibility, sustained memory | Not qualified at final-gate level | Renderer crash, IME, hardware and soak evidence outstanding |

On `b03abe81`, the release build, bounded 182/182 Swift tests and daemon harness passed on macOS 15 (`35468196462`, artifact `10591289876`). Later `page.find` code and its three tests are **not macOS verified**: current GitHub Actions jobs fail before runner allocation (zero steps, no logs); no compiler/test outcome can be inferred from those failures. The legacy unbounded parallel CI remains red on Fetch assertions; Agent 1 PR #5 owns the bounded-runner workflow change and must be preserved.

**Verdict: Step 7 remains open.** A green Agent 3 branch alone cannot satisfy the engine-only gate or authorize GUI work. Run the final pass against the newest integrated Agents 1/2/3 SHAs; report exact artifact IDs and failures before changing these statuses.
