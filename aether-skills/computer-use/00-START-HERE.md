# 00 — Start Here: the 6 rules

Derived from a real run that took ~1 hour. With these rules the same run takes minutes.

---

## Rule 1 — `page-click` is broken on framework pages

`page-click <page> <idx> <gen>` returns `{"ok":true}` and **does nothing** on Google,
Clay, Slack, and anything built on Polymer/React/lit. The native pointer click does not
land on the hit target.

**Always:**
```bash
b page-eval <p> "
(function(){
  var b=Array.from(document.querySelectorAll('button,[role=button]'))
    .filter(function(x){return (x.innerText||'').trim()===TARGET && x.offsetParent;})[0];
  if(!b) return 'not found';
  ['pointerdown','mousedown','pointerup','mouseup','click'].forEach(function(t){
    b.dispatchEvent(new MouseEvent(t,{bubbles:true,cancelable:true,view:window}));});
  return 'clicked';
})()"
```

---

## Rule 2 — Fill with a composed `InputEvent`, never a bare assignment

The single most expensive mistake. `page-fill` sets `.value`; the framework keeps its own
copy; the next re-render **silently wipes it**. You read the value back, it looks correct,
you click Next, and the field is empty. No error anywhere.

**Always (raw form, works on any build):**
```bash
b page-eval <p> "
(function(){
  var e=document.querySelector(SELECTOR);
  if(!e) return 'MISSING';
  e.focus();
  Object.getOwnPropertyDescriptor(
    e.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype,'value'
  ).set.call(e, VALUE);
  e.dispatchEvent(new InputEvent('input',{bubbles:true,composed:true,data:VALUE,inputType:'insertText'}));
  e.dispatchEvent(new Event('change',{bubbles:true,composed:true}));
  e.blur();
  return 'set='+e.value;
})()"
```

Drop any one of `native setter` / `InputEvent` / `composed:true` and you are back in the trap.

**Proof it worked** (5 seconds, saves 20 minutes): force a re-render — click a sibling
dropdown — then re-read. If the value survives, the framework is bound.

---

## Rule 3 — A URL change is not progress

SPA wizards advance the URL without laying out the new step. The new step's inputs then
report `getBoundingClientRect() === 0×0` and structured queries return nothing.

**Always assert before acting:**
```bash
b page-eval <p> "
(function(){
  var e=document.querySelector(SELECTOR);
  if(!e) return 'MISSING';
  var r=e.getBoundingClientRect();
  return 'w='+Math.round(r.width)+' h='+Math.round(r.height);
})()"
```

- `w>0` → live, proceed.
- `w=0` or `MISSING` → re-navigate to the step's own URL, **preserving the query string**:

```bash
FULL=$(b page-eval <p> "location.href" | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['value'])")
QS="${FULL#*\?}"
b page-navigate <p> "https://host/path/nextstep?$QS"
```

Dropping the query string silently **restarts the whole flow**.

---

## Rule 4 — Force a layout when a visible element is "missing"

If a screenshot shows a field but `page-query` returns nothing, the page has not laid out.
Both symptoms look identical to "the field does not exist". They are not.

```bash
b page-resize <p> 1600 1000
b page-eval <p> "window.dispatchEvent(new Event('resize'));'ok'"
```

This single step fixed YouTube's nav, Clay's onboarding, and Slack in the reference run.

---

## Rule 5 — Screenshot early, and screenshot often

`b page-render <p> /tmp/shot.png` is ~2 seconds and is **unambiguous**. `innerText`,
`offsetParent`, and rect heuristics all lie. Google's collapsed listboxes keep reporting
`offsetParent` truthy; a 0-byte `innerText` can mean "not laid out" or "no content".

Rule of thumb: if you are about to theorise why something did not work, screenshot first.

---

## Rule 6 — Credentials never appear in your output

```bash
PW=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)
b credentials-save <ctx> "<origin>" "<user>" "$PW" "<label>" >/dev/null   # returns an ID
unset PW
b credentials-list <ctx>     # metadata only
b credentials-fill <page> <cred-id>    # pulls from Keychain
```

Verify by **length and match booleans only**:
```js
JSON.stringify(Array.from(document.querySelectorAll('input[type=password]'))
  .map(function(e){return e.name+' len='+e.value.length;}))
```

---

## The one exception: never solve these yourself

CAPTCHA, MFA codes, passkeys, phone/SMS verification, payment, and identity checks are
**human-only**. `task.md` forbids circumventing them and so does good practice.

When you hit one:
```bash
b handoff-request <p> <captcha|mfa|passkey|credentials|payment|sensitiveForm> "<exact reason>"
```

This parks the page and blocks further agent control — by design. The handoff is
cancellable with `handoff-cancel <id> <actor>` once the human authorizes you to continue.
