# Visual consistency audit

The supplied Dia screenshots are **structural references only**. The root repository's `DESIGN.md` controls Aether. These rules were applied across every included UI area.

1. **Palette:** The semantic resolver in `Design/AetherPalette.swift` is the sole chrome color source. Light canvas is `#ffffff`, dark canvas `#1c1917`; secondary dark surface is custom `#231f1d`. No purple tint or pitch-black chrome.
2. **Density:** 43-point top tab row, 45-point navigation row, 34-point tabs and 30-point utility hit surfaces. Modest radii: 12 cards, 8 inputs/tabs, 6 utility controls.
3. **Typography:** Compact 11–13-point body/metadata, 19–24-point settings headings. Licensed Instrument Sans fonts are **not bundled**. System sans fallback avoids illegal/broken font references.
4. **Top tabs:** Profile switcher on the left, pinned sites separated, scrollable regular tabs, new tab and search; native macOS window controls remain system-owned.
5. **Sidebar:** Profile switcher, small pinned shortcuts, New Tab, vertical tabs, bottom History/Bookmarks/Search; collapsible and resizable, using exactly the same tab objects as top tabs.
6. **Omnibox:** One compact URL/search field. No AI prompt or duplicate giant new-tab search; editable, focusable, with local structured suggestions.
7. **New tab:** One quiet mark and an editable 4-column shortcut grid centered in ample negative space. No chatbot, feed, marketing card, decorative gradient or oversized search pill.
8. **Settings:** Fixed narrow sidebar, one readable scrollable content area, reusable AetherRow/AetherSection/SettingsDivider. Dark/light color relationship remains consistent in every section.
9. **Motion:** Only hovered controls and actual structural transitions animate, with Reduce Motion support. No web renderer animations, pulse, bounce, or hand-drawn glass imitation. The material pass uses Apple's own APIs exclusively — `glassEffect`, `GlassEffectContainer`, `glassEffectID`/`glassEffectTransition`/`glassEffectUnion`, `.buttonStyle(.glass)`/`.glassProminent`, `.pickerStyle(.tabs)` — unconditionally (macOS 27 floor) with no `NSVisualEffectView` bridge and no availability fallback. Surface-by-surface map and honest limits: `ENHANCED_DESIGN.md`.
10. **Realism:** Unsupported engine features never display fake successful browsing. Inspector/reader/download panels use typed optional providers and honest empty states.

## Screenshot mapping

- `References/example-sidebar-tabs.jpg`, `References/sidebar-tabs-1.jpg`: alternate tab structures.
- `References/example-profile-chnage.jpg`: compact profile selector hierarchy.
- `References/example-settings.jpg`: left settings navigation and grouped content.
- `References/history-open-dialog.jpg`, `References/example-history.jpg`: tab search, recent tabs, history and bookmarks.
- `References/website-search.jpg`: compact address/navigation structure.

These pictures are not runtime UI assets and are not loaded by the SwiftUI app.
