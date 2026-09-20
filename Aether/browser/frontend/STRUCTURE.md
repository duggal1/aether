# Aether — Browser Structure

> **Phase 2B: human-browser shell and interaction architecture.** This is the missing structural specification, **not** a replacement for `design.md`. Use the supplied Dia screenshots only to understand the arrangement and behavior of surfaces. `design.md` owns colors, typography, spacing, blur, radii, gradients, shadows, and other visual tokens.

## 0. Mission and boundaries

Build a complete, native macOS browser **around Aether's existing engine**. It must work beautifully with no AI model, account, sidebar chatbot, or agent attached. No Chromium, duplicated renderer, separate human-only browser engine, Chrome settings UI, fake buttons, or web-based settings page. Keep UI work in SwiftUI/AppKit where native macOS integration requires it. Phase 3 will expose the **same** browser sessions and actions to external agents; Phase 2 must not hardcode agent behavior into the UI.

## 1. Source of truth

One browser application; one session/tab/profile architecture; two **presentations** of tabs. A tab's engine page, URL, history, loading state, scroll position, and authentication context must remain unchanged when its presentation moves between top bar and sidebar.

Suggested conceptual models, mapped to existing code rather than duplicated: `BrowserAppState → BrowserWindow → Profile → TabGroup? → Tab → EnginePage`. Distinguish tab identity from visible position; keep selection scoped to each window, persistence scoped to each profile, and ownership/permission scoped to each session. New windows use the profile selected in settings. Multiple windows can belong to the same profile without merging their selected tabs.

## 2. The browser window: two layouts, same content

### A. Top-tabs layout (Chrome-like)

- Native macOS window and traffic-light controls at upper left, with correct titlebar-safe hit areas.
- Compact top row: profile selector at the left; pinned favorites if the design calls for them; normal tabs; **+** new tab; overflow/tab-search control at right.
- Compact navigation row: Back, Forward, Reload/Stop, omnibox, and only essential contextual actions (bookmark, downloads, site permissions, inspection as applicable).
- Website viewport occupies all remaining space. It must be a persistent surface belonging to its tab, not a screenshot or view rebuilt on each tab switch.
- Tabs support create, close, reorder, pin/unpin, switch, duplicate, restore closed, drag between windows, context menu, and keyboard navigation. Overflow must remain usable with dozens of tabs.

### B. Sidebar-tabs layout (Dia structural reference)

- Left sidebar begins with the current **profile name/selector**, followed by a compact set of optional pinned favorite sites, a **New Tab** action, then the vertical tab list.
- Normal tabs use favicon + readable title + active indication. Clearly separate pinned items from open tabs. Support reorder, close, context menus, overflow, collapse, and adjustable sidebar width.
- The page area retains a minimal navigation/omnibox row across its top; the browser content fills the rest.
- Collapsing the sidebar must preserve the current tab and leave an obvious control to reopen it. Switching between sidebar and top tabs must **never navigate, reload, or recreate the renderer**.

**Layout behavior:** Treat these as alternate views over the same tab manager. Persist the user's layout preference, restore it at launch, and support window-level overrides only if the existing state architecture can do so cleanly.

## 3. Profile dropdown and isolation

Use the supplied profile-menu screenshot for information architecture: clicking the profile name opens a compact popover listing profiles, an active checkmark, optional shortcuts, **New Profile**, and **Profile Settings**. A switch changes active window/profile context predictably; show the correct tabs and bookmarks for that profile. A single profile may sign into multiple Google accounts. Distinct profiles must isolate cookies, site storage, saved sessions, history and bookmarks according to the actual engine's data-store boundaries; never just change a visible name. Profile create/rename/delete needs confirmations where data is destroyed. Agent sessions must not silently inherit personal profiles.

## 4. New-tab page: remove Dia's chatbot

No central AI prompt and no default chat sidebar. Center a small, editable grid of favorite websites/shortcuts, closer to Chrome's frequently-used-sites behavior. Each tile has favicon, concise name, and normal context actions: open, edit, remove. Allow an **Add shortcut** tile. An empty state is still intentional and clean. Use the omnibox for Google search and URL entry; do **not** duplicate it as a giant AI input in the page. Do not copy Dia's tiny favorite-app grid into the browser chrome by default. No news feed, sponsored tiles, upsell, or agent dashboard.

## 5. Omnibox and browser navigation

