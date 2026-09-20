# Aether — Design Issue Tracker

**Companion to:** `DESIGN.md` (the spec every fix below references)
**Audience:** AI coding agents working the redesign. Work top to bottom — issues are ordered by severity, and several later issues are only fixable once an earlier one is fixed (noted under "Depends on").
**Current overall state:** 0/10. This is not polish work — most surfaces need to be rebuilt against `DESIGN.md`, not nudged.

Each issue has: what's wrong, where you can see it, why it's happening, the exact fix, and how to know it's actually fixed. Don't mark an issue closed until its acceptance criteria are visibly true in a screenshot, not just "should be fine."

---

## Index

| # | Title | Severity | Screens affected |
|---|---|---|---|
| [001](#001) | Accent-blue border stuck on as a resting-state style | Critical | Nearly every screen |
| [002](#002) | Letter avatars instead of real fetched favicons | Critical | Sidebar, History, Downloads, command palette |
| [003](#003) | Icon stroke weight too heavy; no fallback icon set | High | Kebab menu, toolbar, sidebar |
| [004](#004) | Background/surface colors off-palette (stone-700/750 in use) | Critical | Global |
| [005](#005) | Buttons carry hard borders | High | Buttons across History, Create Profile, toolbar |
| [006](#006) | Typography weight inconsistent, too heavy in panel titles | Medium | History, Downloads, Settings |
| [007](#007) | No blur/vibrancy material anywhere — everything is flat and opaque | Critical | Sidebar, menus, sheets, popovers |
| [008](#008) | Modals/sheets pop up as flat centered cards, not native sheets | High | History, Downloads, Settings |
| [009](#009) | Sidebar tab list has no visual hierarchy or grouping logic | Medium | Sidebar |
| [010](#010) | Card/tile borders present everywhere instead of elevation | High | Shortcut tiles, menus, cards |
| [011](#011) | No native-feeling toggle/slider/checkbox controls | Medium | Settings |
| [012](#012) | No motion — everything appears/disappears with no transition | Medium | Global |
| [013](#013) | Light mode unspecified / not implemented | Medium | Global |
| [014](#014) | Bookmarks/History/Downloads panels lack Dia's icon+chevron submenu pattern | Medium | Bookmarks, History nav |
| [015](#015) | Command palette (⇧⌘A) pattern doesn't exist yet | Medium | Global (net-new) |

---

<a id="001"></a>
### 001 — Accent-blue border stuck on as a resting-state style
**Severity:** Critical
**Depends on:** nothing — fix first, it touches the most screens

**What's wrong:** A saturated sky-blue rectangular outline renders permanently around specific elements, at rest, with no user interaction happening. It reads as a bug, not a design choice — it's the first thing anyone notices when opening Aether.

**Where it's visible:**
- `aether2.jpg`, `aether3.jpg`, `aether1.jpg`, `aether6.jpg` — the "Personal ⌄" profile switcher pill has a hard blue border box around it in every single screenshot, including ones where nothing is focused or selected.
- `aether6.jpg` — inside the kebab/overflow menu, the top item "Search Tabs" has the same blue rectangular border, while every other row in the same menu correctly has no border.
- `aether4.jpg` — the "Clear History" button has the identical blue border.

**Root cause (most likely):** a CSS `:focus` or `:focus-visible` style (or a SwiftUI `.focusable()`/focus-ring modifier) is being applied unconditionally instead of only while the element actually holds keyboard focus — or a focus ring is being applied via `outline` with no `outline: none` reset on blur, or the "selected/default" first item in a menu list is incorrectly reusing the keyboard-focus style as its default appearance.

**Fix:** Per `DESIGN.md` §2.3 and §2.4 — `--accent` may only render as a 2px ring while an element has *actual* keyboard focus (e.g., a text input being typed into), and must be removed the instant focus moves elsewhere. It is never a resting/default style. Audit every place `--accent` or the blue hex appears in styles and confirm each one is gated behind a real `:focus-visible` (not `:focus`, which also fires on mouse click) or the native equivalent. The profile pill and "Clear History" button should have **no** border in any state except an actual active keyboard focus; on mouse hover they should use `--surface-hover` per `DESIGN.md` §9.11.

**Acceptance criteria:** Open Aether, don't touch the keyboard. Nothing on screen should show a blue outline. Tab-key through the UI — exactly one element (whichever currently holds keyboard focus) may show the accent ring, and it must disappear the moment focus moves to the next element.

---

<a id="002"></a>
### 002 — Letter avatars instead of real fetched favicons
**Severity:** Critical
**Depends on:** nothing

**What's wrong:** Shortcut tiles and history/download rows render a single capital letter on a flat colored square instead of the site's actual logo — "Y" for YouTube, "M" for Gmail, "G" for GitHub, "S" for Slack, "N" for Notion, "C"/"C" for Calendar and ChatGPT. History rows show "Y" for YouTube and "A" for a Gmail/accounts.google.com sign-in URL. This is explicitly called out as the worst offender in the app — every one of these sites has a real, instantly-recognizable, colorful icon, and Dia renders them correctly (`dia3.jpg`, `dia6.jpg`).

**Where it's visible:** `aether1.jpg`, `aether2.jpg`, `aether3.jpg`, `aether6.jpg`, `aether7.jpg` (shortcut grid), `aether4.jpg` (History rows).

**Root cause (most likely):** favicon fetching either isn't implemented at all, or is failing silently and falling back to a generated letter-avatar placeholder that was meant to be a last resort but is currently the only path being used.

**Fix:** Implement the fetch chain in `DESIGN.md` §7.1: (1) the site's own favicon/apple-touch-icon, largest available; (2) a favicon-resolution service as fallback; (3) a Phosphor icon (never a letter) only if both fail. Cache per-domain with a weekly TTL. This should visibly change every shortcut tile and every history/bookmark/download row in the app.

**Acceptance criteria:** The shortcut grid shows YouTube's red play-button mark, Gmail's red/multicolor envelope, GitHub's Octocat mark, Slack's colorful hash mark, Notion's black swirl mark, and real Calendar/ChatGPT icons — zero single-letter tiles anywhere in the app, including History and Downloads rows.

---

<a id="003"></a>
### 003 — Icon stroke weight too heavy; no defined fallback icon set
**Severity:** High
**Depends on:** nothing

**What's wrong:** UI icons (as opposed to brand favicons, see #002) — search, clock/history, bookmark, download, find-in-page, reader, inspect, top-tabs, settings-gear — render at a stroke weight that feels closer to a filled/bold icon set than Apple's characteristically thin system iconography. There's also no defined behavior for what renders when an icon is entirely missing from the current set.

**Where it's visible:** `aether6.jpg` (kebab menu icon column), `aether7.jpg`/`aether2.jpg` (toolbar icons: back, forward, reload, history, downloads, kebab).

**Fix:** Per `DESIGN.md` §7.2–§7.3 — move the whole icon set to Phosphor `Thin` or `Light` weight (or SF Symbols, which are thin by default, as the preferred native fallback). Any icon currently missing gets a Phosphor `Thin` glyph chosen for closest semantic match — never left blank, never a letter, never mixed with a different icon set's visual weight in the same menu.

**Acceptance criteria:** Every icon in toolbar, sidebar, and menus reads visibly thinner side-by-side with the current build. No icon slot renders blank. No menu mixes two visually distinct stroke weights.

---

<a id="004"></a>
### 004 — Background/surface colors off-palette (stone-700/750 in use)
**Severity:** Critical
**Depends on:** nothing — this is a global token-level fix, do it before component-level polish

**What's wrong:** The current build's dark theme is inconsistent and reads as noticeably lighter/washier than intended — described as using an off-brand light stone tone across surfaces where it shouldn't. The target is a strict two-step system: `stone-900` for the base window/sidebar, `stone-850` for anything floating above it, `stone-800` for hover/buttons. Anything at `stone-700` or `stone-750` breaks the near-black look and is explicitly banned.

**Fix:** Per `DESIGN.md` §2.1 — audit every background color in the codebase (CSS variables, SwiftUI `Color` literals, whatever the token source is) and replace any `stone-700`/`stone-750` (or ad hoc hex values that land in that range, roughly `#3a3532`–`#4a4542`) with the correct token from the three-step system. This is a find-and-replace-then-verify pass across the whole app, not a per-component fix.

**Acceptance criteria:** No surface in the app, in any state, samples to a color lighter than `stone-800` (`#292524`) except intentional light-mode surfaces (§2.2) or actual accent/semantic colors (§2.3).

---

<a id="005"></a>
### 005 — Buttons carry hard borders
**Severity:** High
**Depends on:** [001](#001) (the blue border case), [004](#004) (correct fill colors first)

**What's wrong:** Buttons across the app ("Clear History", "Create Profile", "Cancel", kebab trigger) are rendered with a visible 1px stroke outlining the button shape, in addition to their fill. This is part of the broader "you can see the border everywhere" complaint and is the reason buttons feel like web-form elements rather than native Mac controls.

**Where it's visible:** `aether4.jpg` ("Clear History"), `dia2.jpg`/`dia19.jpg` for comparison (Dia's "Create Profile" / "Cancel" buttons have no stroke, just fill + text).

**Fix:** Per `DESIGN.md` §9.11 — remove `border`/`.stroke()` from every button variant. Definition comes entirely from the fill-color step (`stone-800` primary, transparent-to-`stone-800` ghost, `--destructive`-tinted for destructive). No exceptions.

**Acceptance criteria:** Zero buttons in the app have a visible outline distinct from their fill in any state (rest, hover, pressed, disabled).

---

<a id="006"></a>
### 006 — Typography weight inconsistent, too heavy in panel titles
**Severity:** Medium
**Depends on:** nothing

**What's wrong:** Panel titles ("History") render visibly heavier than the 400–500 weight range the rest of the system should stay within — closer to semibold/bold. Browser chrome text should stay quiet; only content the user is reading (page titles rendered from a website, etc.) is exempt.

**Where it's visible:** `aether4.jpg` ("History" heading).

**Fix:** Per `DESIGN.md` §3.2–§3.3 — cap every chrome text weight at 500 (`--type-panel-title` for headings). Sweep panel titles, button labels, and any other heading-like text in Settings/History/Downloads for accidental 600/700 weights.

**Acceptance criteria:** No text anywhere in Aether's own UI (excluding rendered webpage content) computes to a font-weight above 500.

---

<a id="007"></a>
### 007 — No blur/vibrancy material anywhere — everything is flat and opaque
**Severity:** Critical
**Depends on:** nothing, but pair with [004](#004) since the correct base colors need to exist before layering translucency on top of them

**What's wrong:** Every floating surface in Aether — sidebar, toolbar, kebab menu, History/Downloads/Settings panels — is a flat, fully opaque rectangle. None of them are translucent, none of them sample or lens what's behind them. This is the core reason the app reads as a themed web shell instead of a native Mac app; it's also the single largest structural gap versus Dia, whose every floating surface (sidebar, command palette, bookmarks flyout) visibly picks up the desktop wallpaper and page content behind it.

**Where it's visible:** Every Aether screenshot, contrasted with every Dia screenshot.

**Fix:** Implement Apple Liquid Glass materials per `DESIGN.md` §6 — native `.glassEffect()` in SwiftUI if the shell is native, `NSVisualEffectView` materials (Electron `vibrancy` option / Tauri `window-vibrancy` crate) mapped per-surface if the shell is Electron/Tauri, CSS `backdrop-filter` only as a last-resort fallback for portions genuinely stuck in a plain webview. Map each surface to the correct material per §6.2's table (sidebar → `.sidebar`, menus → `.menu`, sheets → `.sheet`, etc.).

**Acceptance criteria:** With something visually busy behind the Aether window (a colorful wallpaper, or another window), the sidebar and any open menu/sheet visibly show a soft, blurred hint of what's behind them — not a flat solid color.

---

<a id="008"></a>
### 008 — Modals/sheets pop up as flat centered cards, not native sheets
**Severity:** High
**Depends on:** [004](#004), [007](#007) (needs correct color + material first), [001](#001), [005](#005) (their internal buttons need the border fix)

**What's wrong:** History, Downloads, and (to a lesser extent) Settings currently open as a card that appears centered over the still-fully-visible, still-fully-sharp sidebar and content area — there's no dimming or blurring of what's behind it, and no sense that this is a distinct, elevated layer of the app. The complaint is specifically that "you can literally see it open up" — the transition and the backdrop treatment both feel wrong, closer to a plain `position: absolute` div than a system dialog/sheet.

**Where it's visible:** `aether4.jpg` (History), `aether5.jpg` (Downloads).

**Fix:** Per `DESIGN.md` §9.9 — present these as true sheets: a scrim (40–50% black) plus a 12–16px blur over the window content behind the sheet, `.sheet` vibrancy material on the sheet itself, `--radius-xl`, `--shadow-lg`, and a spring-based present/dismiss animation (`DESIGN.md` §8.2) instead of an instant appear/disappear.

**Acceptance criteria:** Opening History or Downloads visibly dims and blurs the sidebar/content behind it, the panel animates in rather than snapping into place, and the panel itself uses the sheet material and radius from §6.2/§4, not a plain flat card.

---

<a id="009"></a>
### 009 — Sidebar tab list has no visual hierarchy or grouping logic
**Severity:** Medium
**Depends on:** [002](#002) (favicons), [010](#010) (tile borders)

**What's wrong:** The sidebar tab list currently shows five consecutive rows all labeled "New Tab" with generic icons, giving no way to visually distinguish them at a glance — described as "there is no logic, and it is broken." Compare to Dia's sidebar (`dia3.jpg`), where the active tab gets a distinct highlighted pill and the list otherwise reads cleanly even with generic content.

**Fix:** Per `DESIGN.md` §9.1 — ensure the **active tab** always gets the `--surface-raised` highlight pill distinct from inactive rows (this exists partially already — verify it's consistent), ensure real favicons load per-tab as soon as a page starts loading rather than staying generic indefinitely, and ensure tab titles update from "New Tab" to the actual page title as soon as it's available rather than staying stuck at the placeholder.

**Acceptance criteria:** In a sidebar with multiple tabs open to different real sites, each row is visually distinguishable by icon and title, and exactly one row (the active tab) carries the highlighted background.

---

<a id="010"></a>
### 010 — Card/tile borders present everywhere instead of elevation
**Severity:** High
**Depends on:** [004](#004)

**What's wrong:** Shortcut tiles, menu containers, and cards throughout the app carry a thin, visible stroke around their edges, in addition to (or instead of) a background-color step. This is the general case of issue #001 and #005 — those are the two worst offenders, but the pattern repeats on the shortcut grid tiles and the kebab menu's outer container.

**Where it's visible:** `aether2.jpg` (shortcut tile edges), `aether6.jpg` (kebab menu outer edge).

**Fix:** Per `DESIGN.md` §2.4 and §5 — replace every such border with an elevation step (one shade lighter than the surface behind it) plus a soft shadow. The only permitted exceptions are the dashed "add new shortcut" affordance and a genuine, transient keyboard-focus ring.

**Acceptance criteria:** Visually diffing any tile, menu, or card against its background shows a soft shadow-based separation, not a hard 1px line.

---

<a id="011"></a>
### 011 — No native-feeling toggle/slider/checkbox controls
**Severity:** Medium
**Depends on:** nothing

**What's wrong:** The user wants every form control in Settings (and anywhere else one appears) to be an actual native macOS control — `Toggle`, `Slider`, `Picker` — rather than a custom-drawn div/CSS approximation, so it inherits system behavior, animation, and accessibility for free.

**Where it's visible:** `aether8.jpg` — the "Pinned favorites in sidebar" toggle and the "Sidebar width" slider are already close to correct and should be used as the reference pattern; verify these and any others in the app are backed by real native controls rather than custom CSS, especially as more Settings screens (General, Profiles, Search, Privacy, Passwords, Downloads, Appearance, Shortcuts, Advanced — all visible but unpopulated in the Settings sidebar in `aether8.jpg`) get built out.

**Fix:** Per `DESIGN.md` §9.13 — use `Toggle`/`Slider`/`Picker(.menu)` in SwiftUI, `NSSwitch`/`NSSlider`/`NSPopUpButton` in AppKit, and only fall back to a hand-styled web control (flagged as tech debt) where no native bridge exists.

**Acceptance criteria:** Every control in Settings responds with native macOS animation/timing (a Toggle's knob spring, a Slider's native drag feel) rather than a custom CSS transition.

---

<a id="012"></a>
### 012 — No motion — everything appears/disappears with no transition
**Severity:** Medium
**Depends on:** [007](#007), [008](#008) (motion is layered onto the sheet/menu work)

**What's wrong:** Menus, sheets, and tab open/close currently seem to snap into their final state with no animation, which contributes heavily to the "not Apple native" feeling — Apple's whole interaction language is built on springs, not instant state changes.

**Fix:** Per `DESIGN.md` §8 — apply the spring/duration tokens to every open/close, hover, and press interaction. Respect `prefers-reduced-motion`/system Reduce Motion with a plain cross-fade fallback.

**Acceptance criteria:** Opening the kebab menu, the command palette, a sheet, or closing a tab all show a visible, springy transition rather than an instant cut, and disabling motion (system setting) removes the spring/scale but keeps a basic fade.

---

<a id="013"></a>
### 013 — Light mode unspecified / not implemented
**Severity:** Medium
**Depends on:** [004](#004) (dark tokens need to be locked first, since light mode mirrors the same structure)

**What's wrong:** No screenshots show a light-mode Aether, and the source spec for it was ambiguous (garbled dictation — see `DESIGN.md` §2.2's note). Light mode needs to exist and follow the identical structural rules as dark mode, just with the light token set.

**Fix:** Implement `DESIGN.md` §2.2/§10 — background white (or `stone-50`, confirm which with the human — flagged explicitly in `DESIGN.md`), buttons/cards at `stone-100`, hover at `stone-200`. Every component in §9 gets built once, parameterized by the token set, not duplicated.

**Acceptance criteria:** Toggling system appearance to Light produces a fully themed Aether with no leftover dark-mode surfaces, and every component from §9 renders correctly in both modes from the same underlying implementation.

---

<a id="014"></a>
### 014 — Bookmarks/History/Downloads panels lack Dia's icon+chevron submenu pattern
**Severity:** Medium
**Depends on:** [002](#002), [007](#007)

**What's wrong:** Dia's bookmarks flyout (`dia6.jpg`) uses a specific, reusable pattern — icon/favicon + label rows, dividers between logical groups, and folder rows with a trailing chevron indicating a submenu — that Aether's equivalent surfaces don't yet follow consistently.

**Fix:** Per `DESIGN.md` §9.8 — rebuild the bookmarks flyout to match this pattern exactly, and reuse the same row/divider/chevron pattern anywhere else a similar nested list appears (e.g., a future "Bookmarks Bar" or "Other Bookmarks" expansion).

**Acceptance criteria:** The bookmarks flyout visually matches `dia6.jpg`'s structure: two system-action rows, a divider, real-favicon bookmark rows, a divider, two folder rows with trailing chevrons.

---

<a id="015"></a>
### 015 — Command palette (⇧⌘A) pattern doesn't exist yet
**Severity:** Medium (net-new feature, not a regression, but explicitly requested as part of matching Dia's structure)
**Depends on:** [002](#002), [003](#003), [007](#007)

**What's wrong:** Aether has no equivalent yet of Dia's right-docked search/command panel (`dia5.jpg`, `dia6.jpg`) showing Open Tabs, Recently Closed, History, and Bookmarks in one searchable surface.

**Fix:** Build per `DESIGN.md` §9.7, structured exactly like Dia's: right-docked, full height, glass material, search field pinned at top with the shortcut hint right-aligned, section headers, rows with real favicons and optional trailing chevrons for rows that expand into a submenu (History, Bookmarks).

**Acceptance criteria:** `⇧⌘A` (or the app's chosen binding) opens a right-docked panel matching the structure above; typing filters all listed rows.

---

## Working order for agents

1. **001, 004** — global token/behavior fixes, touch every screen, do first.
2. **002, 003** — icon/favicon system, second-highest visual impact.
3. **005, 010** — remove remaining borders now that colors are correct.
4. **007** — materials layer, now that the surfaces it sits on are correct.
5. **008, 009, 011, 012, 014, 015** — component-level rebuilds, now that tokens/materials/icons are all correct underneath them.
6. **006, 013** — typography and light-mode sweep, last, since they're cross-cutting verification passes rather than structural changes.
