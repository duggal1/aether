# Website rendering in Aether

The native app uses the macOS system WebKit framework through `WKWebView`. This replaces the experimental engine for real browsing. No Chromium is linked or downloaded. Native SwiftUI/AppKit chrome is retained.

Safari’s rendering stack comprises WebCore (HTML/CSS/layout/rendering and web APIs), JavaScriptCore, WebKit’s embedding API and process architecture. Copying a final rasterizer into Aether would not repair JavaScript, DOM, networking, media or web-platform compatibility. The supported macOS integration is the complete system WebKit framework.

## Sources and decision

- [Apple WKWebView documentation](https://developer.apple.com/documentation/webkit/wkwebview): supported native embedding API.
- [WebKit process architecture](https://docs.webkit.org/Deep%20Dive/Architecture/WebKit2.html): separate UI, web-content and network processes; WebKit provides process management and isolation.
- [WebKit documentation](https://docs.webkit.org/): WebKit powers Safari and other Apple apps.
- [Source repository](https://github.com/WebKit/WebKit) and [licenses](https://webkit.org/licensing-webkit/): public source under BSD/LGPL terms. This implementation links the framework supplied by macOS rather than redistributing a fork.
- [Building WebKit](https://webkit.org/building-webkit/) and [developer tools](https://webkit.org/build-tools/): a source fork is possible but introduces build, packaging, updates and security-maintenance obligations. It does not establish a speed benefit.
- [HTTP web-content transport exception](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloadsinwebcontent): allows ordinary HTTP pages without relaxing URLSession globally.
- [Persistent data-store identifiers](https://developer.apple.com/documentation/webkit/wkwebsitedatastore): separate website data per Aether profile.

## Ownership

`AetherEngineAdapter` selects `NativeBrowserEngine(backend: .webKit)`. `BrowserRuntime` owns page identities, profile association and the WebKit page objects. WebKit objects and views run on MainActor. Both the app adapter and the existing authenticated app-agent dispatcher call the same runtime methods. The human sees the same WKWebView whose DOM agents inspect and whose pixels they capture. WebKit performs native input handling, accessibility, scrolling and compositing without the old 33 ms rendering loop.

The `.experimental` backend remains the default for existing engine-library clients, standalone `browserctl`/`browserd`, fixtures and research. Those separate processes do not control an app tab unless connected to the app’s authorized automation socket. This is an explicit migration boundary, not a claim that the experimental engine now supports the modern web.

Native WebKit owns cookies, web storage, network cache, JavaScript execution and website history. SQLite continues to store Aether’s bookmarks/library/session URLs. Existing experimental-engine cookies and localStorage are not imported into WebKit. Profiles use distinct persistent WKWebsiteDataStore identifiers; transient contexts use nonpersistent stores.

## Verification

Build with `nice -n 10 swift build -c release --jobs 1`, then package using `Scripts/build_aether_app.sh --skip-build`.

For the live app verification run, serve `Fixtures/webkit` on `127.0.0.1:8765`, then launch the packaged app with `--verify-webkit`. It opens Apple, YouTube, Wikipedia and the localhost fixture in real tabs. It saves PNG viewport screenshots and JSON observations to the app’s cache directory under `Aether/WebKitVerification`. The localhost checks exercise JS modules, fetch, CSS Grid, canvas, input/click, storage across reload, structured snapshots and stale node rejection. This is opt-in runtime verification, not a unit-test suite.

Passing those pages does not prove universal website compatibility, Safari feature parity, DRM playback, authenticated flows, or a fastest-browser ranking. No comparative performance claim is justified without repeatable measurements against other browsers on the same hardware.
