# Code-first browser recon

Phase 0 artifact required by `Docs/AGENT_CODE_FIRST_BROWSER_DIRECTIVE.md` §2.3.
Every claim is traced to a `path:line` in this working tree or labelled
`UNVERIFIED — hypothesis`. Nothing is from memory. Sources: `./openai-cua-sample-app`,
`./claude-quickstarts`, our `Sources/`.

Baseline facts: `Package.swift:6` is `platforms: [.macOS("27.0")]`; 26 files in `Sources/`
`import WebKit`; a repo-wide grep for `puppeteer|playwright|devtools.?protocol|cdp` across
`Package.swift` and `Sources/` returns **zero** matches. There is no CDP anywhere to remove,
and every Apple API the directive names is available at the declared minimum.

---

## 1. Reference A (openai-cua-sample-app) — what the browser code path does

`README.md:3`: *"we build this loop around models that write code to interact with software.
Code lets the model combine actions, process observations, and choose when to look again."*
Two agents ship side by side: `javascript-app` (Playwright, code) and `python-app` (PyAutoGUI,
desktop screenshots). We copy the first and reject the second.

| File | Model decides | Harness decides | Hard limit |
|---|---|---|---|
| `javascript-app/src/responses-loop.ts:117-137` `buildCodeToolDefinitions()` | the whole program body | the tool surface: **one** tool `exec_js`, `strict:true`, params `{code:string}`, `additionalProperties:false` | exactly 1 tool |
| `javascript-app/src/responses-loop.ts:139-145` `executeJavaScriptToolCall()` | — | `syncBrowserState()` + `captureScreenshot()` run after the program as **artifacts**; the model receives only the program's own outputs | a screenshot is never decision input |
| `javascript-app/src/responses-loop.ts:283-296` request | — | `parallel_tool_calls:false`, `previous_response_id`, `truncation:"auto"`, `reasoning:{effort:"low"}` | turn budget ≤ 50 (`contracts/index.ts` `responseTurnBudgetSchema`) |
| `javascript-app/src/responses-loop.ts:199-205` `classifyResponse()` | — | the whole response is validated before any call dispatches; unknown tool, bad JSON, extra args, duplicate `call_id` → `unexpected_model_response` | argument set is exactly `{code}` |
| `javascript-app/src/javascript-worker.ts:23-50` `createRepl()` | — | REPL globals are exactly `browser`, `context`, `page`, `Buffer`, `console.log`, `display(base64Image)`; `console.log` uses `maxStringLength: 2_000` | no `fs`, no `process` |
| `javascript-app/src/javascript-worker.ts:52-70` `execute()` | program text, loops, branching | the **parent** enforces the deadline, not the sandbox | code ≤ `maxCodeBytes` = 64 KiB (`browser/protocol.ts:19`) |
| `javascript-app/src/javascript-worker.ts:100-113` | — | single-flight `busy` flag; a concurrent request gets `"Invalid or concurrent JavaScript worker request."` | concurrency per worker = 1 |
| `javascript-app/src/browser/protocol.ts:11-20` | — | ops: `initialize \| execute \| inspect \| capture \| close`; output is a list of `input_text`/`input_image`; `parseJavaScriptOutput` rejects anything else and non-base64 URLs | `maxOutputBytes` = 12 MiB |
| `javascript-app/src/browser/javascript-process.ts:44-60, 185-215, 232-244` | — | child env scrubbed of `OPENAI_API_KEY`; a browser handle kept in the **parent** "even if model code blocks the worker"; close = graceful IPC → 250 ms → `SIGKILL` → browser `close()` with a 1 000 ms timer else `kill()`; stderr ring 4 000 bytes; watchdog `?? 60_000` → `javascript_execution_timeout` | every teardown is time-bounded; codes `javascript_worker_crashed`/`_protocol_error`/`_error`/`run_aborted` |
| `javascript-app/src/backend-lease.ts:4-25` | — | one fixed coordination port `4050`; `EADDRINUSE` → refusal message | one backend per machine |
| `javascript-app/src/scenario-runtime.ts:145-190` | — | one lab HTTP server per run over a mutable per-run workspace copy; `syncBrowserState`/`captureScreenshot` called by the **run flow**, outside the model's context | `README.md`: "Each run gets a fresh copy of a lab template" |
| `labs/catalog.json` | the task reading | `instructions` constrain *method*, e.g. paint: *"Do not generate an image externally, write canvas pixels through page.evaluate, or call page-internal drawing, document, or save functions."* | the harness may constrain method, not just goal |
| `contracts/index.ts` | — | `BrowserScreenshotArtifact.source: "browser_preview" \| "code_tool"`; `ReplayBundle.version: 3`; `runnerErrorResponseSchema = {code, error?, hint?}` | screenshots are typed artifacts with provenance |

