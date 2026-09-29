# Floating surfaces: page scroll, and the extension popup

Branch: `feature/code-first-browser-runtime-20260927`
Reported from screenshots: with the three-dot menu, History or the extension
drawer open, the page behind stopped scrolling; and an extension's popup opened
as a blank grey card over the toolbar.

## Root causes

1. **Scroll was taken, not blocked by layout.**
   `BrowserWindowView` put `Color.clear.contentShape(Rectangle()).onTapGesture`
   over `BrowserContentView` whenever one of five surfaces was open. That SwiftUI
   view owns the whole region, so AppKit's hit test answered for it and the
   `WKWebView` underneath was never reached — the page could not be scrolled,
   while the menu itself still worked. (Same failure mode the repository already
   documents for `AetherOverlayScrollerTuning` and `AetherPassthroughView`.)

2. **The popup's sizing script was never called.** `AetherExtensionPopup.measure()`
   sent `preferredSize` — a bare arrow function — to `evaluateJavaScript`. It is
   never answered with a size, so `apply`/`reveal` never ran: `alphaValue` stayed
   0 and the popover stood empty. Every later symptom (blank card, no icons, no
   content) follows from that one call.

3. **The popup was opened through WebKit's own popup.** `press()` called
   `context.performAction`, which made WebKit build its own popup; the delegate
   then called `action.closePopup()` and replaced it with a fresh `WKWebView`
   loading a *copy* of the popup page (`.aether-popup`). `Search/ExtensionPopup.swift`
   (the working reference in this repository) does the opposite, and says why:
   a popup that replaces WebKit's own "has lost the new page's first messages to
   its worker and never renders". It also opened the popup only when
   `action.popupWebView` happened to be non-nil, so a popup whose web view was
   not ready yet opened nothing at all.

## Fix

- `Native/AetherDismissSurface.swift` (new): an `NSViewRepresentable` that
  hit-tests only `.leftMouseDown` / `.rightMouseDown` and returns `nil` for
  every other event, so the scroll wheel reaches the page. It sits exactly where
  the tap overlay did; the surface list is unchanged. Same event-gated hit-test
  pattern as `SecondaryClickSurface` and `TabMiddleClick`.
- `AetherExtensionPopup`: the script is evaluated as `(preferredSize)()`
  (`sizingExpression`); `reveal()` sizes the web view to the popover and turns it
  visible; `apply()` resizes the popover's view controller too; the page is
  loaded from its own URL (no copy); `closes(_:)` plus `popoverWillClose` keep a
  press on the button from closing and immediately reopening the popup; the
  anchor is optional, with the window content as the fallback.
- `AetherExtensions.press`: opens the popup directly on the press, from
  `chrome.action.setPopup` (per tab, then `*`, then the manifest) when
  `action.presentsPopup`; `presentActionPopup` stays as the fallback.
- The drawer's own button is registered as `AetherExtensions.menuAnchor`, so an
  unpinned extension's popup still has something to hang from.
- Removed: `unpopped`/`popupCopy` and `AetherExtensionCompatibility.fileInside`
  (the invented copy path).

## Verification

- `swift build` (debug) clean, no new warnings in the touched files.
- `swift test --filter "AetherHumanUITests\."`: 101 tests in 24 suites pass.
- `swift test --filter "HumanIntegrationTests\."`: 17 tests pass.
- New `AetherFloatingSurfaceTests` (4 tests): the dismissal surface claims
  presses and leaves scroll/move events to the page; and the popup's exact
  `sizingExpression`, run against a stubbed page, answers `[300, 150]`.

## Not verified here

The AppKit delivery of the scroll wheel through a nil hit test to the web view
was reasoned from `TabMiddleClick` (an overlay representable over the sidebar's
scrolling rows) and the `SecondaryClickSurface` precedent, not observed on a
running window. Worth a look the first time the app is run with a menu open.
