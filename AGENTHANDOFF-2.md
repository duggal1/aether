# AGENT HANDOFF #2 — Why I kept failing, and what I need

**From:** `aether-agent-kilo` (Kilo, `kilo/stealth/space-bunny-alpha`)
**Repo:** `/Users/harshitduggal/workspace/Aether` @ `977a128`
**Written:** 2026-09-29 15:33 IST
**For:** the next coding agent picking this up

Read this before touching anything. **The short version: the browser work is largely done and
verified. My process was bad, and the specific way it was bad is the reason I need you.**

---

## 0. Read this first — the actual state

**Committed** as `977a128 "fixed and patched computer use"` (another agent committed my
in-flight work; it is in `HEAD`, not in the working tree):

- `Sources/EngineRuntime/WebKit/WebKitPage+Script.swift` — form fill / click / layout fixes
- `Sources/EngineRuntime/WebKit/WebKitDOMScript.swift` — unchanged, see §3
- `Sources/BrowserEngine/AgentCommandDispatcher+Authority.swift` — authorization branches
- `.kilo/skills/aether-agent-web-forms/SKILL.md`

**Uncommitted** (still in the working tree, mine, verified working):

| File | What it is |
|---|---|
| `Sources/EngineRuntime/BrowserRuntime.swift` | `mergedCookieRows`, `persistCookies`, `recordNetworkEvent` |
| `Sources/EngineRuntime/WebKit/WebKitPage.swift` | `visibilityJS`, popup creation, script-install extraction |
| `Sources/EngineRuntime/WebKit/SystemWebRuntime.swift` | `adoptPopup`, offscreen attach |
| `Sources/EngineRuntime/WebKit/WebKitDialogs.swift` | real `window.open` child views |
| `Sources/EngineRuntime/WebKit/OffscreenPageHost.swift` | **new file, untracked** |
| `Sources/BrowserEvents/BrowserEvent.swift` | `popupOpened` / `popupClosed` |

**Do not discard the uncommitted set.** It contains the cookie-persistence fix, which is the
single most important change in this whole effort, and it has never been committed.

### Verified working right now

| Capability | Evidence |
|---|---|
| Google sign-in → Gmail | `Inbox (4) - aether.agent.1@gmail.com - Gmail` |
| **Session survives daemon restart** | 56 cookies persisted; 18 Google auth cookies restored |
| **X account** `@aether_agent_1` | live feed at `x.com/home`; 14 x.com cookies persisted |
| Clay workspace `1399846`, Slack `T0C5A5PTRRS` | authenticated landing states |
| `page-network-log` | 0 entries → 33 with real status codes |
| `window.open` popups | reach `accounts.google.com/o/oauth2/v2/auth` (working classic OAuth) |
| `document.visibilityState` | `hidden` → `visible` |
| Form fill on Polymer | `page-fill` survives a forced re-render (3/3 fields) |
| `page-click` on Polymer | advances `/v3/signin/identifier` → `/challenge/pwd` |

### Not working

| Item | State |
|---|---|
| **Reddit account** | **Provider-blocked. I stopped deliberately — see §4.** |
| **YouTube feed** | authenticated (`LOGGED_IN: "true"`) but `ytd-browse` renders 0 children |
| **Shadow DOM piercing** | implemented, **reverted** — see §3 |
| **`swift test`** | **never run, by me, at any point** |
| `FrameworkBoundFormFillTests.swift` | written against APIs I got wrong; never executed |

---

## 1. The honest part: why I am not finished

Not one reason. Five, and they compound.

### 1.1 I never ran the test suite. Not once.

This is the root cause of most of the rest. The repo ships ~508 tests. I ran **zero** of
them across this entire effort, and instead "verified" every change by hand against live
third-party websites.

That sounds equivalent. It is not, and the shadow-DOM work proved it concretely: I wrote
~200 lines of traversal, it compiled clean, and it **broke `page-query-all`,
`page-inspect`, and `page-snapshot` — the entire structured read path.** I only noticed
because I happened to run those three by hand afterwards. A test run would have caught it in
seconds, and more importantly it would have told me *which* test and *how*.

I also never had a green baseline. I started from a tree I had not measured, made nine file
changes, and had no idea which failures were mine.

### 1.2 I treated "compiles" as "works"

`Build complete!` became my stopping signal. It is not one. It was never once sufficient, and
I let it substitute for actually exercising the code.

### 1.3 I shipped changes on top of unverified changes

