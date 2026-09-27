# AGENT_CODE_FIRST_BROWSER_DIRECTIVE.md

### A hard directive for rearchitecting the coding agent's browser control path

**Status:** mandatory. Binding on every agent working in this repository.
**Supersedes:** any prior instruction, doc, comment, or habit that implies the agent
drives the browser through a per-click tool loop, or that treats a screenshot as the
automatic observation pushed into the model between steps.
**Applies to:** the agent control surface of Aether (backend, protocol, exec runtime,
event system, leases, verification) and every surface that delegates into it
(native Swift API, CLI, MCP).

---

## HOW TO READ THIS DOCUMENT

1. Read it end to end **before** you open a file, **before** you write a plan, **before**
   you run a build. It is not a suggestion list. It is the specification.
2. `MUST`, `MUST NOT`, `REQUIRED`, `FORBIDDEN` are absolute. There is no "unless it is
   easier", no "for now", no "we can fix it in a follow-up".
3. If any requirement here conflicts with what you find in the code, **stop and report the
   conflict**. Do not silently pick one. Do not route around a requirement by building a
   parallel path that technically satisfies the letter while defeating the point.
4. Numbers in this document are **targets you must measure**, not adjectives you may repeat.
   Any claim of improvement MUST be accompanied by the instrument output that produced it.
   A claim without a measurement is a fabrication and will be treated as a defect.
5. This document is about the **backend**: the execution runtime, the protocol, the event
   pipeline, the lease/scheduling layer, verification, and the isolation boundaries. The
   human-facing browser UI is finished. Do not redesign it. Minimal, surgical hooks are the
   only permitted edits outside the backend.

---

## §0 — WHAT YOU ARE ACTUALLY BEING ASKED TO DO

You are not being asked to "add browser tools". You are being asked to execute a
**rearchitecture**, because the current approach is wrong in a specific, provable way.

Our current approach is the old approach: the model looks at a picture of a page, decides
a pixel coordinate, emits one tool call, waits for a picture, and repeats. That is a
five-step loop per atomic action:

```
1. model requests screenshot
2. model examines the image
3. model guesses/marries a coordinate (or is handed one)
4. one tool call executes one atomic action
5. a new screenshot is captured and pushed back into the model's context
   → repeat
```

Every serious team building this has already moved off it. We are not going to argue about
taste with you; we are going to hand you the receipts (§1) and require you to read them
yourself (§2) before you write code.

The replacement has three sentences. Memorize them:

> **Structured page state is the primary read channel. Code execution with persistent state
> is the primary action channel. Screenshots are a first-class capability the driver may
> choose at any moment — an option with an honestly declared cost, ranked against the other
> channels, and never an observation injected between steps without the program asking.**

And one more, which is ours and which no reference implementation solves for you:

> **Everything must scale to hundreds of thousands of concurrent agent workspaces on one
> fleet without a single unbounded buffer, a single per-step round trip, or a single
> main-thread bottleneck.**

### §0.1 The three laws of this document

**Law 1 — Nothing is inefficient.**
Every hot path has a budget. Every buffer is bounded. Every queue has backpressure. Every
round trip must justify itself. Every allocation in a per-operation loop must be justified.
"Probably fine" is not an engineering position. If you cannot state the cost of a code path
in operations, bytes, or milliseconds, you do not understand the code path yet and you are
not allowed to ship it.

**Law 2 — The agent uses the browser the way a human does, only 100× more intelligently and
100× faster in wall-clock terms.**
Same capabilities as a human operator: navigate, read, find, fill, click, submit, upload,
download, open a tab, switch a tab, close a tab, use history, use an extension, grant a
permission, take over a session, and observe the network. No capability gap is acceptable:
if a human can do it in the shipped browser, the agent MUST have a code-callable equivalent.
But the agent does not do it one gesture at a time; it does it in batched, self-checking,
branching programs whose intermediate results never leave the machine. A human fills 40 form
fields in 40 hand movements and 40 glances. The agent fills 40 fields in **one** program,
verifies all 40, and surfaces one result. That is the 100×.

**Law 3 — Extreme parallelism is a first-class requirement, not a later optimization.**
The target is not 5 workspaces, not 100, not 1,000. The target is a fleet of independent
agent workspaces running concurrently, scheduled under leases, each isolated in context,
cookies, storage, secrets, event stream, and process resources. Every design decision must
be evaluated against this scale. A design that is correct at 10 workspaces and quadratic,
unbounded, or main-thread-serialized at 100,000 is **wrong**, even if it passes its unit
tests.

### §0.2 The seven failures this document exists to eliminate

These are the specific defects we have observed or that every reference implementation
exhibits. Each one is a MUST-FIX.

1. **Screenshot-in-the-loop.** A screenshot is captured *automatically* and pushed into the
   model's context every step, as the observation channel nobody chose. The defect is the
   automaticity and the defaulting, not the image. A driver that consciously decides an image
   is the right evidence for the step it is on has done nothing wrong and MUST NOT be blocked,
   penalized, or second-guessed. Automatic per-step injection is the failure: it burns vision
   tokens to re-derive information that already exists as structured text, and it removes the
   driver's ability to spend its own budget on purpose.
2. **One round trip per atomic action.** The application decides the cadence: action,
   observation, action, observation. The model cannot loop, cannot branch, cannot retry
   without a full model turn for each attempt.
3. **Coordinate guessing.** The model, or a helper, derives a pixel target that goes stale
   the moment the page reflows. A structured element reference tied to the live element does
   not go stale.
4. **Unbounded accumulation.** Screenshots, events, logs, and page states accumulate in
   memory and in model context until something trims them after the fact. Trimming after the
   fact is a confession that the thing should never have been produced.
5. **Optimistic completion.** A task is reported successful because an action returned
   without error. No external state was checked. This is the most commonly missing piece in
   every public implementation we have read.
6. **Per-workspace serialization.** One actor, one lock, one main thread, one browser
   process per workspace doing every operation end to end, so throughput is capped by
   single-thread latency rather than by real resources.
7. **Isolation by convention.** Contexts, profiles, secrets, and event streams are separated
   because the code "tries to" keep them separate, not because a lease boundary makes
   violations impossible and observable.

---

## §1 — RECEIPTS: THE ARCHITECTURE ALREADY MOVED

Do not take our word for it. This section exists so you know *what to look for* when you do
the reconnaissance in §2. Every claim below is traceable to code that is cloned into this
working tree right now.

### §1.1 OpenAI's computer-use reference implementation is code-first for the browser

Repository cloned into this working tree at `./openai-cua-sample-app`.

Its own README states the design intent in the first paragraph — read it yourself at
`openai-cua-sample-app/README.md`:

> "At OpenAI, we build this loop around models that write code to interact with software.
> Code lets the model combine actions, process observations, and choose when to look again."
>
> "A persistent runtime keeps useful state and helper functions available between calls. The
> model can write a loop to fill several fields, check that each change took effect, and
> return only the text or screenshots it needs. This can reduce model round trips and
> repeated input context while giving the model feedback to correct mistakes."

Note the shape of that repository: it contains **two** agents, and the README is explicit
that they are different in kind:

- `javascript-app/` — JavaScript + Playwright, i.e. **the browser is driven by code**.
- `python-app/` — Python + PyAutoGUI, i.e. **a desktop is driven by screenshots and mouse
  movement**.

The browser path is the code path. The screenshot path is the *desktop* path, and it exists
to demonstrate desktop control, not browsing. This is precisely the split we are adopting
and precisely the screenshot-driven loop we are rejecting for browser work.

What the browser code path actually looks like, verified in this tree:

- **The model has exactly one function tool: `exec_js`.**
  `openai-cua-sample-app/javascript-app/src/responses-loop.ts`, function
  `buildCodeToolDefinitions()`. The tool schema has exactly one required property, `code`,
  with `additionalProperties: false`. There is no `click` tool. There is no `screenshot`
  tool. There is no action menu at all.
- **The tool description itself encodes the architecture.** Quoting it verbatim from the
  same function: "JavaScript to execute in an async Playwright REPL. Persist state across
  calls with globalThis. Available globals: console.log, display(base64Image), Buffer,
  browser, context, page. Prefer locator-based waits and domcontentloaded load-state waits
  over fixed delays."
- **The REPL is persistent across model turns.**
  `openai-cua-sample-app/javascript-app/src/javascript-worker.ts`, function
  `createRepl()`: a single `vm.createContext` with `browser`, `context`, `page`, `Buffer`,
  a `console.log` that appends text output, and a `display(image)` that appends an image
  output. It is created once at `initialize` and reused for every subsequent `execute`.
- **The model receives only what its code returns.** Same file, function `execute()`: the
  outputs array starts empty, code runs, and the return value is
  `parseJavaScriptOutput(outputs)` — a list of `input_text` / `input_image` items
  (`openai-cua-sample-app/javascript-app/src/browser/protocol.ts`). If the code does not
  call `display(...)`, **no image reaches the model at all**.
- **Screenshots are artifact/replay evidence, not model input.**
  `responses-loop.ts`, function `executeJavaScriptToolCall()`: after code runs, it calls
  `context.syncBrowserState(session)` and `context.captureScreenshot(session, ...)` and then
  returns `output` — the code's own outputs. The capture feeds the run's artifact timeline
  (`contracts/index.ts` models `BrowserScreenshotArtifact` with
  `source: "browser_preview" | "code_tool"`), which is what a human reviews afterwards in the
  console/replay bundle. That is the correct role for a screenshot: **evidence for the
  operator, not a step in the loop.**
- **The parent process, not the sandbox, enforces the deadline.**
  `javascript-app/src/browser/javascript-process.ts`, function `request()`: a `setTimeout`
  watchdog in the API process fires at `executionTimeoutMs` (default 60,000 ms) and fails
  the run with code `javascript_execution_timeout`. The comment in the code says it
  explicitly: "This watchdog runs in the HTTP/API process, before any code is sent." And in
  `javascript-worker.ts`: "The parent process enforces the deadline, including loops after
  an await." Your code sandbox cannot be the thing that polices its own deadline; a blocked
  or spinning script must be killable from outside.
- **Exactly one operation may be in flight per worker.**
  `javascript-process.ts` throws "A JavaScript operation is already running." if a second
  request arrives, and `javascript-worker.ts` carries a `busy` flag that rejects concurrent
  requests. Bounded concurrency, explicit protocol violation errors, no interleaved garbage.
- **Hard resource caps at the protocol layer.**
  `javascript-app/src/browser/protocol.ts` exports `maxCodeBytes = 64 * 1024` and
  `maxOutputBytes = 12 * 1024 * 1024`; `javascript-worker.ts` truncates each `console.log`
  string to 2,000 characters (`util.formatWithOptions({ maxStringLength: 2_000 })`). A
  model cannot, by accident, stream a 400 MB log into its own context.
- **Teardown is ordered and enforced.**
  `javascript-process.ts`, function `close()`: send a graceful `close` operation, wait up to
  250 ms for exit, then `SIGKILL` the worker; then close the browser server with a 1,000 ms
  timeout and `kill()` it if that times out. The comment "Killing the worker does not
  necessarily kill the Chromium process." is the entire lesson: **orphan process reaping is
  part of the design, not an operational afterthought.**
- **Credentials are removed from the child environment.**
  Same function: `childEnvironment` is built by filtering `OPENAI_API_KEY` out of
  `process.env` before forking the worker. The code the model writes runs in a process that
  structurally cannot read the API key. This is the model of secret isolation we require
  (§11), not "we told the model not to print it".
- **The loop is single-flight and explicitly budgeted.**
  `responses-loop.ts`, function `runResponsesCodeLoop()`: `parallel_tool_calls: false`,
  `truncation: "auto"`, `previous_response_id` chaining, a `maxResponseTurns` budget
  (bounded to ≤ 50 in `contracts/index.ts`), and a hard failure when the budget is exhausted
  without a final answer.
- **Runs are workspace-isolated and replayable.**
  README: "Each run gets a fresh copy of a lab template. Workspaces, screenshots, and
  replays stay in the selected app's ignored `data/` directory." `contracts/index.ts`
  defines a versioned `ReplayBundle` (v3) carrying the run record, scenario, events,
  browser state, and artifact paths.
- **Backends are single-tenant by construction.**
  `javascript-app/src/backend-lease.ts` binds an exclusive listener on port 4050 and refuses
  to start when another backend holds it. Crude, but the *instinct* — one active controller
  per resource, enforced by the OS, with a clear error — is right and we generalize it in
  §9.

Also note what the README warns, because we adopt those warnings as requirements rather than
disclaimers:

> "Generated code runs with your user permissions. These samples do not provide an
> operating-system sandbox or OpenAI's production action-review controls."
>
> "A final answer does not prove the task succeeded. Inspect the result before relying on it."

We are not allowed to ship either of those as a caveat. Sandboxing and verification are
requirements here (§11, §8).

### §1.2 Anthropic's `claude-quickstarts` contains both the thing to copy and the thing to reject

Repository cloned into this working tree at `./claude-quickstarts`.

It contains, side by side, the correct mechanism and the anti-pattern:

**The thing to copy — DOM/accessibility-derived structured state with element references:**

- `claude-quickstarts/browser-use-demo/browser_use_demo/browser_tool_utils/browser_dom_script.js`
- `claude-quickstarts/browser-use-demo/browser_use_demo/browser_tool_utils/browser_element_script.js`
- `claude-quickstarts/browser-use-demo/browser_use_demo/browser_tool_utils/browser_form_input_script.js`
- `claude-quickstarts/browser-use-demo/browser_use_demo/browser_tool_utils/browser_text_script.js`

The repository's own provenance log — `claude-quickstarts/browser-use-demo/CHANGELOG.md` —
says what these scripts are: `browser_dom_script.js` is *"Adapted Playwright's accessibility
tree generation... Implemented accessibility tree extraction with element reference tracking,
visibility filtering, and YAML-formatted output"*, derived from Playwright's
`ariaSnapshot.ts`; `browser_element_script.js` is *"element finding and interaction logic
inspired by Playwright's approach to reliable element targeting and coordinate calculation"*.

The mechanism itself is visible in `browser_dom_script.js` around lines 357–396 and is
small, which is the point:

```js
// existing ref lookup first, then:
ref = "ref_" + ++window.__claudeRefCounter;
window.__claudeElementMap[ref] = new WeakRef(element);
...
var yaml = indent + "- " + role;
if (name) yaml += ' "' + name.replace(/"/g, '\\"') + '"';
yaml += " [ref=" + ref + "]";
if (element.id) yaml += ' id="' + element.id + '"';
if (element.getAttribute("href")) yaml += ' href="' + ... + '"';
```

with stale-reference cleanup at ~line 419 ("Clean up stale references (elements that have
been garbage collected)"). So: walk the DOM, name each interesting element `ref_N`, keep a
`WeakRef` to it, emit a compact line-oriented snapshot the model reads as **text**, and let
the model act on `ref_N` instead of a coordinate. The tool schema in
`claude-quickstarts/browser-use-demo/browser_use_demo/tools/browser.py` (~line 63) documents
the parameter accordingly: *"Element reference string for targeting specific DOM elements...
Optional for click actions and `hover` as an alternative to coordinates."*

