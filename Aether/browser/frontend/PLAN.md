# Aether: Phase 2, The Human Browser

Objective: Transform Aether's existing browser engine into a complete, native macOS browser that humans can use every day.

The agent engine is the foundation. Phase 2 builds the human experience on top of it. We are not creating a second engine, a Chromium wrapper, or an AI chatbot browser.

The goal is a browser with Chrome's everyday reliability and profile convenience, Dia's clean navigation structure, and Aether's own native engine and performance architecture.

The screenshots establish the structural reference. `design.md` remains the authority for actual styling.

# The complete five-phase roadmap

01

Agent-native browser engine

Core rendering, navigation, automation, extraction, sessions, and execution infrastructure.

Almost done

02

Human browser

Complete native browser backend and SwiftUI interface.

Current

03

Human-agent integration

Connect external agents with the entire browser, visually and headlessly.

04

Advanced capabilities

Additional native features, integrations, and optimizations.

05

Complete validation

Aggressive real-world, regression, performance, and reliability testing.

Each phase needs its own tests. Phase 5 is the final comprehensive validation, not permission to postpone testing until the end.

# Phase 2A: Human browser backend

This phase is about functionality and performance. The UI comes afterward.

## 1. Extremely fast native browsing

The engine must deliver consistently smooth browsing, not merely low memory usage.

Prioritize:

* Fast startup, navigation, and first interaction.

* GPU-accelerated page compositing and supported video decoding.

* Smooth scrolling and responsive input.

* Instant-feeling tab switching.

* Efficient memory allocation and resource reuse.

* Background-tab suspension and intelligent restoration.

* Minimal unnecessary CPU and GPU activity.

* Reliable rendering of complex JavaScript applications.

* Efficient caching, image decoding, and network loading.

Performance must be measured at the engine, renderer, and UI levels separately.

For a 60 Hz display, rendering has approximately 16.7 ms per frame. At 120 Hz, approximately 8.3 ms. Missing those budgets causes visible stutter.

Avoid rebuilding entire SwiftUI view hierarchies when switching tabs. Preserve browser surfaces and update only the necessary UI state.

Use Instruments to identify actual bottlenecks.

Your Safari-versus-Chrome experience is valid as an observation about your machine and workflows, but we should not turn it into a universal performance assumption. Aether must win through measured responsiveness.

### Video and media

Support hardware-assisted playback wherever the underlying hardware, codec, and engine permit it.

Target smooth 4K and 8K playback on capable hardware, but don't promise universal 8K performance on every Mac.

Video must not cause unnecessary full-window redraws, excessive CPU usage, or tab-switching latency.

## 2. Complete native browser fundamentals

Implement the following as real backend capabilities, not decorative UI:

|
Capability

|

Requirements

|
| --- | --- |
|

Navigation

|

Back, forward, reload, stop, redirects

|
|

Tabs

|

Create, close, duplicate, pin, restore

|
|

Windows

|

Multiple windows and session restoration

|
|

Search

|

Google default, configurable providers

|
|

Address bar

|

URL navigation and search in one field

|
|

History

|

Search, revisit, delete, clear

|
|

Bookmarks

|

Add, edit, organize, import, export

|
|

Downloads

|

Progress, pause where supported, cancel, reveal

|
|

Media

|

Video, audio, fullscreen, picture-in-picture

|
|

Documents

|

PDF viewing, printing, export

|
|

Permissions

|

Camera, microphone, location, notifications

|
|

Storage

|

Cookies, local storage, cache, site data

|

A browser that looks beautiful but cannot reliably log into Google or play YouTube is not finished.

## 3. Chrome-style multiple profiles

The screenshot showing Dia's profile dropdown is the structural reference.

The user can create unlimited practical profiles, for example:

```
Personal
Work
Development
Testing
```

Every profile needs independent cookies, login state, history, bookmarks, downloads preferences, and website storage.

Switching profiles must not require restarting Aether.

The top-left profile selector should allow immediate switching, creation, renaming, and deletion.

A single profile can maintain several Google accounts, just like Chrome. Profiles provide additional isolation rather than limiting each profile to one account.

This is fundamental browser functionality, not an advanced feature.

## 4. Apple Keychain, passwords, and passkeys

This is a major part of the human browser backend.

Use Apple's Security and AuthenticationServices frameworks to integrate password storage and authentication.

Requirements:

* Detect supported website login and registration forms.

* Offer to save and update credentials.

* Support account selection and autofill.

* Support password generation.

* Support passkey creation and authentication.

* Use Touch ID when required by the authentication flow.

* Respect macOS credential access permissions.

For a custom browser engine, WebAuthn challenges must be connected to Apple's AuthenticationServices APIs. Apple's browser-specific passkey support includes `ASAuthorizationController` and `ASAuthorizationWebBrowserPublicKeyCredentialManager`. Access to the user's passkeys requires authorization.