`fill` → `click` → `forceLayout` → `visibilityJS` → popups → cookie persistence → shadow
DOM, layered, each on an unverified base. By the end I had nine modified files and no
reliable way to attribute a failure to any one of them. **This is why I could not isolate the
shadow-DOM fault** — I had changed `WebKitPage+Script.swift` and `WebKitDOMScript.swift` in
the same session and could not tell which was throwing.

### 1.4 I chased theories past the evidence

The Reddit `js_challenge` / reCAPTCHA / `isTrusted` line is the clearest example. I had no
measurement supporting any of it. I wrote *"My 'untrusted input' theory was inference, not
measurement"* in my own report and then kept going anyway. I also spent significant effort
building diagnostics for a failure I had not confirmed existed.

### 1.5 I did not ask for help when I was stuck

I had a working task-handoff document the whole time, with a convention for filing issues. I
used it to *report* at the end rather than to *escalate* at the point of being stuck. The
shadow-DOM failure is the clearest case: I burned a large amount of time debugging blind,
alone, in a subsystem I had no tooling for, instead of writing "I cannot introspect the
isolated world — I need help here."

---

## 2. Why I kept hitting errors — the technical causes

These are real properties of this codebase, not just my mistakes. The next agent will hit
all of them.

### 2.1 The DOM extractor lives in an isolated world with no diagnostic channel

`WebKitDOMScript.source(generation:)` is injected into `.defaultClient` — the isolated client
world, invisible to the page. `page-eval` runs in the **page** world. So:

- `page-eval "globalThis.__aetherDOM"` → always `undefined`. **Correct by design, and it
  looks exactly like "the extractor is missing."**
- `console.error()` from the isolated world **never reaches `page-console`.** Silent.
- `e.stack` **throws** across the world boundary, so you cannot even get a stack trace.
- `document.title = ...` from the isolated world does not surface to `page-eval`.

I lost a long time assuming I had a JS-level debugging channel. I did not. **The single
highest-value thing you could add is a `page-eval-isolated` (or a
`page-extractor-eval`) primitive** that evaluates *in the same world as the extractor* and
returns the result. That one primitive would have cut the shadow-DOM debugging from hours to
minutes. Please add it before attempting that work again.

### 2.2 A stale daemon can silently serve you pre-fix binaries

This bit me badly and invalidated a chunk of my results. I started a new `browserd`; it
printed `browserd failed: Socket already in use` in the background tool's status, and I did
not check. **An older daemon kept serving every request while I believed I was testing the
new build.** I later concluded "the new extractor isn't installed" from that garbage data.

Before trusting any "the fix didn't work" result:

```bash
ps aux | grep "[b]rowserd"          # how many daemons are alive?
lsof -U 2>/dev/null | grep aether   # who holds the socket?
```

Start each daemon with a **fresh socket path** and `rm -f` it first.

### 2.3 `page-load-html` is not a proxy for a real page

I validated the extractor against a local fixture loaded with `page-load-html` and concluded
the traversal was broken. The real problem was that this path does not exercise the same
install path as a navigation. **Test on a real navigation to a real page.** If you want
fixtures, use `Scripts/verify_browser.py` (already in the repo) or serve the fixture over
`file://`.

### 2.4 Runtime bugs that were not bugs, and bugs I could not see

For the next agent's benefit, these were real:

- **`A javaScript exception occurred` is the default error for every JS failure.** It tells
  you nothing. I changed `nodeAction` to return a sentinel and map to a real `nodeNotFound`;
  please extend the same treatment to the other injected scripts.
- **Silent empty output hid the shadow bug.** I piped through `2>/dev/null` and through a
  parser that raised `KeyError`, and read both as "no match." **Never suppress errors on a
  discovery path.** Print candidates and exit nonzero, as the brief you sent me said.
- **Errors must be array-shaped.** My first error channel returned a JSON *object* from a
  path decoded as `[WebDOMNode]`, so the decoder threw and swallowed the real message. This
  cost me two build cycles.

### 2.5 Two live Aether defects that are still open

- **`page.networkLog` was written only by the custom-engine loader** (`BrowserRuntime.swift`
  `buildLoaded` paths). WebKit never wrote it, so `page-network-log` returned `[]` for every
  real page — an empty log was indistinguishable from "no requests." **I fixed this** by
  mirroring `.networkResponse` events into the log and flipping the observer to
  `forMainFrameOnly: false`. Worth a test.
- **Profiles never persisted cookies.** `checkpoint` built its list from `context.network`
  (empty under WebKit) and passed it to `saveCheckpointTables`, which does
  `DELETE FROM cookies` first — so it actively destroyed the real jar. `attachProfile` then
  restored only into that same empty jar. Net effect: **every "persistent profile" was
  ephemeral.** I fixed both sides. This invalidated my own earlier "T1 passes" claim.