§2.1's per-file question, answered: the model decides **what program to write**; the harness
decides tool count, sandbox globals, argument shape, turn budget, time and size budgets, and
that images are evidence rather than input. Safety posture is explicitly **not** a sandbox —
`README.md` Safety: *"Generated code runs with your user permissions. These samples do not
provide an operating-system sandbox"*, and *"A final answer does not prove the task succeeded."*

---

## 2. Reference B (claude-quickstarts) — mechanism vs anti-pattern

**Mechanism to copy.** `browser-use-demo/.../browser_dom_script.js:357-396` mints refs as
`"ref_" + ++window.__claudeRefCounter`, stores `window.__claudeElementMap[ref] = new
WeakRef(element)`, emits YAML `- role "name" [ref=ref_N]` plus `id`/`href`/`type`/`placeholder`,
caps recursion at `depth > 15` (`:348`), and prunes stale refs when `!weakRef.deref()`
(`:419-424`); return shape `{pageContent, viewport}`.
`browser_element_script.js:42-60` resolves by ref, deletes and types an error if
`!document.contains`, then `scrollIntoView({block:'center'})`, forces layout via
`offsetHeight`, and returns `coordinates:[x,y]` from `getBoundingClientRect()` — i.e. ref→
coordinate conversion is still the click mechanism; the ref is a stable *namespace*, not a
coordinate-free action. `tools/browser.py:63,67` confirms it: `ref` is *"Optional for click
actions and `hover` as an alternative to coordinates"*, while `coordinate` is *"Required for
mouse actions when `ref` is not provided."* The vocabulary is 24 actions (`browser.py:23-55`)
and includes `screenshot`, `zoom`, `execute_js`, `read_page`, `get_page_text`, `form_input`.
`CHANGELOG.md`: `browser_dom_script.js` is adapted from Playwright `ariaSnapshot.ts` (9/23/25);
`execute_js` added 12/19/25; scroll was changed to return a screenshot with a 0.5 s
stabilization delay (10/14/25); a 1/18/26 entry records fixed 1920x1080 dimensions with
"empirical coordinate correction".

**Keepers.** `computer-use-best-practices/computer_use/tools/batch.py:1-10,74-105` —
`browser_batch`/`computer_batch`: a list of `{action,...}` in **one** model turn, stopping on
the first error, returning label-interleaved results (`[{i}:{action}] {text}`) with per-step
images inline. Its docstring is also a documented hazard: *"Coordinates inside a batch refer to
the screenshot taken *before* the batch call (the underlying tool's scale state is not updated
mid-batch…)."* `tools/result.py:19-21,33-56` — `ToolResult` carries at most one text payload
and one image; `is_error` is `error is not None`; `IMAGE_OMITTED_ON_ERROR` exists because *"The
API rejects non-text blocks inside a tool_result with is_error=true."*
`constants.py:411-427` — `BATCH_REMINDER`: *"You ran a single standalone tool call, you should
use the computer_batch and browser_batch tools extensively for efficiency."*, gated by a
12-action set; the precedent for directive §14.4.6. `computer_use/image.py:1-20` — the resize
exists because *"the server resizes it again before the model sees it, and then the model emits
click coordinates in a space we never observed, producing systematic click drift (~14% on a
16:10 MacBook screen)"* — the measured cost of coupling vision to targeting.
`agents/tools/code_execution.py:7-16` is a 16-line `CodeExecutionServerTool` dataclass
(`code_execution_20250522`); the runtime is server-side, so there is no local implementation to
copy.

