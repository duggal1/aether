# Aether — Complete Design Correction & Native Glass Rebuild

**Status:** plan complete · ready for execution approval
**Scope:** `Sources/BrowserUI/Sources/AetherHumanUI/` (+ `Sources/icons/` for new custom icons)
**Constraint:** preserve motion curves (`AetherMotion`), make them feel faster/smoother; significantly darken surfaces; no redesign of structure; no navigation/WebView/persistence/credential/search-routing behavior changes.

---

## 0. Ground truth (verified file:line — no guesses)

| Fact | Evidence |
|---|---|
| Sidebar glass = SwiftUI `.glassEffect(.regular)` + veil `#18191D@0.46` + white top gradient — NOT real blur stack | `Design/AetherMaterial.swift:119-145` |
| Dead native material exists: `AetherNativeSidebarMaterial` (`NSVisualEffectView`, `.sidebar`, `.withinWindow`, `.active`) — **zero call sites** | `AetherMaterial.swift:95-111` |
| Window forced non-opaque + clear bg (wallpaper bleeds through) | `Chrome/BrowserWindowRoot.swift:35-41` |
| Sidebar is conditionally inserted/removed (`.move+.opacity`), width never animates | `Chrome/BrowserWindowView.swift:57-59`, `SidebarTabListView.swift:97-98` |
| Bottom safe area NOT ignored → height gutter suspect | `BrowserWindowRoot.swift:16` (top only) |
| Root bg `Color.clear` when sidebar open → gutters show wallpaper | `BrowserWindowView.swift:96` |
| Toolbar = flat `theme.chrome`, no glass | `AetherMaterial.swift:131`, `TopTabStripView.swift:63` |
| Address bar adaptive ONLY in light mode; dark always `theme.omnibox` | `OmniboxView.swift:26-42` |
| Address text color never set (AppKit default) | `Native/NativeAddressField.swift` |
| Page DOM bg sampled via JS into `tab.siteSurface` | `BrowserWindowView.swift:24-52` |
| Top-strip "New Tab" button renders `AetherLogo`, not plus | `TopTabStripView.swift:37-49` |
| Sidebar "New Tab" row renders `AetherLogo` + text (this IS the favicon row, correct per spec) | `SidebarTabListView.swift:34-49` |
| Plus icon exists as `BrowserIcon.plus` / `AetherSymbol.add` | `BrowserIcons.swift:14`, `AetherSymbols.swift:22` |
| Profile control: 5×3pt static dots, all `theme.soft`; label+chevron in VStack; hover fill flat | `ProfileSwitcherView.swift:14-38` |
| Profile header leading pad 76 (sidebar), cluster fixed 322 wide (top) | `SidebarTabListView.swift:18`, `TopTabStripView.swift:26` |
| Popover/dropdown = glass + `card@0.55` + hairline stroke (brightens menus) | `AetherMaterial.swift:148-161` |
| Hairline = white@0.07 stroke — user wants **transparent borders** | `AetherPalette.swift:66-68` |
| Palette hover 0x292929 / selected 0x2D2D2D / input should darken per new tokens | `AetherPalette.swift:4-29` |
| Settings row: icon frame 21×20 centered vs title+subtitle stack (misaligned when subtitle present) | `Components/AetherRow.swift:21-45` |
| Settings scroll: plain `ScrollView` + eager `VStack`, fixed 800×550 + clipShape | `Settings/SettingsWindowView.swift:24-39` |
| Advanced "Connected" = colored Text, not badge | `Settings/AdvancedSettingsView.swift:9-13` |
| Shortcuts badge: r6 rect, minW44 minH24, pad h8 | `Settings/ShortcutsSettingsView.swift:18-21` |
| SearchLocation: no flag; Country = bare 80pt TextField; long footers (18–27w) | `Settings/SearchLocationSettingsView.swift` |
| Passwords footer = 46 words | `Settings/PasswordsSettingsView.swift:12` |
| Network fields: repeated inline TextField styles, widths 210/80/120 | `Settings/NetworkSettingsView.swift:71-112` |
| History "Today" already correct case | `Panels/HistoryView.swift:27` |
| History/Bookmarks scroll: LazyVStack + mask gradient (OK), row hover flat fill | `HistoryView.swift:63-97`, `BookmarksView.swift:73-98` |
| Folder label already `#2563EB`, icon already neutral | `BookmarksView.swift:123-129` |
| Import/Export already equal 92×30 | `BookmarksView.swift:43,51` |
| NewProfile sheet: has `AetherField` input already | `ProfileSwitcherView.swift:86` |
| Home search: `card@0.5` + glass r13 | `NewTabView.swift:77-78` |
| Suggestion popup: inline glass clone + `card@0.55` | `OmniboxSuggestionsView.swift:33-45` |
| Custom icons live in `Sources/icons/AetherCustomIcons.swift` (svgPaths switch) | enum cases 3-28, svgPaths 72-131 |
| SVG path parser exists: `AetherSVGPathParser` | `Sources/icons/AetherBrandMarks.swift:106+` |
| Settings sidebar icon switch: `SettingsSidebarView.sectionIcon` | `SettingsSidebarView.swift:52-64` |
| No US flag asset anywhere | verified |
| No logo.svg file — logo is `AetherLogo` Swift view | `Sources/icons/favicon.swift:6-34` |

---

## 1. Palette correction (root token change)

**File:** `Design/AetherPalette.swift`

Apply the directive's darker token set. Keep light-mode counterparts sensible.

```swift
// AetherNeutral (dark)
background  = 0x171717   // unchanged
chrome      = 0x1B1B1B   // unchanged
card        = 0x202020   // unchanged
hover       = 0x252525   // was 0x292929 → darken
selected    = 0x292929   // was 0x2D2D2D → darken
input       = 0x262626   // new (replaces ad-hoc dialogField/inset for inputs)
focus       = 0x303030   // new (replaces focusRing 0x4A4E57 for focus fills)
text        = 0xF5F5F5
textStrong  = 0xFAFAFA
muted       = 0xA3A3A3
tertiary    = 0x737373   // new
// hairline/border: alpha → 0 (transparent) per prior plateau + this directive "no visible decorative borders"
```

