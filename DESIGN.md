# Aether Design System — Native macOS / SwiftUI

> Single source of truth for Aether's **browser chrome**. Read this file before creating or editing any native UI. Preserve its tokens, proportions, restraint, and component behavior. The webpage being browsed is **not** Aether UI: never restyle, zoom, blur, recolor, or intercept it to satisfy this document.

## 0. Scope and order

Aether is a native macOS browser for humans **and** first-class AI agents. Agents control structured browser state and engine actions, not a chatbot sidebar that guesses from screenshots.

Implement in this order: **native structure → functioning controls and authoritative state → this design system → native material/motion enhancement → accessibility and performance verification**. If `enhance-browser-ui/SKILL.md` exists, apply it *after* the functional skeleton. Do not redesign components during the enhancement pass.

Target SwiftUI for app views and AppKit where macOS windows, text editing, browser surface integration, or existing code needs it. Prefer existing project architecture. Never replace the browser engine to implement a visual detail.

## 1. Foundations

- **Platform:** native macOS. Use `WindowGroup`/appropriate scenes, standard window controls, proper keyboard focus, menu commands, pointer behavior, drag-and-drop, and native context menus. No HTML/CSS/React/Tailwind/Next.js UI shell.
- **Font:** Instrument Sans Regular 400 and Medium 500 **only**, bundled as licensed app resources; register and reference their actual PostScript font names through SwiftUI custom fonts. The bundled font's actual PostScript name must be checked, not guessed. Fall back to macOS system sans if unavailable. Use system monospaced typography for code, hashes, and keys. Never ship font files as part of an AI reply. Never fake weights by synthesizing 600/700.
- **UI scale:** sizes below are **SwiftUI points**, not CSS pixels. Keep compact browser chrome at 1×. Do **not** apply the website's `zoom: 1.1`, transform-scale the window, or zoom webpages. macOS display scaling and accessibility settings remain authoritative.
- **Layout:** compact, left-aligned, quiet, functional. Reuse the sizes and spacing below. Browser chrome fills the window; marketing-page `64rem` containers and section-padding rules do not apply. Content sheets/panels may use the existing 1024 pt (~64rem) reference maximum where actually appropriate, never on the browser viewport.
- **Spacing:** card interior 24 pt vertical / 12 pt horizontal where that original card pattern exists; 10 pt horizontal in tightly constrained panels. Default card gap 24 pt; compact control gap 8 pt; section/header gap ≥24 pt when space allows. Toolbar/tab row spacing is governed by native control geometry, not marketing section rhythm.
- **Alignment:** labels, section titles, and settings text left-aligned. Place actions at the trailing edge. Never introduce decorative center-aligned headings.
- **Appearance:** three user settings: **System (default), Light, Dark**. The app chrome follows live changes without recreating the browser engine or tabs. The **website** keeps its own page appearance; do not force web content to follow Aether's theme.

## 2. Semantic palette — exact light + dark tokens

All component colors must come from named semantic tokens. Use an Xcode asset catalog with Light/Dark appearances, or one tiny centralized palette resolver. Do not scatter hex strings across views. `stone-850` is Aether's explicit custom token, **not** an official Tailwind color.

| Semantic token | Light | Dark | Use |
|---|---|---|---|
| `canvas` | `#ffffff` | `#1c1917` (stone-900) | Main app chrome behind controls; opaque fallback |
| `surface` | `#fafaf9` | `#231f1d` (custom stone-850) | Cards, sidebar groups, dialogs |
| `surfaceElevated` | `#ffffff` | `#292524` (stone-800) | Inputs, wells, raised panels |
| `cardHover` | `#f5f5f4` | `#292524` (stone-800) | Only existing cards designed to react on hover |
| `surfaceSubtle` | `#f5f5f4` | `#292524` | Segmented wells, secondary buttons |
| `hover` | `#e7e5e4` | `#44403c` (stone-700) | Hover on secondary control |
| `primaryFill` | `rgba(214,211,209,0.70)` | `#44403c` | Primary button only |
| `primaryHover` | `#d6d3d1` | `#57534e` | Primary button hover |
| `featureFill` | `rgba(231,229,228,0.70)` | `#292524` | Existing flat feature/utility cards only |
| `ink` | `#1c1917` | `#fafaf9` | Body, buttons, input text |
| `headingInk` | `#252324` | `#fafaf9` | Headings on surfaces |
| `muted` | `#78716c` | `#a8a29e` | Secondary text, headers |
| `soft` | `#a8a29e` | `#a8a29e` | Nonessential metadata; not critical text |
| `placeholder` | `#b6b0ab` | `#a8a29e` | Input placeholder |
| `fieldIcon` | `#57534e` | `#d6d3d1` | Input prefix icon |
| `hairline` | `rgba(231,229,228,0.70)` | `rgba(168,162,158,0.22)` | Standard 1 pt border |
| `hairlineSubtle` | `rgba(231,229,228,0.45)` | `rgba(168,162,158,0.14)` | Quiet separators |
| `cardBorder` | `#f5f5f4` | `#292524` | Existing capture-like surface |
| `selectionFill` | `#e7e5e4` | `#44403c` | App-owned selection background |
| `liveDot` | `#22c55e` | `#22c55e` | 6 pt live status dot |
| `activeText` | `#16a34a` | `#4ade80` | Active badge |
| `activeFill` | `rgba(34,197,94,0.08)` | `rgba(34,197,94,0.12)` | Active badge backing |
| `revokedText` | `#e11d48` | `#fda4af` | Revoked badge |
| `revokedFill` | `rgba(225,29,72,0.08)` | `rgba(225,29,72,0.12)` | Revoked badge backing |
| `expiredText` | `#b45309` | `#fbbf24` | Expired badge |
| `expiredFill` | `rgba(217,119,6,0.08)` | `rgba(217,119,6,0.12)` | Expired badge backing |
| `errorText` | `#991b1b` | `#fca5a5` | Error text |
| `errorFill` | `#fffafa` | `#352021` | Error well |
| `errorBorder` | `#fecaca` | `rgba(252,165,165,0.30)` | Error well border |

