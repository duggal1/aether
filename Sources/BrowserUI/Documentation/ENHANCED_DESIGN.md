# Aether native material enhancement

This revision **edits the original AetherHumanUI files in place**. It is not a second UI, engine, or browser shell. The root `DESIGN.md` stone tokens remain authoritative; Dia screenshots are structural reference images only.

## Actual implementation

- `Design/AetherGlass.swift` implements a single background-only Liquid Glass primitive. On **macOS 26+**, it calls SwiftUI `glassEffect(_:in:)` with bounded rounded geometry and `.regular.interactive()` only on controls. For **macOS 15–25**, it falls back to SwiftUI's real `.ultraThinMaterial`; with **Reduce Transparency**, it uses an opaque stone token instead. It never blurs text or the webpage.
- `Design/AetherMaterial.swift` uses genuine `NSVisualEffectView` with Apple's `titlebar` and `sidebar` material roles. Titlebar blends within the window; structural sidebars use behind-window blending. Both receive a restrained semantic stone overlay that does not replace the blur with an opaque colored rectangle. The settings sidebar and browser sidebar share this owner. A native popover already supplies native blur, so popup content gets only a legibility tint rather than a second material layer.
- Top tab row and navigation bar share one chrome material, selected **top tab only** gets a bounded Liquid Glass treatment, and vertical tab selection stays matte with a quiet two-point side mark. Profile control and omnibox get bounded Liquid Glass treatments; their text remains editable and unblurred.
- Selected utility actions use bounded glass; ordinary chrome icons do not each generate a glass surface. Related action groups use `GlassEffectContainer(spacing: 8)` on macOS 26+.
- Existing `.smooth`/`.easeOut` transitions remain restrained with Reduce Motion; tab selection has a scoped 160 ms transition. Switching between tab layouts does not create new engine pages or animate the web renderer.

## Actual OS/SDK boundary

The package supports macOS 15+, but **true system Liquid Glass is only selected on macOS 26+**. On older systems, `.ultraThinMaterial` and `NSVisualEffectView` provide real native materials; they are not hand-drawn glass. Build with an Xcode SDK that includes `glassEffect` and `GlassEffectContainer`, even when deploying back to macOS 15, because availability guards do not make missing SDK symbols compilable.

There is **no claim** of a successful macOS build, a pixel-accurate match, working live web rendering, or Instruments measurements. This Linux sandbox can check source parsing and the SwiftPM manifest, but cannot compile AppKit/SwiftUI or inspect the rendered macOS interface. Test System/Light/Dark, Reduce Motion, Reduce Transparency, high contrast, VoiceOver, live typing, open popovers, tabs, and window resizing on the target Mac.

## Official Apple API reference

- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- https://developer.apple.com/documentation/appkit/nsvisualeffectview
- https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency
