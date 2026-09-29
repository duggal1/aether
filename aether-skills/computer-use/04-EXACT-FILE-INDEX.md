# EXACT FILE INDEX — Aether Agent Mission Handoff

Absolute paths, exact symbol names, exact line numbers. No guessing required.
Repo root: `/Users/harshitduggal/workspace/Aether`
Branch: `feature/code-first-browser-runtime-20260727` → actual: `feature/code-first-browser-runtime-20260927`

**Line numbers are against the working tree as of 2026-09-29 11:52 IST, which contains my
uncommitted fixes.** Re-grep by symbol name if the file has moved.

---

# PART 1 — FILES I MODIFIED (fixes, built, verified)

A build is required to inherit these. `nice -n 10 swift build -c release --jobs 1`

## 1.1 `Sources/EngineRuntime/WebKit/WebKitPage+Script.swift`  ← most important file

The WebKit interaction layer. Nearly every agent primitive lands here.

| Line | Symbol | What I changed | Why |
|---|---|---|---|
| **300** | `static let forceLayout` | **NEW.** Dispatches a synthetic `resize` then forces layout via `offsetHeight` | Newly-loaded SPAs hold DOM nodes at `0×0` with null `offsetParent`; structured queries can't see them. Injected into `query` and `interactionTarget` so every interaction lays out first. |
| **279** | `func click(_ node: NodeID)` | Replaced bare `n.click()` with `pointerdown → mousedown → pointerup → mouseup → click` `MouseEvent` sequence; prepends `forceLayout` | `page-click` returned `{"ok":true}` and did nothing on Google/Polymer buttons |
| **390** | `func fill(_ node: NodeID, value: String, append: Bool)` | Native value setter + **composed `InputEvent`** + `change` + `blur`; added `checkbox`/`radio` branch; reordered `isContentEditable` last; prepends `forceLayout` | Value was written to the DOM but the framework kept its own copy and **wiped it on the next re-render** |
| **66** | `func query(_ selector: String)` | Prepends `forceLayout` | Invisible-element class eliminated |
| **233** | `func interactionTarget(_ node: NodeID)` | Prepends `forceLayout` | Click/type coordinates were computed against an unlaid-out document |
| **217** | `func nodeAction(_ node: NodeID, body: String)` | Returns sentinel `"__aether_node_missing__"` instead of throwing in-page; maps to `BrowserRuntimeError.nodeNotFound` | A stale node surfaced as the useless `"A JavaScript exception occurred"` |
| **157** | inside `pressKey` | `new Event('input', {bubbles:true})` → `new InputEvent('input', {composed:true, …})` | `page-press-key` had the same non-composed bug as `fill` |
| **177** | `func snapshot(info:limit:since:)` | **NOT changed** — this is open bug C (§2.3) | |

## 1.2 `Sources/EngineRuntime/WebKit/WebKitPage.swift`

The injected user script that provides `window.__aetherCredentialForms` (installed in an
isolated world at document start).

| Line | Symbol | What I changed |
|---|---|---|
| **422** | `const setValue = (element, value)` | Composed `InputEvent` + `composed: true` on `change` (was non-composed `Event`) |
| **455** | `fill: (fillUser, fillPassword, username, password)` | Was `setValue(fields[0], password)` — **now `fields.forEach(...)`** so confirm-password fields are filled |

Symbol to search: `__aetherCredentialForms`. This is what `credentials-fill` and
`fillCredentials` call.

## 1.3 `Sources/BrowserEngine/AgentCommandDispatcher+Authority.swift`

Authorization gate for non-host principals. **This is why `--token-file` could not do
anything useful.**

| Line | Branch added |
|---|---|
| **70** | `credentials.*` with a `page` param → resolve context from `pageInfo` |
| **72** | `credentials.*` otherwise → resolve from explicit `context` |
| **76** | `workspace.lease.list` with no context → filter result to owned contexts instead of denying |
| **95** | `session.*` with a `session` param → `ownership.ownerOfSession(session) == principal.id` |
| **99** | `session.create` → binds new session via `ownership.bindSession`; `session.list` denied |
| **110** | `fleet.*` → requires ≥1 owned context |