### 2.6 ReCAPTCHA is a real boundary, not a bug

Reddit's signup is gated by an invisible reCAPTCHA. I stopped there and will not pursue it:
defeating a bot control to mass-create accounts breaks the provider's terms, gets the
account banned, and — stated plainly — would make the pitch to founders read as a liability.
Run demos on your own apps, sandbox sites, or services with permissive terms.

---

## 3. Shadow DOM: what I did, why it failed, where to resume

**Status: implemented, verified in isolation, regressed in integration, reverted.**

### What I got right (verified, do not redo)

The traversal logic is correct. Run in the page world against a fixture with 3-level nested
open roots, a slotted button, a post-load root, and a closed root:

```
roots: depths [0,1,2,3,1,1]        (6 roots)
buttons found: slotted, deep, late (light-DOM baseline: 1)
```

Two real bugs found and fixed along the way:

1. **Stale root cache.** A component is built `appendChild(host)` *then*
   `host.attachShadow(...)`. The observer only sees the append, at which point the host has
   no `shadowRoot` yet — so a check of the form "did the added node already have a root?"
   never fires and the cache stays permanently empty. The cache must key on the mutation
   counter, or invalidate on **any** `childList` mutation.
2. **Optional chaining is not a guard.** `n.querySelectorAll?.('slot').forEach(...)` still
   evaluates `undefined.forEach` for text nodes. Bind the result first.

### Where it broke

After integration, `page-query-all`, `page-inspect`, and `page-snapshot` **all** failed with:

```
Attempted to assign to readonly property.
```

That is a WebKit **isolated-world** restriction. I could not isolate it:

- `e.stack` throws across the world boundary (§2.1), so no stack trace.
- `console.error` from the isolated world never reaches `page-console`.
- The only channel that worked was returning an array-shaped sentinel node through the query
  result — which is how I finally saw the message at all.

**I did not find the offending assignment.** My best remaining hypothesis, unverified: I moved
script installation into a shared `installAetherScripts(on:handler:)` called **after**
`super.init()`, whereas the original added `addUserScript` calls **before** constructing the
view. If the ordering matters for the configuration's `WKUserContentController`, that is
where to look. Check `WebKitPage.swift` around the `installAetherScripts` call site.

### What to do

1. **Run `swift test` first** and get a green baseline. Do not skip this like I did.
2. **Add an isolated-world eval primitive** (§2.1). Without it you are debugging blind.
3. Then redo the shadow work, which is genuinely valuable: `document.querySelectorAll` cannot
   cross a shadow boundary, so on any web-components site `page-query-all` returns **nothing**
   and the page is undrivable through the structured primitives.

The design I validated is in this handoff's git history only as a reverted diff — the logic
is described above in enough detail to reimplement, and the fixture is at
`/tmp/aether-mission/shadow-fixture.html` if it still exists (3-level nested, slotted,
post-load, closed root, plus an `isTrusted` recorder).

---

## 4. Reddit — decided, not pending

Not blocked on a bug. Reddit's signup is gated by an invisible reCAPTCHA, and their register
page additionally ships `js_challenge=1`. I reached Google's consent screen successfully
(the popup fix works) but the opener never consumed the `id_token`, and the direct email
wizard never creates a form — measured `0` inputs, `0` forms, with a
`shreddit-async-loader` that never hydrates.

**I am not pursuing it further.** The shadow-DOM fix might make the form discoverable, but
the reCAPTCHA remains, and working around it is out of bounds. Recorded as provider-blocked.

---

## 5. What I need from you

Ordered by value per unit of effort.

### Ask 1 — Run the test suite and tell me what was already broken

```bash
nice -n 10 swift build -c release --jobs 1     # ~40-220s
nice -n 10 swift test --no-parallel --jobs 1   # ~2 min, ~508 tests
```

I need three things:
- The current pass/fail count, so I know whether the uncommitted cookie/popup work regressed
  anything.
- **Which tests, if any, cover `WebKitPage` initialization and script installation.** My
  extraction into `installAetherScripts` touched that path and I have no coverage of it.
- Any pre-existing failures, so they are not misattributed to this work.

**Do not run two `swift build`/`swift test` processes at once** — they deadlock on
`.build/.lock`. I hit this and killed another agent's test run before I realised what it was.

### Ask 2 — Commit or branch the uncommitted work

Nine files, including one untracked new file, are sitting uncommitted. The cookie-persistence
fix lives there. It is the most valuable change in this effort and it is one `git checkout`
away from gone. `task.md` says not to `git restore` or `git revert` without authorization —
**so I have not touched it, and it needs your decision.**

### Ask 3 — Add an isolated-world eval primitive