**The thing to reject — screenshot-per-action with post-hoc trimming:**

- `claude-quickstarts/computer-use-demo/computer_use_demo/loop.py:244` defines
  `_maybe_filter_to_n_most_recent_images(...)`, called from the loop at line 142.
- The identical helper exists again in the browser demo:
  `claude-quickstarts/browser-use-demo/browser_use_demo/loop.py:176`.
- Its docstring is the confession we are quoting back at you (loop.py:250):

  > "With the assumption that images are screenshots that are of diminishing value as the
  > conversation progresses, remove all but the final `images_to_keep` tool_result images in
  > place..."

Read that as an architecture review: the loop produces an image per step *whether or not
anyone wanted one*, then deletes the older ones to keep the context affordable. Producing
those images automatically was never necessary; deleting them afterwards is paying twice —
once to make them, once to reason about which to drop. **We forbid this shape entirely**
(§18): the automatic per-step image. We do *not* forbid images. When the agent's own code asks
for one it gets one, and it is budgeted like any other expensive resource (§10, §4.0).

**The desktop loop, explicitly rejected:** `claude-quickstarts/computer-use-demo/` drives a
whole virtual desktop — X11, a VNC stack, Firefox clicked by coordinate, `bash` and a text
editor as tools — and its system prompt instructs the model to click the Firefox icon and
zoom out so it can see the whole screen. That is computer use *of a desktop*. We are not
building that. Aether is a browser; our agent drives **the page and the browser's own
capabilities**, through structured state and code. Do not port that loop, its tools, or its
coordinate-scaling compensating machinery.

**The thing to copy from the newest reference — batching as a first-class primitive, and
honest evidence objects:**