Original defect was at the chain's `else { return denied() }` fallthrough.

## 1.4 Files I created

| Path | Purpose |
|---|---|
| `/Users/harshitduggal/workspace/Aether/execution.md` | Full mission ledger, all evidence |
| `/Users/harshitduggal/workspace/Aether/agenthandoffissue.md` | This mission's status + requests for help |
| `/Users/harshitduggal/workspace/Aether/agents/aether-professional-workflow/issue.md` | ISSUE-001 (auth denial), ISSUE-002, ISSUE-003 |
| `/Users/harshitduggal/workspace/Aether/Tests/AgentTests/FrameworkBoundFormFillTests.swift` | Regression tests for §1.1 fill — **written, never executed** |
| `/Users/harshitduggal/workspace/Aether/aether-skills/computer-use/SKILL.md` | Skill index |
| `/Users/harshitduggal/workspace/Aether/aether-skills/computer-use/00-START-HERE.md` | The 6 rules |
| `/Users/harshitduggal/workspace/Aether/aether-skills/computer-use/01-primitives.md` | Exact command surface |
| `/Users/harshitduggal/workspace/Aether/aether-skills/computer-use/02-traps.md` | 10 traps, symptom→cause→fix |
| `/Users/harshitduggal/workspace/Aether/aether-skills/computer-use/03-playbooks.md` | Signup / login / OAuth / handoff |
| `/Users/harshitduggal/workspace/Aether/.kilo/skills/aether-agent-web-forms/SKILL.md` | Same content, registered skill location |

---

# PART 2 — FILES TO FIX (open bugs, in priority order)

## 2.1 HIGHEST — `page-network-log` is never populated for WebKit pages

**This is the root blocker for diagnosing the GSI and YouTube bugs.** I traced it exactly.

`page.networkLog.append` occurs at **exactly two** places, both in `BrowserRuntime.swift`:

- `Sources/EngineRuntime/BrowserRuntime.swift:1689` — inside the custom-engine navigation path
- `Sources/EngineRuntime/BrowserRuntime.swift:2010` — inside `loadHTML`, also custom-engine

Both sit next to `buildLoaded(html:url:viewport:storage:network:page:jar:blocker:)` — the
**experimental** engine's loader. **The WebKit production path never appends anything.**

Read chain:
```
Sources/BrowserEngine/AgentCommandDispatcher.swift:339   try await engine.runtime.networkLogEntries(...)
Sources/BrowserEngine/BrowserEngine.swift:239             public func networkLogEntries(pageID:) 
Sources/EngineRuntime/BrowserRuntime.swift:1392           public func networkLogEntries(pageID:) throws
Sources/EngineRuntime/BrowserRuntime.swift:45             var networkLog: [NetworkLogEntry]
```

**Fix location** — the WebKit navigation delegate already exists:
```
Sources/EngineRuntime/WebKit/WebKitPage.swift:1259   func webView(_:didStartProvisionalNavigation:)
Sources/EngineRuntime/WebKit/WebKitPage.swift:1405   func webView(_:decidePolicyFor navigationAction:)
Sources/EngineRuntime/WebKit/WebKitPage.swift:1417   func webView(_:decidePolicyFor navigationResponse:)
```
Wire these into `page.networkLog`. Note the field is capped to the last 32 entries
(`BrowserRuntime.swift:1694`) and only ever records **navigations** — subresources, XHR and
fetch are never captured. If you need the GSI diagnosis you almost certainly need
per-resource visibility, not just navigations; that means intercepting at the
`WKNavigationDelegate` + a `WKURLSchemeHandler` or the inspector path.

**Also worth reading:** `Sources/EngineRuntime/WebKit/WebKitInspector.swift` — it may already
hold the plumbing.

## 2.2 HIGH — TISSUE-002: one principal per daemon process

```
Sources/AgentProtocol/AgentAuth.swift:90
  public nonisolated let principal = AgentPrincipal(id: UUID().uuidString, kind: .agent)
```
It is a single `let` on the session store, so **every** client presenting the token gets the
same principal id. Compare `AgentAuth.swift:21` (`public static let host`).

**Impact:** T7 requires "attempt controlled cross-workspace access and verify isolation
rejects it" — with one principal per process the test is meaningless by construction.

