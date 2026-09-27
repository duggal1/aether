# Agent Verification, Events, and MCP

Aether's public browser operations remain in BrowserRuntime and NativeBrowserEngine. The Agent protocol, browserctl, and aether-mcp forward to the same AgentCommandDispatcher; they do not create browser state or implement browser behavior themselves.

## Verify a task result

Call NativeBrowserEngine.verify(_:using:) or AgentProtocol method task.verify. A plan identifies one live page and has one or more checks:

    {
      "page": 12,
      "checks": [
        {
          "id": "confirmation",
          "assertion": {
            "kind": "element",
            "selector": "[role=status]",
            "condition": {
              "kind": "accessibleName",
              "expectation": { "value": "Deployment complete", "mode": "contains" }
            }
          }
        },
        {
          "id": "destination",
          "assertion": {
            "kind": "pageURL",
            "expectation": { "value": "https://example.test/deploy", "mode": "prefix" }
          }
        }
      ]
    }

Supported assertion kinds:

- pageURL and pageTitle: exact, case-insensitive contains, or case-insensitive prefix text match.
- element: selector state is exists, absent, visible, enabled, or an accessible-name text match.
- navigationResponse: a main-frame response event observed after a supplied event-sequence cursor and an optional exact HTTP status.
- download: a download record ID or a WebKit download event observed after a supplied event-sequence cursor, minimum byte size, and optional artifact-file existence check.
- external: named native verifier with opaque Data payload. Register a BrowserExternalVerifier in the native runtime call to verify an external system such as a live deployment endpoint.

The result contains an aggregate verified, failed, or inconclusive status plus ordered evidence for each check. Any known failed check makes the aggregate failed; otherwise an inconclusive check makes it inconclusive. Missing response or download evidence is inconclusive. Capture events.recent.nextSequence before an action and pass it as sinceSequence for response/download checks so an earlier matching event cannot satisfy a new task. For context.download operations, pass the returned download ID instead. The verifier does not treat a completed click or form submission as proof of success.

Evidence summaries intentionally omit full URLs, page text, download paths, and external payloads. Main-frame WebKit responses can be verified from delegate events. WebKit does not expose a public per-subresource request/response observer, so a check requiring an unobserved subresource response cannot be marked verified.

While a human handoff is open, task.verify and events.recent reads scoped to that page or context are blocked until control resumes to the agent.

## CLI

The verification plan is JSON with page and checks fields:

    browserctl --socket /path/to/browser.sock task-verify plan.json
    browserctl --socket /path/to/browser.sock events-recent --context 3 --since 24 --limit 100

events-recent requires either --context or --page; optional --family, --since, and --limit fields filter the bounded event journal. Results include a resumable event sequence cursor. Native Swift callers can use BrowserRuntime.observeEvents for push-based AsyncStream subscriptions.

## MCP stdio adapter

aether-mcp is a local stdio MCP server and Agent socket client:

    aether-mcp --socket /path/to/browser.sock --token-file /path/to/browser.sock.token

The tool aether_call accepts an exact AgentProtocol method name and its protocol params object. This exposes the existing CLI/runtime methods, including agent.exec, task.verify, and events.recent, through the same dispatcher. Configure the executable and socket arguments in the MCP host's server configuration. If --token-file is omitted, the client uses an unauthenticated local socket.

The adapter supports MCP stdio using modern per-request metadata for protocol 2026-07-28 and the legacy 2025-11-25 initialize flow. Tool calls use the daemon socket's request timeout; agent.exec.timeoutMs is honored up to ten minutes at the transport layer. The execution runtime applies its own lower program timeout limit. A long-lived event subscription is not exposed as an MCP stream; use bounded events.recent calls with the returned cursor.