Light appearance must reproduce the original light styling. Dark appearance must preserve **the same hierarchy and geometry**, swapping only semantic color and material behavior. Dark is stone, not pitch black, blue-gray, purple, or a randomly tinted gradient. Dark `surface` cards may hover to `cardHover` (stone-800); controls already at stone-800 use the more visible `hover` (stone-700). No hover effect is required on static cards.

**Hard rules:** no `#000000` UI surfaces in either mode; no forced white cards in dark mode; no dark surfaces in light mode other than native content or pre-existing functional exceptions explicitly approved. Do not derive all text using `.opacity` on one foreground: use semantic tokens for readable contrast.

## 3. Shape, borders, and density

- **Corner radii:** cards 12 pt (11 pt only in an actually constrained layout); inputs/primary buttons/wells/code/table wraps 8 pt; utility buttons 6 pt; confirmation dialogs 5 pt; sign-in dialogs 10 pt; status badges 2 pt; dots and true pills capsule-only. Native system window corners, menus, popovers, and system controls keep their platform-managed geometry.
- **Borders:** 1 pt hairlines only. `surface` cards on `canvas` normally have no border; distinguish by background step. Raised `surfaceElevated` wells on `surface` get a 1 pt `hairline`. Use `hairlineSubtle` for rows. No dark/heavy/dashed/double strokes. Native focus rings are exempt; never hide them to enforce a 1 pt aesthetic rule.
- **Density:** short controls, generous horizontal padding. Avoid tall narrow buttons, randomly square buttons, huge rounded cards, giant dividers, and per-row box outlines. Keep hover areas large enough to hit even if visual controls are compact.
- **Window chrome:** native macOS traffic lights and titlebar behavior. No fake close/minimize/zoom controls, website navbar, hamburger imitation, or full-screen mobile menu.

## 4. Typography — preserve the original scale in points

| Role | Size / weight | Tracking / line height |
|---|---|---|
| Large in-app title, rarely used | 40 pt / 400 | -0.055em / 1.0; never in compact toolbar |
| Section title | 32 pt / 400; 24 pt constrained | -0.04em / 1.1 |
| Card title | 20 pt / 500; 18 pt constrained | -0.025em / 1.2 |
| Header subtitle | 18 pt / 500 | -0.025em; max ~320 pt, trailing aligned where applicable |
| Primary button | 15 pt / 500 | -0.012em |
| Table/body compact | 13 pt / 400 or 500 | Normal, readable |
| Utility/header/label | 12 pt / 400 | Muted as appropriate |
| Tiny metadata | 11 pt / 400 | Only nonessential information |
| Badge | 10 pt / 400 | Normal case; never uppercase bold |
| Code, key, URL-as-code | 12–13 pt / system monospaced | Truncate when required; provide full value on copy |

Keep live URL/search **editable text** sharp, readable, selectable, and appropriately sized. Browser tab labels and sidebar rows should use compact type, not section-title sizes. Translate tracking to SwiftUI `.tracking` in points; do not paste CSS `em` values into an API that expects points. Use native text layout, line limits, truncation, selectable text where appropriate, and accessibility sizing where available. Never add `.minimumScaleFactor` everywhere to hide a layout bug.

## 5. Browser structure — replace every website section pattern

**Window:** native window controls + unified browser chrome when the existing window setup supports it. Do not sacrifice titlebar dragging, full-screen, restoration, or window focus to imitate a screenshot.

