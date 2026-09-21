# Aether native material pass — actual state

Rewritten after the macOS 27 Liquid Glass pass. The previous revision described a macOS 15–25 fallback architecture that no longer exists in the code.

## 0. Platform floor and evidence

Both manifests — the root `Package.swift` and `Sources/BrowserUI/Package.swift` — target **macOS 27.0**. There are therefore **no availability guards** in the UI: every Liquid Glass call is unconditional.

Verified on this host, not assumed:

```text
xcode-select -p            -> /Applications/Xcode.app/Contents/Developer
xcrun --show-sdk-version   -> 27.0
swift --version            -> Apple Swift 6.4, target arm64-apple-macosx27.0.0
cd Sources/BrowserUI && swift build -> Build complete, 0 errors, 0 warnings
```

APIs confirmed present in the installed SDK by a compiling probe **before** use: `glassEffect(_:in:)`, `GlassEffectContainer`, `glassEffectID(_:in:)`, `glassEffectTransition(_:)`, `glassEffectUnion(id:namespace:)`, `Glass.interactive(_:)`, `GlassButtonStyle`, `GlassProminentButtonStyle`, `TabsPickerStyle` (`.pickerStyle(.tabs)`), `NSGlassEffectView`, `NSGlassEffectContainerView`, `NSSegmentedControlRole.tabs`, `NSMenuItem.preferredImageVisibility`.

There is no separate "Liquid Motion engine" in Apple's public API. Motion is SwiftUI `Animation` — this app uses `.snappy(duration:)` and `.smooth(duration:)` plus one morph spring. Nothing else is claimed.

## 1. The glass system

One owner: `Design/AetherGlass.swift`. Counts below come from `grep` over `Sources/`.

| Piece | Wraps | Real call sites |
|---|---|---|
| `AetherGlassSurface` | `glassEffect` + radius + tint + shadow | 4 |
| `AetherGlassCluster` | `GlassEffectContainer` | 6 |
| `.aetherGlass(_:tint:in:interactive:)` | `glassEffect` | 19 |
| `.aetherGlassID(_:in:transition:)` | `glassEffectID` + `glassEffectTransition` | 3 |
| `.aetherGlassUnion(_:in:)` | `glassEffectUnion` | 4 |
| `.aetherGlassButton()` | `.buttonStyle(.glass)` | 12 |
| `.aetherGlassProminentButton()` | `.buttonStyle(.glassProminent)` | 3 |

Deleted in this pass: `AetherGlassBackdrop` (zero users), the hand-rolled `AetherDialogButtonStyle` with hardcoded hex fills, `AetherLeadingGlassPanel` (zero users), and every `NSVisualEffectView` bridge (`AetherChromeBlur`, `AetherStrongInAppBlur`). `#available(macOS 26…`, `NSVisualEffectView`, `.ultraThinMaterial`, `.regularMaterial` and `matchedGeometryEffect` now appear **0 times** in the UI.

`Glass.interactive(true)` is applied to every control-backed surface. Reduce Transparency, Increase Contrast and Reduce Motion are **not** re-implemented: the material handles the first two and `AetherMotion.*(reduced:)` returns `nil` for the third. Hand-rolled opaque "accessibility" fallbacks were removed because they duplicated and fought the system behavior.

## 2. Where the glass is

| Surface | Treatment |
|---|---|
| Sidebar (browser + settings) | `AetherChromeBackground(.sidebar)` → `glassEffect(.regular)`; the stone veil went from 0.88 to 0.38 opacity so the material actually reads |
| Toolbar / top tab strip | `AetherChromeBackground(.toolbar)` → `glassEffect(.regular)`, veil 0.92 → 0.40 |
| Profile cluster | `AetherGlassCluster(spacing: 7)` + 4 `.aetherGlassUnion` shapes merging into **one** capsule |
| Top tab strip | `AetherGlassCluster(spacing: 0)`; active fused tab is glass with `.aetherGlassID(.tab)` so selection **morphs** instead of cross-fading |
| Sidebar tab rows | active row glass with `.aetherGlassID(.tabActive)` inside `AetherGlassCluster(spacing: 4)` |
| Omnibox + suggestions | glass field, glass suggestion panel |
| Navigation bar controls | glass pills on hover/selected, grouped in two `AetherGlassCluster`s |
| Menus (kebab, profile, context rows) | glass popover surface; menu rows get a transient glass pill on hover |
| Command palette, find bar | glass |
| Sheets (History, Bookmarks, Downloads, Inspector, Reader, Settings) | `AetherSheetBackground` → glass |
| Settings sidebar + tab-layout cards | glass selection morph (`.aetherGlassID(.settingsSection)`), glass cards |
| Form fields, empty-state chips, new-tab cards, shortcut tiles | glass |
| Buttons in panels/dialogs | native `.glass` / `.glassProminent` |
| Inspector mode selector | `.pickerStyle(.tabs)` (macOS 27 tab semantics) |

## 3. What is deliberately not glass

- **The webpage itself.** Aether never blurs, tints or recolors engine-rendered content; that surface is owned by the engine and stays sharp.
- **Text-bearing content blocks** (settings rows, list rows at rest, reader body). They sit inside glass containers as flat text; making each row a glass shape would add render regions without adding legibility.

## 4. Honest limits

1. **Window opacity.** The SwiftUI window is opaque, so chrome glass refracts what is inside the window (chrome base, page edge), not the desktop wallpaper. True wallpaper tinting needs `NSWindow.isOpaque = false` plus a transparent window background — a whole-app structural change that was **not** made and was **not** verified.
2. **Navigation bar layering.** The nav bar is a sibling row above the page, not an overlay on it, so the page never scrolls *under* the omnibox. Glass there renders over the chrome base; its refraction is nominal until the page is hosted edge-to-edge beneath the chrome.
3. **No visual verification.** These changes compile clean and were not inspected on screen: no pixel comparison, no Instruments run, no frame-time measurement. Any performance claim would be unsupported.
4. **Glass region count** is bounded by design: three structural chrome regions plus transient popovers/palette/find bar/hover pills. Grouped glass shares one `GlassEffectContainer` so adjacent shapes composite once.
