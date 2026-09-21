# macOS acceptance checks

## Build

- [ ] `swift build` succeeds with a macOS 27 SDK and Swift 6.2+ (`cd Sources/BrowserUI && swift build` builds the UI alone, expects 0 warnings).
- [ ] `swift test` passes on macOS.
- [ ] Preview opens with native traffic lights and no SwiftUI console warnings.
- [ ] Light, dark and live System appearance switching retain the correct semantic palette in **every** modal and popover.

## Shell interaction

- [ ] Create 12+ tabs, select, reorder, pin, duplicate, close, restore; no unexpected selection jumps.
- [ ] Switch between top and sidebar; tab model and engine page IDs remain identical.
- [ ] Collapse/reopen and drag-resize sidebar; content stays responsive.
- [ ] Create/rename/switch profiles; each preserves its own tabs and shell bookmarks.
- [ ] Add/edit/remove shortcuts, add/remove/search bookmarks, import/export bookmark JSON, filter/clear history.
- [ ] Toggle Search providers and appearance; restart and verify persisted preferences.
- [ ] Use narrow window and dozens of tabs without making active tabs inaccessible.
- [ ] Keyboard focus and every listed shortcut work in the actual running app.
- [ ] VoiceOver, high contrast, Reduce Motion, Reduce Transparency and pointer hit targets checked.

## Real engine integration

- [ ] Engine owns one page instance per tab; layout switch does not call engine createPage or navigate.
- [ ] Real HTTP response title, committed final URL and navigation capabilities propagate to UI.
- [ ] Navigating, scrolling, typing and clicking use Aether's real page instead of screenshots or WebKit.
- [ ] Human/agent event stream updates existing tab state without rebuilding the page view.
- [ ] Cross-profile cookies, localStorage, permissions, downloads and history are genuinely isolated in the engine.
- [ ] Renderer crashes do not hang SwiftUI chrome; errors are visible and recoverable.
- [ ] Every privacy toggle affects real network requests and can be disabled per site when implemented.
- [ ] Inspect DOM/style/network/console, reader Markdown and download records against actual engine output.
- [ ] Profile deletion removes engine data only with deliberate, correctly scoped authorization.

## Performance and web compatibility

- [ ] Measure cold/warm startup, navigation, first interaction, p95 tab switch, 60/120 Hz frame budgets with Instruments.
- [ ] Run authenticated SPA, multi-profile Gmail, YouTube playback, large sites, downloads and long-scroll tests on named Mac hardware.
- [ ] Test bounded memory over hours and repeated window/tab/profile changes.
- [ ] Run hostile-page sandbox, cross-origin denial, password/passkey authorization and download/file-policy tests before shipping a browser for arbitrary web content.
