# Agent 3: execution scope and dependent engine-only gate

Base: `main@01f9ec1d9df377cf8377852e1400782a4366b7a0`. Branch: `agent3/engine-services-gate-20260920`. Preserve the existing Step 1 evidence, the 177-test reported baseline, and later Agent 1/2 commits. Source and new regression tests are not macOS verification until CI finishes.

## Delivered on this branch

- Typed URL versus search-query resolution through `page.navigateInput` and `browserctl page-navigate-input`, using `BrowserRuntime.navigate`. Provider endpoint/query-key configuration is per request; persistent per-profile provider preference is still missing.
- Explicit handling of unsupported URL schemes and forbidden URL userinfo, with regression tests.
- Extended real-daemon verification of a JavaScript DOM/style change in viewport pixels and the capture PNG, plus a typed address going through the live page.
- File-to-runtime integration map at `Docs/AGENT3_INTEGRATION_MAP.md`.
- Separate macOS Actions workflow running bounded Swift tests plus the real daemon/capture harness and uploading evidence.

New dispatcher method changes the method count from the reported **76 to 77** on this branch; `Docs/AGENT_PROTOCOL.md` still describes the base contract and requires a coordinated update as other agents extend it. No versioned protocol or authenticated owner claim is made by this addition.

## Engine-only exit conditions

| Condition | Status on this branch | Evidence / dependency |
| --- | --- | --- |
| Live scripts mutate the DOM and produce captured pixels | Awaiting macOS CI verification | `Scripts/verify_browser.py` pixel cases and uploaded kit |
| Source file-to-runtime map | Source-traced; written | `Docs/AGENT3_INTEGRATION_MAP.md` |
| Authenticated session and sandboxed hostile renderer | **Fail: not implemented in base** | Agent 1 security/process contract required |
| Standards-based modern interactive/authenticated app | **Not qualified** | Agent 1 standards and realistic site qualification |
| Same `PageID` in silent/attached visible presentation | **Fail: no attached surface** | Agent 2 shared rendering contract required |
| Authorized human+two-agent co-control | **Fail: no principal authority** | Agent 1 and Agent 2 shared input contract required |
| Actual supported media playback/seek | **Fail: no media engine in base** | Agent 2 integration required |
| Engine-level blocker before all network paths | **Fail: no integrated blocker in base** | Agent 2 integration required |
| Profile isolation and restore | Existing partial implementation; integration test pending | `Scripts/verify_browser.py` restore/isolation cases; unauthorized cross-principal access not addressed |
| Recovery, accessibility, sustained memory | Not qualified at final-gate level | Renderer crash, IME, hardware and soak evidence outstanding |

**Verdict: Step 7 remains open.** A green Agent 3 branch alone cannot satisfy the engine-only gate or authorize GUI work. Run the final pass against the newest integrated Agents 1/2/3 SHAs; report exact artifact IDs and failures before changing these statuses.