**Anti-pattern, quoted.** `computer-use-demo/computer_use_demo/loop.py:142` calls
`_maybe_filter_to_n_most_recent_images`; defined at `:244`, docstring at `:250`:

> "With the assumption that images are screenshots that are of diminishing value as the
> conversation progresses, remove all but the final `images_to_keep` tool_result images in
> place, with a chunk of min_removal_threshold to reduce the amount we break the implicit
> prompt cache."

The same helper is in `browser-use-demo/browser_use_demo/loop.py:176`. **Why the loop that
needs it is forbidden here:** it produces an image every step whether or not any step needed
one, then deletes the older ones to stay inside budget — paying twice for evidence nobody
requested. Scope precisely: the defect is the automatic production, not the image. A program
that asks for one image gets one.

---

## 3. Current Aether surface inventory

### 3.1 `AgentMethod` (`Sources/AgentProtocol/AgentMessages.swift`, 105 cases)

| Level | Methods | Count |
|---|---|---|
| Page read/state | `page.inspect/query/queryAll/find/snapshot/mutations/metrics/frame/lifecycle/history/scrollOffset/focused/hovered/console/networkLog/workers/dialogs/media` | 18 |
| Page act | `page.create/navigate/navigateInput/back/forward/reload/resize/close/click/drag/type/setValue/evaluate/render/loadHTML/setLifecycle/restore/hover/focus/blur/scroll/scrollIntoView/nodeAtPoint/pressKey/selectOption/fill/submit/mediaControl` | 28 |
| Context / identity | `context.create/destroy/list`, cookies ×5, storage ×5 + values/set/remove/clear ×4, permissions ×3, downloads ×3, `openProfile`, checkpoints ×3, blocking, profileUsage, suggest, searchProvider/setSearchProvider | 30 |
| Credentials / session / fleet | `credentials.list/get/save/delete/fill`; `session.create/list/destroy/pages`; `fleet.stats/pages/sweep` | 15 |
| Lease / handoff / approval | `workspace.lease.acquire/renew/release/cancel/list`; `handoff.request/list/claim/complete/cancel/resume/wait`; `approval.request/list/resolve/cancel/wait` | 17 |
| Execution / verification / events / capture | `agent.exec`, `task.verify`, `events.recent`, `page.capture`, `dialog.resolve` | 5 |

**Present** that §6 asks for and the directive assumed absent: cookies, storage, permissions,
downloads, bookmarks (`context.bookmarkAdd/Bookmarks/BookmarkRemove`), history
(`page.history`), profiles, checkpoints, handoff, approval gates (5 methods), leases.
**Missing vs §6:** extension enumerate/enable/disable/invoke; clipboard; zoom; print;
file-upload (the `fileChooserRequested` *event* exists, with no method to supply a path);
move-tab-between-windows.

### 3.2 Exec vocabulary (`Sources/AgentProtocol/AgentExec.swift`)

18 ops: `createContext`, `createPage`, `navigate`, `loadHTML`, `query`, `queryAll`, `click`,
`type`, `evaluate`, `snapshot`, `inspect`, `wait`, `restore`, `set`, `assert`, `forEach`, `if`,
`result`. Control flow exists: `forEach` with `limit`, `if/then/otherwise`,
`ExecValue.ref(name)` (a **variable** reference), `assert`. The program is declarative JSON,
not source text: `ExecProgram {version, session: UInt64?, timeoutMs?, onError, steps}`.

