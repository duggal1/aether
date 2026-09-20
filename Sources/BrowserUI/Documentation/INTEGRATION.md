# Engine integration contract

## The ownership rule

Aether's engine and its BrowserRuntime own the page, DOM, history, JS state, network state and authenticated context. `BrowserWorkspace` owns only human-shell data: profile labels/IDs, bookmarks, shortcuts and local history. `BrowserWindowModel` owns tab **presentation**, active profile and UI state. Page identifiers come only from `BrowserEnginePort.createPage(profileID:)`.

```text
SwiftUI (BrowserWindowRoot)
    └─ BrowserWindowModel
         ├─ BrowserWorkspace → profiles, bookmarks, preferences
         ├─ BrowserTab → enginePageID
         └─ BrowserEnginePort adapter
              └─ EXISTING NativeBrowserEngine / BrowserRuntime
                   ├─ existing context, page, DOM and JS
                   ├─ existing security / profile storage
                   └─ actual renderer-backed NSView
```

The current `DisconnectedEnginePort` exists solely so the UI can be inspected before the root engine is wired. Never use it for shipping.

## Required mapping

| UI operation | Existing engine operation to locate |
| --- | --- |
| create page | Context ownership + BrowserRuntime page creation |
| navigate | Same page ID, real navigation pipeline |
| back/forward | Existing history methods, **not** UI-synthesized URL navigation |
| reload/stop | Existing navigation lifecycle, including cancellation |
| snapshot | Actual loaded-page title, URL, back/forward capability, security state |
| surface | Persistent native page presentation over the existing display/compositor path |
| close | Destroy the existing engine page only when the tab closes |
| privacy | Existing networking filter owner, not a SwiftUI-only switch |
| inspector | Engine DOM IDs + computed styles + console/network, not screenshots |
| reader | DOM-derived article representation without modifying the live page |
| downloads | Existing download manager and security policy |

For currently absent methods, extend **the existing** engine. Do not import unsupported private symbols or invent a parallel engine. If a feature is not implemented, leave its UI status explicit until the contract is real.

## Renderer lifetime

`PageSurfaceRegistry` caches NSView per opaque page ID. `PersistentPageSurface` attaches that exact view inside a stable AppKit host. Tab selection and layout changes can relocate the host, but they must not recreate the engine page. The coordinator releases a surface when its tab closes. Real Metal/CAMetalLayer attachment requires actual macOS renderer work in the main Aether repository; this ZIP deliberately does not create a fake raster surface.

A future engine event stream should update each `BrowserTab` when user/JS/agent navigation changes the document. `snapshot` after a UI-requested navigation handles only the initial command path; it does not automatically observe redirects or all external agent events. Do not mistake a successful `navigate()` response for complete live synchronization.

## Security and credentials

Aether documentation identifies an unfinished renderer sandbox. Do not automatically grant agents human profile state. Build actual permission and profile capabilities in BrowserRuntime. Credentials belong to authorized Security/AuthenticationServices flows, not browser shell UserDefaults. There are no passwords or passkeys in this package.