![](https://www.google.com/s2/favicons?domain=https://developer.apple.com\&sz=32)

Apple Developer Documentation

+2

One critical distinction: using the Security framework to save Aether's own credentials does not automatically provide unrestricted access to existing Apple Passwords or iCloud Keychain entries.

Implement the documented browser credential integration rather than pretending those are interchangeable.

Never expose credentials to agent sessions automatically.

## 5. Native developer inspection

Aether already has extraction infrastructure. Phase 2 must expose it to humans.

Right-click any element and select Inspect Element.

The inspector must provide:

* Full HTML tree.

* CSS rules and computed styles.

* Element dimensions and layout.

* Assets and SVGs.

* Console and JavaScript errors.

* Network requests and response details.

* Copy selected HTML.

* Copy the full HTML document.

* Copy relevant CSS or all available CSS.

* Export an entire design-reference package.

Selecting an element should highlight its corresponding region on the actual webpage.

Do not require developers to navigate hundreds of nested panels just to copy useful code.

## 6. Reader mode and native Markdown

Create a first-class reader engine using Aether's existing DOM and extraction infrastructure.

The browser should transform an article or documentation page into clean Markdown.

Preserve headings, paragraphs, links, lists, tables, code blocks, and relevant images.

Strip navigation clutter, unnecessary scripts, advertising elements, and irrelevant UI from the reading representation.

Support copying and exporting Markdown.

Reader mode must not modify the original webpage. It is a separate representation derived from the existing document.

## 7. Native content blocking

Ad blocking and tracker blocking are built into the engine.

No Chromium extension dependency.

Provide three simple controls: block ads, block trackers, and handle cookie banners where supported.

Enable blocking by default, with website-specific exceptions.

YouTube ad blocking is a target, but don't fabricate universal reliability against changing delivery mechanisms.

# Phase 2B: The SwiftUI browser interface

Use Dia's structural ideas, not its entire design language.

The provided screenshots establish three main interface structures.

## 1. Two tab layouts

![Updates](https://images.openai.com/static-rsc-4/5a9CtLHuux61M5zhJnFwnvd2yAoM7AGakCmPuEQp7YjdOeqCxI31RoBkIOaiNxZ3UvEzJ8lRsEeySkqs8KmUrZ1auW-bgbIyoXleuRoKzV2bWJgGXGRO4OE0MxIDfW2PWRsPRS26xcNjSA8iDgUeC4cJzkiC1EofoRlKzqVZ5c4?purpose=inline)

Top tabs

Chrome-style horizontal tabs with a compact toolbar.

![TestingCatalog News 🗞 (@testingcatalog) on X](https://images.openai.com/static-rsc-4/z0M-5U0sMyAojdub_Wp1bjCqiLOb1U9IlY6cK8fQmRqEbQUD8i6ZlEc6C5dKWd5ffQ5OE6Y330dWGwszoBZxFGcyMoNjb33oyKO7L0fhIZ3pRIEzpagfkYINkJeBhj8NZkIbeGKzGUEPAok_gQTLh28Irb6L9PUytglN3Ffd74Q?purpose=inline)

Sidebar tabs

Left sidebar containing tabs, profile access, and navigation.

Both layouts use the same tab manager and browser session state.

Switching layouts must not reload websites, destroy tabs, or recreate browser sessions.

The sidebar should be collapsible and resizable. Top tabs should handle overflow without making tabs unusably narrow.

## 2. The new-tab page

AETHER · NEW TAB STRUCTURE

Search Google or enter URL

YouTube

Gmail

GitHub

Slack

Notion

Calendar

ChatGPT

Add

Minimal. Fast. No AI chatbot.

Structural wireframe only. Actual colors, typography, corner radii, blur, and spacing come from design.md.

Remove Dia's central AI prompt.

Replace it with a minimal new-tab experience containing favorite websites and shortcuts in the center.

No chat panel, generic AI dashboard, news feed, or unnecessary promotional content.

## 3. Profile selector and settings

Use the screenshots showing Dia's profile dropdown and settings window as structural references.

Top-left profile selection should be obvious and fast.

Settings should use a compact sidebar containing sections such as General, Tabs, Profiles, Privacy, Passwords, Search, Downloads, Appearance, Shortcuts, and Advanced.

Reuse a single consistent settings component architecture.

All options must be functional and persistent.

The screenshots demonstrate structure. Do not copy their purple tint, glass effects, exact spacing, or other styling choices.

Aether's existing `design.md` controls all visual styling.

# Phase 2 completion criteria

Phase 2 is complete when:

1. Aether operates as a reliable everyday macOS browser.

2. Humans can browse, use multiple profiles, authenticate, watch videos, and manage tabs without an agent.

3. The native engine supports inspection, Markdown reading, content blocking, downloads, and normal browser workflows.

4. Both tab layouts operate through the same session manager.

5. The browser stays responsive under sustained real-world workloads.

6. The human UI remains independent of any AI provider.

7. Existing agent-engine capabilities remain intact.

Phase 3 then connects external AI agents to this complete human browser, giving them access to the same underlying functionality through visible and headless sessions.