`ExecLimits`: `programVersion 1`, `maxSteps 1_000`, `maxExecutedSteps 100_000`,
`maxItems 10_000`, `defaultTimeoutMs 30_000`, `maxTimeoutMs 300_000`,
`maxSnapshotLimit 100_000`. **No output-byte limit** (the reference has 12 MiB,
`openai-cua-sample-app/javascript-app/src/browser/protocol.ts:20`).

`ExecOutcome {executionID, status, results, vars, stepsExecuted, operations, failures, error}`;
`ExecStatus ∈ {completed, failed, timeout, cancelled}`; `ExecFailure {stepPath, op, code,
message}`. Enforcement (`Sources/BrowserEngine/AgentExecRuntime.swift`): the program runs in a
`withThrowingTaskGroup` racing a `Task.sleep` deadline (`:76-99`), so timeout is a race, not a
poll; `ExecChildBox` (`:9-28`) is a lock-guarded cancel box so cancellation lands even if it
arrives *after* `box.adopt` (`:47-55`); lease revocation is registered before the run
(`:44-50`) and forces `status = .cancelled` with `ExecFailure.leaseRevokedCode` (`:105-113`),
never swallowed by `onError: proceed`.

### 3.3 Structured page state — already implemented

`Sources/EngineRuntime/WebKit/WebKitDOMScript.swift:35-90` installs `globalThis.__aetherDOM`.
Per node: `index`, `generation`, `parent`, `children`, `kind` (element/text/document), `tag`,
`text` (4 000 chars), `attributes`, `role`, `name` (aria-label → aria-labelledby → alt →
labels → innerText, 2 000 chars), `value`, `href`, `visible` (non-zero rect and not
`display:none`/`visibility:hidden`), `enabled`, `editable`, `bounds` (`getBoundingClientRect()`
plus scroll offsets). A `MutationObserver` maintains `mutationVersion()`; `snapshot(max)` walks
with a `TreeWalker`, skipping `script,style,noscript` subtrees, capped at `min(max, 20000)`,
pruning disconnected `WeakRef`s. **Secret redaction is already there** (`:50,58`): nodes
matching `input[type=password],input[autocomplete*=cc-],input[autocomplete=one-time-code]`
return `value: "[redacted]"` and redact the `value` attribute — this is §11.3 working today.

Identity is `NodeID(index, generation)`, and staleness fails **loudly**, satisfying §4.1.2:
`WebKitPage+Script.swift:56,300` guard `node.version == generation` and throw
`BrowserRuntimeError.nodeNotFound(node)`; `nodeAction` additionally throws
`"Node is no longer attached"` when `!n.isConnected`.

### 3.4 Events (`Sources/BrowserEvents/`)

17 families (page, navigation, document, console, network, download, popup, dialog, permission,
authentication, fileChooser, focus, context, branch, handoff, execution, lease) and 38 kinds
with `family`/`name`/`details`. Identity `{context, page, navigation, branch, session}`,
ordering by monotonic `sequence`, clock `timestamp: Date`.
Journal: `BrowserEventBus.init(journalLimit: Int = 2048)` (`BrowserEventBus.swift:44`), trimmed
at `:54`, `recent` clamped at `:92`. Drop accounting exists: `droppedTotal`,
`droppedBySubscriber`, `droppedEventTotal`, `droppedEventCount(forSubscriber:)`, with `publish`
inspecting the `yield` result; recovery is the journal via `recent(since:)`.
**The network gap is in the type system, not assumed:** the only network kind is
`networkNavigationResponse(url, statusCode, mimeType)`. There is no per-subresource event, so
§7 is missing *both* layers, not just the proxy layer.
Window-dependent producer: native pointer input. `WebKitPage+Script.swift:334`
`canSendNativePointer() -> Bool { view.window != nil }` and `sendMouseEvent` returns `false`
without a window (`:337`). Structured DOM clicks do **not** need a window (`click(_:)` calls
`n.click()` in page script).

