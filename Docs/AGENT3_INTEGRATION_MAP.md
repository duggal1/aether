# Agent 3: file-to-runtime integration map

Basis: root `Package.swift` and call paths on `main` at `01f9ec1d9df377cf8377852e1400782a4366b7a0`. This map distinguishes reachable root targets from source drops. It does **not** certify security or web compatibility.

| Entry/capability | Root-package call path | Actual owner and boundary |
| --- | --- | --- |
| Daemon commands | `Sources/browserd/main.swift` → `AgentSocketServer` (`AgentProtocol/UnixSocket.swift`) → `AgentCommandDispatcher.handle` → `NativeBrowserEngine.runtime` | `BrowserRuntime` owns contexts and page records. Socket JSON owner is not authenticated; Agent 1 owns principal binding. |
| Remote CLI | `Sources/browserctl/main.swift` → `AgentSocketClient` → same `AgentCommandDispatcher` | No duplicate remote execution engine. `browserctl` local commands have their own entrypoints; do not infer they authenticate remote principals. |
| Navigation | `AgentCommandDispatcher.pageNavigate` → `BrowserRuntime.navigate/performNavigation` → `NavigationPipeline` → `NetworkSession` and `ResourceLoader` | `HTML` tokenizer/tree builder, `DOM`, `CSS`/`Style`, `Layout`, `Display`, `Images`, `WebAPI`/`JavaScript` share the same page record. |
| Typed address/search | `AgentCommandDispatcher.pageNavigateInput` → `NavigationInputResolver` → existing `BrowserRuntime.navigate` | URL/search disambiguation is an engine service, not a new network authority or UI. Provider is per-call configurable; persisted provider settings are outstanding. |
| JavaScript and mutation | `AgentCommandDispatcher.pageEvaluate` → `BrowserRuntime.evaluate` → per-page `JSRuntime` → live `DOMDocument`; mutation triggers `BrowserRuntime.refreshPage` | Not a second JS/event loop. `page.workers` still returns an empty array; that is not worker support. |
| Render | `AgentCommandDispatcher.pageRender` → `BrowserRuntime.render` → page display list → `SoftwareRenderer` → `PixelBuffer` | Same loaded page; retained Metal presentation and native attach/detach remain Agent 2 work. |
| Native capture | `AgentCommandDispatcher.pageCapture` → `NativeBrowserEngine.capturePage` → `CaptureCoordinator` → `BrowserCaptureEngine`/`NativeCaptureSession` → `BrowserRuntime.navigate/captureState/render/captureDocument/cachedResourceBytes` | A private temporary context uses the *same engine* but captures a separate page from the existing interactive `PageID`. Capture does not prove same-PageID attachment. |
| Persistence | `BrowserRuntime.openProfile/checkpoint` → `Persistence/ProfileStore` → `SQLiteStore` and `DiskCache`; `Storage/LocalStorage` and `Networking/CookieJar` restored into context | Profile directory supplied by caller; principal authorization and filesystem confinement are not yet enforced. |
| Security | `Navigation`/network uses `WebSecurity` and live `AetherNetworkHardening` | No renderer sandbox, authenticated socket principal, or arbitrary-hostile-site safety. |
| Scheduler/metrics | `BrowserRuntime` → `Scheduler/EngineScheduler`/`FleetScheduler`, `Diagnostics/Metrics` | Fleet budget logic is not a security boundary. |
| Source-only additions | `Sources/EngineAdditions` nested package | Root `Package.swift` activates **only** `AetherNetworkHardening`; other additions are not live features. |
| Human app and native media | No root GUI or media target | Unsupported in this baseline; do not count fixture pixels as media or attached-window evidence. |

## Reproduction and qualification

`Scripts/verify_browser.py` starts the actual daemon, drives the real Unix-socket dispatcher, serves loopback fixtures, and writes `results.json`, `daemon.log`, raster and capture artifacts. Its dynamic fixture changes both DOM text and CSS through JavaScript, then checks an RGB pixel in the live viewport and captured PNG. `Scripts/test_macos.py` runs the Swift Testing suite with process-tree RSS bounds.

The dynamic pixel tests require a successful macOS CI run and artifact inspection before the two Step 1 evidence items can be recorded as **verified**. This map is a source-traced integration map, not proof of otherwise unsupported processes, codecs, or sites.

Agent 1 should inspect `AgentSocketServer`, `BrowserRuntime` context lookup, `ProfileStore.open`, and capture file paths before supplying authenticated principal/session and renderer IPC. Agent 2 should bind `PageID`, frame input and resource requests without duplicating navigation/rendering. Agent 3's final gate must run only after those branches are integrated.
