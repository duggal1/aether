# 03 — Playbooks

Validated end-to-end. Follow these and you skip the trial-and-error entirely.

---

## P1 — Start the runtime

```bash
.build/release/browserd --socket /tmp/a.sock &
A=/tmp/a.sock
b() { /Users/harshitduggal/workspace/Aether/.build/release/browserctl --socket /tmp/a.sock "$@"; }

b ping                                   # {"ok":true,"engine":"NativeBrowserEngine"}
b context-create agent-profile
b context-open-profile 1 "$HOME/Library/Application Support/Aether/Profiles/agent-profile"
b session-create agent-profile
```

Do **not** pass `--token-file`; that principal cannot use sessions, credentials, handoff
or fleet (see ISSUE-001 in `agents/aether-professional-workflow/issue.md`).

---

## P2 — Sign in to an existing Google account

```bash
# 1. Save credentials (never prints the secret)
PW='<password>'
b credentials-save 1 "https://accounts.google.com" "<user@gmail.com>" "$PW" "google-account"
unset PW          # -> id, e.g. 90DA29A1-...

# 2. Open the identifier step and submit it (Rule 1 + Rule 2)
b page-navigate <p> "https://accounts.google.com/v3/signin/identifier?hl=en&flowName=GlifWebSignIn"
#    fill [name=identifier], then dispatch the event sequence on the "Next" button

# 3. Password step: lay it out, fill from the vault, submit
FULL=$(b page-eval <p> "location.href" | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['value'])")
QS="${FULL#*\?}"
b page-navigate <p> "https://accounts.google.com/v3/signin/challenge/pwd?$QS"
b credentials-fill <p> <cred-id>
#    dispatch the event sequence on "Next"

# 4. Verify — do not stop at a URL change
b page-navigate <p> "https://mail.google.com/"
b page-eval <p> "JSON.stringify({t:document.title,len:(document.body.innerText||'').length})"
```

A selfie-video upsell may appear (T10). Ignore it and go straight to Gmail.

**Success looks like:** `Inbox - <user> - Gmail`, `url=/mail/u/0/`, non-empty body.

---

## P3 — OAuth "Sign in with Google" into a SaaS (Clay, Slack — the working pattern)

```bash
# 1. Open the app's login and click the Google button (Rule 1)
# 2. If it lands on /v3/signin/accountchooser -> GOOD, it will render
# 3. Click the account tile. A bare .click() fails here:
#      ['pointerdown','mousedown','pointerup','mouseup','click'] full sequence
# 4. Consent screen -> "Continue" with the same event sequence
# 5. Verify the app's authenticated landing state
b page-resize <p> 1600 1000        # if the app renders blank
b page-eval <p> "JSON.stringify({u:location.href.slice(0,90),t:document.title})"
```

If step 2 lands on `/gsi/select` with an empty body, the site is unusable (T4). Stop.

**Onboarding wizards with required steps:** expect `<textarea>` (T5), and re-check
`document.querySelectorAll('textarea')` when Continue is disabled.

---

## P4 — Detect a hard blocker and hand off

```bash
b handoff-request <p> captcha "<exact provider wording, verbatim>"
b handoff-list                                     # observe
b handoff-claim <id> human                         # human takes over
b handoff-cancel <id> "human-authorized-<what>"    # human lets you continue
```

A pending handoff **blocks the whole context**, including `events-recent`. Exempt:
`handoff-list`, `handoff-wait`, `fleet-stats`, `page-create`.

---

## P5 — Evidence discipline

```bash
b page-render <p> /tmp/evidence/NAME.png     # 5120x3200 PNG
b page-print  <p> /tmp/evidence/NAME.pdf     # durable
b context-checkpoint 1                       # preserve state
b page-eval <p> "JSON.stringify({u:location.href.slice(0,90),t:document.title,len:(document.body.innerText||'').length})"
```

A screenshot is the only unambiguous proof. `title` containing the account address is
the strongest single assertion of authenticated state.