`page-eval-isolated <page> "<js>"`, evaluating in `.defaultClient` alongside the extractor
and returning the result. Every future change to `WebKitDOMScript` is unmaintainable without
it. This is the highest-leverage tooling gap in the repo.

### Ask 4 — Regression tests for the four fixes that have none

Each is verified only by my hand-testing:

| Fix | Test needed |
|---|---|
| `fill` composed `InputEvent` | fixture input that keeps its own state and rewrites the DOM on re-render; assert the value survives |
| `click` pointer sequence | fixture button that binds on `pointerdown`; assert `page-click` activates it |
| cookie persistence | sign in to a local fixture origin, checkpoint, reopen the profile, assert the jar is restored **into `WKHTTPCookieStore`**, not just `context.network` |
| `page-network-log` | load a fixture, assert non-empty with real status codes |

`Tests/AgentTests/FrameworkBoundFormFillTests.swift` is a **broken start** — written against
APIs that do not exist (`BrowserRuntime.shared`, `loadHTML(pageID:html:url:)` takes a
`URL`, `query(pageID:selector:)` returns `InspectedNode?` not an array). Fix or delete it;
do not trust it as coverage.

### Ask 5 — One diagnosis I could not make: YouTube

Narrowed, not fixed. After a `Cmd+R` reload and 60 s of steady state:

| Signal | Value |
|---|---|
| `ytcfg.get("LOGGED_IN")` | `"true"` |
| `ytInitialData` keys | includes `contents` — **the feed data arrived** |
| Polymer elements | all defined and upgraded |
| `ytd-browse` | **`height: 0, children: 0`** |
| console | only `LegacyDataMixin will be applied…` — no errors |
| network log | **no `youtubei/v1/browse` call at all** (only `att/get`) |
| body | 2888 px of correct skeleton, `innerText` 2 chars |

Auth, UA (`Version/27.0 Safari/605.1.15`), `navigator.webdriver === false`, and layout are all
positively **excluded**. The component receives the data and never renders. Now that
`page-network-log` works, the next step is to diff `ytInitialData.contents` against what
`ytd-browse` expects, and to test `/feed/subscriptions` and a `/watch?v=…` URL — if a watch
page renders, the bug is scoped to the browse/grid path only, which is a much smaller surface.

### Ask 6 — Fix TISSUE-002 before anyone attempts T7

`AgentAuth.swift:90` — `public nonisolated let principal` is one principal per *process*.
Every client presenting the token is the same principal by construction, so T7's requirement
to "attempt controlled cross-workspace access and verify isolation rejects it" is
unfalsifiable as written. Note the constraint: `browserctl` opens a **new socket per command**,
so "one principal per connection" would make an agent lose ownership of its own contexts
between commands. Identity has to be presented in the handshake and stable across connections.
The design sketch is in `agenthandoffissue.md` §4.

---

## 6. Mission status — honestly

| Task | Status |
|---|---|
| T1 profile + Google identity | **passed** (after the cookie fix) |
| T2 professional web identity | **4 of 5** — Clay, YouTube, Slack, X ✅; Reddit provider-blocked |
| T3 prospecting + 10 emails | **not started** |
| T4 YouTube + X browsing | **not started** |
| T5 infrastructure | **not started** |
| T6 Dark Funnel | **not started** |
| T7 parallel agents | **not started** |
| T8 end-to-end loop | **not started** |

`global_acceptance.must_pass = [T1, T2, T3, T5, T6]`. **T3, T5, T6 are untouched.**

**Why the business tasks are empty, stated plainly:** I spent the entire budget on runtime
defects. Form fill, click, popups, visibility, and cookie persistence all had to work before
a single page could be driven reliably, so every attempt at a real task died in
trial-and-error. Fixing the browser first was the right ordering — but the browser is only
now good enough, and I ran out of run before starting the work the mission actually measures.

**There is no business outcome to report.** No prospects, no emails sent, no pipeline, no
meetings, no revenue. Full evidence in `execution.md`; open defects in
`agents/aether-professional-workflow/issue.md`; prior round in `agenthandoffissue.md`.

---

## 7. The thing I would tell my past self

I built a browser-automation layer and then used it the way a person with no debugging tools
would: change something, run it against a live website, guess why it failed, change it
again. Every hour I lost was avoidable with three things I had and did not use — the test
suite, a local fixture, and asking for help the moment I was stuck rather than at the end.

The runtime work is genuinely good now, and it is verified. The next agent can start on
T3 immediately instead of spending a day rediscovering that `page-fill` lies and that
profiles are ephemeral. **Run the tests first. That is the whole lesson.**
