# Local access to the running Aether app

Aether starts its Unix-domain agent server automatically. Local processes running as the same macOS user have full access to the browser. No menu approval, token file, handshake, or profile ownership grant is required. The socket is mode `0600` inside a `0700` directory; there is no TCP listener.

Packaged app endpoint:

```
~/Library/Containers/dev.aether.browser/Data/tmp/aether-agent/browser.sock
```

Send newline-delimited JSON directly. Multiple requests can share one connection, including multiple lines in one write. Responses preserve request IDs and are returned in order within that connection. Separate connections can run independently.

```json
{"id":"1","method":"app.status","params":{}}
{"id":"2","method":"app.open","params":{"url":"https://www.clay.com/"}}
{"id":"3","method":"app.navigate","params":{"tab":"<tab UUID>","url":"https://www.clay.com/pricing"}}
```

Poll `app.status` after launching; do not sleep for a fixed startup interval. `ready` means the UI window model exists. `nativeWindows` reports actual AppKit window numbers and visibility for independent window capture. A successful `ping` means the transport is serving, not that a webpage is painted.

Use `app.open`, `app.navigate`, `app.select`, `app.close`, `app.back`, `app.forward`, and `app.reload` to exercise visible browser tabs through the same UI model used by humans. `app.tabs` returns tab IDs, runtime page IDs, URL, pending URL, title, loading, content readiness, progress, error, and navigation capabilities. `window` optionally selects a window UUID; otherwise the first window is used. Tab commands return promptly after dispatch. Poll tab state and verify page content separately. The runtime page ID can initially be null while page creation is in progress.

All existing engine methods, including `page.evaluate`, `page.snapshot`, and `page.render`, are available on this same socket. `page.create` creates a runtime page, not a visible UI tab; use `app.open` for app testing. A runtime snapshot is not evidence that the native window is displaying the page. Use an independent window capture for that check.

`Scripts/aether_app_protocol.py` provides a direct Python client. It rereads no token and requires no authorization setup. Read timeouts should reflect the selected command; a full-load navigation can take longer than a ping. A disconnected client must reconnect before sending another command.

`browserd` also defaults to direct local access. Explicit `--token-file <path>` retains opt-in authenticated, ownership-scoped daemon sessions for existing integrations. The packaged app never requires this mode.