Related, and currently **dead code** (no call sites anywhere):
- `Sources/AgentProtocol/AgentAuthority.swift:31-37` — `bindSession`, `ownerOfSession`, `releaseSession`
- `Sources/AgentProtocol/AgentAuthority.swift:93` — `ControlEventLedger.record`
- `Sources/AgentProtocol/AgentAuthority.swift:131` — `InputLeaseTable`

My §1.3 change is the first real caller of `bindSession` / `ownerOfSession`.

## 2.3 MEDIUM — `page-inspect` describes a superseded document

```
Sources/EngineRuntime/BrowserRuntime.swift:807   public func inspect(pageID:) async throws -> PageInspection
Sources/EngineRuntime/WebKit/WebKitPage+Script.swift:177   func snapshot(info:limit:since:)
```
On the Google birthday step, `page-inspect` returned the **previous** step's nodes while the
URL had already advanced. Workaround used: `page-query-all` + `page-render` screenshot.
Generational `(index, generation)` refs were correct throughout — it is the aggregate view
that is wrong.

## 2.4 UNFIXABLE TODAY — Google's GSI account chooser renders blank

`https://accounts.google.com/gsi/select?client_id=…` → empty document, **no console error**.

There is no Aether file to fix. What to read:
- `Sources/EngineRuntime/WebKit/WebKitPage.swift:1405` — `decidePolicyFor navigationAction`:
  the place to detect a popup-shaped URL and route it through a window that has a real
  opener relationship, if the opener hypothesis is right.
- The bundle that loads and never paints:
  `https://ssl.gstatic.com/_/gsi/_/js/k=gsi.gsi.en_GB.vX3EWRjMpv0.O/…`
  Grep it for the guard that suppresses the account list when there is no opener / no FedCM
  / no `postMessage` parent. That is static analysis of a public asset.
- Working comparison: `accounts.google.com/v3/signin/…` (Clay, Slack) completes fine.

## 2.5 UNFIXABLE TODAY — YouTube feed never renders

`0` `ytd-rich-item-renderer`, `bodyLen = 32`, on www and m, after reload and after
`page-resize`. Ruled out: auth, user-agent (`Version/27.0 Safari/605.1.15`),
`navigator.webdriver === false`, and lazy layout (a resize made *nav* appear but never
videos). Needs §2.1 first.

## 2.6 LOW — CLI / docs defects

| Defect | File | Line |
|---|---|---|
| `page-open` prints **two** JSON documents (does `page.create` then `page.navigate`, prints both) → not pipe-safe | `Sources/browserctl/main.swift` | find the `page-open` case |
| `browserctl` with no args prints its own usage — **use this, never infer commands** | `Sources/browserctl/main.swift` | — |
| `README.md` claims "zero SwiftUI/AppKit code" (84 SwiftUI files exist), lists 8 deleted Graphics files, says `Scripts/` is empty (18 files) | `README.md` | 46, 395, 182 |
| `task.md:36` points at `manual.md` — **does not exist** | `task.md` | 36 |
| `AGENT_PROTOCOL.md` says 89 methods (there are 123); advertises a `bad_parameter` code never emitted | `Docs/AGENT_PROTOCOL.md` | — |

---

# PART 3 — WHERE EACH BEHAVIOUR LIVES

For when you change something and need to know what else depends on it.

