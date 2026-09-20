# WebKit migration

User authorizes replacing the experimental webpage engine with Safari’s engine, retaining native Aether chrome and excluding Chromium. This supersedes historical no-WebKit instructions.

1. Research Apple/WebKit primary documentation; inspect actual app/runtime boundary and preserve existing working changes.
2. Add a MainActor WebKit page implementation owned through BrowserRuntime. Use system WKWebView, profile-specific WKWebsiteDataStore, native navigation/input/compositing and public APIs only. Keep experimental backend available for existing engine research; app explicitly chooses WebKit.
3. Route app and shared agent runtime navigation, inspection, evaluation, interaction and screenshots to the same live page. Preserve native chrome, tabs, library and profiles. Native WebKit manages cookies/cache/web storage; do not duplicate website execution in the experimental engine.
4. Compile release with jobs=1. Package/sign/install/open Aether. Exercise apple.com, youtube.com, a further public site and localhost JS/CSS/fetch/storage/input/history. Capture real WKWebView and app-window screenshots; inspect and fix evidence-backed failures. User requests no unit-test campaign.
5. Document actual compatibility, measured evidence, remaining engine-specific API limitations, and avoid claims of universal compatibility or fastest performance.

Primary sources: https://docs.webkit.org/Deep%20Dive/Architecture/WebKit2.html ; https://developer.apple.com/documentation/webkit/wkwebview ; https://webkit.org/licensing-webkit/ ; https://github.com/WebKit/WebKit ; https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloadsinwebcontent

Decision: system WebKit API rather than vendoring WebCore. WebCore alone is not a supported standalone macOS embedding API. Building all WebKit adds a large maintenance/distribution burden without evidence of benefit. System framework provides WebCore, JavaScriptCore, networking and sandboxed web processes. Safari application features and every Safari-specific entitlement are not implied.

## Follow-up: performance, theme, stability, address editing, Google

Confirmed: focusing omnibox starts a SwiftUI popover/layout loop. AppKit logs >100 popover windows and main-thread sampling shows 100% CPU in layout invalidation. Fix native address input and use an in-window suggestion overlay, never focus-driven NSPopover creation. Preserve exact chrome geometry.

Performance: lazily restore background tabs; reuse one data store per profile; coalesce redundant WK state notifications; defer full persistence off navigation completion. Keep system GPU compositor and process scheduling; no private GPU switches, unbounded parallelism or claims of zero latency. Collect actual navigation timings and app idle CPU/memory.

Theme: propagate app appearance to WKWebView so standards-based prefers-color-scheme updates; native site themes take priority. User authorizes dark webpage rendering; introduce a reversible, bounded fallback for light-only documents rather than page-wide inversion. Validate actual computed colors and images on Apple/YouTube plus theme fixture.

Search: Google already default. Fix input routing and expose Google AI Mode via documented google.com/ai and Google search links, without paid API credentials. Availability remains Google-controlled.

Compile then install and reproduce address edit/search/repeated navigation/tab switches in real UI; verify screenshots and absence of popover-window growth. Retain prior work and close out original verification.
