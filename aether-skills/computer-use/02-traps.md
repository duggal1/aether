# 02 — Traps

Every trap below cost real time in a live run. Symptom → cause → fix.

---

## T1 — `page-click` silently does nothing

**Symptom:** `{"ok":true}`, page unchanged.
**Cause:** native pointer misses framework hit targets.
**Fix:** Rule 1 in `00-START-HERE.md`. Full MouseEvent sequence.

A bare `el.click()` is *also* insufficient on Google — the sequence is required.

---

## T2 — Filled value silently reverts

**Symptom:** field reads back filled; after any re-render it is empty.
**Cause:** framework owns the value; bare assignment never reached it.
**Fix:** Rule 2. Native setter + composed `InputEvent` + `blur`.

**This also silently breaks `credentials-fill`** on confirm-password forms, because the
old code filled only the *first* password field. Fill **all** visible password fields.

---

## T3 — New wizard step renders 0×0

**Symptom:** `location.pathname` advanced, screenshot shows the **old** step, new inputs
measure `0×0`.
**Cause:** WebKit left the SPA transition un-laid-out.
**Fix:** Rule 3. Re-navigate to the step URL with the full query string.

---

## T4 — Google's GSI "Sign in with Google" renders a blank page

**Symptom:** `accounts.google.com/gsi/select`, `innerText === ''`, 1 div, 0 iframes,
**no console errors**.
**Cause:** GSI is a popup that completes a `postMessage` handshake with its opener. With
no opener it never paints.
**Fix:** not fixable in the runtime. **Route around it.**

| Flow | URL | Works in Aether |
|---|---|---|
| Classic OAuth | `accounts.google.com/v3/signin/…` | **yes** — Clay, Slack |
| GSI / One Tap | `accounts.google.com/gsi/select` | **no** — X, Reddit, most SaaS |

**Detect in one call and move on — do not retry:**
```bash
b page-eval <p> "JSON.stringify({u:location.href.slice(0,60),len:(document.body.innerText||'').length})"
```
`/gsi/select` + `len:0` → dead end. Use the site's email form, phone flow, or a
non-popup Google option if one exists.

---

## T5 — A required field is a `<textarea>`, not an `<input>`

**Symptom:** Continue button stays `[DISABLED]`; `querySelector('input')` finds nothing.
**Cause:** the field is a textarea.
**Fix:** enumerate before concluding a field is missing.
```js
JSON.stringify({
  inputs: document.querySelectorAll('input').length,
  textareas: document.querySelectorAll('textarea').length,
  buttons: Array.from(document.querySelectorAll('button'))
    .map(function(b){return (b.innerText||'').trim()+(b.disabled?' [DISABLED]':'');})
})
```

**A disabled Continue button always means a required field is empty.** Go find the field;
never re-click.

---

## T6 — Nothing renders until you force a layout

**Symptom:** screenshot shows UI; `innerText` is 32 chars; queries return nothing.
**Fix:** `page-resize` + a `resize` event. See Rule 4.

---

## T7 — `page-network-log` returns `[]`

The network observer is not wired in the headless daemon. An empty log is **not** evidence
of no traffic and **not** evidence of a blocked request. Use `page-console` and DOM state.

---

## T8 — Gmail rejects hyphens in the local part

```
Sorry, only letters (a-z), numbers (0-9), and periods (.) are allowed.
```

`aether-agent-name@gmail.com` is **impossible**. Use `aetheragentname@gmail.com`.
Check the constraint before filling, not after.

---

## T9 — Provider policies that end the flow

| Provider | Wall |
|---|---|
| Google (new account) | Physical **phone QR verification** — *"preventing abuse from computer programs or bots"*. No skip. |
| Google (new account) | Mandatory **date of birth** identity data. |
| X | *"Email signups are only allowed on the apps."* Web email signup is prohibited. |
| X / Reddit | Google sign-in uses GSI → T4. |
| Slack (email) | **reCAPTCHA** — use the Google button instead; Slack's Google OAuth uses the working classic flow. |

---

## T10 — Google offers a selfie-video upsell after sign-in

`/verification/selfie/precollection` appears after a successful password login. It is an
**optional upsell, not a gate** — do not try to complete it and do not treat it as a
blocker. Navigate straight to the destination app (`mail.google.com`, `app.clay.com`)
and the session is already authenticated.