Token routing changes in `AetherPalette` / `AetherTheme`:

| Old | New source |
|---|---|
| `hover`, `tabHover`, `chromeHover` | `hover = 0x252525` |
| `selected`, `suggestionSelected`, `settingsRaised`, `raised`, `inputFocus`, `focus`, `profileTop/Bottom` | `selected = 0x292929` |
| `inset`, `dialogField`, field fills | `input = 0x262626` |
| `focusRing` (stroke on focused inputs) | keep `0x303030` for dark (was 0x4A4E57) — still a fill-grade ring, but neutral and darker |
| `hairline`, `faintLine` | alpha 0 (transparent) |
| `dialogCard` 0x23252A | → `card = 0x202020` for consistency with "significantly darker" directive (blue-cast removed) |

Also darken popover fill: `AetherPopoverBackground` uses `theme.card.opacity(0.55)` over glass — raise to `opacity(0.88)` so composited result ≈ `#202020` not neutral-600.

**Do not touch:** `AetherProgressColor` accents, badge variants, profile swatches, `folderBlue`, error/active semantic colors.

---

## 2. Glass material system rebuild

**File:** `Design/AetherMaterial.swift` (primary), call sites listed below.

### 2.1 Activate the real native sidebar material

- Make `AetherNativeSidebarMaterial` internal/public (currently `private`) OR rewrite `AetherChromeBackground(.sidebar)` to host it directly.
- Stack becomes:
  1. `NSVisualEffectView` — `material = .sidebar` (dark) / `.underWindowBackground` fallback for light, `blendingMode = .withinWindow`, `state = .active` (follows window key state).
  2. Neutral dark tint overlay: `Color(#171717).opacity(0.52)` in dark (stronger than current 0.46 veil so wallpaper chroma dies; keeps subtle depth).
  3. Soft top highlight: keep existing 5%/12% gradient but reduce to 0.04 / 10%.
  4. Optional 1px inner top highlight `white@0.06` — no outer border.
- **Why withinWindow:** window is non-opaque (`BrowserWindowRoot`), so behindWindow blending samples wallpaper → green/yellow bleed + fullscreen chroma shift. withinWindow blurs only in-window content; combined with opaque content pane + opaque root fill, wallpaper no longer participates.

### 2.2 Kill wallpaper participation at the root

**File:** `Chrome/BrowserWindowView.swift:96`, `Chrome/BrowserWindowRoot.swift`

- Stop using `Color.clear` as root background when sidebar open. Use `theme.chrome` always (sidebar material sits on top of it).
- Keep window transparency probe only if still needed for titlebar; if sidebar withinWindow is self-sufficient over opaque chrome, consider making window opaque again (`isOpaque = true`) — **verify empirically**; if titlebar transparency breaks, keep probe but paint opaque `theme.chrome` behind entire hierarchy.
- Add `.ignoresSafeArea(.container, edges: [.top, .bottom])` at root (currently `.top` only) so sidebar and content share identical vertical bounds.

### 2.3 Shared material, not per-component glass

- `AetherChromeBackground(.sidebar)` → native stack above (single source).
- `AetherChromeBackground(.toolbar)` → stays flat `theme.chrome` (correct — toolbar is opaque chrome).
- `AetherPopoverBackground` → opaque-first dark dropdown per §10 below.
- `AetherModalBackdrop` → native blur (NSVisualEffectView or glassEffect on full-rect) + neutral `#171717@0.55` tint; no green.
- Delete dead paths: `AetherDitherOverlay` unused — leave (out of scope) unless it confuses; do not add new overlays.

### 2.4 Fullscreen stability

- withinWindow material + opaque root = fullscreen no longer samples desktop.
- No fullscreen-specific padding hacks. Geometry fix (§3) handles bounds.
- Material `state = .active` persists across activation; do not flip materials on fullscreen enter.

---

## 3. Sidebar geometry + motion (root layout)

**Files:** `BrowserWindowView.swift`, `SidebarTabListView.swift`, `SidebarResizeHandle.swift`, `BrowserWindowRoot.swift`

### 3.1 Shared vertical bounds