### 3.5 Runtime, leases, branches, prewarm

`BrowserRuntime` (`Sources/EngineRuntime/BrowserRuntime.swift`, 2 392 lines) is one actor with
process-global state: `var webPages: [PageID: WebKitPage]` (`:147`),
`webPagesPreparedForPresentation` (`:149`), `pageOwner: [PageID: ContextID]` (`:152`).
Lifecycle: `setLifecycle` (`:1036`), `restorePage` (`:1055`), `captureState`/`captureDocument`
(`:988`/`:1003`).
Leases (`WorkspaceLeases.swift`): `BrowserWorkspaceLeaseState ∈ {active, released, cancelled,
expired, recoverable}`; `BrowserWorkspaceLease {workspaceID, leaseID, contextID, agentID,
branchID?, repositoryRoot?, worktreePath?, acquiredAt, expiresAt, state}`;
`LeaseRevocationToken`, `LeaseBoundExecution {contexts: Set<ContextID>, revoke}`; registry
`registerLeaseBoundExecution` (`BrowserRuntime+WorkspaceLeases.swift:260`).
Branches (`BranchTypes.swift`): `BrowserBranchInfo` with computed `restoreRequiredPages`;
`BrowserRuntime+Branches.swift` walks per profile.
Prewarm (`WebKitPrewarm.swift`): warms a WebContent process per store by loading `about:blank`
and nothing else — *"no network traffic, no cookies sent anywhere"* — stopping and detaching
after 30 s. Warmed stores live in a `Set<ObjectIdentifier>` capped at 8. **No identity is
carried over**, which is what §9 requires; the cap of 8 is the scale limit, not the design.

### 3.6 Isolation, identity, secrets

| Resource | Mechanism today | Where |
|---|---|---|
| Profile | `ProfileStore` | `Sources/Persistence/ProfileStore.swift` |
| Website data store | `WebKitStoreCache`, keyed per profile | `Sources/EngineRuntime/WebKit/SystemWebRuntime.swift` |
| Cookies | `WebCookieStorage` | `Sources/EngineRuntime/WebKit/WebCookieStorage.swift` |
| Credentials | `CredentialVault` + `CredentialSecrets` | `Sources/EngineRuntime/CredentialVault.swift`, `CredentialSecrets.swift` |
| Credential DOM fill | `window.__aetherCredentialForms` in the **isolated** world; the page world cannot see it | `WebKitPage+Script.swift:41-52` |
| Page → context | `pageOwner[PageID] = ContextID` | `BrowserRuntime.swift:152,386,729` |
| Execution → contexts | `allowedContexts: Set<UInt64>` on `agent.exec` | `AgentCommandDispatcher+Authority.swift` |

### 3.7 Extensions

`Sources/EngineRuntime/WebKit/AetherWebExtensionRegistry.swift` (24 lines) builds one
`WKWebExtensionController` per profile (`configuration.identifier = profileID`,
`defaultWebsiteDataStore = store`), registers the `chrome-extension` scheme, caches by `UUID`,
and exposes an `onCreate` hook. **No agent-facing method enumerates, enables, disables, or
invokes an extension** — the gap is the absent `extension.*` method, not a missing controller.

### 3.8 Delegation surfaces (verified by reading each)

| Surface | Lines | Business logic contained |
|---|---|---|
| `Sources/browserd/main.swift` | 66 | none — socket path, `dispatcher.handle(request)` (`:36`), `handle(request, principal:, ownership:)` (`:59`) |
| `Sources/aether-mcp/main.swift` | 66 | none — socket path, `--token-file`, usage |
| `Sources/AgentMCP/AgentMCPServer.swift` | 315 | JSON-RPC translation only: `initialize`/`ping`/`tools/list`/`tools/call` forwarded to the same dispatcher |
| `Sources/browserctl/main.swift` | 1 105 | none — argument parsing and forwarding; `page-capture` → `.pageCapture` (`:628`), local `inspect`/`render` straight to `engine.runtime` (`:51`,`:59`) |

