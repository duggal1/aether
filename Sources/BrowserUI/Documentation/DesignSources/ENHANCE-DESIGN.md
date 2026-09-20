
---
name: enhance-browser-ui
description: Enhance Aether's completed native macOS browser UI with Apple Liquid Glass, native blur, precise motion, and lightweight transitions while preserving design.md, existing components, browser functionality, and first-class AI agent control.
---

# Aether — Native UI Enhancement

## Mission

Transform Aether's completed browser interface into an exceptionally clean, responsive, lightweight native macOS experience using Apple's actual Liquid Glass, SwiftUI, AppKit, and system animation APIs.

Aether is a custom browser built for two first-class users:

1. Humans, who need an extremely fast, minimal, reliable browser.
2. AI agents, which control the browser through its engine and structured execution interfaces.

Aether is NOT a chatbot bolted onto a browser. Its agent-native architecture must remain intact.

This skill enhances the existing UI. It does not design a new browser, replace the engine, or introduce product features.

## 1. Mandatory Execution Order

Execute this skill ONLY after:

- Reading the complete `design.md`.
- Creating the browser's skeleton and layout.
- Implementing the actual browser UI components.
- Connecting components to real browser state and actions.
- Establishing functional tab and navigation behavior.

The existing design is the source of truth.

Preserve its typography, color relationships, spacing, component hierarchy, control dimensions, layout, and visual restraint.

Translate web-specific design rules into equivalent native SwiftUI/AppKit behavior. Do not reproduce CSS, Next.js, React wrappers, or browser zoom literally.

Inspect the actual project and installed Apple SDK before selecting APIs.

Do not invent API names or assume unsupported platform availability.

## 2. Native Technology Contract

Use Apple's own frameworks:

- SwiftUI for declarative components and state-driven motion.
- AppKit for macOS-specific window and view integration.
- Native Liquid Glass for appropriate foreground controls.
- Native system materials for translucent surfaces.
- Native SwiftUI animations for state transitions.
- Metal only when the existing architecture genuinely requires custom rendering.

Preferred native APIs:

- `glassEffect(_:in:)`
- `GlassEffectContainer`
- `glassEffectID(_:in:)`
- `glassEffectTransition(_:)`
- `Glass.interactive()`
- `NSVisualEffectView`
- SwiftUI `Material`
- `withAnimation`
- `.smooth`
- `.snappy`
- `.spring`

Use SwiftUI or AppKit according to existing component ownership.

Do not rebuild existing AppKit components in SwiftUI merely to access Liquid Glass.

Do not implement native browser chrome as an HTML overlay.

Never simulate Liquid Glass with CSS, JavaScript, WebGL, screenshot sampling, or handmade blur shaders when a suitable system API exists.

Native Liquid Glass, conventional system blur, and ordinary opaque surfaces are different tools. Choose each deliberately.

## 3. Enhancement Priorities

Enhance these existing browser components in order.

### A. Top Bar and Address/Search Field

This is the highest-priority surface.

Create a visually stable, exceptionally legible navigation area using native materials.

Requirements:

- Native translucent background where appropriate.
- Clear, sharp URL and search text.
- Stable input dimensions during interaction.
- Subtle focus transitions.
- Distinct editing and unfocused states.
- No blur applied directly to glyphs.
- No refraction that obscures typed text.
- No unnecessary focus enlargement.
- No shifting the surrounding toolbar during typing.

The background may be glass. The text must remain visually sharp and readable.

Prefer one coherent material region over separate glass effects around every nested element.

Do not stack several translucent layers to manufacture a stronger blur.

Preserve keyboard focus, text selection, cursor behavior, URL editing, and search execution.

### B. Tab Bar

Enhance tab creation, selection, closing, and reordering.

Use native animations to create subtle continuity between tab states.

Requirements:

- Smooth active-tab selection.
- Lightweight tab insertion and removal.
- Stable tab identifiers.
- Minimal width and position changes.
- No excessive elastic movement.
- No layout jumping.
- No delayed activation.
- No animation blocking tab interaction.

Use a `GlassEffectContainer` where multiple adjacent glass controls should visually cooperate.

Use stable glass effect identities for suitable transitions.

Do not force the entire tab bar into one morphing glass shape if this reduces clarity.

Keep tab titles and close controls legible throughout transitions.

### C. Sidebar

Opening and closing the sidebar must feel immediate.

Use a short native transition with restrained movement.

Requirements:

- Smooth reveal and dismissal.
- Stable browser-content layout.
- No window-wide animation.
- No unnecessary page reconstruction.
- Minimal layout invalidation.
- No lost navigation state.
- No interruption of agent execution.

Use native sidebar materials where appropriate.

Do not add permanent glass surfaces to every sidebar row.

Selection states must remain clearly distinguishable.

### D. Browser Controls

Enhance existing:

- Back and forward.
- Reload and stop.
- New tab.
- Tab close.
- Navigation actions.
- Search suggestions.
- Context menus.
- Popovers.
- Agent execution controls.
- Relevant toolbar actions.

Use native interaction feedback.

Keep hit targets practical while preserving compact visual dimensions.

Do not force a new radius, size, or icon style onto every control.

Do not convert every button into an individual glass capsule.

### E. Agent-Native UI

Agent controls are first-class browser capabilities.

Enhance existing agent execution surfaces without creating chatbot-style interfaces.

Preserve:

- Structured browser actions.
- Native tool execution.
- Agent-readable browser state.
- Agent-readable tab identities.
- Action and execution status.
- Navigation and lifecycle events.
- Existing permission and confirmation flows.

