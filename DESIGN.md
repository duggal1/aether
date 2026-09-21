# Aether — Design System

**Status:** Authoritative. This file replaces any prior `DESIGN.md` and `APPLE-DESIGN.md` in this repo — those are deprecated and wrong. If they still exist, delete them and point all agents here.

**Structure reference:** Dia (`dia1.jpg`–`dia8.jpg`)
**Palette / brand:** Aether (ours, defined below — not Dia's palette)
**Material system:** Apple Liquid Glass (macOS Tahoe 26 / iOS 26, WWDC25)

---

## 0. How to use this document (read this first, agent)

1. Aether currently scores **0/10** on design. It is not "close" — almost every screen needs rework. Don't patch one screen and stop; sweep the whole app against §9.
2. **Structure and information architecture come from Dia.** When you're unsure how a component should be laid out, open the matching `dia*.jpg` screenshot referenced in §13 and copy its structure — spacing, hierarchy, row order, icon placement. Do not invent new layouts.
3. **Color and material come from this document, not from Dia's screenshots.** Dia's own hex values are irrelevant; only its *structure* matters. Aether uses the Stone scale in §2, not Dia's palette.
4. Every visual decision in this file exists to fix a specific, named problem in the current build. The paired file `ISSUE-DESIGN.md` lists each problem with screenshot evidence. Treat that file as the bug tracker and this file as the spec each bug is fixed against.
5. Zero hard borders. Read §2.4 before you write a single `border:` or `.border()` line.
6. When native and web implementations disagree on a specific pixel value, native wins — Aether must read as a first-party Apple app, not a themed Electron shell.

---

## 1. Design North Star

Aether is a native-feeling macOS browser. The bar is: **a person who has never seen Aether should not be able to tell it apart from a first-party Apple app or Dia at a glance.** Concretely:

- **Structure:** sidebar-first tab management, a floating centered "Ask anything…" command bar on new tab, a right-hand slide-in command palette (`⇧⌘A`), flyout submenus for bookmarks — all lifted directly from Dia's layout language.
- **Material:** every floating surface (sidebar, toolbar, menus, popovers, sheets, tooltips) is **Liquid Glass** — a translucent, refractive material that reacts to what's behind it — not a flat, solid `stone-800` rectangle with a 1px border.
- **Color:** near-black Stone, two-step elevation, one accent color reserved exclusively for meaning (focus, selection, destructive), never for decoration.
- **Type:** quiet. 400/500 weight only. The content people are looking at should be the loudest thing on screen — chrome recedes.
- **Icons:** thin stroke, real brand marks fetched live, Phosphor as the only fallback.
- **Motion:** springy, liquid, Apple-native easing — never a linear fade or a hard cut.

---

## 2. Color System

### 2.1 Dark mode — the only palette you may use

| Token | Hex | Use for |
|---|---|---|
| `--surface-window` | `#15161d` | Window background behind everything |
| `--surface-base` | `#17181e` | Content-area background, page surface |
| `--surface-raised` | `#333544` | **Cards, panels, menus, sheets, popovers at rest.** This is the ONE overlay tone. |
| `--surface-active-tab` | `#1b1b23` | Selected tab row — darker inset, never lighter than chrome |
| `--surface-hover` | `rgba(255,255,255,0.08)` | Hover / pressed state on anything (translucent, works over glass) |
| `--surface-selected` | `rgba(255,255,255,0.11)` | Selected menu/palette row |
| `--surface-tile` | `#404253` | Pinned shortcut tiles |
| `--surface-pill` | `#3c3e56` | Profile/pins capsule in top-tab mode |
| `--surface-composer` | `#1b1c21` | New-tab ask card |
| ~~`--stone-750`~~ | | **BANNED.** Do not use. |
| ~~`--stone-700`~~ | | **BANNED.** Reads as washed-out gray, breaks the near-black look. |
| `--text-primary` | `#fafafa` | neutral-50. Titles, primary labels, active tab text |
| `--text-secondary` | `#a3a3a3` | neutral-400. URLs, timestamps, section labels, placeholder text |
| `--text-tertiary` | `#737373` | neutral-500. Disabled text, sublabels |
| `--divider` | `rgba(255,255,255,0.08)` | The *only* line you're allowed to draw — a hairline divider inside a menu, never a box border around a component. See §2.4. |

**Background/overlay rule:** window = `--surface-window`. Content = `--surface-base`. Anything floating above (card, tile, menu, popover, sheet) = `--surface-raised`. Hover/pressed = `--surface-hover` (translucent white, safe over glass). The selected tab row is the one exception that goes darker: `--surface-active-tab`.

### 2.2 Light mode

| Token | Hex | Tailwind ref | Use for |
|---|---|---|---|
| `--surface-base-light` | `#ffffff` | white | App window background, sidebar background |
| `--surface-raised-light` | `#f5f5f4` | stone-100 | Cards, panels, menus, sheets, popovers, tiles, **and buttons** (buttons in light mode = stone-100, matching the dark-mode rule that buttons sit one step above base) |
| `--surface-hover-light` | `#e7e5e4` | stone-200 | Hover / pressed state |
| `--text-primary-light` | `#1c1917` | stone-900 | Titles, labels |
| `--text-secondary-light` | `#78716c` | stone-500 | URLs, timestamps |
| `--divider-light` | `rgba(28,25,23,0.08)` | black 8% | Hairline dividers only |

> Note: the source dictation says "BG Wide" for the light-mode background — this is read as **"BG White"** (voice-to-text artifact). If that's wrong, the only change required is swapping `--surface-base-light` from `#ffffff` to `#fafaf9` (stone-50); every other light-mode token stays identical. Flag this assumption to the human before shipping light mode.

### 2.3 Accent & semantic color — reserved, not decorative

| Token | Hex | Use for | Do NOT use for |
|---|---|---|---|
| `--accent` | `#0a84ff` (systemBlue, dark) / `#007aff` (light) | Active **keyboard focus ring** on a text input while typing. Selected state indicator (a small dot/checkmark), primary CTA button fill when a screen needs exactly one emphasized action (e.g. "Create Profile"). Link text on hover. | Resting-state borders on pills, menu rows, or buttons. This is `ISSUE-DESIGN.md` #001 — the accent color is currently leaking out as a permanent border on the profile switcher and menu items. It must **only** appear transiently, tied to an actual focus/selection event. |
| `--destructive` | `#ff453a` (dark) / `#ff3b30` (light) | Delete/clear actions on confirm, destructive menu items on hover | Anything decorative |
| `--success` | `#30d158` (dark) / `#34c759` (light) | Success toasts, connected states | — |

### 2.4 The zero-border rule

This is the single highest-leverage fix in the whole document (`ISSUE-DESIGN.md` #001, #004, #010).

**Never draw a border to separate a surface from its background.** Separation is created by **elevation** (a one-step-lighter fill, §2.1) plus a **soft shadow** (§5), not by an outline. A 1px stroke around a card, a button, a favicon tile, or a profile pill is *always* wrong in this system.

The only two legitimate uses of a visible stroke anywhere in Aether:
1. A **hairline divider** *inside* a menu or list, at 8% white opacity, to separate grouped rows (see Dia's bookmarks flyout, `dia6.jpg`).
2. A **focus ring**, in `--accent`, 2px, applied only while an element has actual keyboard focus (a text field being typed into) — removed the instant focus moves away. This is not a resting-state style.

If you find yourself writing `border: 1px solid` or `.stroke(.gray)` anywhere else — on a pill, a tile, a button, a dropdown item — stop and re-derive the surface using elevation instead.

---

## 3. Typography

### 3.1 Family

```css
--font-ui: "Instrument Sans", -apple-system, system-ui, sans-serif;
--font-mono: "Instrument Sans", ui-monospace, "SF Mono", monospace;
```

Aether chrome renders exclusively in Instrument Sans (variable face, wght 400–700,
bundled under `AetherHumanUI/Resources/Fonts/`). `AetherFontRegistry` instantiates exact
400 / 450 / 500 weights through the variation axis — never synthetic bolding. SF Symbols
remain the only icon face; SF Pro is not used for chrome text.

### 3.2 Weight — hard limit

**Only three weights exist in browser chrome: 400 (normal), 450 (medium-light, variable-axis interpolation), 500 (medium).** Nothing heavier. This is a hard rule, not a preference — semibold/bold headings are what makes the current Settings and History panels feel like a generic web app instead of a native one (`ISSUE-DESIGN.md` #006).

| Token | Weight | Use for |
|---|---|---|
| `--weight-normal` | 400 | Body copy, list rows, URLs, most labels |
| `--weight-medium-light` | 450 | Row **titles** and tab titles — the exact variable instance, never a faked weight |
| `--weight-medium` | 500 | Panel headings ("History", "Downloads", "Aether Settings"), primary buttons, section labels |

Rendered website content inside the webview is exempt — a page can use whatever weights it wants. This rule governs **Aether's own chrome only.**

### 3.3 Scale

| Token | Size / line-height | Weight | Use for |
|---|---|---|---|
| `--type-panel-title` | 20px / 24px | 500 | "History", "Downloads", "Aether Settings" |
| `--type-body` | 14px / 20px | 400 | Menu items, list rows, buttons, input text |
| `--type-row-title` | 13px / 18px | 450 | History/bookmark row titles, tab titles |
| `--type-caption` | 12px / 16px | 400 | URLs, timestamps, section labels (paired with `--text-secondary` and +4% letter-spacing when used as an uppercase section header like Dia's "Open Tabs" / "Recently Closed") |
| `--type-placeholder` | 15px / 20px | 400 | "Ask anything…", "Search Google or enter URL" |

---

## 4. Spacing, Sizing & Radius

8pt grid with 4pt subdivisions (Apple's de facto convention, not an official mandate, but it's what every Apple surface you're copying actually measures out to).

| Token | Value |
|---|---|
| `--space-1` | 4px |
| `--space-2` | 8px |
| `--space-3` | 12px |
| `--space-4` | 16px |
| `--space-5` | 20px |
| `--space-6` | 24px |
| `--space-8` | 32px |

| Token | Value | Use for |
|---|---|---|
| `--radius-sm` | 8px | Small chips, favicon tiles |
| `--radius-md` | 12px | List rows, menu rows, buttons |
| `--radius-lg` | 16px | Menus, popovers, cards, the command palette panel |
| `--radius-xl` | 20px | Sheets/modals (History, Downloads, Settings, Create Profile) |
| `--radius-full` | 999px | The "Ask anything…" search capsule, profile pill, avatar dots |

| Element | Size |
|---|---|
| Sidebar width | 260pt default (already correct in Settings → Tabs, keep as-is; the slider there is one of the only screens currently built right) |
| Sidebar row height | 36px |
| Toolbar height | 44px |
| Favicon tile | 44×44px (matches Apple's 44pt minimum tap target — don't go smaller) |
| Icon stroke canvas | 20×20px default, 16×16 in dense rows |
| Minimum tap target | 44×44pt on every clickable element, no exceptions (Apple HIG) |

---

## 5. Elevation Without Borders

Replace every border with one of these three shadow tokens, chosen by how far the surface floats above its background:

```css
--shadow-sm:  0 1px 2px rgba(0,0,0,0.28);                 /* resting tiles, pressed buttons */
--shadow-md:  0 8px 24px rgba(0,0,0,0.36), 
              inset 0 1px 0 rgba(255,255,255,0.05);        /* menus, popovers, dropdowns */
--shadow-lg:  0 24px 64px rgba(0,0,0,0.48), 
              inset 0 1px 0 rgba(255,255,255,0.06);        /* sheets, modals, the command palette */
```

The `inset` top highlight is not decorative flourish — it's what sells "glass" rather than "flat gray rectangle." A pane of glass catches a thin line of light along its top edge; a painted rectangle doesn't. Keep it subtle (5–6% white).

---

## 6. Materials — Apple Liquid Glass & Vibrancy

This is the fix for `ISSUE-DESIGN.md` #007 — right now every floating surface in Aether is a flat, opaque `stone-800` rectangle. Nothing is translucent, nothing reacts to what's behind it. That reads as a themed web app, not a Mac app.

### 6.1 What Liquid Glass actually is (so agents stop faking it with a plain blur)

Apple's Liquid Glass (introduced WWDC25, shipped across iOS 26 / iPadOS 26 / macOS 26 "Tahoe") is not a Gaussian blur with transparency. It's a real-time material that **lenses** — bends and concentrates the light of whatever is behind it — rather than scattering it like a traditional blur. It sits exclusively on the **navigation/chrome layer** that floats above content; it is never applied to content itself (never blur a webpage, a list of tabs, or actual page text). Content stays sharp and primary; controls recede and let it show through.

Three variants exist in SwiftUI's `Glass` API:
- **`.regular`** — the default. Use for toolbars, sidebars, menus, buttons, standard controls. Medium transparency, fully adapts to whatever content sits behind it.
- **`.clear`** — for small floating controls over media-rich backgrounds (video, photos) where the content underneath must stay legible and bold. Not needed anywhere in Aether's current surface list.
- **`.identity`** — turns the effect off conditionally (e.g., respecting Reduce Transparency).

### 6.2 Per-surface material map

| Surface | Material | Notes |
|---|---|---|
| Sidebar | `.sidebar` vibrancy / `.regular` glass | Should wallpaper-tint like a native sidebar — see §6.4 |
| Toolbar (back/forward/URL bar row) | `.regular` glass, or `.titlebar` vibrancy if merged with the titlebar | |
| Main content window chrome (non-webview areas) | `.contentBackground` / `.windowBackground` | Opaque enough not to fight with page content |
| Overflow / kebab menu, profile dropdown, right-click context menus | `.regular` glass or `.menu` vibrancy | This is the biggest visible gap right now — the kebab menu in the current build (`aether6.jpg`) is a flat solid fill |
| Command palette (`⇧⌘A` panel) | `.regular` glass, `--radius-xl`, `--shadow-lg` | |
| Bookmarks flyout, "New Profile" color swatch popover | `.popover` vibrancy | |
| History / Downloads / Settings sheets | `.sheet` vibrancy, presented as a true sheet (see §9.9), backdrop **dims and blurs** the window behind it | |
| Tooltips | `.toolTip` vibrancy | |
| HUD-style transient toasts (e.g. "Copied") | `.hudWindow` vibrancy | |

### 6.3 Native SwiftUI implementation

```swift
// A single glass surface
Text("Ask anything…")
    .padding()
    .glassEffect(.regular, in: .capsule)

// Multiple glass elements that should share one lensing pass
// and be able to morph into each other (e.g. toolbar buttons)
GlassEffectContainer(spacing: 20) {
    HStack(spacing: 12) {
        Button("Back", systemImage: "chevron.left") { }
            .glassEffect(.regular.interactive())
        Button("Forward", systemImage: "chevron.right") { }
            .glassEffect(.regular.interactive())
    }
}

// Sidebar / toolbar / menu bar / Dock get Liquid Glass FOR FREE
// when compiled against the macOS 26 SDK — verify Aether is
// targeting it. If it is and these still look flat, something
// is overriding the system chrome (custom NSWindow background,
// or a webview painted over the whole window).
```

Rules for `.glassEffect()` usage:
- Always group adjacent glass elements (toolbar buttons, tab pills) inside one `GlassEffectContainer` — applying `.glassEffect()` to siblings outside a container makes each one sample independently and look inconsistent.
- Use `.tint()` only to convey semantic meaning (a primary/selected action), never as decoration. This is the same rule as §2.3 for the accent color.
- Use `.interactive()` on anything tappable — it adds the scale-on-press, shimmer, and touch-point illumination that makes glass feel alive instead of static.
- Respect system accessibility settings automatically — they come free with the material (see §6.6). Do not hand-roll your own transparency toggle that fights the system one.

### 6.4 Electron / Tauri / AppKit implementation (if Aether is not pure SwiftUI)

If the shell is Electron or Tauri, use real `NSVisualEffectView` materials, not a CSS blur painted over a solid `BrowserWindow` background — a CSS blur alone can't sample the desktop wallpaper or windows behind Aether the way native vibrancy can.

```js
// Electron — electron-vibrancy / window-vibrancy style API
const { BrowserWindow } = require("electron");

const win = new BrowserWindow({
  backgroundColor: "#00000000",   // transparent — let the material show
  titleBarStyle: "hidden",
  vibrancy: "sidebar",            // NSVisualEffectMaterial.sidebar
});
```

```rust
// Tauri — window-vibrancy crate
use window_vibrancy::{apply_vibrancy, NSVisualEffectMaterial};

apply_vibrancy(&window, NSVisualEffectMaterial::Sidebar, None, Some(16.0))
    .expect("Vibrancy is only supported on macOS");
```

Because a single `BrowserWindow`/`NSWindow` only carries one vibrancy material at a time, but Aether needs a *different* material on the sidebar vs. the content area vs. menus, don't rely on the whole-window vibrancy call alone — layer separate `NSVisualEffectView`s (or the Tauri equivalent) per region, matched to §6.2's table. This is the same pattern real sidebar-based Mac apps (Mail, Notes, Dia itself) use, and it's also what lets the sidebar pick up **wallpaper tinting** (System Settings → Appearance → "Allow wallpaper tinting in windows") the way Dia's sidebar visibly does in `dia1.jpg`.

| Region | `NSVisualEffectMaterial` |
|---|---|
| Sidebar | `.sidebar` |
| Toolbar / titlebar | `.titlebar` |
| Overflow / context menus | `.menu` |
| Popovers (bookmarks flyout, profile switcher) | `.popover` |
| Sheets (History, Downloads, Settings) | `.sheet` |
| Tooltips | `.toolTip` |
| HUD toasts | `.hudWindow` |

### 6.5 Web/CSS fallback (only for portions actually rendered in a webview, e.g. the new-tab page)

```css
.glass-surface {
  background: color-mix(in srgb, var(--surface-raised) 72%, transparent);
  backdrop-filter: blur(24px) saturate(140%);
  -webkit-backdrop-filter: blur(24px) saturate(140%);
  box-shadow: var(--shadow-md);
  border-radius: var(--radius-lg);
  /* no border — see §2.4 */
}
```

This is a fallback only — it cannot lens or refract, and it cannot sample content outside the browser window the way native vibrancy can. Never rely on it for the sidebar or menus if a native vibrancy path (§6.4) is available in the same surface.

### 6.6 Accessibility — this comes with the material, don't fight it

Liquid Glass automatically honors three system settings; do not build a custom override that duplicates or conflicts with them:
- **Reduce Transparency** → glass becomes frostier / more opaque automatically.
- **Increase Contrast** → glass elements become predominantly solid black/white with a contrasting edge.
- **Reduce Motion** → disables the elastic/bouncy behaviors in §8, falls back to simple cross-fades.

If building the web fallback path, replicate these three toggles by reading `prefers-reduced-transparency`, `prefers-contrast`, and `prefers-reduced-motion` media queries.

---

## 7. Iconography

Fixes `ISSUE-DESIGN.md` #002 and #003.

### 7.1 Real logos, not letter avatars — this is non-negotiable

The current build renders shortcut tiles as a plain colored square with a single capital letter ("Y" for YouTube, "M" for Gmail, "G" for GitHub, "S" for Slack, "N" for Notion, "C"/"C" for Calendar and ChatGPT — see `aether2.jpg`). This is the single ugliest thing in the app. Every one of these has a real, recognizable, colorful logo. Fetch and render it.

**Fetch order, per site:**
1. The site's own high-res favicon (`<link rel="apple-touch-icon">` or `<link rel="icon">`, largest available, prefer SVG/PNG over `.ico`).
2. A favicon service as fallback (e.g. Google's `s2/favicons?sz=128&domain=`, or an equivalent self-hosted resolver) when the site doesn't expose one directly.
3. **Only if both fail:** a Phosphor icon placeholder (see 7.3) — never a letter avatar. A generic "globe" or "browser" glyph beats a letter every time.

Cache fetched favicons locally, keyed by domain, refreshed on a TTL (weekly is plenty) — don't refetch on every render.

### 7.2 Stroke weight

Every UI icon (toolbar, sidebar, menus, buttons — anything that isn't a fetched brand favicon) currently renders too thick (`aether6.jpg`'s kebab menu icons are a good reference point for "too heavy"). Move to a **thin stroke** icon set:

- Preferred: **Phosphor Icons**, `Thin` or `Light` weight (1px stroke at 20px canvas), NOT `Regular`, `Bold`, `Fill`, or `Duotone`.
- Alternative if already committed to Lucide/Feather elsewhere: set `stroke-width: 1.25` (down from the typical 2) and confirm it doesn't get visually lost at 16px — thin icons need slightly larger canvases to stay legible.
- Never mix icon sets in the same menu. If Phosphor doesn't have a specific glyph, that's the *only* case to reach for SF Symbols as the fallback set (Apple-native, thin by default) before falling back further.

### 7.3 Fallback icon = Phosphor, always

Any icon that's "completely missing" right now — an icon slot with nothing rendered — gets a Phosphor `Thin`-weight glyph, chosen for closest semantic match, never left blank and never substituted with text.

### 7.4 Sizing

| Context | Size |
|---|---|
| Sidebar tab row icon / favicon | 16×16px |
| Toolbar icon (back/forward/reload/history/downloads/kebab) | 18×18px |
| Menu row icon | 16×16px |
| Shortcut tile favicon (the Y/M/G/S grid) | 24×24px inside a 44×44px tile |
| Settings sidebar icon | 18×18px |

---

## 8. Motion — Liquid Motion

Fixes `ISSUE-DESIGN.md` #012. Nothing in the current build springs, morphs, or settles — things just appear/disappear. Apple's whole motion language is built on physical springs, not linear/ease curves.

### 8.1 Tokens

```css
--duration-micro: 120ms;      /* hover state changes, icon color shifts */
--duration-standard: 220ms;   /* menu open/close, tile press */
--duration-large: 380ms;      /* sheet present/dismiss, command palette slide-in */

--ease-standard: cubic-bezier(0.4, 0, 0.2, 1);
--ease-liquid: cubic-bezier(0.34, 1.56, 0.64, 1); /* slight overshoot — CSS approximation of a SwiftUI spring */
```

Native SwiftUI equivalent — use real springs, not the CSS approximation, wherever SwiftUI is available:

```swift
withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
    isExpanded.toggle()
}
```

### 8.2 Interaction patterns

| Interaction | Behavior |
|---|---|
| Tile / button hover | Background steps to `--surface-hover` over `--duration-micro`, no scale change |
| Tile / button press | Scale to 0.97, `--duration-micro`, `--ease-liquid` (slight bounce back on release) |
| Menu open | Fade + scale from 0.96 → 1.0, origin at the trigger element, `--duration-standard`, `--ease-liquid` |
| Sheet present (History/Downloads/Settings) | Backdrop blur + dim fades in over `--duration-standard`; sheet itself scales 0.95 → 1.0 and rises slightly, `--duration-large`, `--ease-liquid` |
| Command palette slide-in | Slides in from the right edge, `--duration-large`, `--ease-liquid`, backdrop dims the rest of the window |
| Glass morphing (e.g. a button expanding into a menu) | Use `GlassEffectContainer` + a shared `glassEffectID` + `@Namespace`, so the shape itself morphs rather than cross-fading two separate shapes |
| Tab close (X appears on hover, `aether3.jpg`) | X fades in over `--duration-micro`; on click, tab collapses width to 0 over `--duration-standard` before removal, siblings slide to fill the gap |

Always check `prefers-reduced-motion` (web) or the system Reduce Motion setting (native) and fall back to a plain opacity cross-fade with no scale/spring when it's on.

---

## 9. Components

For every component below: **structure from the named `dia*.jpg`, palette/material from §2–§8.**

### 9.1 Sidebar — ref `dia1.jpg`, `dia2.jpg`, `dia3.jpg` vs. current `aether1.jpg`, `aether2.jpg`, `aether3.jpg`

- Background: `--surface-base` + `.sidebar` vibrancy (§6.4), wallpaper-tinted.
- Profile switcher at top: plain text button, `--type-body` / 500 weight, small chevron, **no border, no box** — just text sitting directly on the sidebar background (compare Dia's plain "Personal" text in `dia1.jpg` to Aether's boxed-and-blue-bordered "Personal ⌄" in `aether2.jpg`).
- Shortcut grid (2 rows × 3–4 real favicons): 44×44 tiles, `--radius-md`, `--surface-raised` background, **no border**, real fetched favicons per §7.1, tight 8px gutter, matching Dia's density in `dia3.jpg` — Aether's current grid (`aether2.jpg`) has visibly more padding per tile and a border ring around each one; tighten both.
- "+" add-shortcut tile: dashed outline, low-contrast (`--text-tertiary` at 40% opacity), the **one** intentional exception to the no-border rule, because a dashed "add" affordance is a recognized pattern (Dia does this too, `dia3.jpg`).
- "New Tab" row: plain row with a leading "+" icon, no background at rest, `--surface-hover` on hover with `--radius-md`.
- Tab list: each row 36px tall, `--radius-md`, transparent at rest, `--surface-hover` on hover, `--surface-raised` + subtle highlight for the **active** tab (matches Dia's lighter-pill active row in `dia3.jpg`). Favicon or generic icon leading, title trailing, truncate with ellipsis. On hover, a thin-stroke Phosphor "X" fades in trailing-aligned to close the tab (already close to correct in `aether3.jpg` — keep that interaction, fix the icon weight and remove the border on the row).
- Bottom utility row: history / bookmarks / search icons, 18px, thin stroke, evenly spaced, no dividers needed — plain icon buttons on the sidebar background.

### 9.2 Top-tab layout (alternate mode) — ref `dia4.jpg` vs. `aether7.jpg`

Same rules as 9.1, rotated 90°: tabs live in a horizontal strip at the top, each tab a `--radius-md` pill, active tab gets `--surface-raised`, inactive tabs sit flush on `--surface-base` with no border. Toolbar row (back/forward/reload/URL/history/downloads/kebab) sits directly below, also border-free, `.titlebar` vibrancy.

### 9.3 Toolbar / address bar

- Height 44px, `--radius-full` capsule for the URL field itself, `--surface-raised` fill, lock icon + URL text (`--text-secondary` for the domain, `--text-primary` on focus/edit).
- Back / forward / reload icons: 18px thin stroke, plain (no background) at rest, `--surface-hover` circular hit-state on hover, disabled state at 30% opacity (not a different color).
- Trailing icon cluster (history / downloads / kebab): same treatment. **Do not** give any one of these a persistent colored border — this is exactly the bug visible in `aether2.jpg`, `aether6.jpg`, `aether7.jpg` where the URL bar and kebab button sit inside faint boxes.

### 9.4 Favicon / shortcut tiles

Covered in 9.1 — reiterating the fetch requirement (§7.1) because it's the highest-visibility fix in the entire app.

### 9.5 Profile switcher — ref `dia7.jpg` dropdown vs. current bordered pill

- Trigger: plain text + chevron, no box (9.1).
- Dropdown menu on click: `--surface-raised`, `--radius-lg`, `--shadow-md`, `.menu` vibrancy. Rows: colored dot (profile color) + name + optional keyboard shortcut hint right-aligned in `--text-tertiary`, checkmark leading on the active profile. Divider (`--divider`, §2.4) above "+ New Profile" and above "Profile Settings". Icon leading on "+ New Profile" (plus, thin) and "Profile Settings" (gear, thin). This matches `dia7.jpg` almost exactly — Aether just needs the same structure rebuilt in the correct palette/material.

### 9.6 Overflow / kebab menu — ref current `aether6.jpg`, restructure per Dia's menu language (`dia6.jpg`'s command palette rows as the closest available reference)

- Fix the **blue border bug** first — "Search Tabs" currently renders with a persistent `--accent`-colored rectangular outline. That's a stuck focus ring; the fix is behavioral (only render the focus ring while the item actually has keyboard focus) as much as visual.
- Rows: 36px tall, `--radius-md`, icon (16px, thin stroke, §7.2) + label (`--type-body`, 400 weight — "History" currently looks correct weight, keep it), transparent at rest, `--surface-hover` + no border on hover/focus (replace the blue box with a background fill).
- Group with whitespace *or* thin dividers (`--divider`) between: [Search Tabs] · [History, Bookmarks, Downloads] · [Find in Page, Reader, Inspect Page] · [Use Top Tabs, Settings]. Dia leans on generous whitespace between groups rather than solid dividers in the command palette — either is acceptable as long as no group boundary is drawn as a border/box.

### 9.7 Command palette (`⇧⌘A`) — ref `dia5.jpg`, `dia6.jpg`

This entire pattern does not yet exist in Aether and should be built net-new, structured exactly like Dia's:

- Docked to the right edge of the window, full height, `--radius-lg` on the leading edge only, `.regular` glass / `.popover` vibrancy, `--shadow-lg`.
- Search field pinned at top: magnifying glass icon, `Search` placeholder, right-aligned keyboard shortcut hint (`⇧⌘A`) in `--text-tertiary`.
- Section headers ("Open Tabs", "Recently Closed"): `--type-caption`, `--text-secondary`, uppercase-style spacing, no background.
- Rows: icon/favicon leading (real favicon where available, generic thin icon otherwise), label, optional trailing chevron for rows that open a submenu ("History", "Bookmarks"). Hover/selected row gets a `--surface-hover` pill inset by 8px from the panel edge — never full-bleed, never bordered.
- "Show More" row: `...` icon + chevron, same row treatment.

### 9.8 Bookmarks flyout — ref `dia6.jpg`

- Separate floating card from the command palette, same material/shadow tokens (`.popover` vibrancy, `--shadow-md`, `--radius-lg`).
- Top two rows ("Add to Bookmarks Bar", "Manage Bookmarks") — icon + label, no favicon needed (system actions).
- Divider (`--divider`).
- Bookmark list rows — real favicon (§7.1) + title, truncate with ellipsis.
- Divider.
- Folder rows ("Bookmarks Bar", "Other Bookmarks") — folder icon (thin) + label + trailing chevron indicating a submenu.

### 9.9 History / Downloads / Settings — ref current `aether4.jpg`, `aether5.jpg`, `aether8.jpg`

The structural content of these three screens is already reasonably close — the fix here is almost entirely material and border, not layout:

- Stop presenting these as a flat card sitting on top of visible sidebar/content (the "you can literally see it open up" complaint). Present them as a true **sheet**: backdrop behind the sheet dims (40–50% black scrim) **and** blurs (12–16px) the rest of the window, the sheet itself uses `.sheet` vibrancy, `--radius-xl`, `--shadow-lg`, and animates in with the spring in §8.2 rather than just appearing.
- "Clear History" button currently has the stray blue border bug (`aether4.jpg`) — remove it, restyle per §9.12.
- Title weight: "History" / "Downloads" / "Aether Settings" currently render heavier than `--type-panel-title`'s 500 weight allows — bring down to 500 exactly, no semibold/bold.
- Search input inside History: keep the nested-pill treatment, just move its background from whatever it is now to `--surface-base` (one step *darker* than the sheet's `--surface-raised`, to read as inset) with no border.
- List rows (History): already close to right — favicon (must become a real fetched favicon, not "Y"/"A" letters, §7.1), title (`--type-row-title`, 450 weight), URL (`--type-caption`, `--text-secondary`), timestamp, delete icon. Remove any border on the row; separation comes from the row's own `--surface-base` fill sitting inside the sheet's `--surface-raised` background (inset elevation, same principle as the search field).
- Settings window (`aether8.jpg`): this screen is one of the better ones already — Tab layout selector cards and the sidebar-width slider are close to correct. Fixes needed: replace any native OS checkbox/radio look with the SwiftUI-native equivalents (§9.14), confirm the "NATIVE · MACOS" footer label uses `--type-caption` at `--text-tertiary`, and give the two layout-preview cards (`Top of Window` / `Sidebar`) `.regular` glass instead of a flat fill.

### 9.10 Create Profile modal — ref `dia2.jpg` / `dia19.jpg`

Already close to correct in both apps. Confirm: `--radius-xl`, `.sheet` vibrancy, `--shadow-lg`, backdrop dim+blur behind it. Color swatches are circles with a 2px `--accent` ring **only** on the selected swatch (this is a legitimate, meaning-tied use of the accent color, not decoration — keep it). "Cancel" ghost button + "Create Profile" filled button per §9.12.

### 9.11 Buttons

| Variant | Fill (dark) | Fill (light) | Border | Text weight |
|---|---|---|---|---|
| Primary / filled | `--surface-hover` (stone-800) — or `--surface-raised` (stone-850) if stone-800 is already the ambient surface in that context | `--surface-raised-light` (stone-100) | none | 500 |
| Ghost / secondary | transparent, `--surface-hover` on hover | transparent, `--surface-hover-light` on hover | none | 400 |
| Destructive | `--destructive` at 12% fill, full opacity on hover | same | none | 500 |
| Icon-only | transparent, `--surface-hover` circular hit-state on hover | same pattern | none | — |

No button anywhere gets a stroke. If a button currently has one (Clear History, Create Profile, Cancel in several screenshots), remove it and rely on the fill-color step for definition.

### 9.12 Inputs / search capsule ("Ask anything…")

- `--radius-full`, `--surface-raised` fill, `.regular` glass, `--shadow-md`.
- Leading search icon (18px, thin), placeholder `--type-placeholder` / `--text-secondary`.
- Trailing cluster: "+ Add tabs or files" as a nested ghost pill (§9.11 ghost variant, smaller radius), mic icon, submit arrow in a filled circular button (`--surface-hover`, becomes `--accent` filled only once there's actual text to submit — otherwise it should stay neutral, not blue-by-default).
- No border, ever, on this component — it's currently correct in this respect (`dia1.jpg` and `aether2.jpg` both already omit a border here); just needs the glass material layered on top of the flat fill.

### 9.13 Native controls — sliders, toggles, checkboxes, dropdowns

Wherever Aether needs a slider, toggle, checkbox, radio, or dropdown (Settings screens especially), **use the actual native control**, not a custom-drawn one:

- SwiftUI: `Toggle`, `Slider`, `Picker(.menu)`, native `Stepper` — styled with `.tint(.accentColor)`, nothing custom.
- AppKit fallback: `NSSwitch`, `NSSlider`, `NSPopUpButton`.
- Web fallback (only if truly no native bridge exists for a given control): style as closely as possible to the native macOS control — pill-shaped toggle with a spring-animated knob, thin-track slider with a circular thumb — using the tokens in this document, but flag every one of these as tech debt versus a native binding.

The Settings → Tabs screen's toggle (`aether8.jpg`, "Pinned favorites in sidebar") is already close to the right shape — keep that pattern as the reference for any other toggle in the app.

---

## 10. Light Mode Appendix

Apply every rule above 1:1, substituting the light tokens from §2.2 for the dark tokens from §2.1. Specifically:
- `--surface-base` → `--surface-base-light`
- `--surface-raised` → `--surface-raised-light`
- `--surface-hover` → `--surface-hover-light`
- `--text-primary` / `--text-secondary` → their `-light` counterparts
- Shadows (§5) get lighter and lower-opacity in light mode (roughly halve every alpha value above) since a light background doesn't need as much contrast to read depth.
- Material vibrancy on macOS switches automatically with `NSAppearance` / system appearance — no manual branching needed if using real `NSVisualEffectView`/`.glassEffect()`.

---

## 11. Do / Don't Quick Reference

| Don't | Do |
|---|---|
| Draw a border around a card, tile, pill, or button | Use an elevation step (§2.1) + shadow (§5) |
| Use `stone-700` / `stone-750` anywhere | Use `stone-900` (base) / `stone-850` (raised) / `stone-800` (hover/buttons) only |
| Render a letter in a colored square as a "favicon" | Fetch the site's real favicon; fall back to a Phosphor icon, never a letter |
| Use a thick-stroke icon set | Phosphor `Thin`/`Light`, or SF Symbols (thin by default) |
| Leave the accent blue as a resting-state border | Reserve `--accent` for active focus, selection, and one primary CTA at a time |
| Pop a flat card into the middle of the screen for History/Downloads/Settings | Present as a true sheet: dim + blur the backdrop, spring the sheet in |
| Use font-weight 600+ anywhere in chrome | 400 / 450 / 500 only |
| Fade things in/out linearly | Spring easing (§8), morph glass shapes via `GlassEffectContainer` where applicable |
| Hand-roll a toggle/slider/checkbox in CSS/divs | Use the real native control |

---

## 12. Screenshot → Spec Mapping

| Screenshot | What it shows | Relevant section(s) |
|---|---|---|
| `dia1.jpg` | Sidebar, no border on window edge, plain "Personal" text, real favicon grid, floating orb + search capsule | §9.1, §9.12, §2.4 |
| `dia2.jpg` | Create Profile modal, color swatches | §9.10 |
| `dia3.jpg` | Sidebar with active-row highlight, dashed "add" tile | §9.1 |
| `dia4.jpg` | Top-tab layout, new tab state | §9.2, §9.12 |
| `dia5.jpg` | Command palette panel (Open Tabs / Recently Closed / History / Bookmarks rows) | §9.7 |
| `dia6.jpg` | Command palette + Bookmarks flyout open simultaneously, real favicons throughout | §9.7, §9.8, §7.1 |
| `dia7.jpg` | Profile dropdown menu | §9.5 |
| `dia8.jpg` | Create Profile modal, top-tab layout variant | §9.10 |