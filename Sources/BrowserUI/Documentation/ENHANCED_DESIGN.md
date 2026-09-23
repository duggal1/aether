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

One owner: `Design/AetherGlass.swift`. Glass policy: native `glassEffect` renders on dropdown/popover surfaces (`AetherPopoverBackground`), the search-suggestion panel (`AetherSuggestionBackground`, darker veil), settings cards (`AetherSettingsCardBackground`), the selected sidebar tab, and the profile picker (rest + interactive hover). The sidebar's background blur is a real `NSVisualEffectView` (`.sidebar`, `.behindWindow`, active) under a thin contrast veil — not a foundation color pretending to be blur. Veils are kept thin (0.20–0.28) so the native blur stays visible; text always renders above the glass and stays sharp. Everything else — toolbar, omnibox field, inactive tabs, icon hovers, menu rows, suggestion rows, overlay panels — uses flat appearance-aware fills, never glass. `GlassEffectContainer` is not used. Panel/dialog buttons use the flat neutral `AetherNeutralButtonStyle` (`.aetherButton()` / `.aetherProminentButton()`), not `.buttonStyle(.glass)`.

Top tabs compress responsively: per-tab width is allocated from measured strip width (174 pt full → 46 pt favicon-only minimum, compact below 108 pt with the X fully replacing the centered favicon in place, no layout shift). The active fused tab fills with the toolbar surface so it connects seamlessly beneath it. Tab rows are real `Button`s with explicit hit shapes; the overlay tap-catcher covers only the content column so the sidebar stays live with panels open. The profile picker clears the traffic lights (72 pt windowed, 12 pt fullscreen) at 28 pt height. History/Bookmarks panels are forced dark with neutral light/dark action buttons; suggestion rows use rest/hover/selected/selected-hover fills with a `return` indicator on the selected row.

| Piece | Wraps | Real call sites |
|---|---|---|
| `AetherGlassSurface` | `glassEffect` + radius + tint + shadow | 4 |
| `AetherGlassCluster` | `GlassEffectContainer` | 6 |
| `.aetherGlass(_:tint:in:interactive:)` | `glassEffect` | 19 |
| `.aetherGlassID(_:in:transition:)` | `glassEffectID` + `glassEffectTransition` | 3 |
| `.aetherGlassUnion(_:in:)` | `glassEffectUnion` | 4 |
| `.aetherGlassButton()` | `.buttonStyle(.glass)` | 12 |
| `.aetherGlassProminentButton()` | `.buttonStyle(.glassProminent)` | 3 |

Deleted in this pass: `AetherGlassBackdrop` (zero users), the hand-rolled `AetherDialogButtonStyle` with hardcoded hex fills, `AetherLeadingGlassPanel` (zero users), every `NSVisualEffectView` bridge (`AetherChromeBlur`, `AetherStrongInAppBlur`, and the sidebar `NSVisualEffectView` / `SidebarMaterialView`). `#available(macOS 26…`, `NSVisualEffectView`, `.ultraThinMaterial`, `.regularMaterial` and `matchedGeometryEffect` now appear **0 times** in the UI.

`Glass.interactive(true)` is applied to structural control surfaces only (profile picker, omnibox, fused tabs). Dense list hovers (menu rows, suggestion rows, toolbar icon hover) use an appearance-aware translucent fill instead of materializing glass per row, so rapid hover does not thrash glass regions. Reduce Transparency, Increase Contrast and Reduce Motion are **not** re-implemented: the material handles the first two and `AetherMotion.*(reduced:)` returns `nil` for the third.

## 2. Where the glass is

| Surface | Treatment |
|---|---|
| Sidebar (browser) | `AetherChromeBackground(.sidebar)` → neutral dark foundation + `glassEffect(.regular)` with dark tint; forced dark `colorScheme`; **no** `NSVisualEffectView` |
| Toolbar / top tab strip | `AetherChromeBackground(.toolbar)` → appearance-resolved foundation (0.88) + `glassEffect(.regular)` tinted for light/dark |
| Profile cluster | Resting + hover `glassEffect` on the Personal picker; compact padding; dropdown is a custom glass popover |
| Top tab strip | Active fused tab is glass with `.materialize`; sidebar tabs use appearance fills |
| Omnibox + suggestions | glass field; suggestion panel is glass popover; selected row uses appearance `selected` fill |
| Navigation bar controls | appearance-aware hover fills grouped in `GlassEffectContainer`s |
| Menus (kebab, profile, context rows) | glass popover surface; row hovers are lightweight appearance fills (no per-row glass) |
| History / Bookmarks | in-window overlays (not sheets) with `AetherOverlayPanelBackground` glass — ~150–250 ms transitions |
| Command palette, find bar | glass; presented as an overlay over the live browser (page stays mounted) |
| Sheets (Downloads, Inspector, Reader, Settings) | `AetherSheetBackground` → dialog card |
| Form fields, empty-state chips, new-tab cards, shortcut tiles | flat fields; focus uses appearance fill |
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