- `claude-quickstarts/computer-use-best-practices/computer_use/tools/batch.py` defines
  `browser_batch` and `computer_batch`: a list of `{action, ...}` steps executed
  sequentially in **one** model turn, **stopping on the first error**, returning
  label-interleaved results so the model sees exactly what happened at each step, and its
  docstring states the coordinate contract precisely ("Coordinates inside a batch refer to
  the screenshot taken *before* the batch call..."). Errors are reported as
  `batch stopped at actions[i] (label): <error> (N completed, M skipped)`.
- `claude-quickstarts/computer-use-best-practices/computer_use/tools/result.py` defines a
  `ToolResult` with an explicit `is_error` and an `IMAGE_OMITTED_ON_ERROR` constant, because
  the API rejects non-text blocks inside an error result. Structured result objects with
  explicit error state, not prose.
- `claude-quickstarts/computer-use-best-practices/constants.py:411` defines `BATCH_REMINDER`,
  a nudge the harness appends when the model makes a lone single-action call:
  "You ran a single standalone tool call, you should use the `computer_batch` and
  `browser_batch` tools extensively for efficiency." Their `BATCH_REMINDER_ACTIONS` set lists
  exactly the actions they consider batchable.
- `claude-quickstarts/computer-use-best-practices/computer_use/image.py` exists solely to
  port the API's reference resize so that what the model sees and the coordinates it emits
  agree. Bundling coordinate data with an image is a scaling problem that only exists because
  images are in the loop. We keep the resize discipline for the few cases where an image *is*
  the right answer (§4 Tier 3), and we do not build a coordinate pipeline around it.
- The README of that folder is worth one careful read for its honesty: it states that every
  tool the model sees is fully specified in `computer_use/tools/`, that it is a *reference
  implementation* meant to be read and modified rather than imported, that batching
  "can meaningfully reduce latency and cost on workloads where the model can confidently plan
  several steps ahead", and that running an unguarded computer-use agent outside a
  disposable VM is strongly discouraged. We adopt the *specification discipline* and the
  *batch primitive*. We do not adopt "run it in a VM and hope".

### §1.3 What the receipts prove, and what they do not

They prove: the two organizations that defined this problem have both moved to structured
page state plus code execution, with screenshots retained as an explicit, cost-ranked option
rather than an automatic per-step input, and the
open-source ecosystem's most aggressive implementation reports large token reductions from
removing the action menu (Browser Use's published migration claims, which you MUST read at
the source before citing: `github.com/browser-use/browser-use`).

They do **not** prove: that any of those projects has solved fleet-scale execution, secret
isolation below the process boundary, deterministic verification, or hundreds of thousands
of concurrent workspaces. Those are ours to solve, and §9, §8, §11 are where we do it. Do not
copy a reference implementation and call the job done; the reference implementations are
single-workstation demos with an explicit warning label on them.

---

## §2 — PHASE 0: MANDATORY RECONNAISSANCE (NO CODE BEFORE THIS IS DONE)

You MUST complete this phase and write its output to
`agents/agent-native-browser-runtime/code-first-recon.md` before you modify a single
source file. The recon artifact is small (≤ 300 lines), factual, and cites paths and
symbols. It is the evidence base for every later decision, and it is the thing we will
audit you against. Reciting marketing copy from a README is not recon. Reading the code is
recon.

### §2.1 Read the two cloned reference implementations, in this order

Both are already in this working tree. Do not re-clone them. Do not summarize their
marketing. Open the files and describe what the code does.

**Reference A — `./openai-cua-sample-app` (the code-first browser path):**

1. `README.md` — the framing paragraph and the two-agent split (JavaScript/Playwright =
browser, Python/PyAutoGUI = desktop screenshots).
2. `javascript-app/src/responses-loop.ts` — `buildCodeToolDefinitions()`,
`executeJavaScriptToolCall()`, `classifyResponse()`, `runResponsesCodeLoop()`. Record:
the tool count (one), the schema (`code` only, `additionalProperties: false`), the turn
budget, `parallel_tool_calls`, and what is returned to the model after code runs.
3. `javascript-app/src/javascript-worker.ts` — `createRepl()`, `execute()`, the `busy`
flag, the `outputs`/`outputBytes` accounting, `close()`. Record: what globals the sandbox
exposes, how output is produced, how output is capped, how a second concurrent request is
handled.
4. `javascript-app/src/browser/protocol.ts` — `WorkerOperation`, `JavaScriptOutput`,
`maxCodeBytes`, `maxOutputBytes`, `parseJavaScriptOutput()`. Record: the exact operation
vocabulary (`initialize` / `execute` / `inspect` / `capture` / `close`) and every limit.
5. `javascript-app/src/browser/javascript-process.ts` — `launchJavaScriptSession()`,
`request()`, `close()`. Record: the parent-side watchdog, the 250 ms graceful-then-`SIGKILL`
sequence, the browser-server close timeout, the stderr ring buffer, the environment
scrubbing, and the protocol-violation failure codes.
6. `javascript-app/src/backend-lease.ts` — the exclusive coordination port and the refusal
message.
7. `contracts/index.ts` — `RunEvent`, `BrowserScreenshotArtifact.source`
(`browser_preview` | `code_tool`), `BrowserState`, `ReplayBundle` v3, `BackendCapabilities`
(`codeTool: "exec_js"`), `runnerErrorResponseSchema` (code + error + hint).
8. `javascript-app/src/runner-manager.ts` and `javascript-app/src/scenario-runtime.ts` —
run lifecycle, artifact persistence, workspace-per-run preparation, and how
`syncBrowserState` / `captureScreenshot` are used *outside* the model's context.
9. `labs/` — `catalog.json` and the three lab templates. Record what a "lab" is and why
each run gets a fresh copy (workspace isolation per run).

For each file, answer in the recon artifact: *what is the model allowed to decide, what is
the harness deciding for it, and which of those decisions is a hard limit?*

**Reference B — `./claude-quickstarts` (both the mechanism and the anti-pattern):**

1. `browser-use-demo/browser_use_demo/browser_tool_utils/browser_dom_script.js` — the
accessibility-tree walk, `ref_N` assignment, `WeakRef` map, YAML emission, stale-ref cleanup.
2. `browser-use-demo/browser_use_demo/browser_tool_utils/browser_element_script.js` — element
resolution and interaction from a `ref` (and the coordinate fallback).
3. `browser-use-demo/browser_use_demo/tools/browser.py` — the full action vocabulary and the
`ref` parameter semantics; note which actions still return screenshots and how `zoom` is
used to read small text without a second model turn.
4. `browser-use-demo/CHANGELOG.md` — the provenance log (Playwright `ariaSnapshot.ts`
adaptation; the `execute_js` action; the coordinate-scaling caveat).
5. `computer-use-demo/computer_use_demo/loop.py:142` and `:244` —
`_maybe_filter_to_n_most_recent_images`. Quote the docstring in the recon artifact and state
in one sentence why the loop that requires it is forbidden here.
6. `browser-use-demo/browser_use_demo/loop.py:176` — the same helper in the browser demo.
7. `computer-use-best-practices/computer_use/tools/batch.py` — `browser_batch`,
`computer_batch`, stop-on-first-error semantics, label-interleaved results.
8. `computer-use-best-practices/computer_use/tools/result.py` — `ToolResult`, `is_error`,
`IMAGE_OMITTED_ON_ERROR`, `image_block`.
9. `computer-use-best-practices/computer_use/tools/browser.py` — `_ACTIONS`, the input schema,
`ToolResult` usage, `_to_playwright_chord`.
10. `computer-use-best-practices/constants.py:411` — `BATCH_REMINDER`,
`BATCH_REMINDER_ACTIONS`; and the README's statements about specification discipline, batch
latency/cost, and the VM warning.
11. `computer-use-best-practices/computer_use/image.py` — the reference resize and why
coordinate agreement depends on it.
12. `claude-quickstarts/agents/tools/code_execution.py` — a smaller code-execution tool
implementation for comparison.

### §2.2 Read our own repository surfaces before proposing anything

You MUST enumerate, from the code and not from memory, at minimum:

1. Every method in `Sources/AgentProtocol/AgentMessages.swift` (`AgentMethod`). Note which
ones are page-level, context-level, session-level, fleet-level, lease-level, handoff-level,
approval-level, credential-level, execution-level, and event-level. Note which are missing
relative to §6.
2. The exec program model: `Sources/AgentProtocol/AgentExec.swift` and
`Sources/BrowserEngine/AgentExecRuntime.swift`. Record the step vocabulary, the limits
(`ExecLimits`), the outcome shape, the error/status semantics, and how cancellation,
timeouts and lease revocation are enforced.
3. The event pipeline: `Sources/BrowserEvents/BrowserEvent.swift`,
`BrowserEventBus.swift`, and the producers under `Sources/EngineRuntime/WebKit/`. Record the
families, the clock, the identity fields, the journal bound, the subscriber buffer policy,
the drop accounting, and every producer that requires a window to exist.
4. The runtime: `Sources/EngineRuntime/BrowserRuntime.swift` and its extensions
(`+Branches`, `+WorkspaceLeases`), plus `WorkspaceLeases.swift`, `BranchTypes.swift`,
`TaskVerification.swift`, and `Handoff/HandoffCenter.swift`. Record which parts are
per-context, which are process-global, and which are stored on disk.
5. Isolation and identity: profiles (`Persistence/ProfileStore.swift`), website data stores
(`WebKit/SystemWebRuntime.swift` `WebKitStoreCache`), ephemeral stores, cookies
(`WebKit/WebCookieStorage.swift`), storage partitions, and the credential vault
(`CredentialVault.swift`, `CredentialSecrets.swift`).
6. Extensions: how `WKWebExtension*` is wired (`WebKitPage.swift` constructs a
`WebKitContext` whose extension controller comes from `AetherWebExtensionRegistry`). Record
whether an agent can enumerate, enable, disable, or invoke an extension, and where the gap
is.
7. The delegation surfaces: `Sources/browserd/main.swift`, `Sources/browserctl/main.swift`,
`Sources/AgentMCP/AgentMCPServer.swift`, `Sources/aether-mcp/main.swift`. Record which
business logic lives in each and prove (by reading) which of them contains none of its own.
8. The current agent-facing instructions and docs: `AGENTS.md`, `Docs/AGENT_PROTOCOL.md`,
`Docs/AGENT_VERIFICATION_AND_MCP.md`, and the reports under
`agents/agent-native-browser-runtime/`.

### §2.3 The recon artifact must contain

```markdown
# Code-first browser recon

## 1. Reference A (openai-cua-sample-app) — what the browser code path does
## 2. Reference B (claude-quickstarts) — mechanism vs anti-pattern, with file:line quotes
## 3. Current Aether surface inventory (method-by-method, exec-op-by-exec-op)
## 4. Gap table: capability | exists? | file | missing piece | owner
## 5. Inefficiency table: hot path | current cost | measured or suspected | instrument to add
## 6. Isolation table: resource | isolation mechanism today | violation path | enforcement
## 7. Scale table: resource | current per-workspace cost | bottleneck at 1k | at 100k
## 8. Conflicts between this document and the code (if any) — STOP AND REPORT
```

Rules for the recon artifact: no adjectives without a number; no claim without a
`path` or `path:line`; no "probably"; if you did not verify it, label it
`UNVERIFIED — hypothesis` and add the exact experiment that would verify it.

### §2.4 Phase 0 stop conditions

You MUST stop and report to the user, without writing implementation code, if any of the
following is true:

1. A requirement in this document contradicts what the code actually does and you cannot
satisfy both.
2. An existing subsystem already implements a required capability better than this document
assumes (for example, a page-state extractor that is genuinely structured and text-based).
Say so, name it, and propose using it instead of rebuilding.
3. A required capability is impossible with the WebKit API surface available at the minimum
supported macOS version. Name the API, the version, and the alternative.
4. You cannot measure something this document requires you to measure. Say what is missing
and what you need (an instrument, a harness, hardware, or a decision).

Do **not** stop to ask permission for ordinary engineering decisions. Stop only for the four
cases above.

---

## §3 — GROUND TRUTH ABOUT THIS REPOSITORY

This section states the constraints we have verified in this tree. Treat it as the physical
reality you are designing against. Verify each item during Phase 0; if one is wrong, say so.

### §3.1 Aether is WebKit-based. There is no CDP.

Aether's rendering is WebKit / `WKWebView`. Everything above rendering is ours. Consequences:

1. **Do not import Chromium tooling.** `puppeteer`, `playwright` (the Chromium transport),
`chrome-remote-interface`, or any CDP client is forbidden in the agent control path.
2. **Do not attempt to speak CDP to `WKWebView`.** It will not answer. There is no
`Accessibility.getFullAXTree`, no `Runtime.evaluate`, no `Network.enable` on the other end.
3. **Do not assume a 1:1 mapping** from a CDP domain to a WebKit API. Some capabilities have
native equivalents (navigation lifecycle, cookies, downloads, snapshots); some are built by
injecting script (structured page state, `fetch`/XHR observation); one is built by routing
traffic through a local proxy (§7).
4. **Reference material may be used for design only.** You may read Playwright's
testimonial-level ideas (locator semantics, aria snapshot shape, auto-waiting) and reimplement
them; you may not link Playwright's browser transport.

### §3.2 What already exists (verified in this tree)

Do not rebuild these. Read them, extend them, and keep the single-source-of-truth rule
(§13).

- **One state owner.** `BrowserRuntime` is an actor in `Sources/EngineRuntime/` and every
browser mutation goes through it. There is exactly one automation path today. That is the
architecture; preserve it. A second path that reaches WebKit directly is a defect.
- **A typed wire protocol.** `Sources/AgentProtocol/` defines `AgentMethod` (100+ cases),
`AgentRequest`/`AgentResponse`, `AgentProcedure` free of transport details, and the
`agent.exec` typed input/output (`AgentExec.Input` / `ExecOutcome`).
- **A local execution runtime.** `Sources/BrowserEngine/AgentExecRuntime.swift` executes a JSON
step program inside one invocation, with `ExecLimits` (`programVersion`, `maxSteps` 1,000,
`maxExecutedSteps` 100,000, `maxItems` 10,000, `defaultTimeoutMs` 30,000,
`maxTimeoutMs` 300,000, `maxSnapshotLimit` 100,000), `ExecOnError.stop | .proceed`,
`ExecStatus.completed | .failed | .timeout | .cancelled`, `ExecFailure` with step path/op/code,
and lease-revocation abort (`error.code == "leaseRevoked"`).
- **A first-class event system.** `Sources/BrowserEvents/` with `BrowserEventBus` (bounded
journal, `recentEvents` with `since:` catch-up, bounded subscriber buffers, drop accounting)
and real producers for navigation, page, context, branch, console, network, download, popup,
dialog, permission, authentication, file-chooser, focus, document mutation, handoff,
execution, and lease families.
- **Workspace leases.** `Sources/EngineRuntime/WorkspaceLeases.swift` and
`BrowserRuntime+WorkspaceLeases.swift`: acquire/renew/release/cancel/list, states
`active | released | cancelled | expired | recoverable`, a runtime id for restart recovery,
checkpoint-and-freeze on suspension, and a lease-bound-work registry that revokes in-flight
executions when a lease ends.
- **Branchable contexts.** `BatchTypes`/`BranchTypes.swift` and `BrowserRuntime+Branches.swift`:
checkpoint, fork, tree enumeration, deletion, cookie cloning into the destination WebKit store,
an explicit `restoreRequiredPages` contract, and honest `notClonedState`.
- **Deterministic verification.** `TaskVerification.swift` + `Sources/BrowserVerification/`:
plan-driven checks returning `verified | failed | inconclusive`, never optimistic success.
- **Human handoff and approval.** `Handoff/HandoffCenter.swift` and the `handoff.*` /
`approval.*` protocol methods, including a fail-closed gate (`handoff_active`) that blocks
agent operations on a parked page.
- **Credentials.** `CredentialVault.swift`, `CredentialSecrets.swift`, and
`credentials.*` protocol methods.
- **Delegating surfaces.** `browserd` (daemon), `browserctl` (CLI), `aether-mcp`/`AgentMCP`
(MCP) — all of which MUST remain thin delegates into the same runtime (§13).
- **A real test discipline.** `Tests/` runs against real WebKit; the repository's full suite is
expected to pass, and it is expected to grow regression tests for every fix.

### §3.3 What does not exist yet, and must (the actual work)

1. No engine-level structured page-state channel (a11y/ref snapshot) as a first-class
primitive. `page.snapshot` exists but is a node listing, not an addressable, stable-reference
interactive snapshot with a compact text form designed for a model.
2. No single code-execution session that lives *across* model turns with persistent user
state, exposed to the model as the primary tool. `agent.exec` executes one program per call.
3. No per-subresource network observation. Response/request events are navigation-level.
4. No traffic-level network observation (§7 layer 2).
5. No extension control surface for agents (enumerate/enable/disable/invoke).
6. No browse-level parity for several human capabilities (see §6 for the table).
7. No fleet scheduler above leases: leases exist per context, but nothing owns admission
control, quotas, fairness, warm pools, or capacity accounting across workspaces.
8. No scale instrumentation: no per-workspace memory accounting, no throughput harness, no
saturation curve, no documented failure point.

---

## §4 — THE TARGET ARCHITECTURE

```
┌───────────────────────────────────────────────────────────────────────────┐
│ DRIVER (any model: frontier hosted, local, or an automated SDK client)    │
│ Writes programs. Does not pick from an action menu. Does not look at       │
│ pixels to decide where a button is.                                        │
└───────────────┬───────────────────────────────────────────────────────────┘
                │  ONE primary tool: exec(program)   →  ONE result
                ▼
┌───────────────────────────────────────────────────────────────────────────┐
│ CODE EXECUTION SESSION (persistent, per lease/workspace)                  │
│  - state survives across calls (vars, handles, refs, snapshots)            │
│  - loops, branches, retries, assertions happen INSIDE the session          │
│  - hard limits: program size, executed ops, wall clock, output bytes       │
│  - cancel/timeout/revoke enforced by the HOST, never by the sandbox         │
└───────────────┬───────────────────────────────────────────────────────────┘
                │  calls the runtime's typed operations (in-process, batched)
                ▼
┌───────────────────────────────────────────────────────────────────────────┐
│ AETHER RUNTIME (BrowserRuntime — the single state owner)                  │
│                                                                           │
│  TIER 1  structured page state: a11y/DOM snapshot + stable refs (PRIMARY)  │
│  TIER 2  raw capability: runtime.evaluate, shadow DOM, storage, cookies,   │
│          network, console, downloads, permissions, extensions, tabs        │
│  TIER 3  pixels: takeSnapshot — a first-class option a program may request  │
│          at any time; cost-ranked, budgeted, never automatic               │
│                                                                           │
│  EVENTS: bounded, ordered, identity-carrying, drop-accounted              │
│  LEASES: admission, confinement, revocation, recovery                     │
│  VERIFY: plan-driven checks against real state (never the transcript)      │
└───────────────┬───────────────────────────────────────────────────────────┘
                ▼
┌───────────────────────────────────────────────────────────────────────────┐
│ WKWebView / WebKit processes / local proxy / website data stores          │
│ (Isolated per lease. Reaped by the host. Never leaked.)                    │
└───────────────────────────────────────────────────────────────────────────┘
```

### §4.0 The option ledger — no channel is forbidden, every channel is priced

There are four ways to learn something about a page and three ways to act on it. **None of
them is forbidden. All of them are available to the driver at all times.** What the runtime
owes the driver is honest pricing, so the driver ranks the channels on declared cost instead
of habit — and what the runtime MUST NOT do is delete a channel, hide it behind a mode
switch, or refuse to serve it because some other channel could have answered the question.

| Channel | What it answers | Its real cost | The right answer when |
|---|---|---|---|
| **Structured snapshot** (§4.1) | what exists, what it is, where it is, what state it is in | O(elements) serialization, bounded; no vision tokens | DOM content: forms, links, lists, tables, text, controls |
| **Raw capability** (§4.2) | anything the snapshot omits: closed shadow roots, computed style, storage, network, console | one evaluate, bounded bytes; no vision tokens | the snapshot could not see it, or the question is about state it does not model |
| **Screenshot** (§4.3) | how it actually looks, and anything with no DOM form | render + encode + vision tokens; bounded by image budget | canvas/WebGL/video; obfuscated or image-based UI; layout and visual verification; reading text the snapshot could not resolve; **and any step where the driver judges the image to be its cheapest trustworthy evidence** |
| **Coordinate action** (§4.4) | how to hit something with no resolvable reference | one counted coordinate action; fragile under reflow | content with no resolvable reference at all — canvas hit-testing, image maps |

The fourth row is not a moral failing and the third row is not a compromise. They are options
with prices. The only thing this document removes is the choice being made **for** the driver.

REQUIREMENTS:

1. Every channel MUST be reachable **from inside a program**. No channel may be gated behind an
operator flag, a mode switch, a capability negotiation that can be declined, or a path that
only activates when a higher-priority channel fails.
2. The runtime MUST expose the **cost ledger**: a driver can ask what each channel would cost
for the current page — element count and snapshot bytes, whether an image would require a
re-render, current image budget state — and then choose deliberately. Ranking without prices
is guesswork, and guesswork is what produced the loop this document exists to delete.
3. The runtime MUST NOT mark any channel "fallback only", MUST NOT refuse a screenshot because
structured state was available, and MUST NOT record a channel's use as a defect. Use is not
misuse; automaticity is.
4. **The single forbidden thing is automatic injection.** An image placed into a driver's
context without the program asking for it, once per step, is a defect. An image the program
asked for is not, no matter how often it asks, as long as it stays inside its budget.
5. The budgets are the price mechanism, not a prohibition. When an image budget is exhausted
the runtime returns a typed refusal naming the exhausted dimension, and the driver may
re-plan, request a larger budget, or use another channel. It MUST NOT be told that a channel
does not exist.

### §4.1 Tier 1 — structured page state is the default read channel

REQUIREMENTS:

1. Provide a **single operation** that returns a compact, text-first snapshot of the current
page containing, for every interactive or semantically meaningful element: a stable
reference, role, accessible name, current value, state (visible/enabled/checked/selected/
required/readonly), viewport-relative position and size in CSS pixels, and a bounded text
snippet. This is a native capability of the runtime, not a per-caller script.
2. References MUST be stable across operations within a snapshot generation, MUST resolve to
the live element, and MUST fail loudly with a typed error when the element is gone or has been
replaced. Silent resolution to a different element is FORBIDDEN. This is the single most
important correctness property of the whole tier: acting on a stale reference must never
click the wrong thing.
3. The snapshot MUST be **differences-friendly**: snapshots carry a generation id, and a
caller can ask for only what changed since a generation. A page that is stable must not cost
a full re-read every step.
4. The snapshot MUST be **bounded**: a hard element cap per snapshot, deterministic truncation
rule, a total byte cap, and an explicit `truncated: true` flag with the count of omitted
elements. Never silently drop.
5. The snapshot MUST include enough state that a driver can decide and act **without** a
second call for the common cases: fill this field, click this control, read this text,
select this option, submit this form.
6. The snapshot MUST describe **frames**: main frame plus iframes, each with a frame id, and
references scoped so that an action targets the correct frame without the caller managing it.
7. The snapshot MUST be produced without a `WKWebView` window existing. Any part of it that
requires a window is a defect; the repo already runs windowless pages in its test suites and
the control path must work the same way.
8. The snapshot MUST NOT include images, base64, or style dumps by default. If a caller wants
computed styles, they ask for computed styles for specific refs.

FORBIDDEN in Tier 1: screenshot-first design, coordinate-only targets, unbounded element
lists, non-deterministic ordering (sorting must be stable and documented), and any snapshot
that silently omits elements.

### §4.2 Tier 2 — raw capability is the escape hatch

REQUIREMENTS:

1. Expose the runtime's real capability set through typed operations available inside the
execution session: arbitrary script evaluation in a page context; DOM queries beyond what the
snapshot exposes; closed shadow-root traversal; computed style reads; storage reads/writes for
cookies, `localStorage`, `sessionStorage` where available, and IndexedDB where feasible;
network request/response visibility; console capture; downloads; permissions; clipboard;
find-in-page; zoom; history; bookmarks; tab/window operations; profiles; extensions.
2. Every Tier 2 operation MUST be reachable **from inside a program**, not only as a
standalone wire method. A driver that must call out of its program to do something is a
driver whose program is not a program.
3. Every Tier 2 operation MUST return a typed result or a typed error. Strings of prose are
not results. "ok" is not a result.
4. Raw script evaluation MUST be sandboxed per §11, MUST be observable (§7), and MUST NOT be
able to read secrets (§11.3).

### §4.3 Tier 3 — pixels: a first-class option, priced, never automatic

This tier is not a fallback. It is an option with an honest price, and it is available to the
driver from the first step to the last. Anthropic and OpenAI both kept a screenshot capability
in their new code-first toolsets for the same reason: some questions have no text answer, and
sometimes the cheapest trustworthy evidence really is an image.

REQUIREMENTS:

1. A screenshot is produced whenever a program requests one. It is NEVER produced automatically
as part of a step, and it is NEVER withheld because another channel could have answered the
question. A refusal of a requested screenshot is a defect.
2. When an image is produced, it carries structured metadata: page identity, frame, viewport,
device scale, scroll offsets, capture time, and the snapshot generation it belongs to. This is
what `image.py` in the reference implements; we keep the discipline because an image without
its coordinate frame is a trap.
3. Image bytes returned into a model context MUST be bounded by an explicit budget (count per
session, bytes per session, and bytes per program) that the host enforces and reports.
4. The driver decides when an image is worth its price. Permitted uses explicitly include, and
are not limited to: canvas/WebGL/video content with no DOM representation; obfuscated or
image-based UI; visual verification that something rendered as expected; reading text or state
the snapshot could not resolve on a given page; and any step where the driver judges the image
to be its most reliable evidence. The runtime MUST NOT override that judgement, MUST NOT
require a justification, and MUST NOT re-label the use as a violation. What is forbidden is
producing an image **nobody asked for**.
5. Tier 3 MUST NOT be the mechanism by which a driver locates a DOM element that has a
resolvable reference. If a driver computes a coordinate from an image to click a DOM element
whose reference it already holds, that is a defect in the driver's program: fix the program,
not the click. (Reading a coordinate off an image for canvas/WebGL hit-testing is Tier 3 doing
its job, and is counted as a coordinate action per §4.4 — counted, not banned.)

### §4.4 The tier discipline is enforced, not aspirational

REQUIREMENTS:

1. The runtime MUST expose counters for tier usage per workspace and per program:
snapshot calls, tier-2 calls, images produced, images returned to a driver, bytes of image
produced, coordinate-based actions taken.
2. `coordinate-based actions on an element that has a resolvable reference` MUST be reported
as a **violation metric**. It is not required to be zero on day one, but it MUST be
measured, trended, and driven to zero on DOM content.
3. Automated tests MUST assert that a scripted, DOM-only workflow produces **zero images it
did not ask for** and **zero** coordinate actions while completing the task. The assertion is
about automaticity, not about images; a suite that also asks for one image and gets exactly
one is the companion assertion, and MUST exist.

---

## §5 — THE EXECUTION SESSION CONTRACT

This chapter replaces the action menu. Every requirement below is derived from the verified
reference in §1.1 and hardened for the scale required in §9. If you implement only one thing
from this document, implement this, correctly.

### §5.1 One persistent session per lease, surviving driver turns

REQUIREMENTS:

1. A workspace lease owns an execution session. The session outlives individual driver turns
and is keyed by (session id, lease id, workspace id), never by a connection or a socket.
2. State written by a program persists into the next program in the same session: variables,
accumulated collections, handles to pages and contexts, the last snapshot generation, and
login/identity context. The reference does this with a persistent REPL context; the semantic
requirement is what matters, not the mechanism.
3. Session state MUST be bounded and accounted for: total bytes retained, number of live
handles, number of retained snapshots. A session that grows without limit is a leak and MUST
be reported by the runtime as such.
4. Session state MUST be destroyable in constant time and MUST be destroyed on lease release,
lease revocation, lease expiry, workspace teardown, and daemon shutdown. Destruction MUST
free memory, close pages, release WebKit stores, and unregister from the lease registry.
5. A session MUST be recoverable after a daemon restart **only** in the documented form: the
lease becomes recoverable, the workspace is re-attached from its profile, and the session is
rebuilt with **no** in-memory state. Do not pretend to restore a live heap. Report the
limitation in the API.

### §5.2 One entry point: a program, not a step

REQUIREMENTS:

1. The driver's primary and default interaction is: submit a program, receive one structured
outcome. Everything else is secondary.
2. A program MUST be able to: read structured state, act on references, navigate, wait on
real conditions, query, evaluate script, read network/console evidence, write storage,
upload, download, switch tabs, and call verification -- all inside one submission.
3. A program MUST support control flow natively: variables, conditionals, loops over
collections, early termination, and per-step error policies. Loops over hundreds of elements
MUST NOT produce hundreds of host round trips.
4. The runtime MUST NOT require the driver to know a page before writing the program. Reading
state and acting on what was read MUST both be expressible in the same program.
5. Programs MUST be deterministic in the abstract: the same program against the same page
state MUST produce the same sequence of runtime operations. Any nondeterminism (timing,
ordering, scheduling) MUST be an explicit, named option, not an accident.

### §5.3 Limits are mandatory, global, and reported

Every limit below MUST exist, MUST be enforced by the host (not by the program), MUST be
returned in the outcome when hit, and MUST NOT be silently softened:

1. Program size (declared bytes and declared steps). The reference caps code at 64 KiB; pick a
number, enforce it, and document it.
2. Executed operations (a hard ceiling on browser-touching steps, counted by the runtime).
3. Items per collection operation, with over-limit reported as an error, never truncation.
4. Wall-clock deadline per program, enforced by a watchdog outside the program.
5. Output size returned to the driver, with over-limit reported as an error and the partial
result retained in the session for inspection.
6. Per-step wait timeouts, with `wait` failures distinguishable from navigation failures.
7. Concurrent programs per session and per workspace (default 1; if greater than 1 is
allowed, isolation of shared state MUST be specified).
8. Image budget per session (count and bytes) as in §4.3.
9. Total session memory, enforced by eviction policy, not by hope.

### §5.4 Cancellation, timeout, revocation, and crash

REQUIREMENTS:

1. Cancellation MUST be enforced by the host and MUST interrupt a program at the next
operation boundary **and** abort any in-flight browser operation whose runtime supports
abort (navigation, wait, load). Latency to observe cancellation MUST be measured and
reported (percentiles), and MUST be bounded by a documented value for the common cases.
2. Timeout MUST return a typed `timeout` outcome with the partial state preserved and
inspectable. It MUST NOT be reported as a failure of the page or of the driver's logic.
3. Lease revocation MUST abort confined programs with a distinct, typed reason. A program
that loses its workspace MUST NOT continue driving the browser, MUST NOT report partial
success, and MUST NOT leak its registration.
4. Program crash (a runtime-level fault) MUST NOT take down the daemon, the session, or any
other workspace. It MUST be reported as a typed engine failure with the failing operation and
step path, and the session MUST remain usable for the next program.
5. Every terminal path (completed, failed, timeout, cancelled, revoked, engine error) MUST
publish exactly one terminal lifecycle event, MUST release all per-program resources, and MUST
be idempotent under duplicate delivery.
6. No terminal path may leave behind: a running task, a registered revocation hook, an open
page the program created but did not close *when the program was the owner*, a temp file, a
subprocess, or a WebKit store that was created solely for the program.

### §5.4.1 Ownership rules for program-created resources

1. A page or context created inside a program MUST be tracked as program-owned. On normal
completion, program-owned resources remain (the driver asked for them). On failure, timeout,
cancellation, or revocation, program-owned resources created during that program MUST be
destroyed unless the program explicitly declared them as retained.
2. Declared retention MUST be expressed in the program itself, so the behaviour is visible in
the trace and testable without guessing.

### §5.5 The outcome is evidence, not prose

REQUIREMENTS: the outcome MUST carry, at minimum:

1. Execution id (stable, unique, joinable with events).
2. Status (completed, failed, timeout, cancelled, revoked, engine_error) as a typed enum.
3. The driver-visible results, in order, with their types preserved.
4. The final session variable set needed to continue the next program (or a bounded summary
with an explicit truncation flag).
5. Counters: steps executed, browser operations, waits, snapshots taken, images produced,
network requests observed, verification checks run.
6. Per-step failures, each with step path, operation, typed code, and a bounded message.
7. A terminal error object when applicable, with the same fields as a step failure.
8. `truncated` flags wherever a cap was applied, and the cap that applied.

FORBIDDEN: an outcome whose only success signal is the absence of an error; an outcome whose
results are hidden in a log; an outcome that cannot tell the driver why it stopped.

### §5.6 The program is the batching primitive

1. The default driver behaviour MUST be one program per task phase, not one program per
click. The harness MUST NOT need to remind the model to batch (recall the reference's
`BATCH_REMINDER` at `computer-use-best-practices/constants.py:411` -- that reminder exists
only because their primitive is still per-action; ours is per-program, so the equivalent
nudge is unnecessary).
2. The runtime MUST report a batching metric per workspace: operations per program, and
programs per completed task, with a target band. A drift upward is a regression and MUST be
treated as one.
3. Nothing about the driver's transport may force a round trip that the program could have
absorbed. If a required capability can only be invoked from outside a program (as a wire
method), that is a §4.2 violation and MUST be fixed by making it program-callable.

---

## §6 — HUMAN PARITY: THE AGENT MUST DO EVERYTHING A HUMAN CAN DO

This chapter is a checklist, not a paragraph. For every capability below you MUST answer:
*does a code-callable equivalent exist, where, and what is the acceptance test?* A capability
with no equivalent is a defect you fix in this work. A capability with an equivalent that is
only reachable outside a program is a §4.2 defect. A capability with an equivalent that
leaks across workspaces is a §11 defect.

### §6.1 Navigation and orientation

| Capability | Requirement | Acceptance |
| --- | --- | --- |
| Open a URL in a tab | program-callable, returns a typed navigation outcome | real loopback page loads; url/title/status observable |
| Back / forward | program-callable, honours real history | navigation is reflected in the event journal in order |
| Reload, hard reload | program-callable, distinguishes cache behaviour | hard reload re-requests the document |
| Stop loading | program-callable, aborts in-flight work | wait/navigation returns a typed abort, not a hang |
| Redirect chain | observable as data, not inferred | redirect events carry each hop |
| Load state | synchronously queryable: loading or settled | ready/complete wait is event-driven |
| Scroll position and viewport size | synchronously queryable; scroll operations program-callable | position read back matches what was set |
| History and history index | queryable and navigable | index moves with navigation |
| Find in page | program-callable, returns matches with positions | match count and refs for real text |
| Zoom in/out and text zoom | program-callable and queryable | zoom factor round-trips |
| Print to PDF | program-callable, returns a real artifact path | artefact exists and opens |

### §6.2 Reading and acting on a page

| Capability | Requirement | Acceptance |
| --- | --- | --- |
| Structured page state | Tier 1 snapshot with refs, states, frames (§4.1) | snapshot on a real form returns refs for every field |
| Act on a reference | click, focus, fill, set value, select option, check/uncheck, drag, hover | each action verifies the resulting state, not the gesture |
| Form submission | program-callable, returns the outcome of the submission | verified by resulting URL/DOM/network, not by absence of error |
| Text entry with real key semantics | typing and key presses as distinct operations | key events observable in the page |
| Text extraction | full-page text and per-element text, bounded | equals the rendered text for a known fixture |
| Element queries beyond the snapshot | selector and semantic queries inside a program | returns refs, not coordinates |
| Shadow DOM (open and closed) | reachable through Tier 2 | a closed shadow root control is drivable |
| Frame and iframe targeting | refs scoped to frames; actions target correctly | action inside an iframe affects the iframe only |
| Dialogs (alert/confirm/prompt) | observable as events, resolvable programmatically | a real dialog is answered and the page proceeds |
| File upload | program-callable with a path, no OS dialog | the upload reaches the server with the given bytes |
| Downloads | program-callable, observable lifecycle, real path, verified bytes | downloaded file exists, size and hash match |
| Clipboard read/write | program-callable and permissioned | round-trips through the clipboard |
| Context menus and hover-revealed UI | drivable through actions and hover | hover states are reachable without screenshots |

### §6.3 Tabs, windows, and sessions

| Capability | Requirement | Acceptance |
| --- | --- | --- |
| Create, close, list, select tabs | program-callable | tab set matches after operations |
| Move tabs, multiple windows | program-callable where implemented for humans | model matches the human UI state |
| Per-tab identity | page id, frame id, context id, tab index all synchronously queryable | identities stable across operations |
| Multiple pages in one context | program-callable, isolated | navigation in one page does not disturb the other |
| Session restore | same semantics as human session restore | reopened session has the same URLs and history |

### §6.4 Identity, storage, and secrets

| Capability | Requirement | Acceptance |
| --- | --- | --- |
| Profiles | create, open, list, use, isolate | two profiles never share cookies or storage |
| Ephemeral browsing | create and tear down without touching disk | no persisted state after teardown |
| Cookies | read, set, remove, clear, scoped by store | cookie set in one workspace is invisible in another |
| local and session storage | read, write, remove, clear | write is readable back on the same origin only |
| IndexedDB and caches | observable and clearable where feasible; honest about gaps | a clearing operation reports what it cleared |
| Credential injection | performed at the engine or transport boundary, never by page script | a test proves script cannot read the injected secret |
| Password-authenticated login | program-callable end to end against a real fixture | the session becomes authenticated and stays so |
| Permission prompts | observable as events, programmatically grantable or deniable, never auto-approved silently | a permission decision is explicit and audited |
| Client certificates, proxy auth | supported where the engine supports it; honest about gaps | explicit typed failure when unsupported |

### §6.5 Browser features a human has

| Capability | Requirement | Acceptance |
| --- | --- | --- |
| Extensions | enumerate, enable, disable, inspect state, invoke exposed actions | an extension in the store is controllable by the agent |
| Content blocking | observable and testable effects | a blocked request is absent from evidence |
| Search provider and omnibox-style suggestions | program-callable | suggestions come from the real provider path |
| Bookmarks | list, add, remove | persisted across restart |
| Reading view or reader mode, if present | program-callable | content extraction equals expected text |
| Media playback control | program-callable and observable | play, pause, seek, volume, mute round-trip |
| Notifications and popups | observable as events, program-callable handling | popup create and close are evented |
| Captures (screenshot, full-page, region, PDF) | program-callable, budgeted, with metadata | artefact verified byte-wise and dimension-wise |
| Devtools-grade inspection | console log, network log, DOM inspection, accessible-tree inspection | evidence is queryable per workspace |

### §6.6 Observability a human gets from the UI

1. A human can see the URL, title, favicon-ish identity, loading progress, and errors. The
agent MUST be able to read all of those as typed fields.
2. A human can open a network panel and see request/response, status, timing, and sizes. The
agent MUST have an equivalent (§7).
3. A human can open a console and read errors. The agent MUST have a bounded, ordered console
stream that survives under spam (§9.6).
4. A human can see a permission prompt and decide. The agent MUST see the request as an event
and produce an explicit decision.

### §6.7 Parity audit procedure

1. Enumerate the human-facing feature list from the product, in the repository, not from
memory. For each entry, record the agent-callable equivalent or record it as missing.
2. For every missing entry, add it. For every entry that exists only as a wire method, expose
it inside programs. For every entry that exists but cannot be verified, add the acceptance
test.
3. The parity table MUST be committed as documentation with the acceptance test name for each
row. An empty acceptance column is an incomplete row.

---

## §7 — NETWORK VISIBILITY: TWO LAYERS, BOTH REQUIRED

Most verification questions a browser agent has are network questions: did the request go
out, what came back, was it a 200, was there a duplicate submit, did the redirect chain end
where we expected, did the upload actually carry the bytes. Today our evidence is
navigation-level. That is not enough.

### §7.1 The constraint, stated honestly

1. `WKWebView` provides no general, public interception point for `fetch` and `XMLHttpRequest`
issued by page script. There is no CDP `Network` domain to enable.
2. `WKURLSchemeHandler` only handles custom schemes, not `http` and `https`. It is not a path
to visibility on real pages.
3. Therefore: same-origin script-initiated traffic can be observed by injecting an observer;
comprehensive traffic needs the traffic itself routed through something we own.

Do not paper over this. Both layers below are REQUIRED, and the gap between them MUST be
documented in the API surface so a caller knows which evidence it is holding.

### §7.2 Layer 1 — in-page observation (fast, same-origin, always on)

REQUIREMENTS:

1. Inject an observer at document start in every frame, before page script can run, so a page
cannot dodge it.
2. The observer MUST capture, per request: method, URL, request body size and a bounded body
snippet for form-encoded and JSON bodies, headers of interest, start time, end time,
status, response size, and a bounded response snippet where safe.
3. The observer MUST feed the event system as first-class network events, with the same
identity discipline as every other event (§9.6): workspace, context, page, frame, sequence,
monotonic time.
4. The observer MUST be robust to page interference: if a page replaces the observed globals,
the runtime MUST detect it and report degraded observation rather than silently losing
evidence.
5. Redaction is mandatory: authorization headers, cookies, tokens, and password-like fields
MUST be redacted by default with a documented opt-in to see them that is itself audited. A
log that can leak a session token is a defect, not a feature.
6. Layer 1 MUST NOT alter page behaviour in an observable way: no added globals that break
feature detection, no altered timing beyond a documented bound, no changed response objects
that a page could detect as different from the real ones. Prove this with a test that a real
page's feature detection and a fingerprint-check fixture still see ordinary values.

### §7.3 Layer 2 — traffic-level observation through a local proxy (ground truth)

REQUIREMENTS:

1. The runtime MUST be able to route a workspace's traffic through a local proxy it owns,
configured per website data store, so that every request and response -- every subresource,
every frame, every redirect, every upload, cacheable or not -- is observable.
2. This layer is the ground truth for verification. When Layer 1 and Layer 2 disagree, Layer 2
wins and the disagreement is recorded as evidence.
3. The proxy MUST be per-workspace or per-lease-grouped and MUST NOT be a fleet-wide single
point of failure. Its lifecycle MUST be owned by the lease: created on acquisition, destroyed
on release or expiry, reaped on daemon restart.
4. The proxy MUST NOT be a bottleneck: it must stream, not buffer whole bodies in memory by
default, and it MUST have a byte budget per workspace with an explicit, counted drop policy
beyond it.
5. Certificate handling for HTTPS inspection MUST be explicit and auditable: per-workspace
root material, no fleet-wide trust anchor, and a documented failure mode when a site pins
certificates. A pinned site MUST produce a typed, visible limitation, not a silent pass.
6. Traffic capture MUST be bounded: retention window, per-workspace byte cap, and a counting
summary for what was evicted.
7. The proxy MUST expose its own health: bytes in/out, active connections, evictions, and
pin failures per workspace, so that a workspace whose evidence is incomplete is visible as
such.

### §7.4 Network evidence must be queryable as data

REQUIREMENTS:

1. A program MUST be able to ask: give me all requests for this page since this time, filter
by URL pattern, method, status class, or resource type; give me the response body for this
request as a bounded artifact; give me the timing breakdown.
2. A program MUST be able to consume network evidence **without polling**: an event-driven
wait (wait until the matching request appears, until N matching requests appear, until a
matching request completes with a status) MUST exist and MUST be bounded by a deadline that
returns a typed timeout.
3. Evidence MUST be attributable to a workspace, a context, a page, and a frame. Cross
workspace leakage of network evidence is a critical defect (§11).

### §7.5 Anti-patterns forbidden here

1. Shipping Layer 1 only and calling network visibility solved.
2. Reconstructing truth by scraping the page's own performance entries as the primary source.
Reasonable as a hint, not as evidence.
3. Unbounded body capture. Bodies are bounded, redacted, and counted.
4. Logging every request to disk for every workspace without retention limits. That is how a
fleet fills a disk and dies.

---

## §8 — VERIFICATION: NEVER TRUST THE CLAIM

This is the most under-built capability in every implementation we read, including the
reference implementations, which say so themselves. The OpenAI sample README states it
plainly: *a final answer does not prove the task succeeded*. Their console separates the run
status from the outcome for exactly this reason, and their verification inherits the same
principle: inspect the final state of the environment, not the transcript.

### §8.1 The rule

1. A task is complete when **real, external, observable state** matches the expectation, and
not before. The agent's assertion that it succeeded, the absence of an error, and the fact
that a gesture was delivered are all insufficient evidence.
2. Verification MUST be a first-class runtime primitive callable from inside a program, and
MUST be usable as the final step of a consequential task without a separate wire round trip.
3. Verification MUST be able to consume: resulting URL and load state, resulting page state
(refs and values), resulting network evidence, resulting artifacts on disk, resulting
storage and cookie state, resulting server-side state where the runtime can reach it (for
example an API the plan names), and an explicit external command or HTTP assertion when the
plan declares one.

### §8.2 The outcome domain is three-valued, and none of them is inferred

1. `verified`: every declared assertion was checked against real state and passed. Evidence
is attached: what was checked, what was observed, and when.
2. `failed`: at least one declared assertion was checked and did not hold. Evidence is
attached, including the observed value that contradicted the expectation.
3. `inconclusive`: the assertion could not be evaluated (no observation was available, the
target never appeared, the evidence layer reported degradation, the deadline expired).
`inconclusive` MUST NOT be reported as success and MUST NOT be reported as failure.

### §8.3 Assertion families that MUST exist

1. **Navigation**: destination URL matches, path matches, redirect chain contains or ends
with an expected hop, load state settled, title matches, history movement as expected.
2. **Element state**: element exists, does not exist, is visible, is hidden, is enabled, is
disabled, has a value, has text, has an attribute, is checked.
3. **Network**: a request matching a pattern occurred, did not occur, occurred exactly N
times, completed with a status class, carried a body matching a pattern, returned a body
matching a pattern.
4. **Artifacts**: a file exists at a path, has a size, has a hash, is a valid type, was
produced after a timestamp.
5. **Storage**: a cookie exists with a value shape, a storage key holds a value, a session is
authenticated according to a declared check.
6. **External state**: an HTTP request to a declared endpoint returns a declared status or
body; a declared command exits with a declared status.
7. **Visual**: an explicitly requested Tier 3 check (for example a region is not blank, a
region changed, a region matches a reference image within a declared tolerance). Visual checks
are opt-in, budgeted, and MUST NOT be the default verification mechanism for DOM questions.

### §8.4 Verification semantics that MUST hold

1. Assertions MUST be evaluated in a declared order and MUST all be evaluated unless the plan
declares fail-fast.
2. Every assertion MUST record: the plan path, the assertion kind, the expectation, the
observed value (bounded), the source of the observation (page state, network layer 1 or 2,
filesystem, external), and the timestamp.
3. Verification MUST be able to run against a workspace at a moment in time, and MUST be able
to run **after** a lease is released only if the plan explicitly declares post-release checks
against external state.
4. Verification MUST be idempotent and MUST NOT mutate the page. A verification that clicks
something to find out is not verification.
5. Verification MUST fail closed: any internal error while evaluating an assertion yields
`inconclusive`, never `verified`.
6. The runtime MUST expose a verification result as an event and as a durable record, so that
fleet-level reporting can count verified, failed and inconclusive per workspace and per task.

### §8.5 The optimistic-completion ban

1. A task record MUST NOT be markable complete without a verification result (or an explicit,
recorded waiver with a reason).
2. The runtime MUST report, per workspace and per task, the count of completions without
verification. That number is a defect metric, expected to be zero for consequential tasks.
3. Tests MUST include adversarial cases: a button that appears to submit while the server
rejects; a page that shows a success banner while no request was sent; a form that posts 200
with an error body; a download that starts and fails midway; a redirect that lands on an error
page with a 200 status. In each case the verifier MUST return `failed` or `inconclusive`,
never `verified`.

---

## §9 — EXTREME PARALLELISM: THE FLEET IS THE PRODUCT

This chapter is why the rearchitecture exists. A code-first browser agent that works for one
workspace is a demo. What we are building is a control plane in which very large numbers of
independent workspaces run concurrently, each one isolated, each one observable, each one
verifiable, none of them able to degrade the others, and every resource bounded.

A human cannot open a thousand tabs, let alone a hundred thousand, and cannot supervise them.
The fleet does. That is the entire competitive advantage, and it is an engineering property,
not a marketing claim. You will build it and you will measure it.

### §9.0 The headline requirements (all mandatory)

1. The system MUST be designed for a workspace population in the hundreds of thousands,
executing concurrently in a sharded, horizontally scalable control plane.
2. No single process, actor, lock, queue, file, port, or data store may be a global serialization
point on the hot path.
3. Every buffer MUST be bounded, every queue MUST apply backpressure, every cache MUST have an
eviction policy, every counter MUST be observable.
4. Isolation MUST be structural: another workspace's crash, runaway script, memory pressure,
or evidence burst MUST NOT corrupt or stall this workspace.
5. Throughput MUST be measured on a saturation harness, with a documented saturation point and
a documented failure mode, before any scale claim is made.
6. Cost per workspace MUST be measured at steady state (bytes and CPU) and MUST be reduced until
adding a workspace is cheap.

### §9.1 Vocabulary: what a workspace is, precisely

Define these terms in code, and use them consistently in metrics, logs and API responses:

1. **Workspace**: the unit of isolation. One workspace owns exactly one profile directory,
one website data store (or a shared store with strictly partitioned identity), one set of
cookies and storage, one secret scope, one event stream slice, one execution session, and one
network observation domain.
2. **Lease**: the time-bounded right of an agent to drive a workspace. Leases are the admission
control unit. No agent operation happens outside a lease.
3. **Session**: the persistent code-execution state bound to a lease.
4. **Shard**: a supervisor process that owns a bounded number of workspaces.
5. **Fleet**: the set of shards, addressed by a stable supervisor layer.

REQUIREMENT: the API MUST NOT let a caller act on a context without an identity that maps to a
workspace. Anonymous context access is how isolation bugs are born.

### §9.2 Shard the control plane, do not centralize it

REQUIREMENTS:

1. Introduce a supervisor layer above the runtime: a given shard owns a bounded set of
workspaces and their leases. Shard membership MUST be derivable from the workspace id so that
any node can route without a global registry lookup on the hot path, and MUST be re-derivable
after a restart.
2. The shard MUST own: admission, lease lifecycle, session lifecycle, per-workspace resource
accounting, quarantine, and reaping. Nothing else may own those things.
3. Cross-shard operations MUST be the exception, MUST be explicit in the API, and MUST NOT be
required for ordinary agent work.
4. A shard MUST be restartable independently. Restarting one shard MUST NOT restart, stall, or
invalidate leases on any other shard beyond that shard's own recovery semantics.
5. There MUST be no global in-memory registry that every operation reads. Any global view MUST
be an eventually consistent, read-mostly projection used for listing and reporting, never for
routing hot-path operations.

### §9.3 Admission control and fairness

REQUIREMENTS:

1. Admission MUST be explicit and bounded per shard: maximum live workspaces, maximum sessions,
maximum concurrent programs, maximum live pages, maximum Tier 3 images per window, maximum
proxy connections, maximum bytes of retained evidence.
2. Admission MUST be enforced before resource allocation, not after, and MUST return a typed
refusal that names the exhausted dimension. A refusal is a normal, observable outcome; a silent
overcommit is a defect.
3. Fairness MUST be defined: no tenant, task, or workspace may starve others. Long tasks MUST
not hold a global resource while waiting on a browser operation.
4. There MUST be a queue discipline with a bounded depth. When the queue is full, callers
receive backpressure (typed refusal or a bounded wait), never unbounded enqueueing.
5. Priority, if implemented, MUST be explicit, bounded, and immune to starvation. Unbounded
priority inversion is forbidden.

### §9.4 The real resource budget, per workspace

For each workspace, account and expose:

1. Resident bytes: WebKit content process share, pages, snapshots, session state, retained
evidence, retained event buffers.
2. Page counts by lifecycle state: active, background, suspended, frozen, discarded.
3. Open handles: contexts, pages, files, sockets, proxy connections, timers, registered events.
4. CPU time consumed in the last window, and queue wait time.
5. Evidence bytes retained, split by network layer.
6. Images produced and bytes of image, per window.

REQUIREMENTS:

1. Each workspace MUST have a hard cap on every dimension above. Exceeding a cap MUST trigger a
documented, observable policy: eviction, hibernation, refusal, or termination, in that order of
preference.
2. Hibernation MUST be real: suspend or freeze a workspace's pages, release its WebKit content
process pressure if the platform allows, drop rebuildable caches, keep durable state, and
record the transition. On reactivation the workspace MUST come back consistent, with a typed
and measured reactivation cost.
3. Page lifecycle MUST be used as the primary lever for memory: active for the workspace being
driven, background for recently used, suspended for idle-but-warm, frozen for parked, discarded
for hibernated. Transitions MUST be driven by budget and policy, MUST be evented, and MUST NOT
silently break a running program (a program whose page is hibernated MUST receive a typed
failure or an automatic, documented restoration, not corruption).
4. Idle workspaces MUST cost near zero: no timers running, no polling, no empty event buffers
churning, no open WebKit content processes for fully hibernated workspaces if the platform
permits releasing them.

### §9.5 The hot path must not pay for the fleet

REQUIREMENTS:

1. Every browser operation MUST be O(1) in the size of the fleet. Any code that iterates all
workspaces, all contexts, all pages, all events, or all leases on a per-operation path is
FORBIDDEN and MUST be replaced by indexed lookups.
2. Per-operation work in the runtime MUST be bounded: a fixed number of dictionary lookups and
a bounded number of allocations. No per-operation file I/O, no per-operation process spawn, no
per-operation full-state serialization.
3. Main-thread work MUST be minimized and never block on disk, network, or another process.
WebKit calls that must be on the main thread MUST be batched and MUST NOT be interleaved with
waiting. Any operation that requires a main-thread hop MUST document why, and the number of
hops per program MUST be countable.
4. Actor hops MUST be amortized: a program with N browser operations MUST NOT incur N
cross-actor round trips when the operations are sequential and could be issued from the same
context. Batch, coalesce, and PIPELINE: issue the next operation while the previous result is
in flight wherever ordering permits.
5. IPC MUST be batched per program phase, not per step. A wire response MUST carry a program's
outcome, not a per-step stream that the driver has to reassemble.
6. Serialization MUST be avoided on the hot path: no repeated JSON encode/decode of the same
value, no re-encoding of snapshots that have not changed, no copying of large payloads across
isolation boundaries when a bounded reference or a streaming handle will do.
7. Storage writes MUST be batched and asynchronous. A checkpoint MUST NOT serialize behind the
next navigation. Concurrency control MUST be FIFO-consistent, not lock-the-world. If a runtime
uses a background writer with a queue, the queue MUST be bounded, MUST be durable across
shutdown where durability is promised, and MUST be accounted for in the workspace budget.
8. Fleet-wide periodic work (lease expiry sweeps, hibernation decisions, evidence eviction) MUST
be O(live workspaces) at worst with a bounded per-run cost, MUST be incremental and sharded
rather than restarting from zero each tick, and MUST NOT scan the whole fleet in one tick.

### §9.6 The event pipeline at fleet scale

Events are the observability substrate for everything: verification consumes them, agents wait
on them, operators read them, and tests assert on them. The current design (one in-process bus
with a bounded journal and per-subscriber bounded buffers) is correct for a single runtime and
insufficient as the fleet substrate. Required:

1. Per-workspace ordered streams with per-stream monotonic sequence numbers. Global ordering is
NOT required and MUST NOT be attempted; it would be a global serialization point.
2. Per-subscriber bounded buffers with an explicit drop policy and an explicit drop counter.
Silent loss is FORBIDDEN. When a subscriber falls behind, it MUST be able to detect it from the
sequence numbering and recover what is still retained.
3. Retention that is bounded per workspace and governed by the workspace budget. Journal
recovery (read events since sequence N) MUST exist and MUST be bounded in cost.
4. Coalescing and sampling policies for high-volume families (console spam, chatty subresource
network, progress events) MUST exist, MUST be explicit per family, and MUST be recorded in the
stream itself so a consumer knows sampling occurred. An unsampled, unbounded console stream from
one hostile page MUST NOT be able to consume fleet memory.
5. Producers MUST NOT block on consumers. A slow subscriber MUST NOT slow down a page.
6. Fan-out MUST be bounded: adding subscribers MUST NOT be O(subscribers) work per event on the
hot path beyond a documented, bounded fan-out. If a broadcast design is used, it MUST be
per-shard with no global fan-out.
7. Event payloads MUST be bounded and redacted (§11). No event may carry a whole page, a whole
response body, or a secret.
8. Event identity (workspace, context, page, frame, branch, lease, execution) MUST be complete
enough that no consumer ever has to guess. A consumer that must join streams by heuristic is a
design failure.

### §9.7 Isolation at scale: one workspace cannot hurt another

REQUIREMENTS:

1. Cross-workspace access MUST be structurally impossible, not policed: separate stores,
separate secret scopes, separate event streams, separate evidence domains, separate execution
sessions. Enforcement MUST be at the lease boundary, and violations MUST be detectable and
alarmed (a violation attempt MUST be an event).
2. A runaway program (infinite loop, huge allocation, spam output) MUST be contained by the
host-enforced limits of §5.3 within a bounded time, with a measured containment latency.
3. A WebKit content process crash MUST degrade only its workspace: pages MUST be recoverable or
the workspace MUST be marked failed with typed evidence. Other workspaces MUST NOT be affected
-- prove this with a test that kills a content process and asserts that neighbouring workspaces
continue serving operations with no user-visible latency regression.
4. A workspace that repeatedly crashes MUST be quarantined by policy (bounded restart attempts,
exponential backoff, eventual typed eviction) rather than restarting forever and burning the
fleet's CPU.
5. A hostile page MUST NOT be able to affect the control plane: no unbounded dialog storms, no
unbounded popups, no unbounded downloads, no permission-prompt floods. Each MUST be counted and
capped per workspace, with the cap reported.
6. Resource exhaustion MUST be graceful: the system MUST prefer refusing new admission and
hibernating idle workspaces over degrading running ones, and the chosen behaviour MUST be
observable.

### §9.8 Fleet lifecycle: warm pools, cold start, restart storms, reaping

REQUIREMENTS:

1. Cold start of a workspace MUST be measured (p50/p95/p99) and MUST have a documented budget.
2. A warm pool MUST exist for the common case where many workspaces start at once. Prewarming
MUST be bounded, MUST be accounted for in memory, and MUST NOT leak identity across reuse: a
reused workspace MUST NOT inherit cookies, storage, secrets, events, or session state from its
previous lease. Prove it with a test that reuses a warm workspace across two identities and
asserts zero carry-over.
3. Teardown MUST be deterministic and MUST have a documented budget. Teardown MUST reap: pages,
contexts, web processes, proxy connections, sessions, temp files, and registry entries.
4. Orphan reaping MUST be automatic and MUST survive a daemon `SIGKILL`: on startup, the
supervisor MUST adopt or reap every resource it previously owned (profiles, stores, proxy
listeners, child processes, temp directories, socket files) and MUST report what it reaped.
5. Restart MUST NOT produce a thundering herd: recovery MUST be rate-limited, prioritized, and
observable, with a documented time-to-steady-state.
6. Leases MUST survive a supervisor restart according to one documented policy (expire, or
become recoverable and require explicit resumption). Silence or ambiguity here is a defect.

### §9.9 Storage and disk at fleet scale

REQUIREMENTS:

1. Per-workspace durable cost MUST be measured at steady state and MUST be bounded. No
workspace may grow its on-disk footprint without a cap and a policy at the cap.
2. Checkpointing MUST be incremental where the durable store allows it, MUST be batched, and
MUST have a bounded, measured cost per checkpoint. Checkpointing the whole world on every event
is forbidden.
3. Branching or copying state MUST be copy-on-write or delta-based where the store allows it.
A fork MUST NOT copy a profile directory wholesale; the measured fork cost MUST be proportional
to the checkpoint delta, and that ratio MUST be part of the test suite.
4. Retention MUST be explicit per artifact class: profiles, evidence, artifacts, logs, traces.
Each class MUST have a window, a size cap, and an eviction policy with counters.
5. Disk-full MUST be handled as a first-class failure: admission refusal, not corruption. Prove
with a test that fills a bounded volume and asserts typed refusals and no corruption of existing
workspaces.

### §9.10 Measurement protocol (this is not optional)

You MUST build a harness that can run at least these experiments, with these outputs, committed
as reproducible scripts and recorded results:

1. **Throughput curve**: workspaces vs completed tasks per second, at increasing concurrency,
with the saturation point marked.
2. **Latency percentiles**: per-operation and per-program, p50/p95/p99, for read, act, navigate,
verify, and full task.
3. **Memory curve**: resident bytes per workspace at steady state, at 1x, 10x, and Nx the target
concurrency; the point at which hibernation engages; the point at which admission refuses.
4. **Lease latency**: acquire, renew, release, expire-to-frozen, recover-after-restart.
5. **Isolation test**: kill a content process, kill a shard, kill a workspace owner; assert the
blast radius and record it.
6. **Hibernation cost**: freeze and reactivate N idle workspaces; record time and bytes
reclaimed per workspace.
7. **Evidence pressure**: a workspace emitting console and network spam at a hostile rate; assert
sampling engages, memory stays bounded, and no other workspace regresses.
8. **Failure point**: continue increasing load past saturation and record precisely what fails
first (admission, memory, file descriptors, ports, content processes, disk) and how it fails
(typed refusal, degraded latency, crash).

REQUIREMENTS: the harness MUST run in CI in a reduced-size mode on every change, and in full
mode on demand. Results MUST be committed next to the code with the git revision. Any regression
beyond a declared tolerance MUST fail the build.

### §9.11 Fleet anti-patterns (each one is a hard FORBIDDEN)

1. One global actor that handles every workspace's browser operations.
2. One global lock, one global queue, one global mutex on the hot path.
3. One process per workspace with no pooling or hibernation plan at fleet scale.
4. One unfiltered event stream shared by all workspaces.
5. Unbounded subscriber buffers, unbounded journals, unbounded evidence, unbounded logs.
6. Polling loops where events exist (including the supervisor's own timers doing full scans).
7. Per-step disk writes, per-step log lines, per-step metric flushes.
8. Per-operation process spawn, per-operation socket connect, per-operation TLS handshake.
9. "Scale claim by struct count": accepting N lease records and calling that N concurrent
workspaces. Concurrency is real pages, real processes, real memory, measured.
10. Silent degradation: reducing image retention, dropping events, sampling without a counter,
or weakening isolation to keep numbers looking good.

---

## §10 — THE ZERO-INEFFICIENCY LAW

Law 1 of this document, made enforceable. Each rule below has: what is forbidden, how to
detect it, and how to prove it is fixed. You MUST add the detector and the proof, not just the
fix. A fix without a detector regresses the moment someone else touches the code.

### §10.1 Round-trip rules

1. **Forbidden**: one wire round trip per browser operation. **Detect**: count boundary calls
per program; assert it equals one regardless of operation count. **Prove**: a test that runs N
browser operations and asserts a single boundary call with the observed N.
2. **Forbidden**: forcing the driver to call out of its program for a capability. **Detect**: a
list of capabilities only reachable as wire methods; assert it is empty for the §6 parity set.
3. **Forbidden**: waiting by polling when an event or a typed wait exists. **Detect**: count
poll loops and sleep calls in the control path. **Prove**: a test that waits on a slow real
resource and asserts zero page queries during the wait.
4. **Forbidden**: re-reading unchanged state. **Detect**: snapshot generation counters and
unchanged-snapshot returns. **Prove**: a test that reads twice and asserts the second read is
bounded and flagged unchanged rather than a full re-serialization.

### §10.2 Pixel rules

These rules price pixels; they do not forbid them (§4.0). Requesting an image is a driver
decision the runtime serves. Producing one on the driver's behalf is the defect.

1. **Forbidden**: an image produced automatically per step. **Detect**: image counter per
tier; assert automatic origin is zero. **Prove**: a DOM-only workflow completes with zero
images.
2. **Forbidden**: an image used to locate a DOM element. **Detect**: coordinate-action counter
where a ref was resolvable. **Prove**: the violation metric is zero on the DOM suite.
3. **Forbidden**: returning an image to a driver that did not request it. **Detect**: images
returned vs images produced, split by requester. **Prove**: a test that produces an artifact
image and asserts the driver payload contains no image bytes.

### §10.3 Allocation and copy rules

1. **Forbidden**: unbounded retry without backoff and a cap. Every retry loop MUST have a
bounded attempt count, a backoff, and a typed terminal failure.
2. **Forbidden**: re-serializing an unchanged payload. **Detect**: encode counters per program;
assert encoded bytes are proportional to changed data, not to total state.
3. **Forbidden**: holding large payloads alive for the duration of a lease when they were needed
for one operation. **Detect**: retained-bytes accounting per session; a program that does one
big read MUST NOT raise steady-state workspace bytes permanently.
4. **Forbidden**: copying a snapshot, an event batch, or a wire payload more times than
required to cross an isolation boundary. **Detect**: allocation counters in the hot path;
review of the actual call graph.
5. **Forbidden**: unbounded strings in the hot path (log lines assembled per operation,
full URLs repeated per event when an id would do, base64 in logs).

### §10.4 Hot-path rules

1. **Forbidden**: iterating all workspaces, contexts, pages, or leases on a per-operation path.
**Detect**: grep-level proof plus a complexity note in the code; a counter that asserts the
lookup set size is O(1).
2. **Forbidden**: per-operation disk I/O. **Detect**: syscall counters or a writer queue depth
metric; assert zero synchronous writes on the operation path.
3. **Forbidden**: per-operation process spawn or socket connect. **Detect**: process and socket
counters; assert they are stable under steady load.
4. **Forbidden**: main-thread hops that could be avoided. **Detect**: a counter of main-thread
hops per program; a target band per program type.
5. **Forbidden**: a fleet-wide periodic scan. **Detect**: measure the sweep cost against live
workspace count; assert it is proportional and incremental, not quadratic, and assert per-tick
work is bounded.

### §10.5 Buffer and queue rules

1. Every buffer, queue, channel, stream, cache, dictionary, array, and log sink in the control
path MUST have a declared bound, an eviction or refusal policy, and a counter.
2. Every drop MUST be counted and attributable to a subscriber, a family, or a workspace.
3. Every consumer that can be slower than its producer MUST be given backpressure, not a bigger
buffer. Enlarging a buffer to hide a backpressure bug is forbidden.
4. Every queue MUST expose depth, high-water mark, and drop count as metrics.

### §10.6 The efficiency ledger

REQUIREMENT: maintain a single document (committed, kept current) that lists every hot path in
the agent control surface, its bound, its measured cost, its detector, and its test. The ledger
is reviewed in every change that touches the control surface. The ledger is the answer to
"is anything inefficient?" -- not an assurance, a table.

---

## §11 — ISOLATION, SECRETS, AND AUTHORIZATION

### §11.1 The isolation boundary is the lease

1. A lease MUST confer: the right to drive specific contexts and pages, access to the
workspace's storage and cookies, access to the workspace's event stream, and access to the
workspace's secrets. Nothing more.
2. Operations outside the lease's scope MUST fail with a typed authorization error. The check
MUST happen at the operation boundary, not only at admission, because programs carry context
identities through variables.
3. Lease scope MUST be evaluated for every operation that touches a context, a page, a profile,
a store, a secret, an event stream, or an artifact path. A single unchecked path is a defect.
4. Cross-workspace reads MUST be impossible even for a buggy or malicious program. Tests MUST
attempt: reading another workspace's cookies, storage, events, artifacts, secrets, pages, and
screenshots, and MUST observe typed refusals.
5. Authorization failures MUST be recorded as events with the attempting lease id, so that
repeated attempts are visible to an operator.

### §11.2 Partition the resources physically where possible

1. Separate website data stores per workspace (or strictly partitioned identity inside a shared
store) so cookies and storage cannot mix by mistake.
2. Separate profile directories per workspace, with per-workspace file permissions where the
platform allows.
3. Separate event streams, separate evidence stores, separate artifact directories.
4. Separate proxy or observation domain per workspace or lease group, never a single shared
observation point that could merge evidence.
5. Ephemeral workspaces MUST NOT touch durable storage at all, and MUST be verifiable as such
(no files created, no directory touched, no store registered).

### §11.3 Secrets never reach code the model wrote

This is the rule that the reference implementation gets right by construction, and we adopt it
without compromise.

1. Credentials, tokens, cookies of value, and keys MUST NOT be readable from the execution
session. The session runs in an environment where those values are absent (§1.1 documents the
environment-scrubbing technique; the requirement is the property, not the technique).
2. Filling a login form or Authorization header MUST be performed by the runtime on the
workspace's behalf, at a boundary the model's code cannot read from. The model supplies an
intent -- use credential X for this origin -- and never the value.
3. A test MUST prove this: run a program that attempts to read the credential value, the
injected header, the vault contents, and the vault key, and assert every attempt fails with a
typed error while the login still succeeds.
4. Secrets MUST NOT appear in: events, logs, traces, artifacts, replay bundles, error messages,
or driver-visible output. Redaction MUST be applied at the producer, not at the reader. A
redaction that happens on the way out means the value existed in the pipeline.
5. Human-entered values during a handoff MUST be treated as secrets by default, with an explicit
allowlist for values the workflow declares as non-sensitive.

### §11.4 Hard stops that the runtime enforces for humans

1. Categories that MUST pause for human approval: payments and money movement, MFA and
passkey steps, legal acceptance and attestations, and destructive production changes. The pause
MUST be a runtime gate, not a paragraph in a prompt.
2. The gate MUST be: the operation cannot proceed without a recorded human decision; the
pending state MUST be durable across restarts; the decision MUST be attributable to a principal;
the resulting action MUST be recorded as evidence.
3. A program that hits a gate MUST be parked, not failed: the page MUST be frozen for human
takeover, the state MUST be preserved (page, context, branch, lease, target URL, relevant
storage), and resumption MUST continue from exactly that state.
4. The gate MUST NOT be bypassable by the model writing different code, by a different
interface, or by a different authority path. There MUST be exactly one enforcement point and
tests that attempt bypass through every surface (native, CLI, MCP, exec).

### §11.5 Multi-principal hygiene

1. Every request MUST carry a principal identity, and every authorization decision MUST be made
against that identity.
2. Sharing one credential across workers MUST NOT collapse distinct principals into one. If the
transport cannot distinguish principals today, say so explicitly and make the limitation
visible in the API rather than pretending isolation exists.
3. Ownership of a workspace, a lease, a branch, an artifact, and an approval MUST be recorded
and enforced. A wrong principal attempting to resume, claim, or release MUST be refused with a
typed error and an event.

### §11.6 The hostile-page boundary

1. A page MUST NOT be able to: read another workspace's data, escape its process isolation,
survive a lease end, retain a permission decision granted to another origin, flood the control
plane, or corrupt the event pipeline.
2. Dialogs, popups, downloads, permission requests, and navigation attempts MUST each be
counted and capped per workspace, with caps reported and enforced.
3. Navigation to unsupported schemes MUST be refused by policy with a typed event, not by
crash or by silent nothing.
4. Any page-triggered action that reaches the control plane MUST be treated as untrusted input:
bounded, validated, and never used to build a file path, a shell command, or a query without
validation.

---

## §12 — FAILURE SEMANTICS AND RECOVERY

A serious runtime is defined by what it does when things break. Every failure below MUST have
a defined behaviour, a measured bound, and a test.

### §12.1 Failure catalogue (each row requires a test)

1. Page closed while a program is mid-operation: typed step failure, no crash, session alive.
2. Navigation fails (DNS, connection refused, TLS, HTTP error): typed failure with the phase
that failed; the program may handle it in-code.
3. Navigation succeeds with an error status: the status is data, not an exception, and is
available to verification.
4. Timeout inside a wait versus timeout of the whole program: distinct types and distinct
recovery.
5. Program cancelled by the driver: bounded observation latency, partial state preserved and
inspectable.
6. Lease expired mid-program: program revoked with a distinct reason, resources released, no
partial success reported.
7. Lease released by the driver mid-program: same revocation semantics.
8. Daemon killed while programs run: leases become recoverable or expire per the documented
policy; programs do not resume with stale state; orphans are reaped on startup.
9. WebKit content process crash: affected workspace degraded or recovered, others unaffected,
event published, recovery time measured.
10. Supervisor crash: its workspaces are recovered or reaped on restart; no other shard
affected.
11. Storage corrupted or missing (profile, store, artifact): typed errors, no silent data loss,
and an explicit repair or refusal path.
12. Disk full or over quota: typed refusals, no corruption, admission control engages.
13. Malformed program or malformed wire input at every surface: typed refusal at decode, never
a crash, never a partial execution.
14. Hostile input through a page (huge strings, recursion, exotic encodings): bounded, typed
failure; no control-plane impact.
15. Clock skew or a changed system clock: lease expiry and deadlines MUST use a monotonic
source for durations and MUST NOT be defeated by a clock jump.
16. Duplicate delivery of a terminal event or a terminal request: idempotent, no double release,
no double charge, no double freeze.

### §12.2 Recovery rules

1. Recovery MUST be explicit and typed. Nothing may be silently "retried until it works".
2. Recovery MUST be bounded: attempt counts, backoff, and a terminal state.
3. Recovery MUST NOT resurrect work that the driver believes is finished. Terminal is terminal.
4. Recovery MUST publish an event that a supervisor can observe; operators MUST be able to see
recoveries, quarantines, and reapings as a time series.
5. Recovery MUST be tested by killing things for real (processes, shards, content processes),
not by simulating a flag.

---

## §13 — ONE RUNTIME, MANY SURFACES

### §13.1 The single-source-of-truth rule

1. `BrowserRuntime` (and the layers directly above it) is the only implementation of browser
behaviour. The native API, the CLI, the MCP server, and any SDK are adapters. An adapter that
contains business logic -- a default, a retry, a transformation, a policy -- is a defect.
2. The exec program model is the only implementation of batching. An adapter MUST NOT implement
its own batching loop.
3. Verification is the only implementation of "did it work". An adapter MUST NOT decide success.
4. Authorization is enforced in one place. An adapter MUST NOT add or remove a check.

### §13.2 Parity requirements

1. Every public operation MUST be reachable through native, CLI, and MCP, and -- where it makes
sense for a driver -- from inside a program. The parity table MUST be committed and MUST have a
test per row per surface.
2. Return structures MUST be identical in meaning across surfaces: same ids, same statuses,
same error codes, same limits, same timeouts, same cancellation semantics.
3. Error codes MUST be a closed, documented set. Adapters MUST NOT invent codes or map a typed
code into a string.
4. Timeouts, cancellation, and verification MUST behave identically across surfaces. A CLI that
cancels differently from the native API is a defect.
5. Malformed input, unknown ids, a disconnected daemon, and a restarted daemon MUST produce the
same typed behaviour through every surface.
6. Concurrency: multiple clients using different surfaces against the same workspace MUST be
serialized by the runtime's own rules (leases and program concurrency limits), not by accident.

### §13.3 Adapter thinness enforcement

1. Add a test that fails if an adapter file references browser-mutating internals directly
(instead of delegating through the protocol).
2. Add a test that asserts a representative operation's response is byte-identical when issued
through each surface (modulo ids and timestamps).
3. Document, in the API docs, the one enforcement point for authorization and the one for
verification, with file references.

---

## §14 — MODEL-AGNOSTIC DRIVERS: FRONTIER, LOCAL, AND EVERYTHING BETWEEN

The control plane MUST NOT be shaped around one model. A frontier hosted model, a mid-size
model, a small local model, and an automated SDK client all drive the same runtime through the
same single primary interface. What differs is the *authoring* of programs, not the execution,
verification, isolation, or evidence path.

### §14.1 One interface, no second implementation

1. There MUST be exactly one execution channel: submit a program, receive an outcome. A second
channel that does the same thing with different semantics is forbidden.
2. A driver that cannot author a program in the primary language MUST still submit a program.
The lowering step (see §14.3) MUST produce the same program type and MUST go through the same
runtime, the same limits, the same verification, and the same evidence. There MUST NOT be a
"small model path" in the runtime.
3. Model identity MUST NOT appear in authorization, isolation, or verification code.

### §14.2 Capability tiers for drivers (declared, not assumed)

Define a small, explicit driver-capability declaration that the runtime records with a lease:

1. `authoring`: full (writes arbitrary programs) or structured (submits a declarative plan that
the runtime lowers into a program).
2. `context_budget`: the maximum bytes of page state the driver can accept in one result, which
the runtime MUST honour by paging or truncating **with an explicit flag**.
3. `image_budget`: the driver's image allowance per window (count and bytes). Every driver may
receive images; this is a quantity, never a switch that turns the channel off.
4. `tool_surface`: the driver's view of the runtime (see §14.4).
5. `deadline_preference`: the driver's preferred program deadline, bounded by the runtime's
maximum.

REQUIREMENTS: the runtime MUST enforce every declared budget, MUST report when it truncated,
and MUST NOT silently exceed a declared context budget. A driver that asked for text MUST NOT
receive base64.

### §14.3 Deterministic lowering for structured drivers

1. Provide a documented, versioned declarative form (a plan) that expresses: read state, select
by ref, act, wait by condition, assert, verify. This is a **lowering target**, not a second
runtime.
2. Lowering MUST be total and deterministic: the same plan MUST produce the same program. Plans
that cannot be lowered MUST fail with a typed error naming the unsupported construct.
3. Every limit of §5.3 MUST apply after lowering, and the lowered program MUST be inspectable
(the program text MUST be returned or retrievable so an operator can see exactly what ran).
4. Evidence MUST be identical whether the program came from free authoring or from lowering.
This is testable and MUST be tested: run the same task both ways against the same fixture and
compare the verification evidence.

### §14.4 The tool surface a driver sees

1. Default: **one** tool, `exec`, whose input is a program, and whose output is the outcome of
§5.5. Do not ship a menu of per-action tools as the default surface.
2. Optional convenience tools (`snapshot`, `verify`, `inspect`) MAY exist for drivers whose
models are trained around short tool calls, but they MUST be implemented as thin wrappers over
the same runtime operations and MUST be off by default.
3. It is FORBIDDEN to expose a `click_at(x, y)` tool. If coordinates are needed for canvas
content, expose `click_point` documented as Tier 3 and counted as a coordinate action.4. It is FORBIDDEN to expose an automatic capture loop, or any tool surface in which a
   screenshot is inserted between steps without the program asking for it. It is REQUIRED to
   expose a screenshot capability that a program can call at any time; screenshots are
   requested deliberately and are budgeted, never injected. The distinction is request versus
   injection — see §4.0.4.
5. The tool descriptions MUST teach the correct pattern in the same way the reference tool
description does (persist state, prefer condition waits over sleeps, act on refs, batch work,
return only what you need).
6. When a driver makes a lone single-action call where a program was expected, the runtime MUST
record it as a batching regression metric. A gentle reminder may be appended, but the metric is
the requirement; the reminder is cosmetic and optional.

### §14.5 Local models specifically

1. Local models get the same runtime guarantees. Their smaller context is handled by §14.2
budgets and by paging state, not by weakening isolation or verification.
2. The runtime MUST provide a compact snapshot mode for small-context drivers: fewer elements,
shorter names, no optional fields, stable ordering, and an explicit `truncated` flag with a
pointer to how to page the rest.
3. The runtime MUST NOT "help" a weak driver by skipping verification or by accepting optimistic
completion. If a local model cannot verify a task, the outcome is `inconclusive`, and that is a
correct, honest result.
4. Latency MUST NOT be traded for correctness for any driver class: identical limits, identical
timeouts, identical evidence.

### §14.6 Frontier models specifically

1. Frontier drivers MUST be able to write long, branching programs -- respect the program size
limit and make it generous enough for real work (the reference allows 64 KiB of code; do not
choose something smaller without a measured reason).
2. Frontier drivers MUST be able to consume several thousand elements of structured state in one
call when the page warrants it, within the declared context budget.
3. Frontier drivers MUST be able to run long tasks: multi-minute programs with many operations,
bounded by explicit deadlines, with progress observable through events so an operator can see
what a long task is doing.

---

## §15 — TESTING DOCTRINE

Our validation standard is already unusually strict: tests run against real WebKit, and a claim
without a reproduction is not a claim. Extend that standard to everything in this document.

### §15.1 Non-negotiable test rules

1. Real browser, real HTTP origin, real cookies, real storage, real navigation. Mocking WebKit is
allowed only for unit tests of pure logic, and such tests MUST NOT be cited as evidence that a
browser behaviour works.
2. Every fix MUST come with a regression test that fails before the fix and passes after. State
the before/after result in your report.
3. Every performance requirement in this document MUST have a test or a harness assertion, not a
comment.
4. No test may be weakened to make a build green. If a test is wrong, say why, fix the test, and
state that you changed it in the report.
5. Flaky tests MUST be fixed or quarantined explicitly with a linked issue; silent retries are
forbidden.
6. Tests MUST clean up: no orphaned processes, ports, temp directories, or files. A test that
can leak a listener or a child process is a defect (and the fix is the test's responsibility, not
the operator's).

### §15.2 Adversarial suites required by this document

1. **Anti-optimism suite** (§8.5): fake success, silent server rejection, success banner with no
request, 200 with an error body, partial download, redirect to an error page.
2. **Isolation suite** (§11.1): cross-workspace reads of every resource class, from every
surface, including through variables inside programs.
3. **Secret suite** (§11.3): attempts to read credentials, headers, vault contents, and vault
keys from inside a program; assert refusals and assert no secret appears in any event, log,
trace, artifact, or error.
4. **Hostile-page suite** (§11.6): dialog storms, popup storms, download storms, permission
floods, huge strings, deep recursion, navigation to exotic schemes, and a page that tries to
break the network observer.
5. **Containment suite** (§9.7): infinite loop, unbounded allocation, output spam; assert the
host kills them within the measured bound and that neighbours are unaffected.
6. **Crash suite** (§12.1): kill a content process, kill a shard, kill the daemon, kill a worker
mid-program; assert blast radius and recovery time.
7. **Pressure suite** (§9.10): thousands of idle workspaces, then hundreds active, then the
saturation sweep; assert admission refuses before anything degrades.
8. **Zero-image suite** (§4.4): a DOM-only task that never asks for an image completes with zero
images and zero coordinate actions; and a companion task that asks for exactly one receives
exactly one (proving the channel is live, not merely unexercised).
9. **Snapshot-fidelity suite**: refs resolve correctly after reflow, after DOM mutation, after
frame changes; stale refs fail loudly; a snapshot against a real complex page matches expected
elements.
10. **Network-evidence suite** (§7): same-origin fetch observed, cross-origin subresource
observed at layer 2, redirect chain observed, upload body observed, pinned-certificate site
produces a typed limitation.

### §15.3 Test-scale rules

1. Scale tests MUST run in a reduced mode in CI with fixed thresholds that catch regressions, and
in a full mode on demand.
2. Scale tests MUST record the machine's capacity in the result, because a number without a
machine is meaningless.
3. Scale tests MUST assert bounds, not just print numbers: memory per workspace under a ceiling,
latency under a ceiling, containment within a ceiling.
4. A scale regression MUST fail the build.

---

## §16 — INSTRUMENTATION AND THE EVIDENCE PROTOCOL

You will be judged on the evidence you produce, so the evidence must be designed, not improvised.

### §16.1 Required instruments

1. **Transport counter**: boundary calls per program. Proves batching and locality.
2. **Operation counter**: browser operations per program, split by kind (snapshot, act, navigate,
evaluate, verify).
3. **Tier counters**: tier 1 / tier 2 / tier 3 usage, including images produced and images
delivered, and coordinate actions taken where a ref existed.
4. **Latency histograms**: per-operation and per-program, p50/p95/p99, per shard and per
workspace class.
5. **Resource gauges**: per-workspace bytes, pages by lifecycle, handles, evidence bytes, queue
depths, high-water marks, drop counts.
6. **Lease instruments**: acquire/renew/release/expire/recover counts and latencies; revocation
count; registration leaks (must be zero).
7. **Verification instruments**: verified / failed / inconclusive counts per task class, and
completions without verification (must be zero for consequential tasks).
8. **Isolation instruments**: authorization refusals, cross-workspace attempts (must be zero in
normal operation), quarantine counts.
9. **Reaping instruments**: orphans reaped on startup, by kind, and any resource that survived
teardown (must be zero).

### §16.2 The evidence artifact for your work

For every claim you make, the report MUST contain:

1. The command you ran (exact).
2. The instrument output (exact, trimmed to the relevant lines, with the raw log retained).
3. The expected value and the observed value.
4. The revision (git sha) and the machine.
5. For negative results: the observed failure and whether you fixed it or filed it.

Claims without this structure MUST be treated as unverified and MUST be removed from the report.

### §16.3 Logging rules

1. No per-operation log line in the hot path. Logs are evented, sampled, and budgeted.
2. Logs MUST be structured, MUST carry the identity tuple (workspace, lease, session, program,
page), and MUST be redacted at the producer.
3. A log line MUST NOT contain a URL with credentials, a cookie value, a token, a form value, or
an image.
4. Debug logging MUST be switchable per workspace at runtime so that a fleet can be investigated
without a restart and without enabling debug globally.

### §16.4 Traces and replays

1. Maintain a per-run trace sufficient to reconstruct: the program, the operations, the observed
state changes, the events, the verification result, and the artifacts. The reference does this
with a replay bundle; adopt the concept, not the file format.
2. Traces MUST NOT contain secrets (§11.3). They MUST be bounded and retention-managed.
3. A trace MUST be able to answer, without rerunning: which tier did this action use, was an
image produced and why, which network observations backed this assertion, and which references
were resolved at which generation.

---

## §17 — DEFINITION OF DONE

This work is done when **every** box below is checked with evidence attached. Not when the code
compiles, not when the new tests pass, not when the architecture diagram looks right.

### §17.1 Architecture

- [ ] Exactly one execution channel exists (program in, outcome out), and every driver uses it.
- [ ] The driver's default tool surface is one program-execution tool. No per-action menu by
default. No coordinate-click tool. No screenshot tool in the loop.
- [ ] Structured page state with stable references is the primary read channel and works without
a window.
- [ ] Screenshots are a first-class, always-available, program-callable option; none is
      produced that a program did not request, and every one is budgeted, counted, and priced
      in the cost ledger (§4.0).
- [ ] Every capability in §6 has a program-callable equivalent with a named acceptance test.
- [ ] Network visibility has both layers (§7) and the API states which layer produced any given
piece of evidence.
- [ ] Verification is a first-class primitive with three-valued outcomes and attached evidence.
- [ ] The human-approval gates are runtime gates, not prompt instructions, and are bypass-proof.

### §17.2 Efficiency (§10)

- [ ] One boundary call per program regardless of operation count, proven by a counter.
- [ ] Zero automatic images per step, proven by a counter and a zero-image DOM suite.
- [ ] Zero coordinate actions where a reference was resolvable on the DOM suite, proven by the
violation metric.
- [ ] Zero polling waits where an event or typed wait exists, proven by a count.
- [ ] Every buffer, queue, journal, cache, and sink has a declared bound and a drop counter.
- [ ] Every hot path has a measured cost and a ledger entry.
- [ ] No per-operation disk I/O, process spawn, or socket connect on the control path, proven by
counters under steady load.

### §17.3 Scale (§9)

- [ ] Sharded supervisor with no global hot-path registry.
- [ ] Admission control with typed refusals naming the exhausted dimension.
- [ ] Per-workspace budgets for memory, pages, handles, evidence, and images, each enforced.
- [ ] Page-lifecycle-driven hibernation with a measured reactivation cost and no cross-lease
carry-over (proven by a warm-pool reuse test).
- [ ] Per-workspace bounded event streams with sampling policies, drop counters, and sequence
recovery.
- [ ] Containment: a runaway program is stopped within a measured bound and neighbours are
unaffected.
- [ ] Orphan reaping on startup after a `SIGKILL`, with a report of what was reaped.
- [ ] A committed saturation harness with a recorded saturation point and failure point, plus a
reduced-mode CI gate that fails on regression.
- [ ] A committed per-workspace cost number (bytes, CPU) at steady state, with the machine
stated.

### §17.4 Correctness and safety

- [ ] Verification MUST NOT report success without evidence, proven by the anti-optimism suite.
- [ ] Secrets are unreachable from programs, proven by the secret suite, and absent from all
evidence streams.
- [ ] Cross-workspace access is refused on every resource class from every surface, proven by the
isolation suite.
- [ ] Every failure row in §12.1 has a test that triggers it for real.
- [ ] Terminal states are idempotent and leak nothing (no tasks, hooks, pages, files, processes,
registrations).
- [ ] Clock-jump-proof deadlines (monotonic durations).

### §17.5 Surfaces

- [ ] Native, CLI, and MCP expose the same operations with identical semantics and error codes,
proven by a parity test per row per surface.
- [ ] Adapters contain no business logic, proven by a test or a lint that fails on direct
runtime mutation from adapter code.
- [ ] One enforcement point each for authorization and verification, documented with file
references.

### §17.6 Reporter hygiene

- [ ] `code-first-recon.md` exists, is complete, and conflicts were reported.
- [ ] The efficiency ledger is complete and current.
- [ ] The parity table is complete with acceptance test names.
- [ ] Every fix has a regression test and a before/after result.
- [ ] The final report uses the format in §19 and contains no unverified claim.

---

## §18 — PROHIBITIONS (ABSOLUTE)

Read these as constraints on your behaviour, not as advice. Each one is a defect if violated.

**Read prohibitions 1 and 2 precisely: they constrain automaticity and default-ness, not
capability.** Nothing in this list forbids a driver from requesting a screenshot, forbids the
runtime from serving one, or permits any channel in §4.0 to be removed, gated, deprecated, or
labelled "fallback only".

1. Do NOT build, keep, or reintroduce a loop that captures a screenshot before or after each
action and feeds it to a driver as the decision input.
2. Do NOT expose per-action tools (`click`, `type`, `scroll`, `screenshot`) as the default driver
surface. They may exist only as functions inside programs, and only where they are genuinely
needed (coordinate work for canvas content).
3. Do NOT emit one round trip per browser operation.
4. Do NOT derive a coordinate from an image to act on a DOM element that has a resolvable
reference.
5. Do NOT attempt to speak CDP to WebKit, import a Chromium transport library, or assume a CDP
domain has a native counterpart.
6. Do NOT bridge the platform accessibility API into the control path as the primary structured
state source before checking whether the in-page structured snapshot is simpler and sufficient.
If you believe the platform API is required, present the measurement that shows why.
7. Do NOT claim network visibility is complete with only in-page observation.
8. Do NOT allow a task to be marked complete on the strength of an action not erroring.
9. Do NOT add unbounded buffers, unbounded retries, unbounded evidence retention, or unbounded
per-workspace growth.
10. Do NOT centralize the hot path: no global lock, no global actor, no single proxy, no single
queue, no fleet-wide scan per operation.
11. Do NOT let a second implementation of batching, verification, authorization, or page-state
reading appear in an adapter.
12. Do NOT weaken limits, isolation, verification, or evidence to make a number or a test look
better.
13. Do NOT remove, gate, deprecate, hide, or re-label a capability channel. Every channel in
§4.0 stays reachable from inside a program. The price signal is the budget and the ledger, never
an absence. A driver asking for a screenshot because it decided that is the right call is
correct behaviour, and treating it as a defect is itself a defect.
13. Do NOT touch, redesign, or regress the human-facing browser UI. The only permitted edits
outside the backend are minimal hooks the control surface requires.
14. Do NOT invent file names, type names, or existing signatures. Read the code first (§2.2).
15. Do NOT cite a performance or token improvement without the instrument output that produced
it and the command that ran it.
16. Do NOT use destructive git operations to make a problem disappear, and do NOT delete another
agent's tests or code to reach green.
17. Do NOT leave a leak behind: no orphan process, listener, temp directory, socket file, store,
or registration. Reaping is part of the feature.
18. Do NOT hide a failure in prose. Every unresolved problem gets a reproducible entry with a
command, an observation, and a root-cause statement (or an explicit "root cause not yet
established" plus the next experiment).

---

## §19 — REQUIRED REPORT FORMAT

Write your report to `agents/agent-native-browser-runtime/code-first-report.md` and keep it
current. Sections are mandatory; an empty section MUST say why it is empty.

```markdown
# Code-first browser control — implementation report

## Current status (one table, updated every session)
| Area | Status: PASS / PASS WITH LIMITATIONS / FAIL / NOT STARTED | Evidence |

## Recon summary (link to code-first-recon.md; list conflicts found)

## What changed, file by file (path: what and why)

## Architecture proof
- One execution channel: evidence
- Tier discipline: evidence (counters)
- Structured state: evidence (snapshot sample, ref stability test)
- Verification: evidence (three-valued outcomes, anti-optimism results)
- Network layers: evidence (layer 1, layer 2, disagreement handling)

## Efficiency proof (one row per §10 rule: rule, detector, measured value, test)

## Scale proof (one row per §9.10 experiment: experiment, command, result, saturation/failure point)

## Isolation and secret proof (attempted violation, observed result, test name)

## Failure injection results (one row per §12.1 row: scenario, behaviour, bound, test)

## Surfaces parity (table: operation, native, CLI, MCP, identical semantics?)

## Fixes made (defect, root cause, fix, regression test, before/after)

## Measured performance (machine, revision, numbers with units)

## Remaining failures (each with reproduction, and whether it is open, blocked, or wontfix with
justification)

## Limitations (honest, typed, visible in the API — not buried here)

## Next steps (ordered, with the smallest next experiment first)
```

---

## APPENDIX A — WEBKIT CAPABILITY MAP

Design guidance, verified against the API shape available to us. Confirm each during recon; where
a version constraint applies, state the minimum supported macOS version and the fallback.

| Need | WebKit mechanism | Notes |
| --- | --- | --- |
| Navigate, history, reload, stop | `WKWebView` load/back/forward/reload/stopLoading, `backForwardList` | Return typed outcomes; do not infer state after the fact |
| Navigation lifecycle | `WKNavigationDelegate` (start, commit, finish, fail, policy decisions) | The event spine for navigation events |
| Structured page state | Injected `WKUserScript` at document start in all frames, message via `WKScriptMessageHandler` | The primary read channel; must work without a window |
| Arbitrary page script | `evaluateJavaScript` (async) | Tier 2 escape hatch; sandboxed and observed |
| Downloads | `WKDownloadDelegate` | Real path, real completion, real failure; never "the click worked" |
| Cookies and storage | `WKHTTPCookieStore`, `WKWebsiteDataStore` APIs | Scoped per store; clearing must report what it cleared |
| Profiles and isolation | `WKWebsiteDataStore(forIdentifier:)`, ephemeral store | One store per workspace; never shared silently |
| Traffic-level network observation | Proxy configuration per data store plus a local proxy process | The only comprehensive path; see §7.3 |
| Full-page and region capture, PDF | `takeSnapshot` / `createPDF` | Tier 3; must carry geometry metadata and be budgeted |
| Media | Media element APIs and the runtime's media control surface | Program-callable, observable |
| Extensions | `WKWebExtensionController` and context APIs | Agent control surface is a §6.5 gap today |
| Permissions | `WKUIDelegate` permission callbacks | Must be an explicit, recorded decision |
| Dialogs and file choosers | `WKUIDelegate` | Evented; resolvable programmatically; never require a window to be observable |
| Content blocking | Content rule lists | Observable effect; testable |
| Page lifecycle / memory | Page lifecycle states plus store teardown | The lever for hibernation (§9.4) |

If a row cannot be satisfied on our minimum target, say so in recon with the version boundary and
the explicit typed limitation the API will expose.

---

## APPENDIX B — VERIFIED REFERENCE ANCHORS (READ THESE, DO NOT TRUST THIS LIST BLINDLY)

Reference A — `./openai-cua-sample-app`:

- `README.md` — code-first framing; the browser-agent vs desktop-agent split.
- `javascript-app/src/responses-loop.ts` — `buildCodeToolDefinitions`, `executeJavaScriptToolCall`,
`classifyResponse`, `runResponsesCodeLoop`.
- `javascript-app/src/javascript-worker.ts` — the persistent REPL, output accounting, `busy`
flag, close.
- `javascript-app/src/browser/protocol.ts` — operation vocabulary, `maxCodeBytes`,
`maxOutputBytes`, output parsing.
- `javascript-app/src/browser/javascript-process.ts` — host watchdog, close sequence, stderr ring
buffer, environment scrubbing, failure codes.
- `javascript-app/src/backend-lease.ts` — exclusive coordination port.
- `contracts/index.ts` — run events, screenshot artifact source, replay bundle, error schema.
- `labs/` and `javascript-app/src/runner-manager.ts` — per-run workspace isolation and artifacts.

Reference B — `./claude-quickstarts`:

- `browser-use-demo/browser_use_demo/browser_tool_utils/browser_dom_script.js` — accessibility tree
walk, `ref_N` assignment with `WeakRef`, YAML output, stale-ref cleanup.
- `browser-use-demo/browser_use_demo/browser_tool_utils/browser_element_script.js` — reference
resolution and interaction.
- `browser-use-demo/browser_use_demo/tools/browser.py` — action vocabulary and the `ref`
parameter.
- `browser-use-demo/CHANGELOG.md` — provenance: adapted from Playwright accessibility snapshot
work; the added `execute_js` action; the coordinate-scaling caveat.
- `computer-use-demo/computer_use_demo/loop.py:142` and `:244`,
`browser-use-demo/browser_use_demo/loop.py:176` — `_maybe_filter_to_n_most_recent_images`, the
anti-pattern, quoted in §1.2.
- `computer-use-best-practices/computer_use/tools/batch.py` — batch primitives and stop-on-first-
error semantics.
- `computer-use-best-practices/computer_use/tools/result.py` — structured `ToolResult`,
`is_error`, image-omitted-on-error.
- `computer-use-best-practices/computer_use/tools/browser.py` — `_ACTIONS`, input schema, result
handling.
- `computer-use-best-practices/constants.py:411` — `BATCH_REMINDER` and its action set.
- `computer-use-best-practices/computer_use/image.py` — reference resize and coordinate agreement.
- `claude-quickstarts/agents/tools/code_execution.py` — a second, smaller code-execution tool for
comparison.

External material you MUST read at the source before citing (do not paraphrase a blog post):
Browser Use's own published account of removing its fixed action menu in favour of code execution
(`github.com/browser-use/browser-use`).

---

## APPENDIX C — THE MINIMUM IMPLEMENTATION ORDER

Do the work in this order. Each step ends with evidence, and each step must not break the ones
before it.

1. Recon (§2), including the gap tables and the conflict report.
2. Structured page state (Tier 1) as a runtime primitive, with ref stability, frame scoping,
bounds, and a change-friendly generation model. Acceptance: snapshot tests plus a zero-image DOM
workflow.
3. Resolution of every Tier 1 action against references, with typed stale-reference failures.
4. Program-callable exposure of every §6 capability, one family at a time, each with its
acceptance test.
5. Persistent execution sessions with host-enforced limits, cancellation, timeout, revocation,
and no leaks.
6. Network layer 1, then verification families that consume it.
7. Verification primitive and the anti-optimism suite.
8. Network layer 2 (traffic-level proxy) and the evidence-disagreement handling.
9. Supervisor, admission control, per-workspace budgets, and hibernation.
10. Scale harness, saturation curve, failure point, and the reduced-mode CI gate.
11. Surface parity for native, CLI, MCP, with adapter-thinness enforcement.
12. Documentation: protocol reference, efficiency ledger, parity table, limitation register.

Do not start step 9 before step 2 has acceptance evidence. A fleet of fast workspaces with wrong
page state is a fleet of fast mistakes. Equally, do not stop at step 3 and call the architecture
done: the fleet requirement is the point.

---

## APPENDIX D — GLOSSARY

- **Driver**: whatever writes programs (a frontier model, a local model, an SDK client).
- **Program**: the unit of work submitted to the execution channel.
- **Session**: persistent execution state bound to a lease.
- **Workspace**: the unit of isolation (profile, store, storage, secrets, events, evidence).
- **Lease**: the time-bounded right to drive a workspace.
- **Shard**: supervisor process owning a bounded set of workspaces.
- **Tier 1 / 2 / 3**: structured state / raw capability / pixels.
- **Reference (ref)**: a stable handle to a live element within a snapshot generation.
- **Evidence**: observed, attributable facts (state, network, artifact, storage, external).
- **Consequential task**: a task whose outcome matters enough that completion requires
verification.
- **Containment**: the host's ability to stop runaway work within a measured bound.
- **Quarantine**: policy-driven eviction of a repeatedly failing workspace.

---

## APPENDIX E — THE HARNESS SPECIFICATION

A single committed harness must be able to run, in reduced mode and full mode:

1. `throughput`: N concurrent workspaces, each running a fixed task, with wall-clock completion
rate, per-workspace latency percentiles, and a saturation point.
2. `memory`: steady-state per-workspace bytes at increasing N, with hibernation onset and
admission-refusal onset recorded.
3. `isolation`: concurrent hostile and benign workspaces; assert zero cross-effects on counts,
latencies, and evidence.
4. `containment`: runaway programs of each class; assert kill latency and neighbour impact.
5. `restart`: kill shard and daemon; assert recovery semantics, reap report, and time to steady
state.
6. `pressure`: forced disk and memory pressure; assert typed refusals and no corruption.

Each mode writes a machine-readable result (JSON) plus a human summary, both keyed by revision
and machine. The CI gate compares against the committed baseline with declared tolerances.

---

## APPENDIX F — THE ONE-PARAGRAPH SUMMARY

Structured page state with stable references is the default read channel. A persistent,
host-policed code-execution session is the default action channel, so one program performs many
operations and returns one verified result. Raw capability is the escape hatch. Pixels are a
first-class, cost-ranked option the driver can request at any moment -- priced by an explicit
budget, never produced automatically, and never withheld. Verification checks real
external state and can only say verified, failed, or inconclusive. Every workspace is isolated by
lease, every buffer is bounded, every limit is enforced by the host, and the whole thing is
designed, measured, and proven at fleet scale. If you build that, you have built the product. If
you build a screenshot loop with nicer plumbing, you have rebuilt the thing this document exists
to delete.

