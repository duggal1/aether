# Native design correction

User rejected the prior correction because the sidebar's within-window blur over an opaque base eliminated visible translucency. Restore native Liquid Glass and genuine blur before further visual tuning.

1. Prove the native sidebar composition in a small rendered AppKit comparison. Preserve transparent window backing; remove opaque sidebar base and arbitrary dark overlays.
2. Make native hover/selection effects and material transitions shared across chrome controls. Keep text outside backdrop effects and appearance coherent.
3. Finish stable website appearance, popup anchoring/dismissal, profile/incognito states, fullscreen geometry, settings, bookmarks, and context menus.
4. Build serially, run relevant UI tests, inspect rendered light/dark and overlay states. Verify a live WKWebView remains mounted behind Search Tabs.
5. Record actual evidence and any missing input. The 19 annotated screenshots and separately supplied SVGs are not present in this conversation or the repository image inventory; do not invent per-screenshot acceptance.

Existing working tree contains extensive unrelated modifications. Preserve them. Snapshot at `/tmp/aether-ui-before-native-correction-20260923` captures the UI at restart.

## Latest user direction

Stop testing and edit main code only; user will run verification. The material comparison process was stopped. No build or test was run after this direction.

Implemented untinted `NSGlassEffectView(.regular)` for the sidebar, removed the opaque root/sidebar backing, removed all added popover tint/veil layers, introduced native interactive glass hover surfaces, corrected shared text appearance, removed popup dimming, corrected fullscreen/seam geometry, restored the white profile selection ring, and replaced New Tab shortcut menus with anchored custom glass popovers. Settings color choices now wrap rather than expanding the sheet beyond its bounds. Existing SVG engine/sliders assets are used.

Rendered acceptance remains unverified by user instruction. The earlier successful builds do not cover the latest changes.
