# Search to Aether migration plan

## Verified baseline

- Search is an MIT-licensed SwiftPM SwiftUI/WebKit application (`Search/Sources/Search`, 26,375 Swift lines). Preserve its copyright and license when copying substantial code.
- Aether is a macOS 27 SwiftPM application with separate `EngineRuntime`, `AetherHumanUI`, and `AetherApp` modules. Its persistent WebKit stores are keyed by profile UUID. Existing worktree edits must be preserved.
- Xcode and the macOS SDK are both 27.0.
- Search's `FrameRate.swift` toggles a **private** WebKit feature flag. Search's `Inspector.swift` invokes a **private** inspector selector. The requested no-private-API constraint rules those exact mechanisms out. Aether already sets `WKWebView.isInspectable` and has its own inspector panel.
- Search's browser passkey entitlement is restricted and embeds Search's Team ID and application identifier. It cannot be copied into Aether. Aether already has an AuthenticationServices authorization adapter, but no verified browser entitlement.
- Search's Homebrew script publishes a cask in a separate repository for Search. Aether needs its own cask and release artifact before an equivalent install path can function.

## Source and destination map

| Behavior | Search source and dependencies | Aether destination and integration |
|---|---|---|
| Video continuation | `Float.swift`, `Tab.swift`, `Browser.swift`, `Stage.swift` | `EngineRuntime/WebKit`, `AetherHumanUI/Chrome`, `AetherHumanUI/State`; retain a live page or use a supported native PiP path. |
| High refresh | `FrameRate.swift`, `Tab.swift`, `Settings.swift` | `EngineRuntime/WebKit/WebKitPage.swift`, performance probes; do not use the private flag. Measure on 120 Hz display. |
| Link preview | `StatusLine.swift`, `Tab.swift`, `Browser.swift` | WebKit script relay in `WebKitPage.swift`, state and overlay in `AetherHumanUI/Chrome`. Keep source URL extraction and dismissal semantics. |
| Passkeys | `Passkeys.swift`, `Registrable.swift`, `Forms.swift`, `Tab.swift`, passkey entitlement | `EngineRuntime/WebKit`, `AetherApp/Integration/AetherEngineAdapter+Passkeys.swift`, app entitlement; only enable when Aether has Apple's browser entitlement. |
| Passwords | `Forms.swift`, `Vault.swift`, `Passwords.swift`, `Browser.swift`, `Tab.swift` | New Keychain service and form relay, plus Aether password settings and consent UI. Save only after a successful sign-in signal. |
| Audio, sharing, Markdown | `Tab.swift` (`Muter`), `Sharing.swift`, `App.swift` | WebKit runtime for audio; browser command and tab context menus for share/copy. |
| Mouse and tab interactions | `Tab.swift` (`PageView`, `MiddleRelay`), `TabBar.swift`, `Side.swift`, `Stage.swift` | WebKit view or event relay; `TabItemView`, `TopTabStripView`, `BrowserWindowModel`. Preserve native page menu. |
| Spaces and sessions | `Spaces.swift`, `SpaceSwipe.swift`, `Browser.swift`, `TabBar.swift`, `Session.swift` | `BrowserWorkspace`, `BrowserWindowModel`, profile store mapping and top strip. Aether profiles already isolate WebKit stores; spaces need their own explicit session model and optional shared-login mapping. |
| Sidebar and inspector | `App.swift`, `Side.swift`, `Inspector.swift` | `BrowserCommands`, `BrowserWindowView`; use public inspectability and existing panel. |
| Search and packaging | `Engine.swift`, `tap.sh`, `build.sh` | `AddressResolver.swift`, search settings, Aether packaging scripts. Brave already exists; add Qwant. Homebrew needs Aether release/tap infrastructure. |
| Input and sign-in fixes | `App.swift`, `Tab.swift`, `Stage.swift`, `Forms.swift`, extension files | Browser commands, WebKit view integration, and credential relay. Verify each fix against a reproducible failing interaction. |
| Dark Search UI | `Design.swift`, `Plate.swift`, `SiteCard.swift`, `TabBar.swift`, `Side.swift`, `Settings.swift`, related controls | Aether's existing dark theme and chrome; preserve geometry and interaction of each migrated component while adapting colors and engine bindings. Avoid replacing Aether's more capable controls wholesale. |

## Execution order

1. Build the current Aether baseline and record failures.
2. Migrate isolated source behaviors first: provider, keyboard/sidebar, sharing/Markdown, mouse/tab actions, link preview and audio. Wire each through its real engine and UI state.
3. Integrate WebKit-dependent systems: video continuation, credentials and passkeys, including permissions and lifecycle cleanup.
4. Add Spaces with explicit cookie-store isolation and migrate the relevant Search top-bar interaction.
5. Port remaining requested Search components and their supporting state to dark mode, keeping Aether's current user edits.
6. Build, run, exercise features in the app, and run focused tests. Record CPU, memory, cold start, interaction latency, and frame delivery. State hardware, account, signing, and external-service limitations explicitly.

## Acceptance criteria

- Each control performs the actual operation; native menus and credentials use supported macOS APIs.
- Passwords remain in Keychain, are offered only with consent after confirmed authentication, and are scoped to the correct origin.
- A separate Space can use a separate persistent WebKit data store; optional shared login is explicit.
- Standard form Tab behavior and text input are retained; shortcuts and mouse navigation work without spurious reloads or beeps.
- 120 Hz is claimed only after measuring actual frame delivery on compatible hardware. Native passkeys are claimed only after a signed, entitled live test.
- The app builds and launches, and the report distinguishes transplanted, adapted, newly implemented, verified, and blocked behavior.