No surface contains a second implementation of batching, verification, authorization, or
page-state reading (§18.11 clean).

### 3.9 Verification — already three-valued

`Sources/BrowserVerification/VerificationTypes.swift:4-8`:
`BrowserVerificationStatus ∈ {verified, failed, inconclusive}`. Assertions: `pageURL`,
`pageTitle`, `element(selector, condition)` with `BrowserElementCondition ∈ {exists, absent,
visible, enabled, accessibleName}`, `navigationResponse(statusCode, sinceSequence)`,
`download(downloadID, minimumBytes, verifyFileExists)`, `external(identifier, payload)`.
`TaskVerify` is an `AgentProcedure` (`Sources/AgentProtocol/VerificationProcedures.swift`).
The primitive exists; what does not exist is a `verify` **step**, so a program cannot verify
without leaving the program.

---

## 4. Gap table

| Capability | Exists? | File | Missing piece |
|---|---|---|---|
| Structured text-first page state with stable handles | **Yes** | `WebKitDOMScript.swift`, `WebKitPage+Script.swift` | document-start install; per-frame scoping; a handle that is not a snapshot index (§8.1) |
| Loud per-element staleness failure | **Yes** | `WebKitPage+Script.swift:56,300` | nothing |
| Secret redaction in the extractor | **Yes** | `WebKitDOMScript.swift:50,58` | the same guarantee on the `evaluate` path |
| Persistent program state across turns | **No** | `AgentExecRuntime.swift:41` | `ExecRunState` is per-run; `program.session` only selects a browser session |
| Bounded program output | **No** | `AgentExec.swift`; `AgentExecRuntime.swift:852` | no byte cap on `results`/`failures`; no `maxOutputBytes` |
| Runtime code authoring (control flow as source) | **No** | `AgentExec.swift` | only declarative steps; §14.3 `authoring: full` unimplemented |
| `verify` callable inside a program | **No** | `AgentExec.swift` | `task.verify` is a separate RPC only |
| Tier 3 capture with metadata | **Yes** | `page.capture` → `BrowserEngine.capturePage` (`BrowserEngine.swift:312`) → `LivePageCapture`, `Sources/NativeCapture/Sources/AetherCapture/CaptureCoordinator.swift` | no cost ledger, no per-workspace image budget, no counter shared with `pixels()` |
| Cost ledger / channel pricing (§4.0) | **No** | — | nothing prices snapshot vs evaluate vs image vs coordinate action |
| Two-layer network visibility | **No** | `BrowserEvent.swift` (navigation-response kind only) | the JS `fetch`/XHR patch layer and the local-proxy layer |
| Extension agent access | **No** | `AetherWebExtensionRegistry.swift` | any `extension.*` method |
| File upload | **No** | — | `fileChooserRequested` event exists; no method supplies a path |
| Clipboard / zoom / print | **No** | — | no methods |
| Fleet admission control with typed refusals | **Partly** | `Sources/Scheduler/FleetScheduler.swift` | per-workspace budgets for memory/pages/handles/images — `UNVERIFIED — hypothesis` |
| Hibernation with measured reactivation | **Partly** | `BrowserRuntime.swift:1036,1055`; `WebKitPrewarm.swift` | no measured reactivation cost anywhere; warm pool capped at 8 |
| Sharded supervisor, no global hot-path actor | **No** | `BrowserRuntime.swift:147-152` | one actor owns all `webPages`/`pageOwner` |

---

## 5. Inefficiency table

