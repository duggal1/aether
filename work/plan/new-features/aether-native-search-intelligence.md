# Aether native search intelligence

**Status:** Research-backed implementation plan · September 23, 2026

## Goal

Add Safari-inspired, AI-assisted search to Aether’s existing WebKit runtime: save websites shared from macOS, bring them back through natural-language autocomplete, and make saved pages discoverable through system search.

## Findings

- Aether already renders with `WKWebView` and has one `BrowserRuntime`, saved bookmarks/history, provider autocomplete, and Jev search intelligence. Jev completions are not yet connected to the omnibox.
- macOS 27 Golden Gate is real. Its new Safari features include topic-based tab grouping, page-change notifications, and natural-language extension creation. Apple does not document a public API for embedding Safari’s own search intelligence or using its private suggestion pipeline in another app. [`macOS 27 release notes`](https://support.apple.com/en-us/127257)
- Apple’s supported native path is the [`Foundation Models framework`](https://developer.apple.com/macos/whats-new/): on-device language-model tasks, with availability checks because Apple Intelligence may be unavailable or not ready. It can judge and generate suggestions; it does not retrieve current web results.
- [`Core Spotlight` and App Intents](https://developer.apple.com/documentation/appintents/spotlight) let Aether index saved pages for system search and Apple Intelligence. [`WKWebView`](https://developer.apple.com/documentation/webkit/wkwebview) remains the rendering/navigation engine.

## Integration plan

1. **Receive shared websites.** Add a macOS Share extension that accepts a URL and optional title from Safari and other apps. Save into Aether’s existing bookmark library, deduplicate by profile and URL, and exclude Incognito. The current app is assembled from SwiftPM by `Scripts/build_aether_app.sh` and has no Xcode project, so first prove extension packaging and signing in a small spike.
2. **Use native intelligence while typing.** Add a Foundation Models adapter to the existing search-intelligence path. Feed it the query plus the active profile’s bookmark/history candidates and provider suggestions; have it rank those candidates and produce natural-language query completions. Route calls through `BrowserRuntime` so the human UI and agent surface share the same runtime.
3. **Keep web retrieval separate.** On submission, use Aether’s selected search provider for current web results and `WKWebView` for navigation. The on-device model improves intent and relevance; it is not a search index or source of live facts.
4. **Expose saved pages to macOS search.** Index non-Incognito saved pages with Core Spotlight/App Intents and add an intent to open a result in Aether. Keep indexing opt-in and profile-aware.
5. **Preserve safe behavior and fallback.** Show local matches immediately, then update them asynchronously with model results. Validate model output against supplied candidates; never let generated text directly navigate to a URL. If the model is unavailable, retain current local and provider completions. Do not silently send local history or queries to a cloud model.

## Delivery order and acceptance

First validate Share extension packaging. Then implement shared-URL saving, native omnibox ranking/completions, and Spotlight indexing. Verify that sharing a page from Safari saves it once, it appears in Aether’s suggestions and (when enabled) Spotlight, model unavailability still permits normal search, and Incognito data is neither saved nor indexed.

Search ranking and query suggestions may be probabilistic; URL validation, persistence, profile boundaries, and navigation remain code-controlled for correctness.

## Sources

- [Apple: macOS 27 Golden Gate features](https://support.apple.com/en-us/127257)
- [Apple Developer: Foundation Models and macOS 27](https://developer.apple.com/macos/whats-new/)
- [Apple Developer: SystemLanguageModel availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Apple Developer: Spotlight integration](https://developer.apple.com/documentation/appintents/spotlight)
- [Apple Developer: WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)
- [Apple Developer: Share extension support on macOS](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AppExtensionKeys.html)
