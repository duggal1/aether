# Aether Agent Issues — aether-professional-workflow

Open issues discovered by executing `task.md` / `tasks.yml` against the live runtime.
Every issue here is evidence-backed: reproduced against a real `browserd` process.

---

## ISSUE-001 — Authenticated daemon (`--token-file`) denies the entire session / fleet / credential / handoff / approval surface

**Status:** OPEN
**Severity:** HIGH — blocks any authenticated (multi-client) deployment
**Found:** 2026-09-29, T1 bootstrap
**Component:** `Sources/BrowserEngine/AgentCommandDispatcher+Authority.swift`

### Reproduction

```
$ .build/release/browserd --socket /tmp/aether-mission/aether.sock \
      --token-file /tmp/aether-mission/aether.sock.token
browserd listening on /tmp/aether-mission/aether.sock, token at /tmp/aether-mission/aether.sock.token

$ b ping                       -> {"result":{"engine":"NativeBrowserEngine","ok":true}}
$ b context-create agent-profile
                              -> {"result":{"id":1,"pageCount":0,"name":"agent-profile"}}
$ b context-list               -> [{"id":1,"name":"agent-profile","pageCount":0}]
$ b page-create 1              -> OK
$ b page-list 1                -> OK
$ b context-bookmarks 1        -> OK
$ b context-cookies 1          -> OK
$ b events-recent --context 1  -> OK

$ b session-list               -> unauthorized: Operation requires ownership of this context
$ b fleet-stats                -> unauthorized: Operation requires ownership of this context
$ b handoff-list               -> unauthorized: Operation requires ownership of this context
$ b approval-list              -> unauthorized: Operation requires ownership of this context
$ b workspace-lease-list       -> unauthorized: Operation requires ownership of this context
$ b credentials-list 1         -> unauthorized: Operation requires ownership of this context
```

### Root cause

`AgentSessionStore.principal` is always `kind: .agent`
(`Sources/AgentProtocol/AgentAuth.swift:90`), so a token-authenticated connection always
takes the guarded `handle(_:principal:ownership:)` path.

That path resolves an owning context through an `if/else` chain
(`AgentCommandDispatcher+Authority.swift:55-80`). Any method that does not match a branch
falls through to:

```swift
} else { return denied() }        // line 80
```

The chain has branches for `task.verify`, `events.recent`, `page.create`/`page.list`/`context.*`,
`workspace.lease.*`, `extension.*`, `page.*`, and `handoff.*`/`approval.*`. It has **no branch**
for:

- `session.create` / `session.list` / `session.destroy` / `session.pages`
- `fleet.stats` / `fleet.pages` / `fleet.sweep`
- `credentials.list` / `.get` / `.save` / `.delete` / `.fill`
- `workspace.lease.list` when called without an explicit `context` param
  (the CLI signature is `workspace-lease-list [context]` — the context is optional, so
  `identifier("context")` returns `nil` and the `guard let context` at line 81 fails)

### Impact

`Docs/AGENT_PROTOCOL.md` documents all of these as available agent capabilities. On a
token-authenticated daemon they are **unreachable**. Consequences for this mission:

- T1 credential storage (`credentials-save` / `credentials-fill`) — blocked
- T1 session creation (`session-create`) — blocked
- T2/T6 human handoff (`handoff-request` / `handoff-wait`) — blocked
- T7 fleet supervision and per-worker isolation (`fleet-*`) — blocked

Only the **host** principal (the default, unauthenticated `browserd`, and the
`AetherApp` automation socket) reaches the full surface. So the documented,
widely-described authenticated mode is the *less* capable one.

### Secondary finding (same area)

`AgentSessionStore` issues **one** `AgentPrincipal` per daemon process
(`AgentAuth.swift:90, 110-111`). Every client presenting the same token receives the same
principal id, so per-client identity and per-client ownership are indistinguishable.
This is the previously recorded TISSUE-002 and it is **still open**. It independently
blocks T7's "verify isolation rejects cross-workspace access" requirement, because two
workers on one token are the same principal by construction.

Related dead code in the same subsystem: `AgentOwnershipRegistry.bindSession` /
`ownerOfSession` / `releaseSession` (`AgentAuthority.swift:31-37, 50-52`) are never called;
`ControlEventLedger.record` (`:93`) and `InputLeaseTable` (`:131`) have no call sites.

### Proposed fix direction

Extend the context-resolution chain so every family resolves an owner:

1. `credentials.*` → resolve from the `context` param, or from the `page` param
   (`credentials.fill`) via `pageInfo(...).contextID`.
2. `workspace.lease.list` with no `context` param → treat as a *scoped list*: return only
   leases on contexts this principal owns, instead of denying.
3. `session.*` and `fleet.*` → these are genuinely cross-context. Scope them to the
   principal's owned contexts (filter the result) rather than denying outright, and
   `bindSession` the new session on `session.create`.

Must preserve the existing security property: **an agent principal may only ever act on a
context it owns**, and the workspace-lease check at line 82-84 must still apply.

No code changed yet — the mission was unblocked by running the daemon in its default
host mode first, and the fix should be made with a regression test rather than hastily
mid-mission.