| Hot path | Current cost | Measured or suspected | Instrument to add |
|---|---|---|---|
| One program → one boundary call | `operations` exists in `ExecOutcome`; measured this cycle: 400-node DOM loop → `operations == 4`, `stepsExecuted == 806`; 40 browser ops behind one dispatcher call → `operations == 43`; two-page program → `operations == 7` | **Measured** | per-lease aggregate |
| Snapshot re-read per step | full `TreeWalker` walk each call; `mutationVersion()` exists but no caller diffs against it | **Suspected** | snapshot generation id + changed-since query |
| Image production | `pixels()` (`WebKitPage+Script.swift:375`) and `page.capture` both call `takeSnapshot`; neither reports to a shared counter | **Verified in code** — no image counter exists | image counter split by requester |
| Automatic image injection | cannot occur — images come only from an explicit RPC or program | **Verified absent**; no per-step push exists in this repo | zero-unrequested-image test |
| Per-run state allocation | `ExecRunState()` per `run` (`AgentExecRuntime.swift:41`); `results`/`failures` grow uncapped | **Verified in code** | output-bytes counter + truncation flag |
| Event fan-out | journal 2 048; per-subscriber bounded buffer; a 700-event burst dropped 188, all recoverable from the journal | **Measured** | already counted (`droppedTotal`, `droppedBySubscriber`) |
| Coordinate action | `page.click` takes `index`+`generation`, never a point; `page.nodeAtPoint`/`page.drag` take points | **Verified** — there is no `click_at(x,y)` method | coordinate-action counter |
| Polling waits | `ExecStep.wait(selector, condition, timeoutMs)` is selector-based; no sleep step exists | **Verified** — polling cannot be expressed | count waits whose condition is a fixed delay |
| Injected source per operation | `domScript(_:)` prepends `WebKitDOMScript.source(generation:)` (~3.5 KiB) before every call, guarded only *after* prepending by `if (globalThis.__aetherDOM?.generation === N) return;` | **Suspected** | bytes of injected source per operation |
| Per-operation I/O on the control path | snapshot path is in-process `evaluateJavaScript` | **Verified** | counters under steady load |

---

## 6. Isolation table

| Resource | Mechanism today | Violation path | Enforcement |
|---|---|---|---|
| Page → context | `pageOwner[PageID] = ContextID` | a new entry point could address a page in another context | `AgentCommandDispatcher+Authority.swift` |
| Execution → contexts | `allowedContexts` on `agent.exec` | an exec step addressing a page outside the set | dispatcher, per call |
| Cookies / storage | per-profile `WKWebsiteDataStore` via `WebKitStoreCache` | cross-profile read through a shared context handle | `WebKitStoreCache` keying |
| Secrets | `CredentialVault` + `CredentialSecrets`; DOM fill only via the isolated world's `__aetherCredentialForms` | **`page.evaluate` and exec `evaluate` run in the page world** (`WebKitPage+Script.swift:34`) and are not redacted; anything reachable from page script is reachable from them | **none today — open §11.3 surface** |
| Lease → in-flight work | `registerLeaseBoundExecution` + `LeaseRevocationToken` | revocation arriving after `box.adopt` | runtime actor + the lock-guarded `ExecChildBox` (`:9-28`) |
| Weakening to pass a test | not observed; the NSWindow bundle segfault was fixed by `isReleasedWhenClosed = false`, not by deleting a producer | — | the test suite |

---

## 7. Scale table

| Resource | Current per-workspace cost | Bottleneck at 1k | At 100k |
|---|---|---|---|
| Runtime state | one `webPages` entry, one `pageOwner` entry, one `webPagesPreparedForPresentation` entry per page | one actor serializes every mutation | the actor is the ceiling; `UNVERIFIED — hypothesis`: no measurement exists, verify with the §9.10 sweep |
| Warm WebContent process | `WebKitPrewarm` warms ≤ 8 stores total | a pool of 8 cannot cover 1 000 stores | prewarming is not a strategy at 100k; needs admission control |
| Event stream | journal 2 048 per bus; per-subscriber bounded buffer | 1 000 workspaces sharing one bus contend on one journal | `UNVERIFIED — hypothesis`: the bus is not sharded per workspace |
| Snapshot payload | up to 20 000 nodes; text ≤ 4 000 chars, name ≤ 2 000 | a 20 000-node snapshot is a multi-MB allocation per call | needs a byte cap plus paging (§4.1.4) and per-lease byte accounting |
| Program output | `results` uncapped | grows with work done | unbounded × 100k is a memory incident; needs the §10 bound |
| Page memory | fallback estimate `8 * 1024 * 1024` when measurement is 0 (`BrowserRuntime.swift:1111`) | an estimate is not a budget | needs real measurement |
| Images | no counter, no budget | unmeasurable | unmeasurable |

