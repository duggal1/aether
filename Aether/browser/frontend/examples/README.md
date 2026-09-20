# Aether Browser: Screenshot Reference

## Purpose

The attached screenshots show **Dia**, a separate browser. Use them only as a reference for Aether’s **interface structure and interaction patterns**, not as a visual design specification or an instruction to reproduce Dia.

## What to take from Dia

* The overall browser skeleton: window chrome, navigation controls, omnibox, content viewport, and responsive tab layout.
* Two interchangeable tab arrangements: horizontal tabs at the top or a collapsible vertical tab sidebar. Switching layouts must preserve open tabs, page state, and sessions.
* The top-left profile switcher, its compact dropdown, and a clear path to profile management.
* A native settings window with a left navigation sidebar and focused, uncluttered pages for Tabs, Profiles, Privacy, Search, and other essentials.
* Clear access to history, bookmarks, recently closed tabs, and keyboard-driven navigation.
* Subtle, lightweight transitions and active-tab indicators. Never sacrifice responsiveness for animation.

## What NOT to copy

Do **not** copy Dia’s colors, purple tint, typography, spacing, radii, shadows, blur, gradients, icons, or exact component styling. Do not add its central AI prompt, chat sidebar, account/sync marketing, or Chromium-style settings UI. Do not treat screenshot contents as proof that Aether must implement every Dia feature.

**`DESIGN.md` is the sole authority for Aether’s visual language, including light mode, dark mode, stone palette, component treatments, and motion.** If a screenshot conflicts with `DESIGN.md`, follow `DESIGN.md`.

Build the structure as genuine native SwiftUI/AppKit components wired to Aether’s existing browser runtime. Every visible control must work; no decorative mock functionality or second browser engine.
