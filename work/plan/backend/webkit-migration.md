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

### Google search and AI Mode resolution (measured)

Root cause: `WebKitAppearance.install(in:)` was an empty function, so the single `WKWebView` construction site sent the bare `AppleWebKit/605.1.15 (KHTML, like Gecko)` user agent with no `Version/… Safari/…` token. Google classified the client as a non-browser and refused to serve a normal results document: `/search` returned its JavaScript bootstrap (`/httpservice/retry/enablejs`, 0 links, "if you are not redirected within a few seconds"), `udm=50` was stripped, and `google.com/ai` bounced to `webhp?aep=11`.

Fix: `WebKitAppearance` sets `configuration.applicationNameForUserAgent = "Version/<OS major>.0 Safari/605.1.15"` and keeps content JavaScript explicitly enabled. `AddressResolver` builds search URLs with `URLComponents`/`URLQueryItem`; `.googleAI` routes to `search?udm=50&q=`, and `google.com/ai` is the AI Mode homepage. The omnibox AI Mode button and the settings dropdown read those same provider properties, so chrome, homepage and agent navigation cannot disagree.

Measured with `browserctl` against live Google at the URLs the resolver produces:

| Input | Result |
| --- | --- |
| `/search?q=swift%20programming` | `swift programming - Google Search`, 97 links, hydrates with `&sei=` |
| `/search?udm=50&q=swift%20programming` | `udm=50` preserved, hydrates with `mstk=`/`csuir=1`, 40 links |
| `/ai` | resolves to `/search?udm=50&aep=11` |

Constraint for future work: Google `/search` commits a JavaScript bootstrap shell first; results exist only after client-side hydration (0 links immediately after commit, full results after several seconds). Any change that interrupts or re-issues navigation during hydration returns the user to Google's interstitial. Google's routing parameters are web-interface details, not a versioned API, and remain Google-controlled.

Compile then install and reproduce address edit/search/repeated navigation/tab switches in real UI; verify screenshots and absence of popover-window growth. Retain prior work and close out original verification.