**Top bar / address and search:** compact, visually calm, first-priority interaction surface. Retain URL/search editing, caret, selection, suggestions, keyboard shortcuts, paste, and focus. Keep text on a legible foreground layer; use native system material behind it only where it improves clarity. No blur filter applied to text, no constant resizing on focus, no giant search capsule, no multiple stacked glass backplates. Address-field geometry stays stable while typing.

**Tab strip:** compact identifiable tabs with title, optional favicon/loading state, active distinction, and close action. Add/select/close/reorder transitions must preserve tab identity and browser-view lifetime. A tab selection is a state change, **not** permission to rebuild its engine or web content. Use subtle background/material differences; active state must not depend on color alone.

**Sidebar:** a native sidebar, not a chatbot panel. Use `NavigationSplitView` only if it fits the existing window and browser-surface ownership; otherwise keep the existing sidebar implementation. Preserve navigation, collapse width, keyboard/pointer selection, and agent-related workflows. Sidebar sections and selected rows use semantic surface tokens. No individual glass pill on every row.

**Web content:** edge-to-edge within the area left by chrome. No artificial max width, page recoloring, app-level zoom, blur, overlay, or animation applied to the actual webpage. Preserve scrolling, selection, video, interaction, and engine ownership while chrome animates.

**Agent-native surfaces:** compact action status, progress, permission/confirmation, and execution visibility when those features already exist. No mandatory chat sidebar. Human and agent actions derive UI from the same authoritative tabs/navigation/execution state. Do not wait for an animation before returning a valid engine action result.

**Panels/settings:** use consistent left-aligned content, `surface` cards, 8 pt wells, hairlines, compact rows, and familiar macOS sheets/popovers. Only use the old ~1024 pt content maximum for a genuinely wide settings/documentation panel, not for browser chrome or the webpage.

**Tables/keys (only if such a feature exists):** `surfaceElevated` wrap, 10 pt × 14 pt cells, subtle separators, names truncate, actions trailing, badges radius 2 pt. Never invent auth/API-key features merely because the website design previously mentioned them.

**Errors/loading:** error well uses semantic red tokens; provide text and accessibility announcement. Use compact progress indicators only for actual indefinite work. Do not shimmer the entire browser or obscure a live webpage with fake skeleton content.

## 6. Buttons, fields, and toggles

- **Primary:** visual height 40 pt, min width 100 pt, 24 pt horizontal content inset, radius 8 pt, `primaryFill` → `primaryHover`, `ink` text, disabled ~0.48 opacity **unless it harms legibility**. Use only for actual primary actions.
- **Secondary/utility:** visual min height 30 pt, 14 pt horizontal inset, radius 6 pt, `surfaceSubtle` → `hover`, borderless. Never invisible white-on-white or dark-on-dark.
- **Cancel:** `surfaceElevated` + 1 pt `hairline`. Destructive actions use semantic error emphasis, not an arbitrary bright brand color.
- **Press:** immediate native pressed feedback; if movement is used, 1 pt downward maximum, never at the cost of pointer hit-testing. Prefer native `Button` behavior over hand-built gesture replacement.
- **Input:** 8 pt radius, readable `ink`, `placeholder`, and `fieldIcon`; 44 pt address-field height only if that fits the chosen top-bar geometry. Native text editing and focus first, appearance second.
- **Toggle/segmented control:** retain native semantics and keyboard access. Use `surfaceSubtle` well with ~3 pt interior gap where a custom segment is needed; active segment uses `surfaceElevated` and a hairline. Use actual `Toggle` for binary state, not a decorative fake toggle.
- **Icon-only actions:** accessible label and helpful tooltip. Keep compact visual icon size but sufficient clickable area. Disabled/loading/hover/focus/pressed states must exist in both themes.

## 7. Icons — native substitute for Hugeicons

The original React Hugeicons package is **not a SwiftUI dependency**. Prefer native SF Symbols via `Image(systemName:)` for macOS toolbar/navigation/control semantics, with consistent approximately 1.55-weight visual stroke, 16–17 pt in controls, ≤20 pt in input prefixes, ≤32 pt for rare feature illustrations. Symbol weight is optical, not a guarantee of an exact 1.55 px stroke. If an existing brand or proprietary icon is essential, use a properly licensed asset; never import a React package into the native app.

Icons exist only where they communicate an action/state. No emoji-as-icons, decorative icon grids, enormous symbols, icon-per-row clutter, or icons in ordinary body copy. Native help tooltips, keyboard shortcuts, VoiceOver labels, and selection state replace HTML `aria-*` attributes.

## 8. Liquid Glass, native blur, and native motion

Use **actual Apple APIs**, not simulated CSS glass. The design system specifies *where* enhancement is appropriate; `enhance-browser-ui/SKILL.md` details the later implementation pass.