- Root: ignore top+bottom safe area (§2.2).
- Sidebar already `.frame(maxHeight: .infinity)` — keep; ensure parent HStack stretches both columns equally (already `.frame(maxWidth:.infinity, maxHeight:.infinity)` on right column :81 — add same explicit max on HStack or use `HStack { ... }.frame(maxHeight:.infinity)`).
- Content pane bottom/top insets: keep the intentional 6pt chrome inset around rounded content card (that's design, not a bug) **but** eliminate the *clear* root showing through: with opaque root (§2.2), gutters become `theme.chrome`, not dead glass.

### 3.2 Same-transaction layout animation

Current: conditional insert + `.move(edge:.leading)+.opacity` + implicit `.animation(value: sidebarCollapsed)`.

Change to **width-driven layout, not insert/remove**:

```swift
// SidebarTabListView
.frame(width: sidebarCollapsed ? 0 : currentWidth)
.frame(maxHeight: .infinity)
.clipped() // or overflow hidden
.opacity(sidebarCollapsed ? 0 : 1)
```

- Keep view always in hierarchy when `arrangement == .sidebar` (no `.transition` removal) so width tweens and main pane resizes in the **same** transaction via the existing `withAnimation(AetherMotion.sidebar)` at `NavigationBarView.swift:19-21` and implicit animations `BrowserWindowView.swift:100-101`.
- Content column width follows automatically (HStack layout).
- **Do not** recreate `PersistentPageSurface` / WKWebView: sidebar visibility must not change `BrowserContentView`'s `.id(tab.id)` — only frame widths. Verify no `.id` depends on sidebarCollapsed.
- Resize handle drag: wrap transient width writes so commit animates — on `.onEnded`, `withAnimation(AetherMotion.sidebar)` when collapsing transient → committed (drag itself stays unanimated for 1:1 tracking).

### 3.3 Motion polish (keep curves, reduce work)

- `AetherMotion.sidebar` stays `.smooth(duration: 0.26)` — directive says keep motion, make it smoother/faster. Tighten to `.smooth(duration: 0.24)` only if needed after visual check; primary win is animating width not opacity-only.
- Material host stays **static** (never animate blur radius). Animate only overlay opacity + content.
- Tab list content fades with sidebar opacity (already combined).

### 3.4 No blank placeholder rows

- Sidebar renders only real tabs (`ForEach(window.tabs)`) — already true. Remove dashed `addShortcutTile` visual weight? Spec §6: "Do not reserve visible tab backgrounds for nonexistent content" — the dashed add-shortcut tile is a shortcut control, not a fake tab; keep but restyle neutrally (no white@0.12 dash → `theme.muted@0.25` dash).
- Empty space below tabs: uninterrupted glass (already Spacer).

---

## 4. Personal profile control rebuild

**File:** `Chrome/ProfileSwitcherView.swift`, parents `SidebarTabListView.swift:14-19`, `TopTabStripView.swift:15-29`

### 4.1 Alignment

- Label + chevron remain one inline `HStack` (already are).
- Dots: change from 5×3pt `theme.soft` all-equal → **spec dots**: 5pt circles, active `#FAFAFA`, inactive `#A3A3A3`. Represent "active" as first profile index (or profile index derived from `window.activeProfileID` among `workspace.profiles.prefix(5)`).
- Center dots group under the control (VStack `.alignment(.center)` already; ensure dots HStack centers — use `.frame(maxWidth:.infinity)` only inside the button label, button itself not stretched by parent Spacer).
- Sidebar header: reduce `.padding(.leading, 76)` → keep 76 for traffic lights (required clearance) but reduce header height 48 → 40 and stop letting Spacer push layout; control hugs leading edge after clearance.
- Top strip: profile cluster fixed width 322 is huge — reduce `AetherMetrics.profileClusterWidth` 322 → ~200 so tabs start further left (directive §5 horizontal tab layout). Keep traffic-light leading 78 on strip.

### 4.2 Surface

- Background: dark neutral glass — replace flat hover fill with `AetherGlassSurface(radius: 8, interactive: true)`-equivalent: clear + `glassEffect(.regular.interactive(), in: r8)` + veil `#171717@0.35` on hover only (restrained hover, no border/shadow).
- Padding: horizontal 12 → 10; height 27 → 26 (slightly reduced vertical).

### 4.3 Incognito indicator (replaces wrong plus)

- Spec §4.2: "Replace incorrect plus affordance with private/incognito indicator."
- Current neighbor is `IncognitoToggleView` using custom `.incognito` icon already (`BrowserIcon.incognito` → `AetherCustomIcon.incognito`). If a "plus" appears near Personal in some state, it's the profile popover "New Profile…" row or `addProfile` symbol — audit: popover menu `ProfileSwitcherView.swift:72` uses `.plus` for "New Profile…" which is correct as a menu action, not a status icon.
- Ensure the **leading indicator beside the profile control** (if present in top cluster) is `BrowserIcon.incognito` at size ~13 matching lock icon scale (omnibox lock is iconSize 12, frame 16×20).

---

## 5. Tab creation architecture (logo vs plus)

**Files:** `TopTabStripView.swift`, `SidebarTabListView.swift`, `TabItemView.swift`, `Components/DomainIcon.swift`

### 5.1 Split the two concepts

| Element | Role | Visual |
|---|---|---|
| New Tab **page** favicon | favicon of a tab whose url is nil/about:blank | `AetherLogo` via `DomainIcon(nil)` — **already correct** (`DomainIcon.swift:29-32`) |
| Sidebar "New Tab" row | create new tab affordance w/ label | Keep logo + "New Tab" text (`SidebarTabListView:34-49`) — spec says logo is new-tab favicon in sidebar rows; this row is the create action **with** logo as favicon-like leading mark. |
| Top strip trailing button | **create another tab** | **Currently logo — WRONG.** Replace with `BrowserIconView(icon: .plus)` in same 29×40 hit target. |

Edit `TopTabStripView.swift:37-49`:

```swift
Button { _ = window.newTab() } label: {
    BrowserIconView(icon: .plus, tint: theme.muted)
        .iconSize(14)
        .frame(width: 29, height: AetherMetrics.tabHeight)
        .contentShape(Rectangle())
}
```

- Hover: `theme.hover` fill r6 (glass hover per §3.5 of older spec → use `glassEffect(.regular.interactive())` light touch).
- Never show logo as the plus button.

### 5.2 Horizontal tab strip leading position

- `AetherMetrics.profileClusterWidth`: 322 → 200 (fits profile + incognito + fewer/no pinned pills overflow; pinned pills remain but cluster shrinks).
- Strip `.padding(.leading, 78)` stays (traffic lights).
- Prevent overlap: profile cluster trailing pad 5 stays; ScrollView starts immediately after.
- Tab width: keep 174 fixed (structure preservation) unless padding change requires; reduce tab horizontal padding 10 → 8 (`TabItemView.swift:89` when topFused).

### 5.3 Active tab polish

- Fill: `activeSurface` (site-aware) — keep.
- Add subtle shadow not heavy dark rect: `.shadow(color: .black.opacity(theme.dark ? 0.18 : 0.08), radius: 1, y: 1)` on `fusedActive` only.
- Close icon: iconSize 11 → 10; tint already `closeTint` (#1A1B1F light / text@0.78 dark) — keep.
- Favicon size: keep 16 top / 15 sidebar (already matches prior spec).
- Hover inactive: currently flat `tabHover` fill on UnevenRoundedRectangle — change to clear + `glassEffect(.regular, in:)` for glass hover, no chunky ring.

### 5.4 Sidebar tab rows

- Selected: `theme.tabActive.opacity(0.6)` + glass + glassID — with darker palette, `tabActive` is background #171717; opacity 0.6 over sidebar glass may vanish. Change selected fill to `theme.selected.opacity(0.85)` (flat restrained contrast) and **drop glassEffect on the row** (glass-on-glass in sidebar is muddy). Keep `aetherGlassID` only if still wanted for matched transition — prefer removing glassID to cut GPU work (lag).
- Hover: clear + no glass; use `theme.hover` @ 0.7 or flat `theme.hover` (darker token).
- Truncation, DomainIcon, close alignment: keep.

---

## 6. Adaptive toolbar + address bar (one resolver)

**New file:** `Design/AetherChromeAppearance.swift`
**Edit:** `OmniboxView.swift`, `NavigationBarView.swift`, `TopTabStripView.swift`, `ChromeButton.swift`, `NativeAddressField.swift`, `OmniboxSuggestionsView.swift`, `TabItemView.swift` (tab text/close when top-fused over adaptive strip)

### 6.1 Resolver

```swift
enum AetherChromeAppearance: Sendable {
    case light, dark
    var toolbarBG: Color   // light: #FAFAFA  dark: #171717
    var addressBG: Color   // light: #F5F5F5  dark: #202020
    var text: Color        // light: #171717  dark: #FAFAFA
    var icon: Color        // light: #262626  dark: #D4D4D4
}

struct AetherChromeAppearanceResolver {
    static func resolve(siteSurface: UInt?, systemDark: Bool) -> AetherChromeAppearance {
        guard let hex = siteSurface else { return systemDark ? .dark : .light }
        // normalize → luminance (0-255 scale like existing OmniboxView weights)
        // saturate chroma: if max-min channel > 40, desaturate toward gray before threshold
        // luminance > 190 → .light ; else .dark
        // (near-white toolbar per spec; mid stays dark family with slightly raised contrast)
    }
}
```

- Compute **once** from `window.selected?.siteSurface` + `theme.dark`.
- Dark mode system + dark page → `.dark`; light system + white page → `.light`; light system + dark page → `.dark` (page wins for chrome); no site sample → system.

### 6.2 Consumers (single source)

| Consumer | Change |
|---|---|
| `AetherChromeBackground(.toolbar)` | fill `appearance.toolbarBG` instead of always `theme.chrome` — needs appearance passed in or Environment |
| `OmniboxView.omniboxFill` | replace entire light-only hack with `appearance.addressBG` |
| `NativeAddressField` | set `field.textColor` / attributed placeholder from `appearance.text` in `updateNSView` |
| Omnibox icons (lock/search/warning), AI Mode, clear, bookmark | tint `appearance.icon` |
| `NavigationBarView` ChromeButtons | pass tint or read appearance from environment |
| Top tab strip bg | `appearance.toolbarBG` |
| Selected top-tab title/close | use `AetherPalette.siteInk(siteSurface)` already; if no surface, `appearance.text` |
| Suggestion popup | fill derived from focused appearance: light → `#FFFFFF@0.92` + blur; dark → `card@0.88` + blur |

Implementation: put `@Environment` or pass `appearance` via `BrowserWindowView` → child. Simplest: compute in `BrowserWindowView`, inject with `.environment(\.aetherChromeAppearance, appearance)`.

### 6.3 Focus behavior

- Focused omnibox on light appearance: address field `#FFFFFF` or `#F5F5F5`, text `#171717`, icons `#262626`, suggestion surface light with glassEffect blur.
- Focused on dark: keep dark stack.
- Replace white glow overlay (`searchGlow` white@0.04/0.07) with appearance-aware: light → `black@0.04`; dark → `white@0.04`.
- Stroke on focus: currently hairline (now transparent) → use `appearance`-appropriate `focus` token `#303030` / `#C4C4C4` 1pt — **or** per directive "no visible border" use a 1px outer focus ring only while keyboard-focused via `focusRing` — keep subtle `appearance.icon@0.35` stroke.

### 6.4 Lock icon optical nudge

- `OmniboxView.swift:50` `.offset(y: -1)` already present. Keep; verify equal L/R breathing: leading pad 12, icon frame 16 — OK.

---

## 7. Home search field darkening

**File:** `Pages/NewTabView.swift:77-78`

- Replace `theme.card.opacity(0.5) + glassEffect` with: solid `AetherPalette.card` (#202020) **or** `card@0.92` + **subtle** glass only if it doesn't lift luminance — prefer flat `theme.card` fill + `glassEffect(.clear)` or no glass, radius 13 kept, no glow/shadow/outline.
- Hierarchy: brand → field → shortcuts (unchanged).
- Arrow button circle: `theme.control` (=card) → use `theme.selected` (#292929) when enabled for slight lift.

---

## 8. Dropdowns — remove forced glass, go darker

**File:** `Design/AetherMaterial.swift` `AetherPopoverBackground` + `AetherDropdown.swift`

New popover stack:

```swift
ZStack {
    RoundedRectangle(r: menuRadius).fill(theme.card)        // opaque #202020
    // optional: very light glass only if over rich content — default OFF for settings/sheets
    RoundedRectangle(r: menuRadius).fill(Color.black.opacity(0.25)) // depth without blur wash
}
// NO hairline stroke (transparent border token)
```

- For popovers genuinely floating over page content (omnibox suggestions, command palette): keep **one** layer of `glassEffect(.regular)` **under** opaque `card@0.9` so composited result stays dark, not neutral-600.
- `AetherDropdown` trigger fill `settingsRaised` → now #292929 (darker automatically via token).
- Row hover `theme.hover` → #252525; selected `theme.selection` → #292929.
- Menu rows (`AetherMenuRow`) same tokens.
- Avoid nested glass: command palette sits on modal backdrop (already glass) — popover content itself opaque.

---

## 9. Settings rebuild (compact information interface)

### 9.1 Row component — `Components/AetherRow.swift`

Restructure to icon-aligned-to-title-line:

```swift
HStack(alignment: .firstTextBaseline, spacing: 13) {
    // fixed leading icon column 21×20, vertically aligned to TITLE line only:
    icon.frame(width: 21).alignment(.top) // or align to title baseline via overlay
    VStack(alignment: .leading, spacing: 3) {
        Text(title) // emphasis 14
        if let subtitle { Text(subtitle).font(body 12).muted } // optional, ≤9 words
    }
    Spacer(minLength: 12)
    accessory // vertically centered against primary row content
}
.padding(.horizontal, 15)
.padding(.vertical, 11) // was 13 — slightly tighter
```

Better concrete approach: `HStack(alignment: .top)` with icon `.padding(.top, 1)` so icon centers on title line (title ~17pt line height), subtitle hangs below without pulling icon down. Trailing accessory: wrap in `.frame(maxHeight: .infinity, alignment: .center)` **or** structure as:

```
HStack {
  icon (top-aligned to title)
  title+subtitle
  Spacer
  accessory (aligned to title row only — use VStack { accessory; Color.clear(height: subtitleHeight) } 
}
```

Simplest correct: put accessory inside a header HStack with title, subtitle below spanning:

```
VStack(alignment: .leading, spacing: 4) {
  HStack(alignment: .center, spacing: 13) {
    iconColumn
    Text(title)
    Spacer(minLength: 10)
    accessory
  }
  if subtitle { Text(subtitle).padding(.leading, 21+13) }
}
```

This guarantees icon/title/accessory share one alignment line; subtitle indents under title. **Adopt this.**

- `SettingsDivider`: add trailing inset to match — `.padding(.horizontal, 15)` or leading 15 / trailing 15.

### 9.2 Scroll architecture — `SettingsWindowView.swift`

- Keep nav fixed (left).
- Content: `ScrollView` already independent; ensure title header is **outside** scroll (it is) and content bottom padding 30 remains accessible.
- Section switch already `.id(selection)` + transition — keep; scroll position resets naturally on id change.
- Reduce `VStack(spacing: 23)` → 20 for denser editorial feel.
- Remove hairline stroke overlay on dialog (`:40-44`) per no-border rule; keep clipShape r13.
- LazyVStack for content if any section gets long (Network/Passwords) — use `LazyVStack` inside ScrollView for section list only if measured lag; prefer keep VStack (settings rows are cheap) but **History/Bookmarks already LazyVStack**.
- Scrolling must not rebuild material: settings dialog is flat `theme.background` (no glass) — already cheap.

### 9.3 Section-by-section

**General** (`GeneralSettingsView`): drop "Continue where you left off." subtitle (self-explanatory). Rows get no icons (none today) — acceptable per "icons only when useful"; or add SF `arrow.counterclockwise` / `person` for consistency — **prefer adding icons to all settings rows** for the fixed icon column system: General → `power` / `person.crop.circle`.

**Tabs** (`TabsSettingsView`): sidebar width row subtitle 5 words OK; trim to "Preferred sidebar width." Layout cards keep.

**Search** (`SearchSettingsView`): trim subtitles:
- full address: drop or "Show the complete URL."
- suggestions: "Tabs, bookmarks, and history under the address bar."
- provider suggestions: "Completions over a private connection."
Provider row: tighter — use AetherRow with `symbol: magnifyingglass`, dropdown minHeight 30 (from 34), same trailing column.

**Search Location** (`SearchLocationSettingsView`):

| Row | Subtitle | Trailing |
|---|---|---|
| City | Preferred city for local search results. | field w=180 |
| Region / State | State used for regional search targeting. | field w=90 |
| Country | Country used for localized search results. | **flag + field** |
| Primary postal code | Postal code used for nearby searches. | field w=110 |
| Nearby areas | Additional areas included in local searches. | count text |

- Footers: collapse to ONE sentence total across sections: "These settings shape result locality only — they never change your network route." (replace 18w + 27w + 17w footers).
- Query behavior toggle subtitle: drop long interpolation → "Append city and region to searches."
- Route independence subtitle: "Search locality never changes your exit region."
- **US flag:** add custom icon `AetherCustomIcon.usFlag` — implement as filled multi-path icon from provided SVG (22×16 viewBox; treat as `space: 22` filled, not stroked). Show when `countryCode.uppercased() == "US"` leading the country field or as field accessory. Non-US: no flag.
- Reset button: keep trailing.

**Passwords** (`PasswordsSettingsView`):
- Footer 46w → move essential security text to a DisclosureGroup "About passkey security" with 2–3 sentences; default collapsed; row subtitle per-state only (already short variants).
- Apple Passwords row: with new row layout, icon aligns to title.
- Device ready / auth / autofill / saved / WebAuthn: subtitles cut to ≤6 words:
  - ready: "Passkeys configured on this Mac."
  - auth: "Confirm identity with Touch ID or passcode."
  - autofill: drop subtitle, trailing "Engine integration required"
  - saved: drop subtitle, trailing "Not connected"
  - WebAuthn: "Handled by Apple's system flow." trailing "System flow"
- Trailing statuses right-aligned (row system does this).
- No section borders (dividers transparent anyway after hairline=0 — keep dividers as value separators with faintLine still 0? Spec says no borders around cards; **intra-row dividers OK** but should be subtle: restore divider to white@0.06 **only inside cards**, while card outer stroke = none. Distinguish `hairline` (outer, transparent) vs `SettingsDivider` fill (keep 0.06 white / 0.06 black light).

Decision: `AetherNeutral.hairline` alpha → 0 for strokes; `SettingsDivider` uses its own `Color.white.opacity(0.06)` literal (dark) — update `SettingsControls.swift:25`.

**Downloads**: drop subtitle "Preferred download folder label." keep trailing status.

**Advanced** (`AdvancedSettingsView`):
- Icons → custom assets:
  - Engine connection → new custom `.engine` (user ENGINE SVG paths)
  - Browser engine → SF `square.stack.3d.up` (keep) or `.cpu` 
  - Page inspection → SF `chevron.left.forwardslash.chevron.right` keep
- Descriptions cut:
  - connection: drop "Same runtime..." 
  - engine: drop stale "No WebKit..." → remove subtitle entirely (honesty: don't replace with new claim in this visual pass)
  - inspection: drop subtitle
- Connected → compact badge: use `AetherBadge("Connected", variant: .green)` — already correct green shades; radius 3 → match spec r5, padding 3×9, font 12 medium — adjust AetherBadge radius to 5 and font weight medium. Not connected → muted text badge style or plain muted text.
- "Adapter required" / "Aether" mono values keep as trailing muted.

**Network Privacy** (`NetworkSettingsView`):
- Extract shared `settingsField(_ label, text:, width:)` helper → same style as localityField but fill `theme.input` (#262626), h=28, r=6, no border.
- Align all trailing fields to same right edge / consistent widths: Host 200, Port 72, User 140, Pass 140 — right-aligned HStack.
- Credentials: keep SecureField behavior + Keychain path untouched.
- Status: switch ad-hoc capsule → `AetherBadge` or keep capsule but r5 not full Capsule for consistency with shortcut badges? Spec §14 badge style for Connected; Network status can stay dot+label in rounded-rect r5 `theme.input` fill.
- Save/Verify/Remove buttons: equal height 28, horizontal pad 12, same baseline — use `.frame(minHeight: 28)` on all three glass buttons; already in one HStack.
- Footers: trim to ≤12 words each.
- Icons: Host → custom `.server` (provided SVG); Fail closed keeps `.lockPrivacy`; add server-offline/crash icons only if status states need them (status detail can swap icon: connected `.server`, offline `.serverOffline`, crash `.serverCrash` — implement three custom icons, use in Status row leading or badge).

**Shortcuts** (`ShortcutsSettingsView`):
- Badge: force same right edge — row accessory already trailing; set fixed `frame(width: 52, height: 24)` , r5 (match badge radius), pad h8, mono 11, fill `theme.input` (#262626), text muted. All rows identical.

**Privacy / Appearance / Profiles**: apply row system + subtitle cuts; Profiles delete message can shrink; Appearance cards keep (structure).

### 9.4 Settings sidebar icons — custom SVG set

**File:** `Settings/SettingsSidebarView.swift` `sectionIcon` + `nativeIcon`, `Sources/icons/AetherCustomIcons.swift`

Add custom icon cases (stroked, space 24, stroke 1.5, round caps/joins as in SVGs):

| Section / row | Icon |
|---|---|
| Advanced (Engine connection) | `.engine` (ENGINE svg) |
| Search Location / City | `.gps` (GPS svg) |
| Search Location / Postal | `.zipCode` (pick first zip svg) |
| Search Location / Nearby | `.nearby` (second "OR" svg) |
| Network / Host | `.server` |
| Network status offline | `.serverOffline` |
| Network status crash | `.serverCrash` |
| Downloads (optional) | `.cloudDownload` (cloud-download svg) |
| Settings gear (if used) | existing `.gear` already matches provided setting icon |
| Tabs section | `.tabsGrid` (TABS svg) |
| Filter/tune fallback | `.filter` (last svg) — only if a row needs it |

Zap svg: use for **loading/power** only if an existing row needs it — likely skip (no obvious row); do not invent rows.

Wiring: `SettingsSection.icon` stays for SF fallback; `sectionIcon(for:)` switches to `AetherCustomIconView` for advanced, searchLocation (gps on section? section-level: searchLocation → keep SF `location` or use gps — use `.gps` for section icon), networkPrivacy → `.server`, tabs → `.tabsGrid`, downloads → SF or `.download` existing.

Apple native symbols remain default for: General, Profiles, Search, Privacy, Passwords, Appearance, Shortcuts (keyboard), and any row without a supplied SVG.

Bookmark icon: existing custom `.bookmark` already matches provided bookmark SVG. Filter svg → optional Advanced or Settings header — use only if replacing a wrong icon.

### 9.5 US flag icon

Add `AetherCustomIcon.usFlag` — filled paths from provided SVG (rect white, blue canton, red stripes, white stars as single paths). `space = 22`, `stroked = false`. Render at 18×13 next to country value.

---

## 10. Dialogs / panels (History, Bookmarks, New Profile)

### History
- "Today" already correct.
- Scroll: keep LazyVStack; ensure row backgrounds don't recompute — hover uses flat `theme.hover` (cheap). Remove bottom mask gradient when not needed? Keep (visual fade). No per-row blur — already none.
- Blank entries: `DomainIcon(nil)` → brand mark — already.
- Backdrop: sheets use system; `AetherModalBackdrop` used for command palette — darken tint to `#171717@0.55` + native blur, no green.
- Close X: already 24×24 with symbol 11 — spec earlier wanted slightly smaller → keep 24 hit target, glyph 10.

### Bookmarks
- Folder icon neutral + label `#2563EB` — already correct.
- Import/Export equalized — already.
- Search field: `AetherField` uses `dialogField` → retoken to `input` #262626; focus ring #303030.
- Dialog card `dialogCard` → `card` #202020.

### New Profile sheet (`ProfileSwitcherView.swift:83-129`)
- Input: `AetherField` present — retoken field fill to #262626, focus #303030.
- Card: `theme.dialogCard` → #202020.
- Actions: Cancel currently plain + Create prominent — shift Cancel with `.padding(.trailing, 4)` relative balance? Spec: "Shift Cancel slightly left" — structure is `Spacer; Cancel; Create` — Cancel already left of Create. Keep trailing group; ensure both height-aligned (`controlSize` consistent).
- Create button: glassProminent keep; horizontal pad default.

---

## 11. Search intelligence blur-in/out

**Files:** `OmniboxSuggestionsView.swift`, `Design/AetherMotion.swift` (already has `blurInOut`, `blurMicro`)

- Insertion already uses `AetherMotion.blurInOut` — extend removal to symmetric: `.modifier(active: hidden, identity: visible)` both ways (currently removal `.opacity` only) — `OmniboxSuggestionsView.swift:49-51`.
- Row refinement on `rows.count` change: already `.animation(dropdown)` — add `.transaction { $0.animation = AetherMotion.dropdown }` scoped.
- `AetherBlurReveal`: opacity + blur 4 + scale 0.985 — matches spec. Tune blur to 3, scale 0.988 for subtlety; duration via `blurMicro` 140ms.
- Gradient/glow: omnibox `searchGlow` tied to focus/draft already (0 → 0.04 → 0.07). Convert white overlay to appearance-aware (§6.3). No permanent bright glow.
- Home field: no glow (flat fill §7).

---

## 12. Motion system (keep liquid, zero lag)

**File:** `Design/AetherMotion.swift` — do not replace curves.

| Token | Current | Action |
|---|---|---|
| sidebar | smooth 0.26 | keep 0.26 (layout now width-tweens → feels faster) |
| hover | smooth 0.15 | keep |
| focus | smooth 0.21 | keep |
| dropdown | snappy 0.12 | keep |
| tab | smooth 0.19 | keep |
| blurMicro | easeOut 0.14 | keep |
| blurInOut transition | modifier | symmetrical exit |

Lag sources to remove (not curve changes):
1. Sidebar glassID matched-geometry on every tab — remove glass from sidebar rows (§5.4).
2. Sidebar insert/remove transition → width animation (§3.2) avoids full view teardown (WKWebView stability).
3. Suggestion popup glass recompute — stable material host, animate overlay only (§11).
4. History/Settings scroll — flat fills, no per-row glass (already mostly flat).

---

## 13. Icon implementation detail (custom SVGs)

**Files:** `Sources/icons/AetherCustomIcons.swift` (+ optional `AetherCustomIconPaths.swift` regeneration via `svg2swift.py` — prefer **inline svgPaths** for new cases to avoid regenerating the 70KB file)

For each new case:
1. Add enum case.
2. Add to `space` switch (24) and `stroked`/`cap`/`join` as appropriate.
3. Add `svgPaths` entry with exact `d` strings from user SVGs (strip SVG attrs).
4. Zap is fill-only path (256 viewBox) → `space: 256`, `stroked: false`.
5. US flag: multi-path fill, space 22.

Parser `AetherSVGPathParser` supports AaCcHhLlMmQqSsTtVvZz — verify engine SVG paths (curves C present — OK). Zip has `C` and `Z` — OK. Tabs icon has many M/L/C — OK.

---

## 14. Execution order (topological)

1. **Palette tokens** (`AetherPalette.swift`, `AetherTheme.swift` if new props) — foundation.
2. **Glass/material** (`AetherMaterial.swift` + `BrowserWindowRoot/View` opaque root + safe area) — sidebar/fullscreen root cause.
3. **Sidebar layout/motion** (`BrowserWindowView`, `SidebarTabListView`, resize handle) — geometry + width animation.
4. **Chrome appearance resolver** (`AetherChromeAppearance.swift` + omnibox/toolbar/strip/icons/suggestions) — adaptive colors.
5. **Tabs: plus vs logo, padding, hover glass, selected fill** (`TopTabStripView`, `TabItemView`, metrics).
6. **Profile control** (`ProfileSwitcherView` + header pads + cluster width + dots).
7. **Dropdown/popover darkening** (`AetherPopoverBackground`, `AetherDropdown`, menus, suggestions panel).
8. **Home search field** (`NewTabView`).
9. **Settings row + divider + scroll** (`AetherRow`, `SettingsControls`, `SettingsWindowView`).
10. **Custom icons** (`AetherCustomIcons` new cases).
11. **Settings sections** (SearchLocation+flag, Passwords+disclosure, Advanced+badge+icons, Network fields/buttons/icons, Shortcuts badge, Search/General/Tabs/Privacy copy cuts).
12. **Dialogs** (History/Bookmarks/Profile sheet tokens + backdrop).
13. **Suggestion blur symmetry** (`OmniboxSuggestionsView`).
14. **Build + verify.**

---

## 15. Verification

```bash
cd /Users/harshitduggal/workspace/Aether/Sources/BrowserUI && swift build 2>&1 | tee /tmp/aether_ui_build.log | grep -E "error:|warning:.*AetherHuman" | head -40
echo exit=$?
```

Manual matrix (cannot automate pixels here — user runs app):

| Check | Expect |
|---|---|
| Sidebar open/close | width tween, no WKWebView reload, no clear gutter, full-height match |
| Fullscreen | neutral blur, no green, no gray strip |
| White page | toolbar #FAFAFA, address #F5F5F5, dark icons/text |
| Dark page | dark chrome family, address slightly lighter than toolbar |
| Focus address light page | light field, dark text, light suggestions |
| Top strip | plus button (not logo); tabs start after ~200pt cluster |
| New tab favicon | Aether logo in tab + sidebar row |
| Dropdowns | dark #202020, no bright wash, no border |
| Settings each section | aligned icon/title/trailing, short copy, Connected green badge, US flag, uniform fields/badges |
| Profile control | centered dots 5pt active/inactive, compact glass hover |
| History scroll | smooth, Today, brand mark blanks |
| Search suggestions | blur-in/out both directions |

Acceptance (directive §18): sidebar not merely more transparent; address not black on light chrome; plus present; settings copy not bloated; no bottom layout gaps.

---

## 16. Explicit non-goals

- No WebView lifecycle/navigation/persistence/credential/search-routing changes.
- No new components beyond appearance resolver + custom icon cases + shared settings field helper.
- No redesign of layout structure (sidebar vs top tabs arrangement preserved).
- No motion curve replacement (only symmetric blur exit + remove glassID cost).
- No engine-module edits.

---

## 17. Risk notes

| Risk | Mitigation |
|---|---|
| withinWindow material shows nothing blur-worthy if content fully opaque | Sidebar sits beside opaque content; withinWindow still blurs toolbar/sidebar chrome overlapping? Actually withinWindow blurs content **behind** the material view **in the same window**. If sidebar is the bottom-most layer, blur has nothing behind → appears flat. **Correct approach:** keep window non-opaque OR put a behind-window content layer. Re-evaluate: use `blendingMode = .behindWindow` **only if** we neutralize chroma with stronger opaque-ish tint (`#171717@0.55+`) and accept desktop diffusion — directive wants subtle wallpaper sense. **Plan: behindWindow + stronger neutral veil (#171717 @ 0.55) + desaturate via material .hudWindow or .sidebar** (sidebar material is designed to be dark). Fullscreen: behindWindow samples desktop fullscreen wallpaper — tint must be strong enough. Alternative: behindWindow + veil 0.58. Pick **behindWindow + veil 0.55–0.60** to satisfy "subtle sense of wallpaper" + "no green". If green persists, switch material to `.fullSizeContentView`/`.underWindowBackground` or add saturation-killing overlay `Color(white:0.07).opacity(0.35)` above material before tint. |
| Removing sidebar glassID | visual only; reduces lag |
| Palette darken breaks light mode | light hexes unchanged except hover/selected follow same relative steps: light hover #E8E8E8→#EBEBEB optional keep light as-is |
| AetherBadge radius change affects JevSearch | r3→r5 acceptable; verify Jev view still fine |
| profileClusterWidth 322→200 clips pinned pills | pills live inside cluster — shrink cluster but let pills overflow into scroll? Move pills OUT of fixed cluster into the ScrollView prefix (structure change). **Safer: keep pills in cluster, set cluster width to fit profile+incognito only (~140), move pinned pills to start of tab ScrollView.** |

---

## 18. File touch list (complete)

| File | Phases |
|---|---|
| `Design/AetherPalette.swift` | 1 |
| `Design/AetherTheme.swift` | 1 (new tokens: input, focus, tertiary) |
| `Design/AetherMaterial.swift` | 2, 8 |
| `Chrome/BrowserWindowRoot.swift` | 2 |
| `Chrome/BrowserWindowView.swift` | 2, 3, 6 (env inject) |
| `Chrome/SidebarTabListView.swift` | 3, 5, 6 |
| `Chrome/SidebarResizeHandle.swift` | 3 |
| `Chrome/NavigationBarView.swift` | 6 |
| `Chrome/TopTabStripView.swift` | 5, 6 |
| `Chrome/TabItemView.swift` | 5 |
| `Chrome/ProfileSwitcherView.swift` | 4, 10 |
| `Chrome/OmniboxView.swift` | 6, 11 |
| `Chrome/OmniboxSuggestionsView.swift` | 6, 8, 11 |
| `Chrome/MoreMenuView.swift` | 8 |
| `Chrome/IncognitoToggleView.swift` | 4/8 (popover bg inherits) |
| `Chrome/FindBarView.swift` | 8 |
| `Native/NativeAddressField.swift` | 6 |
| `Components/ChromeButton.swift` | 6 |
| `Components/AetherDropdown.swift` | 8 |
| `Components/AetherRow.swift` | 9 |
| `Components/AetherField.swift` | 1 (input token) |
| `Components/AetherBadge.swift` | 9 (r5, medium) |
| `Components/HoverSurface.swift` | 1 (token inherit) |
| `Components/DomainIcon.swift` | — (verify only) |
| `Pages/NewTabView.swift` | 7 |
| `Panels/HistoryView.swift` | 10, 12 |
| `Panels/BookmarksView.swift` | 10, 12 |
| `Panels/CommandPaletteView.swift` | 8 |
| `Settings/SettingsWindowView.swift` | 9 |
| `Settings/SettingsSidebarView.swift` | 9.4 |
| `Settings/SettingsControls.swift` | 9.1 divider |
| `Settings/SettingsSection.swift` | 9.4 |
| `Settings/GeneralSettingsView.swift` | 9.3 |
| `Settings/TabsSettingsView.swift` | 9.3 |
| `Settings/SearchSettingsView.swift` | 9.3 |
| `Settings/SearchLocationSettingsView.swift` | 9.3 |
| `Settings/PasswordsSettingsView.swift` | 9.3 |
| `Settings/AdvancedSettingsView.swift` | 9.3 |
| `Settings/NetworkSettingsView.swift` | 9.3 |
| `Settings/ShortcutsSettingsView.swift` | 9.3 |
| `Settings/DownloadsSettingsView.swift` | 9.3 |
| `Settings/PrivacySettingsView.swift` | 9.3 |
| `Settings/ProfilesSettingsView.swift` | 9.3 |
| `Settings/AppearanceSettingsView.swift` | 9.3 |
| `Design/AetherChromeAppearance.swift` | **new** 6 |
| `Sources/icons/AetherCustomIcons.swift` | 10, 9.4 |
| `Design/AetherMotion.swift` | 11 only if blur reveal tweak |
| `State/BrowserPreferences.swift` | — no behavior change |

---

**Plan ends. Execute in order 1→14 after approval.**