Human interactions and agent-triggered interactions must update the same authoritative browser state.

An agent opening a tab should produce the same coherent UI state as a human opening one.

Visual animations must not become dependencies of browser execution.

An agent must never need to wait for decorative animation to finish before receiving a valid action result.

Never make screenshots, pixel coordinates, or visual inference the primary mechanism for agent control.

## 4. Liquid Glass Design Rules

Liquid Glass is an interaction material, not a universal background.

Prioritize:

1. Top navigation controls.
2. Search and address surfaces.
3. Active tab treatment.
4. Floating browser controls.
5. Appropriate popovers and overlays.

Use conventional native material or opaque surfaces for large structural regions.

Avoid Liquid Glass on:

- Main rendered web content.
- Every sidebar row.
- Every tab simultaneously.
- Large static backgrounds.
- Dense text panels.
- Repeated nested containers.
- Decorative surfaces without interaction value.

Group nearby glass elements into coherent containers.

Do not create a separate rendering container for every control.

Use interactive glass only on genuinely interactive elements.

Respect system appearance and accessibility preferences.

The intended appearance is restrained, clear, and light, not glossy or excessively reflective.

## 5. Native Motion Language

Use one coherent motion system.

Suggested initial timing targets:

| Interaction | Initial target |
|---|---|
| Hover feedback | 80–120ms |
| Button press | Immediate |
| Focus change | 100–160ms |
| Active tab | 140–200ms |
| New/closed tab | 160–220ms |
| Sidebar | 180–260ms |
| Popover | 140–200ms |

These are starting points, not fixed requirements.

Tune by testing real interaction latency.

Use `.snappy` for quick selection changes and `.smooth` for restrained structural transitions.

Prefer minimal bounce.

Avoid:

- Rubber-band motion on ordinary buttons.
- Large overshoots.
- Repeated pulsing.
- Continuous ambient animations.
- Excessive opacity and scale combinations.
- Animation attached to every state update.
- Delays before an action becomes usable.

An animation must improve continuity, feedback, or spatial understanding.

If it does none of these, remove it.

## 6. Performance Contract

The browser must remain responsive during heavy browsing and parallel agent operations.

Never perform expensive work on the main actor merely to support visual effects.

Keep browser-engine operations separate from presentation animation.

Requirements:

- Keep glass rendering regions bounded.
- Minimize simultaneous glass effects.
- Avoid redundant material layers.
- Keep component identities stable.
- Avoid unnecessary view-tree reconstruction.
- Limit animation to the state actually changing.
- Avoid animating the entire browser window.
- Avoid layout-heavy transitions where simpler ones suffice.
- Never capture or blur rendered web pages manually for UI chrome.

Use Instruments and real runtime profiling to investigate animation hitches, CPU use, memory use, and rendering performance.

Target the display's native refresh cadence during interaction.

Never claim zero latency or perfect frame rates without measurement.

Do not degrade navigation, text input, scrolling, or agent execution to preserve decorative effects.

## 7. Accessibility and Legibility

Honor macOS accessibility settings.

When Reduce Transparency is enabled, provide appropriate opaque backgrounds.

When Reduce Motion is enabled, remove unnecessary movement and use simpler transitions.

Preserve:

- Text contrast.
- Keyboard navigation.
- Visible focus.
- VoiceOver labels.
- Reliable hit targets.
- Readable inactive controls.

Test glass above light, dark, colorful, and high-contrast web content.

If glass reduces readability, simplify the effect or use an opaque backing.

Readability has priority over material fidelity.

## 8. Architecture Preservation

Before editing, inspect component ownership and existing state flow.

Do not:

- Rewrite the browser engine.
- Replace existing navigation infrastructure.
- Change agent execution protocols.
- Introduce an independent animation state store.
- Add unnecessary dependencies.
- Change backend contracts.
- Replace the established design system.
- Reimplement the same component in several frameworks.
- Create duplicate browser state.

Preserve existing public interfaces wherever possible.

Keep enhancements isolated and maintainable.

Implement visual states as projections of existing authoritative state.

Use the existing browser's component structure rather than creating another UI architecture.

## 9. Implementation Workflow

1. Read `design.md` completely.
2. Inspect the current browser UI.
3. Identify SwiftUI and AppKit ownership.
4. Identify available SDK APIs.
5. Record the baseline appearance and performance.
6. Locate the minimum components requiring enhancement.
7. Implement the native material layer.
8. Implement local interaction animations.
9. Verify human interaction.
10. Verify agent-triggered interaction.
11. Profile performance.
12. Remove unnecessary effects.
13. Compare the final UI against `design.md`.

Do not stop when the code compiles.

Inspect the running application.

Verify actual material rendering, behavior, accessibility, and performance.

## 10. Completion Criteria

The work is complete only when:

- The existing design remains recognizable.
- The top bar has appropriate native translucency.
- URL and search text remain exceptionally legible.
- Tab transitions feel smooth and immediate.
- Sidebar transitions are clean and restrained.
- The browser remains responsive during agent execution.
- Agents and humans share coherent browser state.
- The application uses actual supported Apple APIs.
- No unnecessary rendering effects remain.
- Existing browser functionality is preserved.
- Builds and relevant tests pass.
- Runtime performance has been checked.

The finished result should feel native because it uses the native platform correctly, not because it imitates an Apple screenshot.

Final principle:

**Design first. Function second. Native enhancement third. Performance and correctness always.**