- Liquid Glass: restrained interactive navigation controls, select toolbar groups, appropriate floating actions and transitions. Inspect installed SDK and deployment target before using `glassEffect`, `GlassEffectContainer`, glass identities/transitions, or AppKit glass views.
- Native blur/material: top-bar backing and suitable sidebar/sheet surfaces when legible. SwiftUI `Material` or AppKit `NSVisualEffectView` can serve surfaces that should not be individual Liquid Glass shapes.
- Opaque `canvas`/`surface` is the correct answer when blur undermines contrast or performance.
- Group related glass shapes in a shared container rather than many separate render regions. Avoid glass on the entire browser viewport, every tab, every sidebar row, or every nested card.
- Focus 100–160 ms; hover 80–120 ms; active tab 140–200 ms; add/close tab 160–220 ms; sidebar 180–260 ms. These are **tuning starting points**, not hardcoded universal values. Favor `.snappy` or `.smooth`; no theatrical bounce, ambient motion, or massive slide distances.
- Animate only the relevant chrome state. Browser navigation, text entry, scroll, and engine actions must not wait for decorative animation to complete.
- No visual trick that makes text blurry, delays interaction, rebuilds the web view, or causes a massive translucent layer over changing page pixels.

## 9. Responsive macOS behavior and accessibility

Resize according to **available window width**, not CSS media queries or phone breakpoints. Keep browser chrome usable in narrower windows by truncating tab titles, reducing nonessential controls, using native overflow, and retaining key actions. Do not convert macOS into a mobile website.

Honor system **Reduce Motion**, **Reduce Transparency**, increased contrast, keyboard navigation, focus visibility, and VoiceOver. Reduced transparency means opaque, legible surfaces; reduced motion means remove unnecessary spatial motion, not 0.01 ms CSS hacks. Never suppress native focus rings. Check light and dark chrome above light, dark, and colorful webpages. Respect accent and system UI behavior where it does not contradict the explicit stone design.

## 10. Minimal native state and dependency rules — for agents new to Swift

**SwiftUI View** = a description of what a control looks like for the current data. **State** = data that can change. **Dependency injection** = giving a view or service the thing it needs, instead of having every component secretly create its own browser engine.

- `@State`: temporary UI-owned values such as whether a popover is open or the address field is editing.
- `@Binding`: child control reads and writes a value owned elsewhere; do not create a second copy.
- An existing observable browser model: authoritative tabs, active tab ID, navigation, loading, and agent execution status. Keep one owner. Use the observation system already used by the repository; prefer modern `@Observable` when supported rather than a rewrite for its own sake.
- `@Environment(\.colorScheme)`: read current light/dark appearance. A small user appearance preference (`system`, `light`, `dark`) may persist with `@AppStorage`; apply any override at the proper scene/window boundary. System is the default.
- Pass an existing browser model/service through a view initializer or a properly scoped environment, rather than calling a new engine constructor from each tab, sidebar row, or button. This is all the “dependency injection” Aether needs until complexity actually requires more.
- Engine calls and agent actions live in the existing service layer. Views invoke those actions and display the resulting shared state. **Never duplicate browser navigation logic in a visual modifier.**

Do not introduce a DI framework, global singleton maze, unnecessary protocol forest, state-management package, or parallel UI store. Prefer simple existing code and correct ownership.

## 11. Quality gates / hard bans

**DO**

- Keep all literal light colors and sizing relationships above, and their exact dark semantic counterparts.
- Reuse the nearest native component before creating another style variant.
- Check Instrument Sans registration and actual weights in the Xcode app bundle.
- Test System → Light → Dark and live OS appearance switching.
- Test address input, tab close/reorder, narrow windows, sidebar, and agent-triggered navigation under both themes.
- Profile animation, main-thread work, memory, and browser rendering on representative hardware. Match the display's refresh cadence where practical; never claim measured speed without measuring.
- Preserve native macOS menus, keyboard shortcuts, focus, titlebar, window restoration, and accessibility.

**DON'T**

- No website navbar, hero, FAQ, alternating marketing sections, CSS zoom, CSS breakpoints, Tailwind classes, Next.js font loading, React Hugeicons, HTML `aria-*`, or fake macOS window controls.
- No pitch-black dark mode, purple/blue-gray gradients, random accent palette, oversized radii, thick outlines, giant pill buttons, or glass everywhere.
- No web-content recoloring, browser-wide blur, independent tab-state copies, hidden new engine instances, or re-created web views when switching themes/tabs.
- No superfluous dependencies, unnecessary redesign, chatbot sidebar requirement, or runtime performance claims without testing.

**Done means:** Aether remains the same restrained stone-based design in both appearances; it feels native to macOS, preserves real browser/agent functionality, keeps text sharp, respects accessibility, and adds only the effects that earn their rendering cost.
