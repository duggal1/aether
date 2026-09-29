# Computer Use — Aether Browser Runtime

**Audience: coding agents. Not humans.**

This is the operational skill for driving a real browser through the Aether agent runtime
(`browserd` + `browserctl`). Everything here was derived by actually driving Google,
Clay, Slack, X, Reddit and YouTube in Aether and observing what worked.

## Read this first

| File | Read it when |
|---|---|
| `00-START-HERE.md` | Always. The 6 rules that prevent every failure below. |
| `01-primitives.md` | You need the exact command/JSON for a capability. |
| `02-traps.md` | Something worked but the result is wrong or empty. |
| `03-playbooks.md` | You are doing a known task (signup, login, wizard). |
| `04-EXACT-FILE-INDEX.md` | **You are changing or debugging the runtime.** Absolute paths, exact symbol names, line numbers, and the precise fix location for every known open bug. |

## Non-negotiables

1. **Never use `page-click`.** It reports `ok` and silently does nothing on framework
   buttons. Use `page-eval` with the event sequence from `02-traps.md` §1.
2. **Never use `page-fill` for a form a framework controls.** It sets the DOM value and
   the framework wipes it on the next re-render. Use `page-eval` with the composed
   `InputEvent` from `02-traps.md` §2. (The runtime now does this for you in current
   builds — but if you are on an older binary, use the raw form.)
3. **Never trust a URL change as proof of progress.** Always assert the new step rendered.
4. **Screenshot early.** It is 2 seconds and it is the only unambiguous signal.
5. **Never write a password to a file, log, or your own output.** Use
   `credentials-save` / `credentials-fill`.
6. **Stop at CAPTCHAs, MFA, passkeys, and phone verification.** Request a handoff. Do not
   attempt to solve or bypass them.

## Daemon

```bash
.build/release/browserd --socket /tmp/a.sock          # host principal: full surface
.build/release/browserctl --socket /tmp/a.sock <cmd>  # 134 subcommands
```

`browserctl` with no arguments prints its own authoritative command list. **Read it
instead of guessing.** Never infer a command from a filename.

Do not use `--token-file`: the authenticated principal is denied `session.*`,
`credentials.*`, `handoff.*`, `fleet.*` and `approval.*`.

## Status

The runtime changed after this skill was written. Verify before trusting a primitive:

```bash
b page-eval 1 "(function(){var e=document.querySelector('input');if(!e)return 'no input';
e.focus();Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(e,'probe');
e.dispatchEvent(new InputEvent('input',{bubbles:true,composed:true,data:'probe',inputType:'insertText'}));
return 'composed ok';})()"
```

`composed ok` means the compiled fix is live and you can use the short primitives.
