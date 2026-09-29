# 01 — Primitives

Exact invocations. `b <cmd>` = `browserctl --socket /tmp/a.sock <cmd>`.

## Session and context

```bash
b ping                                    # health
b context-create <name>                   # -> {"id":N}
b context-list
b context-open-profile <ctx> <dir>        # persistent profile on disk
b context-checkpoint <ctx>
b context-destroy <ctx>
b session-create <name> / session-list / session-destroy <id>
```

## Page lifecycle

```bash
b page-create <ctx> [w h]                 # -> page id
b page-navigate <p> <url>
b page-resize <p> 1600 1000               # ALSO forces layout (T6)
b page-reload <p> [--bypass-cache]
b page-lifecycle <p> / page-set-lifecycle <p> <active|background|suspended|frozen|discarded>
b page-restore <p>
b page-close <p> / page-list <ctx>
```

## Reading — the read channel

```bash
b page-eval <p> "<js>"                    # returns {"value","console"} — most reliable
b page-query <p> "<css>"                  # first match
b page-query-all <p> "<css>"              # all matches
b page-inspect <p>                        # structured node list
b page-snapshot <p> [limit] [--since N]   # bounded, diffable
b page-find <p> "<text>"
b page-wait <p> "<css>" [attached|visible|hidden|detached] [timeout-ms]
b page-eval <p> "document.body.innerText" # fastest truth check
```

`page-eval` returns `{value, console}`; parse with:
```bash
b page-eval <p> "1+1" | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['value'])"
```

## Acting — the action channel

```bash
b page-click <p> <idx> <gen>              # BROKEN on framework pages -> use page-eval (T1)
b page-type  <p> <idx> <gen> "<text>"     # same caveat as fill (T2)
b page-fill  <p> <idx> <gen> "<value>"    # same caveat as fill (T2)
b page-set-value <p> <idx> <gen> "<v>"
b page-submit <p> <idx> <gen>
b page-press-key <p> <Enter|Tab|Escape|...>
b page-scroll <p> <x> <y> / page-scroll-into-view <p> <idx> <gen>
b page-select-option <p> <idx> <gen> <value>
b page-hover <p> <idx> <gen> / page-focus / page-blur
```

**For framework pages, all of the above are replaced by `page-eval`** with the patterns
in `02-traps.md` §T1 and §T2.

## Credentials

```bash
b credentials-save <ctx> "<origin>" "<user>" "<pass>" "<label>"   # -> id
b credentials-list <ctx> [origin]                                 # metadata only
b credentials-fill <page> <cred-id>                               # from Keychain
b credentials-get <ctx> <cred-id>
b credentials-delete <ctx> <cred-id>
```

## Cookies and storage

```bash
b context-cookies <ctx>                   # names/attrs; treat values as secrets
b context-set-cookie <ctx> <n> <v> <domain> [path]
b context-remove-cookie / context-clear-cookies
b context-storage-origins <ctx>
b context-storage-values <ctx> <origin>
b context-storage-set <ctx> <origin> <k> <v>
b context-permissions <ctx>
```

## Evidence

```bash
b page-render <p> /tmp/x.png
b page-print  <p> /tmp/x.pdf
b page-capture <url> /tmp/dir [--format png|jpeg|webp] [--quality 0..1] [--max-steps N]
b page-metrics <p> / page-mutations <p> [sinceVersion]
b page-console <p>                        # [] or lines; NOT a network log (T7)
```

## Fleet, handoff, approval

```bash
b fleet-stats / fleet-pages / fleet-sweep [maxActive] [memBudget]
b workspace-lease-acquire <ctx> <agent> [sec] [branch] [repoRoot] [worktree]
b workspace-lease-list / -renew / -release / -cancel
b handoff-request <p> <category> "<reason>"
b handoff-list / -claim <id> [who] / -complete / -cancel / -resume / -wait <id> [ms]
b approval-request <category> "<reason>" [--ttl-seconds N]
b approval-list / -resolve <id> <approve|deny> / -cancel / -wait
b events-recent (--context N | --page N) [--family F] [--since N] [--limit N]
b task-verify <plan.json>
b exec <program.json> [--timeout-ms N]   # code-first: 21 step ops, persistent sessions
```

Handoff categories: `handoff approval mfa captcha passkey credentials payment
sensitiveForm destructiveAction permission explicit other`.

## app.* — the packaged GUI app's own socket (no token)

```bash
b --app app-status / app-tabs / app-open <url>
b --app app-navigate|app-select|app-close|app-back|app-forward|app-reload|app-metrics <tab-uuid>
```