| Concern | File | Key symbols |
|---|---|---|
| Agent command dispatch (all 123 methods) | `Sources/BrowserEngine/AgentCommandDispatcher.swift` | `handle(_:)`; `networkLogJSON` at :1010 |
| Authorization gate | `Sources/BrowserEngine/AgentCommandDispatcher+Authority.swift` | `handle(_:principal:ownership:)` |
| Ownership registry | `Sources/AgentProtocol/AgentAuthority.swift` | `AgentOwnershipRegistry`, `ownerOfContext`, `bindSession` |
| Auth / principals | `Sources/AgentProtocol/AgentAuth.swift` | `AgentPrincipal`, `AgentAuthenticator`, `host` at :21, `principal` at :90 |
| Wire protocol | `Sources/AgentProtocol/*.swift` | newline-delimited JSON over `AF_UNIX`; **not** JSON-RPC |
| CLI (134 subcommands) | `Sources/browserctl/main.swift` | prints usage when run with no args |
| Daemon | `Sources/browserd/main.swift` | `--socket`, `--token-file`, `--no-auth` |
| MCP surface (1 tool, 123 methods) | `Sources/aether-mcp/main.swift` | `aether_call` |
| Runtime core | `Sources/EngineRuntime/BrowserRuntime.swift` | `inspect` :807, `networkLogEntries` :1392, `PageState.networkLog` :45 |
| WebKit page | `Sources/EngineRuntime/WebKit/WebKitPage.swift` | `WKNavigationDelegate` :157, `didStartProvisionalNavigation` :1259, `decidePolicyFor` :1405/:1417, `__aetherCredentialForms` :422/:455 |
| WebKit interaction | `Sources/EngineRuntime/WebKit/WebKitPage+Script.swift` | see Part 1.1 |
| DOM extractor (the `index`/`generation` refs) | `Sources/EngineRuntime/WebKit/WebKitDOMScript.swift` | `source(generation:)`, `activation(generation:)`, `describe(_:)`, `get(_:)` |
| Credential vault | `Sources/EngineRuntime/CredentialVault.swift` | `fillCredential(pageID:credentialID:)` ~:230 |
| Handoff / approval types | `Sources/EngineRuntime/Handoff/HandoffTypes.swift` | `HumanRequestCategory` :9, `HandoffState` :23, `HandoffError` :136 |
| Handoff gate (fail-closed) | `BrowserRuntime` | blocks `page-eval`/`page-click`/`page-navigate` and context `events-recent` while a handoff is open; exempts `handoff-list`, `handoff-wait`, `fleet-stats`, `page-create` |
| Profile persistence | `Sources/Persistence/` | SQLite v4, WAL, `state.sqlite` |
| User agent | `Sources/EngineRuntime/WebKit/WebKitUserAgent.swift` | emits `Version/27.0 Safari/605.1.15` |
| Workspace leases | `Sources/EngineRuntime/BrowserRuntime+WorkspaceLeases.swift` | `workspaceLease(contextID:)` :106 |
| Code-first executor | `Sources/AgentExecRuntime/` | 21 step ops, persistent sessions, lease-bound revocation |

---

# PART 4 — VERIFY BEFORE YOU TRUST

Do **not** assume my fixes are correct because they compiled. Re-run these:

```bash
cd /Users/harshitduggal/workspace/Aether
nice -n 10 swift build -c release --jobs 1        # required
nice -n 10 swift test --no-parallel --jobs 1       # ~2 min, 508 tests expected green
```

**`Tests/AgentTests/FrameworkBoundFormFillTests.swift` has never been executed.** I wrote it
against APIs I then discovered were wrong (`BrowserRuntime.shared` does not exist;
`loadHTML(pageID:html:url:)` takes a `URL`; `query(pageID:selector:)` returns
`InspectedNode?`, not an array). Fix or delete it before trusting it as coverage.

Two independent checks I ran that a new agent should repeat:

```bash
A=/tmp/a.sock
b() { ./.build/release/browserctl --socket /tmp/a.sock "$@"; }

# (a) fill survives a framework re-render — run against a fixture that keeps its own state
b page-eval <p> "window.__rerender(); 'ok'"        # then re-read the value
#   before the fix: emptied.   after: preserved.

# (b) plain page-click advances a real Polymer wizard
b page-navigate <p> "https://accounts.google.com/v3/signin/identifier?hl=en&flowName=GlifWebSignIn"
b page-fill <p> <idx> <gen> "someone@gmail.com"
b page-click <p> <nextIdx> <gen>                    # "Next"
b page-eval <p> "location.pathname"
#   before the fix: stayed on /v3/signin/identifier.
#   after:          /v3/signin/challenge/pwd
```

**Re-read the `generation` immediately before every action.** It changes on each document
swap; acting on a stale one fails, and that failure used to be reported as
`"A JavaScript exception occurred"` (now fixed to `nodeNotFound`).

**Never run two `swift build` / `swift test` processes concurrently** — they deadlock on
`.build/.lock`. I hit this and it cost time.