Single keyboard-first URL/search field: typed URL, Google search, history matches, bookmarks, open-tab matches, and switch-to-tab. Distinguish suggestions by type and allow arrow/Enter/Escape navigation. Display the final committed URL and site security context, not misleading placeholder domains. Back/Forward/Reload/Stop reflect real engine navigation state; loading failures show a usable retry and diagnostic message. Provide normal paste-and-go, URL copy, find-in-page, downloads, and site-permission affordances without permanently cluttering the bar.

## 6. History, bookmarks, tab search, and menus

Use the screenshot's top-right compact popover pattern: a search field plus **Open Tabs**, **Recently Closed**, **History**, **Bookmarks**. Each section links to a functional full view when needed. Never place hundreds of entries in one giant menu: use search, limited recent results, and **Show More**. Support keyboard access and dismiss on Escape/outside click. History and bookmark full views should reuse the app's native shell, not chromium:// clone pages. Use native macOS menus and shortcuts for the actions exposed in the interface.

## 7. Settings: native two-column structure

Use the Dia settings screenshot for **navigation skeleton only**: a dedicated settings window/sheet with a narrow left navigation sidebar and a right content pane. Sections should reflect what Aether actually implements: **General, Tabs, Profiles, Search, Privacy, Passwords & Passkeys, Downloads, Appearance, Shortcuts, Advanced**. Do not add empty sections or copy Dia-specific Account/Sync/Skills panels unless those systems exist. Keep section content as clear native grouped rows, short descriptions, toggles, popovers, and explicit destructive actions. The **Tabs** section includes a visual choice between Top of Window and Sidebar, with immediate preview/application and persistence. Profiles include create, reorder (if supported), rename, delete, default new-window profile, and storage controls. Privacy contains ad/tracker blocking and per-site exceptions. Search chooses default provider. Appearance exposes system/light/dark. Avoid nested settings dialogs when an inline row will do.

## 8. Transitions, themes, and interaction polish

Keep a subtle **line/gradient selection indicator** for tab selection and transitions, if consistent with `design.md`; animate indicator position/width and content presentation, **never** animate the web renderer by rebuilding it. Support macOS system appearance, explicit dark, and explicit light. Resolve *all* surfaces, hover/selection/focus states, icons, separators, and dialogs from design tokens. Maintain readable contrast and reduced-motion alternatives. Hover transitions and tab reorder should stay responsive even while a webpage is loading. Do not import Dia's purple tint or literal styling.

## 9. Native component boundaries

Suggested UI areas, adapted to the real repository's existing names:

```text
BrowserShell/
  BrowserWindowView.swift
  BrowserChromeView.swift
  TopTabStripView.swift
  SidebarTabListView.swift
  TabItemView.swift
  ProfileSwitcherView.swift
  OmniboxView.swift
  BrowserContentHost.swift
  NewTabView.swift
  TabSearchPopover.swift
  Settings/
    SettingsWindowView.swift
    SettingsSidebarView.swift
    GeneralSettingsView.swift
    TabsSettingsView.swift
    ProfilesSettingsView.swift
    PrivacySettingsView.swift
    AppearanceSettingsView.swift
```

These are **responsibilities, not an instruction to create duplicate files**. Audit and extend existing equivalents. Keep persistent model/session operations out of SwiftUI view bodies. Ensure the engine owns page lifecycle, SwiftUI owns presentation, and commands go through the existing browser coordinator.

## 10. Phase 2 structural acceptance tests

- Both tab layouts operate on identical tabs; switching layout preserves live page state, video position where feasible, profile identity, and scroll position.
- Profiles truly isolate authenticated sessions; switching back restores each profile's tabs and history.
- Native menus, history/bookmark search, new-tab shortcuts, settings navigation, and all visible controls work without AI.
- Settings persist across app restart; system/light/dark and reduced motion work across every window/popover.
- A loading or crashed page never freezes chrome, profile switching, or tab selection.
- Verify keyboard, mouse, trackpad, accessibility labels, focus order, and multiwindow behavior.
- Measure cold/warm startup, tab-switch input latency, scrolling frame times, memory per active/background tab, and sustained real-site browsing on actual supported Macs. **“Zero lag” is a performance goal, not an untestable claim.**

**Done means a complete, usable human browser shell connected to the real Aether engine.** Phase 3 adds agent control over that same shell and underlying sessions; it must not require a rewrite.