---

## 8. Conflicts between this document and the code — STOP AND REPORT

Four decisions are needed before implementation. None is a reason to discard the directive.
The four §2.4 stop conditions were otherwise checked and **not** triggered: no requirement
contradicts the code irreconcilably beyond what is listed below; an existing subsystem is
better than the directive assumed (Conflict 3); no required capability is impossible on
`platforms: [.macOS("27.0")]`; and the one thing that could not be measured is named in
Conflict 2 and §7.

**Conflict 1 — §5.1 "state persists across driver turns" cannot be met by extending
`ExecProgram`.**
`AgentExecRuntime.swift:41` constructs `ExecRunState()` per `run`, and `program.session`
(`:133-139`) is only validated against `runtime.listSessions()`, yielding `sessionNotFound`.
`vars` therefore die with the run. The directive is right and the code must change: a
session-scoped variable store keyed `(session id, lease id)`, owned by the runtime, with the
lease registry built this cycle as its revocation path. **Also rename a collision:**
`ExecValue.ref(name)` means *variable* reference today, while the directive uses `ref_N` for
*element* handles — and the RPC surface already says `nodeIndex`/`nodeGeneration`. Pick one
vocabulary before writing either.

**Conflict 2 — §4.1 prescribes `WKUserScript` at `.atDocumentStart` for all frames; our
extractor is an on-demand `evaluateJavaScript` in the isolated world.**
`WebKitPage+Script.swift:33-35` evaluates in `.defaultClient` (isolated) and `domScript(_:)`
prepends `WebKitDOMScript.source(generation:)` to every call. This is a **better** isolation
story than the directive assumed — page scripts can neither see nor tamper with the extractor —
but it is **worse** on two §4.1 requirements: it does not exist before page scripts run, and it
is main-frame only (§4.1.6). Recommendation: keep the isolated world, add a `WKUserScript` in
that same client world at document start plus per-frame scoping, and record that
`.atDocumentStart` is satisfied *within the isolated client*, not the page world. The suspected
cost of the current prepend-every-call is in §5 and must be measured before it is changed.

**Conflict 3 — §8's `verify()` is already better than the directive assumes; do not rebuild it.**
`BrowserVerificationStatus` is three-valued and `BrowserVerificationAssertion` already covers
URL, title, element conditions, navigation response, download-with-file-existence, and external
payloads (§2.4.2 applies: name it, extend it). The remaining work is (a) a `verify`/`assertExternal`
step in `ExecStep` so a program can verify inline, and (b) verification as the default at the end
of a consequential program.

**Conflict 4 — §11.3 "script execution must not be able to read secrets" is false on exactly
one path, and the fix is confinement, not redaction.**
`WebKitPage+Script.swift:34` `evaluate(_:)` calls `script(source, isolated: false)` — the page
world — while the extractor's redaction (`WebKitDOMScript.swift:50,58`) applies only in the
isolated world. The repository already contains the correct pattern: `fillCredentials`
(`:41-52`) runs in the isolated world precisely because `__aetherCredentialForms` is invisible
to the page. So: credential *values* are unreachable from page-world code (true today), and the
exec `evaluate` step must be confined so it cannot reach any vault-backed value. That is the
§11.3 requirement, stated precisely.
