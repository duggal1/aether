# Aether Native Capture

A standalone Swift **source module intended to become part of Aether's engine**. It is not a standalone renderer. No Chromium, Puppeteer, WebKit, Playwright, axios, Cheerio, SVGO, network re-fetches, or third-party dependencies. It never opens a second browser or uses JavaScript-injection for capture.

## What it delivers

- Natural document scrolling to load JS/lazy sections and a second pass capturing actual rendered viewport tiles.
- CSS-pixel/document coordinates retained for every tile; overlap is removed before encoding.
- WebP preferred **only where an ImageIO encoder is actually present**. JPEG auto-fallback if WebP is unavailable/fails. PNG only when explicitly selected.
- Optional bounded full-page composite, individual ordered tiles **always**, section-specific image crops, live `website.html`, `styles/*.css`, `computed-styles.json`, sections, assets, and manifest.
- A local `design-reference.md` suitable for external coding agents. Export is a directory; zip it from the caller if desired.
- No hidden fresh HTTP request for HTML, CSS, images, fonts, SVGs. Aether's loaded DOM, CSSOM and resource cache are the authority, so the export represents the same authenticated session and page state as its screenshots.

## Critical integration: source still incomplete by design

The `AetherCaptureEngine` and `AetherCaptureSession` interfaces in `EnginePort.swift` are the only deliberate adaptation point. They must be connected to Aether's actual in-repo Swift engine types. This package cannot know their names, APIs, or exact cache/renderer design without access to that source. `EngineClosureAdapter.swift` provides a strongly typed mapping option. The fake renderer in `Tests` is **only a test fixture**.

Aether must provide these real primitives:

1. Create an isolated page/session in the **existing** engine, with viewport size/scale, explicit profile and permissions.
2. Navigate, report final URL/title/viewport/document height/actual scroll position, and surface site blocks as errors (do not circumvent bot challenges).
3. Scroll via Aether's document scrolling path, triggering real intersection observers and loading. Wait for visual/layout stability with bounded deadlines and cancellation. This must not require an animated onscreen window.
4. Render the currently visible viewport into a small RGBA8 sRGB buffer; own the Metal texture/readback in Aether's renderer. Handle sticky/fixed-overlay de-duplication **in engine capture mode** if required. This package deliberately does not apply destructive stylesheet hacks to the live DOM.
5. Serialize **live** DOM after lazy loading and supply loaded source/CSSOM style text, DOM layout rectangles, selector/role/text/computed-style data, and resource references (img/srcset/currentSrc, CSS backgrounds, font loads, SVGs, etc.). List inaccessible CSS/frames/resources as explicit warnings. Never call an extracted document an exact original source unless it is.
6. Supply bytes from Aether's resource cache for a requested URL, respecting byte limits and making missing resources explicit. Inline SVG is already preserved in DOM serialization; external SVG is saved from resource cache when available.
7. Close the page/session after success or failure. Ensure cookies, active human profiles, and sensitive inputs are protected by the engine boundary.

No Swift library can recover inaccessible cross-origin iframe DOM, live canvas/WebGL drawing commands, protected video resources, or JavaScript application state just because it runs inside a browser. The screenshots still record their pixels when the engine can render them.

## Add it to Aether

Copy `Sources/AetherCapture` into your existing Swift package target or add this folder as a local SPM package, then implement `AetherCaptureEngine` with Aether engine references. Do not integrate the test actor as a real renderer. `CaptureCoordinator` is the coordinator entrypoint; connect it to your existing CLI/MCP dispatch and engine session scheduler, not a new daemon.

```swift
import AetherCapture

// aetherEngine is your real AetherCaptureEngine implementation.
let coordinator = CaptureCoordinator(engine: aetherEngine)
var options = CaptureOptions()
options.preferredFormat = .webp // automatic JPEG fallback
let result = try await coordinator.capture(
    URL(string: "https://example.com")!,
    into: URL(fileURLWithPath: "/tmp/example-ai-kit"),
    options: options
)
print(result.manifest.finalURL)
```

`result.directory` contains the generated AI kit. Destination **must not already exist**. A sibling staging directory is cleaned on failure and published as a complete folder on success.

## Output shape

```text
example-ai-kit/
  manifest.json
  design-reference.md
  website.html
  styles/index.json
  styles/0001.css ...
  computed-styles.json
  sections.json
  screenshots/0001.webp (or .jpg) ...
  sections/section-001-part-001.webp (or .jpg) ...
  full-page.webp (only if it fits the memory budget)
  assets/{images,svg,fonts,css}/...
```

No forced 25K-token truncation, no speculative minified CSS, and no destructive SVG optimizer: original readable data is better for a faithful design reference. Asset budget is deliberately finite and omissions are recorded. Format extensions reflect actual encoder output.

## Known limitations to wire in Aether before calling this production-grade

- This code is not compilable **against your actual Aether engine** until the adapter is implemented. The core and tests compile on Linux; ImageIO screenshot encoding needs a **macOS build/test**.
- ImageIO's WebP **encoder** availability varies by OS. Runtime detection and fallback are intentional; this is not a promised WebP encoder for every macOS version.
- Additional testing is needed for CSS import chains, constructed stylesheets, adoptedStyleSheets, Shadow DOM, cross-origin frames, CSS background/video/canvas content, sticky painting, dynamically expanding endless pages, Unicode/URL resource edge cases, and very long page timing.
- Structural section detection uses engine-provided tags/roles/rectangles, not an ML guess; the engine must emit useful structural nodes.
- Runs one page's state-changing operations in order; wider fleet scheduling belongs in Aether's existing scheduler.
