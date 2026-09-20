# Aether Human UI

**Phase 2B: native macOS human-browser interface, packaged independently of GitHub.**

This project is a modular SwiftUI/AppKit shell for Aether's existing custom Swift browser engine. It does not contain Chromium, WebKit, React, Electron, a second JavaScript runtime, or an AI chatbot. It also does **not** pretend a standalone UI can supply missing rendering, media, authentication, or web standards.

## Native material enhancement (updated release)

This is the **same project, enhanced in place**. `Design/AetherGlass.swift` now applies real Apple Liquid Glass to bounded primary navigation controls on macOS 26+; `Design/AetherMaterial.swift` adds native AppKit blur to the browser chrome and both sidebars. Omnibox text stays sharp, selected top tabs receive restrained glass, sidebar rows remain matte, and Reduce Transparency falls back to opaque stone. macOS 15–25 use real SwiftUI/AppKit materials, not a fake shader. See `Documentation/ENHANCED_DESIGN.md` for the design/material map and remaining macOS verification requirements.

## What's in the ZIP

- Two switchable tab layouts: compact top tabs and a resizable/collapsible sidebar, both reading **the same** `BrowserWindowModel` and `BrowserTab` objects.
- Native macOS window, menus and shortcuts; profile switcher and per-profile tab selection.
- New-tab shortcut grid with add/edit/delete and persistent data.
- Editable omnibox with URL-or-search resolution, open-tab, bookmark and history suggestions.
- Tab create/close/duplicate/pin/reorder/restore, back/forward/reload/stop commands routed through the engine port.
- Searchable history, bookmarks, JSON bookmark import/export, recently closed tabs, tab search.
- Dedicated settings scene, consistent 10-section navigation, top/sidebar selection, appearance, profiles, search, and privacy policy controls.
- System/light/dark appearances using exact semantic stone palette; compact controls; VoiceOver labels and reduced-motion-aware chrome transitions.
- Native, **retained NSView** page surface host for real renderer integration. Switching tab layout never creates a new page.
- Typed opt-in port contracts for inspector, HTML/CSS/console/network views, reader Markdown, downloads and find-in-page.
- Explicit not-connected UI for engine-dependent features. Preview never renders a fake website.

## Build on macOS

Requires macOS 15+, full compatible Apple SDK/Xcode, and Swift 6.2 package tools.

```bash
cd AetherHumanUI
swift build
swift test
swift run AetherHumanPreview
```

The preview intentionally uses `DisconnectedEnginePort`. **It is a native shell preview, not a browsing application.** Its tabs, profiles, shortcuts, native panels, search-provider preference, appearance and shell bookmarks/history are interactive. Opening an external URL produces an explicit integration error until the real engine is injected.

Do not call a green UI build proof that Google sign-in, YouTube, hardware video, passkeys, hostile-page isolation or real-site compatibility work. Those are engine responsibilities and require separate macOS integration evidence.

## Connect to the real Aether repository

1. Copy `Sources/AetherHumanUI/` into a new target in Aether's **root** SwiftPM manifest. Do not replace its existing `Package.swift` or embed this preview executable in the browser engine.
2. Implement `BrowserEnginePort` as an adapter over Aether's **existing** `NativeBrowserEngine`/`BrowserRuntime`. Map its real context and page identifiers to opaque `String` handles in the adapter. Preserve all underlying page instances.
3. Ensure one profile ID maps to a genuinely isolated engine context and persistent site-data partition. This UI's separate bookmarks and tab lists **do not** establish engine cookie or credential isolation.
4. Implement `surface(pageID:)` using an existing engine-owned **persistent `NSView`** hosting its actual presentation surface. Attach/reattach the same view in `PersistentPageSurface`; do not render a fake copy or instantiate WebKit.
5. Implement the async navigation methods using the existing runtime. Return actual final URL/title/history/loading/security state from `snapshot(pageID:)`. Deliver engine-initiated page changes through an observation event channel (still to be added to the root integration).
6. Implement real inspector/reader/download/find providers only if Aether's real runtime exposes those capabilities. Never infer DOM access from pixels.
7. Bind security enforcement and profile deletion to the real engine before enabling production browsing. Existing Aether `SECURITY.md` states it is **not** a hostile-web sandbox.
8. Run macOS compilation, tests, real-browser workflows, accessibility audits and Instruments profiling on the integrated app before calling it complete.

### Source map

| Folder | Owner |
| --- | --- |
| `Design/` | Semantic design tokens, motion, typography and appearance environment |
| `Models/` | Profile, tab, bookmark, history, shortcuts and closed-tab types |
| `State/` | App-wide workspace, per-window tab/profile state, user preferences |
| `Engine/` | Integration port and opt-in feature contracts, disconnected preview implementation |
| `Native/` | Persistent native renderer surface and focused-scene commands |
| `Chrome/` | Top tabs, sidebar, omnibox, profile selector, navigation, browser window |
| `Pages/` | New-tab shortcuts and editor |
| `Panels/` | Search, history, bookmarks, downloads, inspection and reader |
| `Settings/` | Reusable settings shell and each individual settings page |
| `Foundation/` | Address resolution, stored shell data, bookmark transfer |
| `Components/` | Shared row, fields, buttons, hover, empty states and domain fallback |

### Important limitations

- **No engine source was read or altered for this delivery.** The only repository context is the Aether Markdown documentation read earlier. Actual Swift API signatures cannot be inferred responsibly from a documentation diagram.
- Native macOS UI cannot be typechecked or launched in this Linux sandbox. The Swift parser and SwiftPM manifest were checked; **actual Xcode build and visual testing remain outstanding**.
- No licensed Instrument Sans font files are bundled. `AetherType` currently uses the system sans fallback. If you have licensed font assets, register the exact PostScript names when integrating the macOS app.
- Actual favicons must come from the engine's resource/cache path. Domain-initial fallback is intentional rather than a remote favicon request from the chrome.
- Profile deletion here removes the shell's data and closes its window-local tabs; **it does not securely erase the engine's cookies, site storage or Keychain records**.
- The preview does not implement real downloads, password/passkey integration, native video, blocking, PDF rendering or modern-website compatibility. Their settings either defer to a connected port or state plainly that integration is required.
- Window/session restoration requires the real engine's profile/page restore semantics. It is not simulated by re-creating title-only fake tabs.

See `Documentation/INTEGRATION.md`, `Documentation/DESIGN_AUDIT.md`, and `Documentation/QA_CHECKLIST.md`.
